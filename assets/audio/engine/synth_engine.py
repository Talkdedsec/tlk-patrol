"""Synthesises the engine loops, tyre skid loop and an impact thud (numpy only, original sounds).

Run: python assets/audio/engine/synth_engine.py   (writes WAV files next to this script)

engine_idle/mid/high.wav : seamless loops of a V8-like engine at 1000 / 3000 / 5200 rpm. Vehicle.gd crossfades them and
                           scales pitch_scale by rpm / base_rpm. Built from phase-locked crank harmonics (4-stroke, 8 firing
                           pulses per 2 revolutions) plus circular (seamless) band-shaped noise.
skid.wav                 : loopable tyre squeal (band-passed noise with slow wobble).
impact.wav               : one-shot body thud used for PIT contact (not looped).
"""
import os
import wave
import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(7)


def write(name, x):
	x = np.asarray(x, dtype=np.float64)
	x = x / max(1e-9, np.max(np.abs(x))) * 0.7
	data = (x * 32767).astype("<i2")
	with wave.open(os.path.join(HERE, name), "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(data.tobytes())
	print("wrote", name, len(x) / SR, "s")


def circular_noise(n, lo, hi, slope=0.0):
	"""Seamless band-limited noise: shaped in the frequency domain, so the loop point has no click."""
	spec = rng.normal(size=n // 2 + 1) + 1j * rng.normal(size=n // 2 + 1)
	f = np.fft.rfftfreq(n, 1.0 / SR)
	mask = ((f >= lo) & (f <= hi)).astype(float)
	mask *= (np.maximum(f, 1.0) / 1000.0) ** slope
	return np.fft.irfft(spec * mask, n)


def engine(rpm, cycles):
	"""cycles = number of 2-revolution engine cycles in the loop (so the loop is exactly periodic)."""
	cycle_t = 120.0 / rpm
	n = int(round(cycles * cycle_t * SR))
	t = np.arange(n) / SR
	f_half = rpm / 120.0  # one engine cycle (two crank revolutions) per period
	# exact periodicity: stretch the time axis so n samples hold `cycles` whole cycles
	phase = 2 * np.pi * cycles * np.arange(n) / n
	x = np.zeros(n)
	fire = 8  # firing pulses per cycle
	for k in range(1, 56):
		freq = f_half * k
		if freq > 9000:
			break
		amp = 1.0 / (k ** 0.85)
		if k % fire == 0:
			amp *= 3.2  # firing frequency and its multiples dominate
		elif k % 4 == 0:
			amp *= 1.6
		amp *= 1.0 + 1.4 * np.exp(-((freq - 240.0) / 160.0) ** 2) + 0.8 * np.exp(-((freq - 700.0) / 300.0) ** 2)
		x += amp * np.sin(k * phase + rng.uniform(0, 2 * np.pi))
	# cylinder to cylinder unevenness: slow periodic amplitude wobble tied to the cycle
	x *= 1.0 + 0.18 * np.sin(phase * 2 + 0.7) + 0.08 * np.sin(phase * 3 + 1.9)
	# intake / exhaust roar, louder when revving
	load = np.clip((rpm - 800.0) / 5000.0, 0.0, 1.0)
	x = x / np.max(np.abs(x))
	roar = circular_noise(n, 90, 2400, slope=-0.6)
	roar = roar / np.max(np.abs(roar))
	x = x * 0.9 + roar * (0.12 + 0.25 * load) * (1.0 + 0.4 * np.sin(phase * fire))
	# mild saturation for grit
	x = np.tanh(1.6 * x)
	return x


def skid():
	n = int(1.6 * SR)
	a = circular_noise(n, 1400, 4200)
	b = circular_noise(n, 2600, 5200)
	t = np.arange(n) / n
	wob = 0.65 + 0.35 * np.sin(2 * np.pi * 5 * t)
	return (a * 0.7 + b * 0.5) * wob


def impact():
	n = int(0.9 * SR)
	t = np.arange(n) / SR
	thump = np.sin(2 * np.pi * (70 - 35 * t) * t) * np.exp(-t * 9.0)
	crunch = circular_noise(n, 200, 6000) * np.exp(-t * 14.0)
	return thump * 1.0 + crunch * 0.6


if __name__ == "__main__":
	write("engine_idle.wav", engine(1000.0, 8))
	write("engine_mid.wav", engine(3000.0, 25))
	write("engine_high.wav", engine(5200.0, 43))
	write("skid.wav", skid())
	write("impact.wav", impact())

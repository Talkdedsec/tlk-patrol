#!/usr/bin/env python3
"""Synthesizes the siren set as seamless looping mono WAV files.

Frequencies, periods and sweep shapes are the tuned values below.
Unmeasured tones (MAN, A/H, rumbler sub layer, blip) use a standard electronic-siren approach and are
listed under "Tasarım varsayımları" in docs/api/sirens.md.

Usage: python araclar/ses/sirenler.py [--out assets/audio/sirens] [--check]
"""
import argparse
import math
import os
import struct
import wave

import numpy as np

SR = 44100
TWO_PI = 2.0 * math.pi
BAND_LIMIT = 4200.0  # measured harmonics reach ~4 kHz; rolled off per sample to avoid aliasing


def t_axis(duration):
    return np.arange(int(round(duration * SR))) / SR


def exp_fall(x, tau, length, hi, lo):
    """Exponential decay hi -> lo over `length`, forced to land exactly on lo."""
    e = np.exp(-x / tau)
    e_end = math.exp(-length / tau)
    return lo + (hi - lo) * (e - e_end) / (1.0 - e_end)


def sweep_curve(t, period, lo, hi, rise, fall_tau, concave=False):
    """Periodic rise (linear or concave) then exponential fall: classic yelp/wail contour."""
    x = np.mod(t, period)
    f = np.empty_like(x)
    r = x < rise
    u = x[r] / rise
    f[r] = lo + (hi - lo) * ((1.0 - (1.0 - u) ** 2) if concave else u)
    f[~r] = exp_fall(x[~r] - rise, fall_tau, period - rise, hi, lo)
    return f


def harmonic_osc(freq, weights):
    """Band-limited harmonic oscillator driven by an instantaneous frequency curve.

    weights: {harmonic_number: amplitude}. The integrated phase is rescaled so the loop closes on a
    whole number of cycles (frequency error well under 1%), which makes the file seamless.
    """
    phase = np.cumsum(freq) / SR  # in cycles
    total = phase[-1] + freq[0] / SR
    cycles = max(1, round(total))
    phase = phase * (cycles / total)
    out = np.zeros_like(freq)
    for n, a in weights.items():
        roll = np.clip((BAND_LIMIT - n * freq) / 700.0, 0.0, 1.0)
        out += a * roll * np.sin(TWO_PI * n * phase)
    return out


def square_weights(n_max=15):
    return {n: 1.0 / n for n in range(1, n_max + 1, 2)}


def saw_weights(n_max=14, power=1.0):
    return {n: 1.0 / (n ** power) for n in range(1, n_max + 1)}


def am(t, rate, depth):
    return (1.0 - depth) + depth * (0.5 + 0.5 * np.cos(TWO_PI * rate * t))


def normalize(x, peak=0.5):
    x = x - np.mean(x)
    return x * (peak / np.max(np.abs(x)))


def repeat_to(duration_min, period):
    return max(1, math.ceil(duration_min / period)) * period


def loop_siren(period, lo, hi, rise, fall_tau, min_len=1.6):
    length = repeat_to(min_len, period)
    t = t_axis(length)
    f = sweep_curve(t, period, lo, hi, rise, fall_tau)
    return harmonic_osc(f, square_weights())


def smooth_gate(t, seg, period, ramp=0.004):
    """1 during the first `seg` of every `period`, 0 for the rest, with short raised-cosine edges."""
    x = np.mod(t, period)
    up = np.clip(x / ramp, 0, 1)
    down = np.clip((seg - x) / ramp, 0, 1)
    g = np.where(x < seg, np.minimum(up, down), 0.0)
    return 0.5 - 0.5 * np.cos(np.pi * g)


def make_wail():
    # 900 -> 1630 Hz over 2.35 s (concave, measured); 1.8 s fall is a guess for the unmeasured tail.
    period, rise = 4.15, 2.35
    t = t_axis(period)
    f = sweep_curve(t, period, 900.0, 1630.0, rise, 0.7, concave=True)
    return harmonic_osc(f, square_weights())


def make_hilo():
    t = t_axis(1.0)
    a = harmonic_osc(np.full_like(t, 1351.0), {1: 1.0, 2: 0.45, 3: 0.35, 4: 0.2})
    # B: 3rd harmonic dominant at ~1803 Hz, weak ~601 Hz fundamental (measured).
    b = harmonic_osc(np.full_like(t, 601.0), {1: 0.3, 3: 1.0, 5: 0.5, 7: 0.25, 9: 0.12})
    gate = smooth_gate(t, 0.5, 1.0)
    return a * gate + b * (1.0 - gate)


def make_piercer():
    t = t_axis(5.0)  # 13.4 Hz AM -> 67 cycles
    base = harmonic_osc(np.full_like(t, 1351.0), {1: 1.0, 2: 0.4, 3: 0.3})
    upper = harmonic_osc(np.full_like(t, 2272.0), {1: 0.7, 2: 0.2})
    return (base + upper) * am(t, 13.4, 0.75)


def make_hyper_hilo():
    t = t_axis(5.0)  # 20.2 Hz AM -> 101 cycles; A/B every 0.5 s
    gate = smooth_gate(t, 0.5, 1.0)
    a = harmonic_osc(np.full_like(t, 1351.0), {1: 1.0, 2: 0.4, 3: 0.3})
    b = harmonic_osc(np.full_like(t, 1809.0), {1: 1.0, 2: 0.3, 3: 0.2})
    low_b = harmonic_osc(np.full_like(t, 301.0), {1: 0.35, 2: 0.1})
    upper = harmonic_osc(np.full_like(t, 2272.0), {1: 0.7, 2: 0.2})
    return ((a * gate + (b + low_b) * (1.0 - gate)) + upper) * am(t, 20.2, 0.7)


def make_rotor():
    rise, fall = 3.4, 4.0  # rise measured, fall duration is a guess
    t = t_axis(rise + fall)
    f = np.empty_like(t)
    r = t < rise
    f[r] = 200.0 + 530.0 * (1.0 - np.exp(-t[r] / 1.7)) / (1.0 - math.exp(-rise / 1.7))
    f[~r] = exp_fall(t[~r] - rise, 3.5, fall, 730.0, 200.0)
    tone = harmonic_osc(f, saw_weights(24, 0.9))
    rattle_phase = np.cumsum(f * 0.16) / SR
    rattle_phase *= round(rattle_phase[-1]) / rattle_phase[-1]  # whole cycles per loop
    return tone * (0.78 + 0.22 * np.cos(TWO_PI * rattle_phase))


def make_mech_wail():
    rise, plateau, fall = 1.3, 0.6, 2.4  # fall to the floor is a guess
    t = t_axis(rise + plateau + fall)
    f = np.empty_like(t)
    a = t < rise
    b = (t >= rise) & (t < rise + plateau)
    c = t >= rise + plateau
    f[a] = 560.0 + 1110.0 * (1.0 - (1.0 - t[a] / rise) ** 2)
    f[b] = 1670.0
    f[c] = exp_fall(t[c] - rise - plateau, 1.2, fall, 1670.0, 560.0)
    return harmonic_osc(f, square_weights(13))


def make_man():
    t = t_axis(1.0)
    return harmonic_osc(np.full_like(t, 900.0), square_weights(15))


def make_air_horn():
    t = t_axis(1.0)
    a = harmonic_osc(np.full_like(t, 420.0), saw_weights(10, 1.0))
    b = harmonic_osc(np.full_like(t, 535.0), saw_weights(10, 1.0))
    return a + 0.9 * b


def make_rumbler():
    # Measured layer: saw-like 190-690 Hz, period 0.309 s (rides under the yelp). Sub tone is a guess.
    period = 0.309
    t = t_axis(repeat_to(1.5, period))
    f = sweep_curve(t, period, 190.0, 560.0, 0.06, 0.08)
    body = harmonic_osc(f, saw_weights(12, 1.1))
    sub = harmonic_osc(np.full_like(t, 55.0), {1: 1.0, 2: 0.3})
    return body + 0.5 * sub


def make_blip():
    t = t_axis(0.30)
    f = 650.0 * (1500.0 / 650.0) ** np.clip(t / 0.18, 0, 1)
    phase = np.cumsum(f) / SR
    s = sum((1.0 / n) * np.sin(TWO_PI * n * phase) for n in (1, 3, 5, 7))
    env = np.clip(t / 0.01, 0, 1) * np.clip((0.30 - t) / 0.08, 0, 1)
    return s * env


def make_click():
    t = t_axis(0.05)
    env = np.clip(t / 0.003, 0, 1) * np.clip((0.05 - t) / 0.02, 0, 1)
    return np.sin(TWO_PI * 2700.0 * t) * env


def write_wav(path, x, loop=False):
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    if loop:
        # 'smpl' chunk with one forward loop over the whole file, so importers that read loop points loop it.
        n = len(pcm)
        chunk = struct.pack('<4sIIIIIIIIIIIIIIII', b'smpl', 60, 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0,
                            0, 0, 0, n - 1, 0, 0)
        with open(path, 'ab') as f:
            f.write(chunk)
        with open(path, 'r+b') as f:
            f.seek(4)
            f.write(struct.pack('<I', os.path.getsize(path) - 8))


def dominant_track(x, win=2048, hop=512):
    out = []
    w = np.hanning(win)
    for i in range(0, len(x) - win, hop):
        spec = np.abs(np.fft.rfft(x[i:i + win] * w))
        out.append(np.argmax(spec[5:]) + 5)
    return np.array(out) * SR / win


def main():
    ap = argparse.ArgumentParser()
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
    ap.add_argument('--out', default=os.path.join(root, 'assets', 'audio', 'sirens'))
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    tones = {
        'wail': (make_wail(), 0.5),
        'yelp': (loop_siren(0.309, 750.0, 1570.0, 0.06, 0.08), 0.5),
        'prty': (loop_siren(0.0848, 800.0, 1570.0, 0.017, 0.022, min_len=1.2), 0.5),
        'hilo': (make_hilo(), 0.5),
        'hyper_yelp': (loop_siren(0.080, 1010.0, 1570.0, 0.016, 0.02, min_len=1.2), 0.5),
        'yelp2': (loop_siren(0.239, 720.0, 1770.0, 0.05, 0.06), 0.5),
        'pierce': (make_piercer(), 0.5),
        'hyper_hilo': (make_hyper_hilo(), 0.5),
        'mech_wail': (make_mech_wail(), 0.5),
        'rotor': (make_rotor(), 0.5),
        'man': (make_man(), 0.5),
        'ah': (make_air_horn(), 0.5),
        'rumbler': (make_rumbler(), 0.45),
        'blip': (make_blip(), 0.5),
        'click': (make_click(), 0.35),
    }
    for name, (x, peak) in tones.items():
        if name in ('blip', 'click'):
            y = x * (peak / np.max(np.abs(x)))
        else:
            y = normalize(x, peak)
        write_wav(os.path.join(args.out, name + '.wav'), y, loop=name not in ('blip', 'click'))
        line = '%-11s %6.2f s' % (name, len(y) / SR)
        if args.check and name != 'click':
            f0 = dominant_track(y)
            line += '  dominant %5.0f..%5.0f Hz' % (np.percentile(f0, 3), np.percentile(f0, 97))
        print(line)


if __name__ == '__main__':
    main()

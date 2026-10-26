#!/usr/bin/env python3
"""Synthesizes the weapon sound set (mono 16-bit WAV, 44.1 kHz) with numpy only.

Shots are layered noise (bright crack + body), a pitch-dropping thump and a convolved room tail.
Band limits: wide-band transient, about 2.5-7.8 kHz.
The alert beep: four beats alternating about 1.05 kHz and 1.7 kHz, beat 0.28 s,
period about 0.47 s, total about 1.7 s, weak partials near 2.65, 4.2 and 5.9 kHz.
Everything except the alert beep timing is a guess (listed in docs/api/weapons.md).

Usage: python araclar/ses/silah_sesleri.py [--out assets/audio/weapons] [--check]
"""
import argparse
import os
import wave

import numpy as np

SR = 44100
TWO_PI = 2.0 * np.pi


def tax(duration):
    return np.arange(int(round(duration * SR))) / SR


def fft_filter(x, lo=None, hi=None):
    """Zero-phase 2nd-order Butterworth-style high/low/band pass in the frequency domain."""
    n = len(x)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    mask = np.ones_like(f)
    if lo:
        mask *= 1.0 / (1.0 + (lo / np.maximum(f, 1e-9)) ** 4)
    if hi:
        mask *= 1.0 / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(spec * mask, n)


def fft_convolve(x, ir):
    n = len(x) + len(ir) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]


def attack(t, ms=0.25):
    return 1.0 - np.exp(-t / (ms / 1000.0))


def finish(x, peak=0.9, fade=0.02, drive=1.6):
    x = np.tanh(drive * x)
    n = int(fade * SR)
    x[-n:] *= np.linspace(1.0, 0.0, n)
    return x * (peak / np.max(np.abs(x)))


def room_tail(dry, rng, length, tau, lo=90.0, hi=3800.0):
    n = int(length * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n) * np.exp(-t / tau)
    ir = fft_filter(ir, lo, hi)
    ir[:int(0.004 * SR)] = 0.0  # no tail inside the first 4 ms
    wet = fft_convolve(dry, ir)
    scale = np.max(np.abs(dry)) / max(np.max(np.abs(wet)), 1e-9)
    return wet * scale


def gunshot(seed, dur, crack_tau, crack_gain, body_tau, body_gain, thump_f0, thump_f1, thump_tau,
            thump_gain, tail_len, tail_tau, tail_mix, drive):
    rng = np.random.default_rng(seed)
    t = tax(dur)
    n = len(t)
    crack = fft_filter(rng.standard_normal(n), 1800.0, 7800.0) * np.exp(-t / crack_tau)
    body = fft_filter(rng.standard_normal(n), 110.0, 1500.0) * np.exp(-t / body_tau)
    f = thump_f1 + (thump_f0 - thump_f1) * np.exp(-t / 0.04)
    thump = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / thump_tau)
    dry = (crack_gain * crack / max(np.max(np.abs(crack)), 1e-9)
           + body_gain * body / max(np.max(np.abs(body)), 1e-9)
           + thump_gain * thump) * attack(t)
    wet = room_tail(dry, rng, tail_len, tail_tau)
    return finish(dry + tail_mix * wet, drive=drive)


def metal_click(t0, length, freqs, tau, rng, gain=1.0, noise_gain=0.6):
    """Short metallic transient: ringing partials plus a noise tick, placed by the caller."""
    t = tax(length)
    ring = sum(a * np.sin(TWO_PI * f * t) for f, a in freqs) * np.exp(-t / tau)
    tick = fft_filter(rng.standard_normal(len(t)), 1500.0, 9000.0) * np.exp(-t / (tau * 0.35))
    out = gain * (ring / max(np.max(np.abs(ring)), 1e-9) + noise_gain * tick / max(np.max(np.abs(tick)), 1e-9))
    return t0, out * attack(t, 0.1)


def rustle(length, rng, lo=300.0, hi=3200.0, shape=1.0):
    t = tax(length)
    noise = fft_filter(rng.standard_normal(len(t)), lo, hi)
    env = np.sin(np.pi * np.clip(t / length, 0, 1)) ** shape
    flutter = 0.65 + 0.35 * np.sin(TWO_PI * 23.0 * t + rng.uniform(0, 6.28))
    return noise * env * flutter / max(np.max(np.abs(noise)), 1e-9)


def mix(total, parts):
    out = np.zeros(int(round(total * SR)))
    for t0, x in parts:
        i = int(round(t0 * SR))
        j = min(len(out), i + len(x))
        if j > i:
            out[i:j] += x[:j - i]
    return out


def make_pump(rng):
    back = metal_click(0.00, 0.18, [(780, 1.0), (2150, 0.7), (3300, 0.3)], 0.045, rng, 1.0)
    fwd = metal_click(0.23, 0.18, [(640, 1.0), (1900, 0.8), (3700, 0.35)], 0.05, rng, 1.15)
    slide = (0.03, 0.18 * rustle(0.18, rng, 500.0, 2600.0))
    return finish(mix(0.55, [back, fwd, slide]), peak=0.8, drive=1.2)


def make_dry_click(rng):
    t0, x = metal_click(0.0, 0.06, [(1400, 1.0), (3100, 0.5)], 0.012, rng, 1.0, 0.8)
    return finish(mix(0.07, [(t0, x)]), peak=0.55, fade=0.01, drive=1.1)


def make_pistol_reload(rng):
    parts = [
        metal_click(0.00, 0.1, [(1500, 1.0), (3400, 0.5)], 0.02, rng, 0.8),      # magazine release
        (0.10, 0.35 * rustle(0.28, rng, 400.0, 2400.0)),                          # magazine slides out
        (0.55, 0.28 * rustle(0.3, rng, 300.0, 2000.0)),                           # new magazine moves
        metal_click(0.95, 0.12, [(520, 1.0), (1700, 0.6)], 0.04, rng, 1.1),      # magazine seats
        metal_click(1.30, 0.14, [(900, 1.0), (2400, 0.7), (3600, 0.3)], 0.05, rng, 1.0),  # slide release
    ]
    return finish(mix(1.6, parts), peak=0.7, drive=1.2)


def make_rifle_reload(rng):
    parts = [
        metal_click(0.00, 0.1, [(1300, 1.0), (3000, 0.5)], 0.02, rng, 0.8),
        (0.12, 0.35 * rustle(0.4, rng, 300.0, 2200.0)),
        (0.75, 0.3 * rustle(0.45, rng, 250.0, 1800.0)),
        metal_click(1.25, 0.14, [(420, 1.0), (1400, 0.7)], 0.05, rng, 1.2),      # magazine seats
        metal_click(1.75, 0.16, [(700, 1.0), (2000, 0.8), (3300, 0.35)], 0.055, rng, 1.0),  # charging handle back
        metal_click(1.98, 0.16, [(600, 1.0), (1800, 0.8), (3500, 0.4)], 0.06, rng, 1.15),   # and forward
    ]
    return finish(mix(2.3, parts), peak=0.7, drive=1.2)


def make_shell(rng):
    parts = [
        metal_click(0.00, 0.1, [(1100, 1.0), (2600, 0.5)], 0.02, rng, 0.9),
        (0.04, 0.4 * rustle(0.12, rng, 600.0, 3000.0)),
        metal_click(0.13, 0.14, [(560, 1.0), (1500, 0.6)], 0.045, rng, 1.0),
    ]
    return finish(mix(0.3, parts), peak=0.6, drive=1.1)


def make_draw(rng):
    parts = [(0.0, 0.5 * rustle(0.28, rng, 250.0, 2600.0, 0.8)),
             metal_click(0.26, 0.1, [(1000, 1.0), (2800, 0.6)], 0.02, rng, 0.7)]
    return finish(mix(0.4, parts), peak=0.5, drive=1.1)


def make_holster(rng):
    parts = [(0.0, 0.5 * rustle(0.32, rng, 250.0, 2200.0, 0.8)),
             metal_click(0.34, 0.12, [(800, 1.0), (2200, 0.6)], 0.03, rng, 0.9)]
    return finish(mix(0.5, parts), peak=0.5, drive=1.1)


def make_impact(rng):
    t = tax(0.25)
    thud = np.sin(TWO_PI * (170.0 * np.exp(-t / 0.03) + 70.0) * t) * np.exp(-t / 0.04)
    grit = fft_filter(rng.standard_normal(len(t)), 600.0, 5000.0) * np.exp(-t / 0.05)
    x = (0.8 * thud + 0.6 * grit / max(np.max(np.abs(grit)), 1e-9)) * attack(t, 0.3)
    return finish(x, peak=0.5, fade=0.03, drive=1.1)


def make_alert_beep():
    """Four-beat two-tone alert: 1.05 kHz / 1.7 kHz alternating, 0.28 s beats, 0.47 s period."""
    beat, period, count = 0.28, 0.47, 4
    total = period * (count - 1) + beat
    t = tax(total)
    out = np.zeros_like(t)
    partials = [(1.0, 1.0), (2.65 / 1.7, 0.10), (4.2 / 1.7, 0.06), (5.9 / 1.7, 0.04)]
    for k in range(count):
        base = 1050.0 if k % 2 == 0 else 1700.0
        i0 = int(round(k * period * SR))
        n = int(round(beat * SR))
        tt = np.arange(n) / SR
        env = np.clip(tt / 0.006, 0, 1) * np.clip((beat - tt) / 0.012, 0, 1)
        tone = sum(a * np.sin(TWO_PI * base * ratio * tt) for ratio, a in partials)
        out[i0:i0 + n] += tone * env
    return out * (0.6 / np.max(np.abs(out)))


def write_wav(path, x):
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype('<i2')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def describe(x):
    spec = np.abs(np.fft.rfft(x[:min(len(x), 8192)] * np.hanning(min(len(x), 8192))))
    f = np.fft.rfftfreq(min(len(x), 8192), 1.0 / SR)
    centroid = float((spec * f).sum() / max(spec.sum(), 1e-9))
    return 'peak %.2f  centroid %5.0f Hz' % (np.max(np.abs(x)), centroid)


def main():
    ap = argparse.ArgumentParser()
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
    ap.add_argument('--out', default=os.path.join(root, 'assets', 'audio', 'weapons'))
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    rng = np.random.default_rng(7)

    sounds = {
        'pistol_shot': gunshot(11, 0.7, 0.010, 2.6, 0.035, 0.9, 260.0, 90.0, 0.04, 0.55, 0.6, 0.18, 0.18, 1.5),
        'rifle_shot': gunshot(12, 1.1, 0.014, 2.8, 0.06, 1.0, 170.0, 55.0, 0.09, 0.8, 1.0, 0.35, 0.22, 1.6),
        'shotgun_shot': gunshot(13, 1.5, 0.02, 3.0, 0.10, 1.2, 125.0, 40.0, 0.14, 1.0, 1.4, 0.5, 0.25, 1.7),
        'shotgun_pump': make_pump(rng),
        'dry_click': make_dry_click(rng),
        'pistol_reload': make_pistol_reload(rng),
        'rifle_reload': make_rifle_reload(rng),
        'shotgun_shell': make_shell(rng),
        'draw': make_draw(rng),
        'holster': make_holster(rng),
        'impact': make_impact(rng),
        'alert_beep': make_alert_beep(),
    }
    for name, x in sounds.items():
        write_wav(os.path.join(args.out, name + '.wav'), x)
        line = '%-14s %5.2f s' % (name, len(x) / SR)
        if args.check:
            line += '  ' + describe(x)
        print(line)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Generates the radio voice clips (assets/audio/radio) for Calls and TrafficStop.

Pipeline: araclar/ses/telsiz_satirlar.json (written by scripts/traffic_stop/dev/dump_lines.gd)
  -> Windows SAPI voice via araclar/ses/telsiz_sapi.ps1 (22.05 kHz; the only English voice installed is Microsoft Zira)
  -> radio filter in numpy (band pass 350-3000 Hz, soft clip, faint static, silence trim) -> 8 kHz mono WAV
  -> assets/audio/radio/manifest.json {"lines": {key: file}, "words": {word: file}}.
Also writes chirp.wav (transmit beep, 1.1 kHz + 2.2 kHz), squelch.wav (end-of-transmission noise tail)
and alert_beep.wav (EMERGENCY alert: four beats alternating ~1.05 and ~1.7 kHz).
Speaker differences (dispatch / unit / officer / driver) are made at runtime with pitch_scale: one clip serves all voices.

Usage: python araclar/ses/telsiz_uret.py [--out assets/audio/radio] [--keep-raw] [--only chirp|alert|voices]
"""
import argparse
import hashlib
import json
import math
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SR_OUT = 8000
BAND = (350.0, 3000.0)


def read_wav(path):
    with wave.open(str(path), "rb") as w:
        rate = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
        if w.getnchannels() > 1:
            data = data.reshape(-1, w.getnchannels()).mean(axis=1)
    return data, rate


def write_wav(path, data, rate):
    pcm = np.clip(data, -1.0, 1.0)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((pcm * 32767.0).astype(np.int16).tobytes())


def bandpass(x, rate, lo=BAND[0], hi=BAND[1]):
    """Zero-phase FFT band pass with smooth Butterworth-like skirts."""
    n = len(x)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / rate)
    f[0] = 1e-6
    high = 1.0 / np.sqrt(1.0 + (lo / f) ** 4)
    low = 1.0 / np.sqrt(1.0 + (f / hi) ** 8)
    return np.fft.irfft(spec * high * low, n)


def resample(x, rate_in, rate_out):
    if rate_in == rate_out:
        return x
    t_out = np.arange(int(len(x) * rate_out / rate_in)) / rate_out
    return np.interp(t_out, np.arange(len(x)) / rate_in, x).astype(np.float32)


def trim(x, rate, threshold=0.012, pad=0.02):
    mask = np.abs(x) > threshold
    if not mask.any():
        return x
    idx = np.where(mask)[0]
    a = max(idx[0] - int(pad * rate), 0)
    b = min(idx[-1] + int(pad * rate), len(x))
    return x[a:b]


def radio_filter(x, rate, rng):
    x = trim(x, rate)
    x = bandpass(x, rate)
    # light compression / soft clipping like an over-driven handheld
    x = np.tanh(2.2 * x / (np.max(np.abs(x)) + 1e-6)) / np.tanh(2.2)
    # faint static under the speech
    noise = bandpass(rng.standard_normal(len(x)).astype(np.float32), rate, 500.0, 2800.0)
    x = x * 0.92 + noise * 0.012 * (0.4 + np.abs(x))
    x = x / (np.max(np.abs(x)) + 1e-6) * 0.82
    return x.astype(np.float32)


def run_sapi(items, tmp_dir):
    tsv = tmp_dir / "in.tsv"
    tsv.write_text("\n".join("%s\t%s" % (i, t.replace("\t", " ").replace("\n", " ")) for i, t in items), encoding="utf-8")
    cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "araclar/ses/telsiz_sapi.ps1"),
           "-InFile", str(tsv), "-OutDir", str(tmp_dir)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    print(result.stdout.strip(), result.stderr.strip()[:300])


def make_voices(out_dir, keep_raw):
    data = json.loads((ROOT / "araclar/ses/telsiz_satirlar.json").read_text(encoding="utf-8"))
    rng = np.random.default_rng(7)
    work = []  # (id, spoken, kind, key)
    manifest = {"lines": {}, "words": {}}
    for item in data["lines"]:
        ident = "l_" + hashlib.sha1(item["key"].encode()).hexdigest()[:10]
        work.append((ident, item["spoken"], "lines", item["key"]))
    for word in data["words"]:
        ident = "w_" + hashlib.sha1(word.encode()).hexdigest()[:10]
        work.append((ident, word, "words", word))
    tmp = Path(tempfile.gettempdir()) / "telsiz_raw"  # persistent: reruns only render new lines
    tmp.mkdir(exist_ok=True)
    run_sapi([(w[0], w[1]) for w in work], tmp)
    total = 0.0
    for ident, spoken, kind, key in work:
        raw = tmp / (ident + ".wav")
        if not raw.exists():
            print("missing", ident, spoken)
            continue
        x, rate = read_wav(raw)
        x = resample(radio_filter(x, rate, rng), rate, SR_OUT)
        write_wav(out_dir / (ident + ".wav"), x, SR_OUT)
        manifest[kind][key] = ident + ".wav"
        total += len(x) / SR_OUT
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=1, sort_keys=True), encoding="utf-8")
    print("voices: %d lines, %d words, %.0f s of audio" % (len(manifest["lines"]), len(manifest["words"]), total))
    print("raw SAPI cache:", tmp)


def envelope(n, attack, release, rate):
    env = np.ones(n, dtype=np.float32)
    a, r = int(attack * rate), int(release * rate)
    if a > 0:
        env[:a] = np.linspace(0, 1, a)
    if r > 0:
        env[-r:] = np.linspace(1, 0, r)
    return env


def make_chirp(out_dir):
    """Transmit beep: 1.1 kHz then 2.2 kHz (constant tones before each transmission)."""
    rate = SR_OUT
    t1 = np.arange(int(0.13 * rate)) / rate
    t2 = np.arange(int(0.09 * rate)) / rate
    a = np.sin(2 * math.pi * 1100 * t1) * envelope(len(t1), 0.004, 0.01, rate)
    b = np.sin(2 * math.pi * 2200 * t2) * envelope(len(t2), 0.004, 0.02, rate)
    write_wav(out_dir / "chirp.wav", np.concatenate([a, b]) * 0.32, rate)


def make_squelch(out_dir):
    rate = SR_OUT
    rng = np.random.default_rng(3)
    n = int(0.07 * rate)
    noise = bandpass(rng.standard_normal(n).astype(np.float32), rate, 600.0, 3000.0)
    write_wav(out_dir / "squelch.wav", noise * np.exp(-np.arange(n) / (0.018 * rate)) * 0.35, rate)


def make_alert(out_dir):
    """EMERGENCY alert: four 0.28 s beats on a 0.5 s grid alternating ~1.05 and ~1.7 kHz, partials at 2.65, 4.2, 5.9 kHz."""
    rate = 22050
    x = np.zeros(int(1.8 * rate), dtype=np.float32)
    for i in range(4):
        f = 1050.0 if i % 2 == 0 else 1700.0
        n = int(0.28 * rate)
        t = np.arange(n) / rate
        tone = (np.sin(2 * math.pi * f * t) + 0.30 * np.sin(2 * math.pi * 2650 * t)
                + 0.15 * np.sin(2 * math.pi * 4200 * t) + 0.08 * np.sin(2 * math.pi * 5900 * t))
        tone *= envelope(n, 0.006, 0.03, rate)
        start = int(i * 0.5 * rate)
        x[start:start + n] += tone.astype(np.float32)
    write_wav(out_dir / "alert_beep.wav", x / np.max(np.abs(x)) * 0.6, rate)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / "assets/audio/radio"))
    parser.add_argument("--keep-raw", action="store_true", help="(kept for compatibility; the raw cache is always kept)")
    parser.add_argument("--only", choices=["chirp", "alert", "voices"])
    args = parser.parse_args()
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    if args.only in (None, "chirp"):
        make_chirp(out_dir)
        make_squelch(out_dir)
    if args.only in (None, "alert"):
        make_alert(out_dir)
    if args.only in (None, "voices"):
        make_voices(out_dir, args.keep_raw)


if __name__ == "__main__":
    sys.exit(main())

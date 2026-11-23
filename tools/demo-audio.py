#!/usr/bin/env python3
"""Build the demo video's soundtrack.

    demo-audio.py <sfx.log> <rec-start-ms> <captions> <duration-s> <out.wav> <tv-root>

- An original synthwave bed (A minor, 108 BPM): drums, bass, arpeggio, pads,
  all synthesized here, so the video carries no licensed music.
- Every interface sound the TV played during the recording, placed at the
  moment it played (from the shell's sfx.log, written in demo mode).
- A swoosh under each caption change and a sting on the closing title.
"""

import sys
import wave

import numpy as np

RATE = 44100
BPM = 108
BEAT = 60 / BPM


def load_wav(path):
    with wave.open(path) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float32) / 32768
        if w.getnchannels() == 2:
            data = data.reshape(-1, 2).mean(axis=1)
        return data


def place(track, sound, t, gain=1.0):
    i = int(t * RATE)
    if i >= len(track) or i < 0:
        return
    n = min(len(sound), len(track) - i)
    track[i:i + n] += sound[:n] * gain


def adsr(n, a=0.01, d=0.1, s=0.6, r=0.1):
    e = np.full(n, s, dtype=np.float32)
    ai, di, ri = int(a * RATE), int(d * RATE), int(r * RATE)
    ai = min(ai, n); e[:ai] = np.linspace(0, 1, ai)
    de = min(n, ai + di); e[ai:de] = np.linspace(1, s, de - ai)
    if ri and n > ri:
        e[-ri:] *= np.linspace(1, 0, ri)
    return e


def saw(freq, n, detune=0.0):
    t = np.arange(n) / RATE
    out = np.zeros(n, dtype=np.float32)
    for d in (-detune, 0, detune) if detune else (0,):
        f = freq * (1 + d)
        out += 2 * ((t * f) % 1) - 1
    return out / (3 if detune else 1)


def square(freq, n, duty=0.5):
    t = np.arange(n) / RATE
    return np.where((t * freq) % 1 < duty, 1.0, -1.0).astype(np.float32)


def lowpass(x, cutoff):
    # one-pole, vectorised via cumulative filtering in chunks
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(0, len(x), 4096):
        chunk = x[i:i + 4096]
        out = np.empty_like(chunk)
        for j, v in enumerate(chunk):
            acc = (1 - a) * v + a * acc
            out[j] = acc
        y[i:i + 4096] = out
    return y


def note(n):  # MIDI to Hz
    return 440 * 2 ** ((n - 69) / 12)


def kick():
    n = int(0.35 * RATE)
    t = np.arange(n) / RATE
    f = 45 + 110 * np.exp(-t * 28)
    return (np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 9)).astype(np.float32)


def snare(rng):
    n = int(0.22 * RATE)
    t = np.arange(n) / RATE
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30)
    hiss = rng.uniform(-1, 1, n) * np.exp(-t * 16)
    return (0.5 * body + 0.6 * hiss).astype(np.float32)


def hat(rng, open_=False):
    n = int((0.18 if open_ else 0.05) * RATE)
    t = np.arange(n) / RATE
    x = rng.uniform(-1, 1, n)
    x = x - np.concatenate([[0], x[:-1]])  # crude high-pass
    return (x * np.exp(-t * (14 if open_ else 60)) * 0.5).astype(np.float32)


def music(duration):
    rng = np.random.default_rng(3)
    n = int(duration * RATE)
    drums = np.zeros(n, dtype=np.float32)
    bass = np.zeros(n, dtype=np.float32)
    arp = np.zeros(n, dtype=np.float32)
    pad = np.zeros(n, dtype=np.float32)

    # Am - F - C - G, one bar each
    chords = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]
    roots = [45, 41, 48, 43]
    bar = 4 * BEAT
    k, s = kick(), snare(rng)
    t = 0.0
    bar_i = 0
    while t < duration:
        c = chords[bar_i % 4]
        r = roots[bar_i % 4]
        intro = bar_i < 2
        # pads: whole bar, detuned saws, softened
        pn = int(bar * RATE)
        chunk = sum(saw(note(m), pn, 0.004) for m in c) / 3
        place(pad, chunk * adsr(pn, 0.3, 0.2, 0.8, 0.3) * 0.22, t)
        for beat in range(4):
            bt = t + beat * BEAT
            if not intro:
                place(drums, k, bt, 0.9)
                if beat in (1, 3):
                    place(drums, s, bt, 0.45)
            for e in range(2):
                place(drums, hat(rng, open_=(e == 1 and beat == 3)), bt + e * BEAT / 2, 0.22 if not intro else 0.12)
            # bass: driving eighths
            for e in range(2):
                bn = int(BEAT / 2 * RATE * 0.9)
                tone = saw(note(r - 12 if e == 0 else r), bn) * adsr(bn, 0.005, 0.08, 0.5, 0.03)
                place(bass, tone * (0.0 if intro else 0.35), bt + e * BEAT / 2)
            # arpeggio: sixteenths up the chord
            for sx in range(4):
                an = int(BEAT / 4 * RATE * 0.8)
                m = c[(beat * 4 + sx) % 3] + 12 * (1 + ((beat * 4 + sx) // 3) % 2)
                tone = square(note(m), an, 0.25) * adsr(an, 0.002, 0.05, 0.3, 0.02)
                place(arp, tone * 0.07, bt + sx * BEAT / 4)
        t += bar
        bar_i += 1

    bass = lowpass(bass, 420)
    pad = lowpass(pad, 1800)
    mixd = drums * 0.8 + bass + arp + pad
    # fade in and out
    fade = np.ones(n, dtype=np.float32)
    fi, fo = int(1.5 * RATE), int(3.0 * RATE)
    fade[:fi] = np.linspace(0, 1, fi)
    fade[-fo:] = np.linspace(1, 0, fo)
    return mixd * fade


def swoosh(rng):
    n = int(0.45 * RATE)
    t = np.arange(n) / RATE
    x = rng.uniform(-1, 1, n).astype(np.float32)
    x = lowpass(x, 2500)
    env = np.sin(np.pi * np.clip(t / 0.45, 0, 1)) ** 2
    return x * env * 0.5


def sting():
    n = int(2.2 * RATE)
    out = np.zeros(n, dtype=np.float32)
    for i, m in enumerate((69, 76, 81, 88)):
        sn = n - int(i * 0.09 * RATE)
        tone = saw(note(m), sn, 0.006) * adsr(sn, 0.01, 0.3, 0.4, 1.2)
        out[n - sn:] += tone * 0.18
    return lowpass(out, 3000)


def main():
    log_path, rec0, captions_path, duration, out, root = sys.argv[1:7]
    rec0 = float(rec0)
    duration = float(duration)
    n = int(duration * RATE)
    rng = np.random.default_rng(11)

    bed = music(duration) * 0.5
    fx = np.zeros(n, dtype=np.float32)

    cache = {}
    try:
        lines = open(log_path).read().split("\n")
    except OSError:
        lines = []
    for line in lines:
        parts = line.split()
        if len(parts) != 3:
            continue
        ms, pack, event = parts
        key = (pack, event)
        if key not in cache:
            try:
                cache[key] = load_wav(f"{root}/sounds/{pack}/{event}.wav")
            except OSError:
                continue
        place(fx, cache[key], (float(ms) - rec0) / 1000, 1.3)

    sw = swoosh(rng)
    caps = [l.split(" ", 1) for l in open(captions_path).read().strip().split("\n") if l.strip()]
    for i, (t, text) in enumerate(caps):
        if text.strip() == "Omarchy TV":
            place(fx, sting(), float(t), 1.0)
        elif i > 0:
            place(fx, sw, float(t) - 0.15, 0.6)

    # Duck the music a little under interface sounds.
    env = np.abs(fx)
    win = int(0.08 * RATE)
    env = np.convolve(env, np.ones(win) / win, mode="same")
    duck = 1 - np.clip(env * 3, 0, 0.35)
    mixd = bed * duck + fx
    peak = np.max(np.abs(mixd)) or 1
    mixd = mixd / peak * 0.89
    pcm = (np.clip(mixd, -1, 1) * 32767).astype("<i2")
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print("soundtrack:", out)


if __name__ == "__main__":
    main()

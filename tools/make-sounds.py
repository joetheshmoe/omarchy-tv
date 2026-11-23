#!/usr/bin/env python3
"""Generate Omarchy TV's interface sound packs into sounds/<pack>/<event>.wav.

Every sound is synthesized here (no samples, no licences to worry about):

  soft   rounded sine blips, quiet and warm (the default)
  retro  8-bit square and pulse chirps
  glass  bright FM bells

Events: move, select, back, open, close, toggle, guide, type, error, notify.
Drop your own pack in ~/.config/omarchy-tv/sounds/<name>/ with the same file
names (any you leave out fall back to "soft"); it shows up in Settings.

    python3 tools/make-sounds.py [out-dir]
"""

import os
import sys
import wave

import numpy as np

RATE = 44100


def env(n, attack=0.004, release=None, curve=6.0):
    t = np.linspace(0, 1, n, endpoint=False)
    e = np.exp(-curve * t) if release is None else np.clip(1 - t / release, 0, 1)
    a = max(1, int(attack * RATE))
    e[:a] *= np.linspace(0, 1, a)
    return e


def tone(freq, dur, kind="sine", curve=6.0, glide=None, duty=0.5, fm=None):
    n = int(dur * RATE)
    t = np.arange(n) / RATE
    f = np.full(n, float(freq)) if glide is None else np.geomspace(freq, glide, n)
    phase = 2 * np.pi * np.cumsum(f) / RATE
    if fm:
        ratio, index = fm
        phase = phase + index * np.exp(-8 * t) * np.sin(phase * ratio)
    if kind == "sine":
        w = np.sin(phase)
    elif kind == "square":
        w = np.where((phase / (2 * np.pi)) % 1 < duty, 1.0, -1.0) * 0.55
    elif kind == "tri":
        w = 2 * np.abs(2 * ((phase / (2 * np.pi)) % 1) - 1) - 1
    else:
        w = np.sin(phase)
    return w * env(n, curve=curve)


def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out.append(p)
        if gap:
            out.append(np.zeros(int(gap * RATE)))
    return np.concatenate(out)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def noise(dur, curve=10.0, lowpass=0.2):
    n = int(dur * RATE)
    w = np.random.default_rng(7).uniform(-1, 1, n)
    # one-pole low-pass for a softer swish
    y = np.zeros(n)
    acc = 0.0
    for i in range(n):
        acc += lowpass * (w[i] - acc)
        y[i] = acc
    return y * env(n, curve=curve)


def soft():
    return {
        "move": tone(880, 0.045, curve=14) * 0.35,
        "select": seq(tone(660, 0.05, curve=10), tone(990, 0.09, curve=8)) * 0.45,
        "back": seq(tone(740, 0.05, curve=10), tone(520, 0.08, curve=9)) * 0.4,
        "open": mix(tone(440, 0.32, glide=880, curve=4) * 0.35, noise(0.3, curve=7, lowpass=0.05) * 0.25),
        "close": mix(tone(700, 0.25, glide=330, curve=5) * 0.35, noise(0.22, curve=8, lowpass=0.04) * 0.2),
        "toggle": tone(1175, 0.06, curve=12) * 0.4,
        "guide": seq(tone(523, 0.06, curve=9), tone(659, 0.06, curve=9), tone(784, 0.12, curve=7)) * 0.4,
        "type": tone(1500, 0.025, curve=20) * 0.22,
        "error": seq(tone(330, 0.09, curve=6), tone(262, 0.16, curve=5)) * 0.45,
        "notify": seq(tone(988, 0.07, curve=8), tone(1319, 0.14, curve=6)) * 0.4,
    }


def retro():
    sq = lambda f, d, **k: tone(f, d, kind="square", **k)
    return {
        "move": sq(1046, 0.035, curve=10, duty=0.25) * 0.3,
        "select": seq(sq(784, 0.045, curve=6), sq(1046, 0.045, curve=6), sq(1568, 0.08, curve=6)) * 0.35,
        "back": seq(sq(880, 0.045, curve=6), sq(587, 0.08, curve=6)) * 0.35,
        "open": sq(262, 0.3, glide=1046, curve=3, duty=0.125) * 0.35,
        "close": sq(880, 0.25, glide=196, curve=3, duty=0.125) * 0.35,
        "toggle": sq(1318, 0.05, curve=8, duty=0.25) * 0.3,
        "guide": seq(sq(659, 0.05, curve=5), sq(784, 0.05, curve=5), sq(1046, 0.05, curve=5), sq(1318, 0.1, curve=5)) * 0.32,
        "type": tone(2093, 0.02, kind="square", curve=18, duty=0.5) * 0.18,
        "error": seq(sq(196, 0.1, curve=4), sq(147, 0.18, curve=3)) * 0.4,
        "notify": seq(sq(1046, 0.06, curve=6), sq(1568, 0.06, curve=6), sq(2093, 0.1, curve=6)) * 0.3,
    }


def glass():
    bell = lambda f, d, c=5: tone(f, d, fm=(3.5, 2.4), curve=c)
    return {
        "move": bell(1760, 0.08, 16) * 0.25,
        "select": mix(bell(1318, 0.35, 6) * 0.35, bell(1976, 0.3, 7) * 0.2),
        "back": bell(988, 0.22, 8) * 0.35,
        "open": seq(bell(1046, 0.08, 9), bell(1568, 0.08, 9), bell(2093, 0.35, 5)) * 0.33,
        "close": seq(bell(1568, 0.08, 9), bell(1046, 0.08, 9), bell(784, 0.3, 5)) * 0.33,
        "toggle": bell(2349, 0.12, 12) * 0.28,
        "guide": mix(bell(784, 0.5, 4) * 0.3, bell(1175, 0.45, 4) * 0.2, bell(1568, 0.4, 5) * 0.15),
        "type": bell(2637, 0.04, 22) * 0.16,
        "error": bell(440, 0.4, 4) * 0.45,
        "notify": seq(bell(1760, 0.1, 8), bell(2349, 0.3, 5)) * 0.3,
    }


def write(path, data):
    data = np.clip(data, -1, 1)
    pcm = (data * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")
    for name, pack in (("soft", soft()), ("retro", retro()), ("glass", glass())):
        d = os.path.join(out, name)
        os.makedirs(d, exist_ok=True)
        for event, data in pack.items():
            # a few ms of silence up front avoids a click on some outputs
            write(os.path.join(d, event + ".wav"), np.concatenate([np.zeros(int(0.003 * RATE)), data]))
    print("sound packs written to", os.path.abspath(out))


if __name__ == "__main__":
    main()

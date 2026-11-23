#!/usr/bin/env python3
"""Cut the recorded demo into the README video.

    demo-edit.py <work-dir> <tv-root> <out-dir>

<work-dir> (from tools/demo.sh) holds raw.mp4, marks, sfx.log, rec0 and
voice.wav. Marks are "<seconds> begin <caption>", "<seconds> speed <x>",
"<seconds> voice" and "<seconds> end", timed from the start of recording.

- Scenes are cut together on the beat: each one is trimmed to a whole number
  of half bars of the 108 BPM soundtrack, after the speed-ups.
- A two-bar title card opens (matching the music's two-bar intro, so the
  drums land as the TV appears) and a two-bar card closes with the install
  command.
- Captions are lower thirds that slide in with an accent bar.
- The soundtrack is rebuilt to match the edit: synthwave bed, every interface
  sound remapped through the cuts and speed changes, the spoken request,
  swooshes on cuts and a sting on the closing card.
"""

import math
import os
import subprocess
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import demo_audio as A  # noqa: E402

BAR = 4 * 60 / A.BPM
HALF = BAR / 2
FPS = 60
REPO = "github.com/joetheshmoe/omarchy-tv"


def theme_colors(root):
    colors = {}
    try:
        for line in open("/usr/share/omarchy/themes/tokyo-night/colors.toml"):
            if "=" in line and '"#' in line:
                k, v = line.split("=", 1)
                colors[k.strip()] = v.strip().strip('"').lstrip("#")
    except OSError:
        pass
    return {
        "bg": colors.get("background", "1a1b26"),
        "fg": colors.get("bright_foreground", "c0caf5"),
        "dim": colors.get("foreground", "a9b1d6"),
        "accent": colors.get("accent", "7aa2f7"),
    }


def parse(work):
    scenes, cur = [], None
    voice_t = None
    for line in open(os.path.join(work, "marks")):
        parts = line.strip().split(" ", 2)
        if len(parts) < 2:
            continue
        t, kind = float(parts[0]), parts[1]
        arg = parts[2] if len(parts) > 2 else ""
        if kind == "begin":
            cur = {"caption": arg, "start": t, "changes": [(t, 1.0)]}
        elif kind == "speed" and cur:
            cur["changes"].append((t, float(arg)))
        elif kind == "voice":
            voice_t = t
        elif kind == "end" and cur:
            cur["end"] = t
            scenes.append(cur)
            cur = None
    return scenes, voice_t


def build(scenes, intro):
    """Pieces of raw footage with speeds, placed on the output timeline."""
    pieces, captions = [], []
    out_t = intro
    for sc in scenes:
        ch = sc["changes"] + [(sc["end"], None)]
        segs = [(ch[i][0], ch[i + 1][0], ch[i][1]) for i in range(len(ch) - 1) if ch[i + 1][0] > ch[i][0]]
        length = sum((b - a) / s for a, b, s in segs)
        target = max(HALF, math.floor(length / HALF) * HALF)
        # Trim the tail until the scene is a whole number of half bars.
        excess = length - target
        while excess > 1e-6 and segs:
            a, b, s = segs[-1]
            dur = (b - a) / s
            if dur <= excess:
                segs.pop()
                excess -= dur
            else:
                segs[-1] = (a, b - excess * s, s)
                excess = 0
        start = out_t
        for a, b, s in segs:
            pieces.append({"a": a, "b": b, "speed": s, "out": out_t})
            out_t += (b - a) / s
        captions.append((start, out_t, sc["caption"]))
    return pieces, captions, out_t


def raw_to_out(t, pieces):
    for p in pieces:
        if p["a"] <= t < p["b"]:
            return p["out"] + (t - p["a"]) / p["speed"]
    return None


def esc(path):
    return path.replace("\\", "\\\\").replace(":", "\\:").replace("'", "\\'")


def textfile(work, name, text):
    path = os.path.join(work, name)
    with open(path, "w") as f:
        f.write(text)
    return esc(path)


def video(work, pieces, captions, intro, outro_start, total, colors, font, out):
    bg, fg, dim, ac = colors["bg"], colors["fg"], colors["dim"], colors["accent"]
    f = []
    # Title card
    t_title = textfile(work, "t-title.txt", "OMARCHY TV")
    t_sub = textfile(work, "t-sub.txt", "turn any PC into a living-room console")
    fade_in = lambda t0, d=0.35: f"alpha='min(1,max(0,(t-{t0})/{d}))'"
    f.append(
        f"color=c=0x{bg}:s=1920x1080:r={FPS}:d={intro:.4f},format=yuv420p,"
        f"drawtext=fontfile={font}:textfile={t_title}:fontsize=160:fontcolor=0x{fg}:x=(w-text_w)/2:y='h/2-110+30*max(0,1-(t-0.3)/0.5)':{fade_in(0.3)},"
        f"drawtext=fontfile={font}:textfile={t_sub}:fontsize=48:fontcolor=0x{dim}:x=(w-text_w)/2:y=h/2+110:{fade_in(1.1, 0.5)},"
        f"drawbox=x=(iw-360)/2:y=ih/2+80:w='360*min(1,max(0,(t-0.8)/0.6))':h=6:color=0x{ac}:t=fill[intro]"
    )
    # Footage
    for i, p in enumerate(pieces):
        f.append(f"[0:v]trim=start={p['a']:.4f}:end={p['b']:.4f},setpts=(PTS-STARTPTS)/{p['speed']},fps={FPS},format=yuv420p,settb=1/{FPS}[p{i}]")
    # Closing card
    outro = total - outro_start
    t_install = textfile(work, "t-install.txt", "omarchy plugin add " + REPO)
    t_repo = textfile(work, "t-repo.txt", REPO)
    f.append(
        f"color=c=0x{bg}:s=1920x1080:r={FPS}:d={outro:.4f},format=yuv420p,"
        f"drawtext=fontfile={font}:textfile={t_title}:fontsize=130:fontcolor=0x{fg}:x=(w-text_w)/2:y=h/2-160:{fade_in(0.1)},"
        f"drawtext=fontfile={font}:textfile={t_install}:fontsize=40:fontcolor=0x{fg}:box=1:boxcolor=0x{ac}@0.18:boxborderw=26:x=(w-text_w)/2:y=h/2+40:{fade_in(0.6)},"
        f"drawtext=fontfile={font}:textfile={t_repo}:fontsize=30:fontcolor=0x{dim}:x=(w-text_w)/2:y=h/2+150:{fade_in(1.0)}[outro]"
    )
    labels = "[intro]" + "".join(f"[p{i}]" for i in range(len(pieces))) + "[outro]"
    f.append(f"{labels}concat=n={len(pieces) + 2}:v=1:a=0[cat]")

    # Lower-third captions
    chain = "[cat]"
    for i, (s0, s1, text) in enumerate(captions):
        a, b = s0 + 0.15, s1 - 0.12
        tf = textfile(work, f"cap{i}.txt", text)
        slide = f"130-80*max(0,1-(t-{a:.3f})/0.28)"
        alpha = f"alpha='min(1,max(0,(t-{a:.3f})/0.2))*min(1,max(0,({b:.3f}-t)/0.18))'"
        en = f"enable='between(t,{a:.3f},{b:.3f})'"
        f.append(
            f"{chain}drawbox=x=96:y=ih-192:w=10:h=78:color=0x{ac}:t=fill:{en},"
            f"drawtext=fontfile={font}:textfile={tf}:fontsize=44:fontcolor=0x{fg}:box=1:boxcolor=0x{bg}@0.9:boxborderw=20:x='{slide}':y=h-173:{alpha}:{en}[c{i}]"
        )
        chain = f"[c{i}]"
    f.append(f"{chain}null[v]")
    graph = ";\n".join(f)
    with open(os.path.join(work, "graph.txt"), "w") as fh:
        fh.write(graph)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(work, "raw.mp4"),
         "-/filter_complex", os.path.join(work, "graph.txt"), "-map", "[v]",
         "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-r", str(FPS), out],
        check=True)


def soundtrack(work, root, pieces, captions, intro, outro_start, total, voice_t, out):
    n = int(total * A.RATE)
    bed = A.music(total) * 0.5
    fx = np.zeros(n, dtype=np.float32)
    rec0 = float(open(os.path.join(work, "rec0")).read())
    cache = {}
    for line in open(os.path.join(work, "sfx.log")):
        parts = line.split()
        if len(parts) != 3:
            continue
        ms, pack, event = parts
        t = raw_to_out(float(ms) / 1000 - rec0, pieces)
        if t is None:
            continue
        key = (pack, event)
        if key not in cache:
            try:
                cache[key] = A.load_wav(f"{root}/sounds/{pack}/{event}.wav")
            except OSError:
                continue
        A.place(fx, cache[key], t, 1.25)

    if voice_t is not None:
        v44 = os.path.join(work, "voice44.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", os.path.join(work, "voice.wav"), "-ar", str(A.RATE), "-ac", "1", v44], check=True)
        t = raw_to_out(voice_t + 0.2, pieces)
        if t is not None:
            A.place(fx, A.load_wav(v44), t, 1.4)

    rng = np.random.default_rng(5)
    sw = A.swoosh(rng)
    for s0, _, _ in captions[1:]:
        A.place(fx, sw, s0 - 0.2, 0.45)
    A.place(fx, sw, outro_start - 0.2, 0.5)
    A.place(fx, A.sting(), outro_start, 1.0)

    env = np.convolve(np.abs(fx), np.ones(int(0.08 * A.RATE)) / (0.08 * A.RATE), mode="same")
    mixd = bed * (1 - np.clip(env * 3, 0, 0.4)) + fx
    mixd = mixd / (np.max(np.abs(mixd)) or 1) * 0.89
    pcm = (np.clip(mixd, -1, 1) * 32767).astype("<i2")
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(A.RATE)
        w.writeframes(pcm.tobytes())


def main():
    work, root, outdir = sys.argv[1:4]
    colors = theme_colors(root)
    font = esc(subprocess.run(["fc-match", "-f", "%{file}", "monospace:bold"], capture_output=True, text=True).stdout.strip())
    scenes, voice_t = parse(work)
    intro = 2 * BAR
    pieces, captions, outro_start = build(scenes, intro)
    total = outro_start + 2 * BAR
    print(f"{len(scenes)} scenes, {total:.1f}s")
    vid = os.path.join(work, "video.mp4")
    video(work, pieces, captions, intro, outro_start, total, colors, font, vid)
    aud = os.path.join(work, "audio.wav")
    soundtrack(work, root, pieces, captions, intro, outro_start, total, voice_t, aud)
    mp4 = os.path.join(outdir, "demo.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", vid, "-i", aud, "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                    "-shortest", "-movflags", "+faststart", mp4], check=True)
    gif = os.path.join(outdir, "demo.gif")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp4, "-vf",
                    "fps=15,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];"
                    "[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle", gif], check=True)


if __name__ == "__main__":
    main()

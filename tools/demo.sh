#!/bin/bash

# Record the README demo: drives a hidden Omarchy TV session with scripted
# remote presses, records its 1080p headless output, then captions it.
#
#   tools/demo.sh [out-dir]     writes demo.mp4 and demo.gif (default: docs/)
#
# Needs wf-recorder and ffmpeg. Uses your real TV settings and Omarchy theme;
# your settings.json is restored afterwards.

set -uo pipefail
root=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
out=${1:-$root/docs}
work=$(mktemp -d)
mkdir -p "$out"
export OMARCHY_TV_TEST=1 OMARCHY_TV_DEMO=1
tv="$root/bin/omarchy-tv"
settings=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-tv/settings.json
cp "$settings" "$work/settings.json" 2>/dev/null || true
trap 'cp "$work/settings.json" "$settings" 2>/dev/null; "$tv" stop >/dev/null 2>&1; rm -rf "$work"' EXIT

# Fresh look for the recording: default layout, tutorial on.
jq '.tutorialDone = false | .agent = "claude" | .sounds = "retro" | .soundVolume = 0.7 | del(.layout)' "$work/settings.json" >"$settings" 2>/dev/null || echo '{}' >"$settings"

"$tv" stop >/dev/null 2>&1
"$tv" test >/dev/null || exit 1
sleep 6
source "${XDG_RUNTIME_DIR}/omarchy-tv-test/session.env"
export WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
ipc() { qs ipc --pid "$(pgrep -f "[q]s -p $root/shell" | head -1)" call tv "$@" >/dev/null; }
key() { for k in "$@"; do wtype -k "$k"; sleep "${GAP:-0.55}"; done; }
global() { hyprctl dispatch "hl.dsp.global(\"omarchy-tv:$1\")" >/dev/null; }

# Everything is timed from the moment recording starts, so captions and the
# interface sounds (logged by the shell in demo mode) land on the right frame.
rec0=$(date +%s.%N)
caption() { echo "$(echo "$(date +%s.%N) - $rec0" | bc) $*" >>"$work/captions"; }

wf-recorder -o TV-HEADLESS --no-damage -r 30 -c libx264 -p crf=18 -p preset=veryfast -f "$work/raw.mp4" >/dev/null 2>&1 &
rec=$!
sleep 1.5

sleep 2.5
caption "Your PC, now a living-room console"
sleep 2
key Right
sleep 1.6
key Menu # skip the rest of the tutorial
sleep 1.2

caption "Couch-first: remote, controller or keyboard"
GAP=0.45 key Right Right Right Down Right Down Down Up Up Up
sleep 0.8

caption "Every app full screen, in its own container"
ipc open vibes
sleep 5.5
GAP=0.7 key Right Right Left
sleep 0.8

caption "Home brings up the guide: switch, close, force quit"
global home
sleep 2.2
GAP=0.5 key Down Down Down Up Up Up
sleep 0.6
key Down Return # Home
sleep 1.6

caption "Retro music, radio and Spotify in cliamp"
ipc open cliamp
sleep 3.5
GAP=0.4 key Down Down Down
sleep 1.2
global close
sleep 2

caption "Ask your Omarchy agent. Out loud."
ipc ask "Recommend one cozy movie for tonight, in two sentences."
for _ in $(seq 1 60); do
  sleep 0.5
  qs ipc --pid "$(pgrep -f "[q]s -p $root/shell" | head -1)" call tv state | grep -q '"busy":false' && break
done
sleep 4
key Escape
sleep 0.8

caption "A keyboard that shows up when you need it"
global keyboard
sleep 1
# Spell "lofi" on the on-screen keyboard, the way a remote does.
GAP=0.22 key Down Right Right Right Right Right Right Right Right
key Return
GAP=0.3 key Up Return
GAP=0.22 key Down Left Left Left Left Left
key Return
GAP=0.22 key Up Right Right Right Right
key Return
sleep 1.2
key Escape
sleep 0.8

caption "Make it yours: move anything, add anything"
key Down Menu
sleep 1
key Down Return # Move
sleep 0.6
GAP=0.6 key Right Right Down
sleep 0.6
key Return
sleep 1

caption "Omarchy's install menu and Control, from the couch"
ipc open install
sleep 1.8
GAP=0.45 key Down Down Down Down Down Down Return
sleep 2
key Escape Escape
sleep 0.6
ipc open settings
sleep 1.2
GAP=0.35 key Down Down Down Down Down Down Down Down Right
sleep 2.4
key Escape Escape
sleep 1

caption "Omarchy TV"
sleep 3
kill -INT "$rec"
wait "$rec" 2>/dev/null
cp "${XDG_RUNTIME_DIR}/omarchy-tv-test/sfx.log" "$work/sfx.log" 2>/dev/null || : >"$work/sfx.log"
[[ -n ${DEMO_KEEP:-} ]] && { cp "$work/raw.mp4" "$work/captions" "$work/sfx.log" "$DEMO_KEEP/"; echo "$rec0" >"$DEMO_KEEP/rec0"; }

# Captions: a bar along the bottom, Omarchy's font, the theme's colors.
font=$(fc-match -f '%{file}' "monospace:bold")
fg=$(sed -n 's/^bright_foreground *= *"#\(.*\)"/\1/p' ~/.local/state/omarchy/current/theme/colors.toml)
accent=$(sed -n 's/^accent *= *"#\(.*\)"/\1/p' ~/.local/state/omarchy/current/theme/colors.toml)
bg=$(sed -n 's/^background *= *"#\(.*\)"/\1/p' ~/.local/state/omarchy/current/theme/colors.toml)
filters=()
mapfile -t lines <"$work/captions"
for i in "${!lines[@]}"; do
  t=${lines[$i]%% *}
  text=${lines[$i]#* }
  next=${lines[$((i + 1))]:-}
  next=${next%% *}
  [[ -z $next ]] && next=999
  printf '%s' "$text" >"$work/cap$i.txt"
  size=44; [[ $text == "Omarchy TV" ]] && size=96
  y="h-150"; [[ $text == "Omarchy TV" ]] && y="(h-text_h)/2"
  box="box=1:boxcolor=0x${bg}@0.88:boxborderw=28"
  # Each caption fades in and out over a quarter second.
  fade="alpha='if(lt(t,$t+0.25),(t-$t)/0.25,if(gt(t,$next-0.25),max(0,($next-t)/0.25),1))'"
  filters+=("drawtext=fontfile=$font:textfile=$work/cap$i.txt:fontsize=$size:fontcolor=0x${fg}:$box:x=(w-text_w)/2:y=$y:$fade:enable='between(t,$t,$next)'")
done
# Opening title over the first seconds.
printf 'OMARCHY TV' >"$work/title.txt"
printf 'turn any PC into a living-room console' >"$work/subtitle.txt"
titlefade="alpha='if(lt(t,0.3),t/0.3,if(gt(t,2.6),max(0,(3.0-t)/0.4),1))'"
filters+=("drawbox=x=0:y=0:w=iw:h=ih:color=0x${bg}@0.82:t=fill:enable='lt(t,3.0)'")
filters+=("drawtext=fontfile=$font:textfile=$work/title.txt:fontsize=140:fontcolor=0x${accent}:x=(w-text_w)/2:y=(h-text_h)/2-60:$titlefade:enable='lt(t,3.0)'")
filters+=("drawtext=fontfile=$font:textfile=$work/subtitle.txt:fontsize=46:fontcolor=0x${fg}:x=(w-text_w)/2:y=(h)/2+70:$titlefade:enable='lt(t,3.0)'")
vf=$(IFS=,; echo "${filters[*]}")
ffmpeg -y -loglevel error -i "$work/raw.mp4" -vf "$vf" -c:v libx264 -crf 23 -preset medium -pix_fmt yuv420p "$work/video.mp4"

# Soundtrack: original synthwave bed + the interface sounds + swooshes.
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/video.mp4")
rec0_ms=$(echo "$rec0 * 1000" | bc)
python3 -I "$root/tools/demo-audio.py" "$work/sfx.log" "$rec0_ms" "$work/captions" "$duration" "$work/audio.wav" "$root"
ffmpeg -y -loglevel error -i "$work/video.mp4" -i "$work/audio.wav" -c:v copy -c:a aac -b:a 160k -shortest -movflags +faststart "$out/demo.mp4"
# The README GIF: 1.6x speed, 720p, 10 fps, so it stays under ~10 MB.
ffmpeg -y -loglevel error -i "$out/demo.mp4" -vf "setpts=PTS/1.6,fps=10,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" "$out/demo.gif"
ls -la "$out/demo.mp4" "$out/demo.gif"

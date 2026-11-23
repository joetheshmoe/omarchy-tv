#!/bin/bash

# Record and edit the README demo.
#
#   tools/demo.sh [out-dir]       writes demo.mp4 (60 fps, with sound) and demo.gif
#
# 1. Starts a hidden Omarchy TV session (headless 1080p output) in demo mode:
#    app audio goes to a silent sink, the TV's own sounds are logged instead of
#    played, the desktop's now-playing is hidden, and the theme comes from a
#    demo folder so it can change live without touching your desktop.
# 2. Plays a scripted tour with remote presses, recording at 60 fps, and marks
#    where each scene starts and ends.
# 3. tools/demo-edit.py cuts the scenes together on the music's beat, speeds
#    up waiting, adds captions and title cards, and builds the soundtrack: an
#    original synthwave bed, every interface sound where it played, and the
#    spoken request (Piper TTS) where the "user" spoke it.
#
# Needs: wf-recorder, ffmpeg, python3 + numpy, Piper TTS (PIPER, PIPER_VOICE).

set -uo pipefail
root=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
out=${1:-$root/docs}
work=$(mktemp -d)
mkdir -p "$out"
tv="$root/bin/omarchy-tv"
settings=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-tv/settings.json
piper=${PIPER:-piper}
voice=${PIPER_VOICE:?set PIPER_VOICE to a Piper .onnx voice}

export OMARCHY_TV_TEST=1 OMARCHY_TV_DEMO=1
cp "$settings" "$work/settings.json" 2>/dev/null || echo '{}' >"$work/settings.json"

# A silent sink for app audio (YouTube, games).
sinkmod=$(pactl load-module module-null-sink sink_name=omarchy_tv_demo sink_properties=device.description=OmarchyTVDemo)
export PULSE_SINK=omarchy_tv_demo

cleanup() {
  cp "$work/settings.json" "$settings" 2>/dev/null
  "$tv" stop >/dev/null 2>&1
  pactl unload-module "$sinkmod" 2>/dev/null
  [[ -n ${DEMO_KEEP:-} ]] && cp -r "$work/." "$DEMO_KEEP/" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# Demo theme, switchable live.
mkdir -p "$work/theme-link"
settheme() {
  ln -sfn "/usr/share/omarchy/themes/$1" "$work/theme-link/theme"
  ln -sfn "$(ls -d "/usr/share/omarchy/themes/$1/backgrounds/"* | head -1)" "$work/theme-link/background"
  date +%s%N >"$work/theme-link/gen"
}
settheme tokyo-night
export OMARCHY_TV_THEME_DIR=$work/theme-link/theme OMARCHY_TV_BACKGROUND=$work/theme-link/background OMARCHY_TV_THEME_GEN=$work/theme-link/gen

# The spoken request.
echo "Hey, put on some chill synthwave music." | "$piper" -m "$voice" -f "$work/voice.wav" 2>/dev/null
export OMARCHY_TV_DEMO_VOICE=$work/voice.wav

# Fresh look: default layout, tutorial on, Claude answers, Retro sounds.
jq '.tutorialDone = false | .agent = "claude" | .sounds = "retro" | .soundVolume = 0.7 | del(.layout)' \
  "$work/settings.json" >"$settings"

"$tv" stop >/dev/null 2>&1
"$tv" test >/dev/null || exit 1
sleep 7
source "${XDG_RUNTIME_DIR}/omarchy-tv-test/session.env"
export WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
qspid() { pgrep -f "[q]s -p $root/shell" | head -1; }
ipc() { qs ipc --pid "$(qspid)" call tv "$@" >/dev/null; }
state() { qs ipc --pid "$(qspid)" call tv state; }
key() { for k in "$@"; do wtype -k "$k"; sleep "${GAP:-0.4}"; done; }
global() { hyprctl dispatch "hl.dsp.global(\"omarchy-tv:$1\")" >/dev/null; }
waitfor() { for _ in $(seq 1 "${2:-80}"); do state | grep -q "$1" && return 0; sleep 0.25; done; return 1; }

rec0=$(date +%s.%N)
now() { echo "$(date +%s.%N) - $rec0" | bc; }
mark() { echo "$(now) $*" >>"$work/marks"; }
begin() { mark begin "$@"; } # begin <caption>
speed() { mark speed "$1"; }  # play what follows at this speed
end() { mark end; }

wf-recorder -o TV-HEADLESS --no-damage -r 60 -c h264_vaapi -d "${DEMO_RENDER_NODE:-/dev/dri/renderD129}" -f "$work/raw.mp4" >"$work/wf.log" 2>&1 &
rec=$!
sleep 1.5

# --- 1. Home ------------------------------------------------------------------
begin "Your PC, now a living-room console"
sleep 1.2
key Menu # skip the tutorial
sleep 0.6
GAP=0.32 key Right Right Right Down Right Right Down Up Up Left Left
sleep 0.4
end

# --- 2. Voice → agent → YouTube -----------------------------------------------
begin "Just say what you want"
global talk
mark voice
sleep 2.4
global talk
speed 3 # transcribing and thinking
waitfor '"busy":false,"voice"' 120
waitfor '"answer":"[^"]' 40
speed 1
sleep 2.6 # read the reply; the TV acts on it
speed 2.5 # YouTube loading
waitfor '"front":"youtube"' 120
sleep 6
speed 1
# Browse the results (playing one would hit YouTube's sign-in check).
GAP=0.55 key Right Right Down Right Left Up
sleep 0.8
end

# --- 3. Guide ------------------------------------------------------------------
begin "Home opens the guide: switch, close, force quit"
global home
sleep 1
GAP=0.4 key Down Down Down Up # Home, Close, Force quit, back to Close
sleep 0.5
key Return # Close YouTube
sleep 1.6
end

# --- 4. Game Vibes ------------------------------------------------------------
begin "Omarchy's Game Vibes, built in"
ipc open vibes
speed 2.5
waitfor '"front":"vibes"' 80
sleep 3
speed 1
GAP=0.5 key Right Right Right
sleep 0.6
global close
sleep 1.2
end

# --- 5. Live theme ------------------------------------------------------------
begin "It wears your Omarchy theme. Live."
sleep 0.6
for t in catppuccin gruvbox retro-82 rose-pine tokyo-night; do
  settheme "$t"
  sleep 1.11
done
end

# --- 6. Sounds ----------------------------------------------------------------
begin "Pick a sound pack. Or none at all."
ipc open settings
waitfor '"screen":"settings"' 40
sleep 1.2
GAP=0.45 key Right Down Down
sleep 0.4
GAP=0.95 key Right Right Right Right
sleep 0.3
end

# --- 7. Move ------------------------------------------------------------------
begin "Move anything. Add anything."
GAP=0.3 key Escape Escape
sleep 0.4
key Menu
sleep 0.6
key Down Return # Move
sleep 0.3
GAP=0.55 key Right Right Down
sleep 0.4
key Return
sleep 0.8
end

# --- 8. Keyboard --------------------------------------------------------------
begin "A keyboard that shows up when you need it"
global keyboard
sleep 0.8
speed 1.6
# o m a r c h y, spelled with the remote
GAP=0.12 key Right Right Right Right Right Right Right Right; key Return
GAP=0.12 key Down Down Left Left; key Return
GAP=0.12 key Up Left Left Left Left Left Left; key Return
GAP=0.12 key Up Right Right Right; key Return
GAP=0.12 key Down Down Left; key Return
GAP=0.12 key Up Right Right Right; key Return
GAP=0.12 key Up; key Return
speed 1
sleep 1.4
key Escape
sleep 0.4
end

# --- 9. Install + Control -----------------------------------------------------
begin "Omarchy's install menu and Control, from the couch"
ipc open install
sleep 1.4
GAP=0.3 key Down Down Down Down Down Down
key Return
sleep 1.6
key Escape Escape
sleep 0.4
end

sleep 0.5
kill -INT "$rec"
wait "$rec" 2>/dev/null
cp "${XDG_RUNTIME_DIR}/omarchy-tv-test/sfx.log" "$work/sfx.log" 2>/dev/null || : >"$work/sfx.log"
echo "$rec0" >"$work/rec0"

python3 -I "$root/tools/demo-edit.py" "$work" "$root" "$out"
ls -la "$out/demo.mp4" "$out/demo.gif"

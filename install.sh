#!/bin/bash

# Install Omarchy TV for this user, from wherever this folder lives.
#
#   ./install.sh           Put `omarchy-tv` on PATH and "Omarchy TV" in the app launcher
#   ./install.sh --bind    Also bind Super+Alt+T to it in ~/.config/hypr/bindings.lua
#   ./install.sh --remove  Undo both
#
# Nothing in /usr/share/omarchy is touched; everything is a symlink or a small
# file in your home, so `git pull` in this folder updates the TV in place.

set -euo pipefail

root=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
bin="$HOME/.local/bin"
apps="$HOME/.local/share/applications"
entry="$apps/omarchy-tv.desktop"
bindings="$HOME/.config/hypr/bindings.lua"
marker="-- omarchy-tv"

remove() {
  rm -f "$bin/omarchy-tv" "$entry"
  if [[ -f $bindings ]] && grep -q "$marker" "$bindings"; then
    sed -i "/$marker/d" "$bindings"
    hyprctl reload >/dev/null 2>&1 || true
  fi
  echo "Omarchy TV removed (your ~/.config/omarchy-tv and app profiles are kept)."
}

if [[ ${1:-} == --remove ]]; then
  remove
  exit 0
fi

missing=()
for cmd in Hyprland qs jq systemd-run foot; do command -v "$cmd" >/dev/null || missing+=("$cmd"); done
((${#missing[@]} == 0)) || { echo "Missing: ${missing[*]}" >&2; exit 1; }

# Omarchy Control is the TV's advanced settings, and a requirement.
if ! command -v omarchy-control >/dev/null; then
  echo "Omarchy TV needs Omarchy Control; installing it..."
  omarchy pkg add omarchy-control || { echo "Install it with: omarchy pkg add omarchy-control" >&2; exit 1; }
fi
command -v chromium >/dev/null || command -v google-chrome-stable >/dev/null ||
  echo "Note: web apps (YouTube, Netflix, Twitch) need Chromium or Chrome: omarchy install browser chromium"
command -v mpv >/dev/null || echo "Note: Videos and Music need mpv: omarchy pkg add mpv"

chmod +x "$root"/bin/*
mkdir -p "$bin" "$apps" "$HOME/.config/omarchy-tv"
ln -sfn "$root/bin/omarchy-tv" "$bin/omarchy-tv"

cat >"$entry" <<EOF
[Desktop Entry]
Type=Application
Name=Omarchy TV
GenericName=10-foot TV mode
Comment=Fullscreen, remote-friendly TV interface
Exec=$root/bin/omarchy-tv
Icon=video-display
Categories=AudioVideo;Video;
Keywords=tv;10ft;couch;media;remote;big picture;
StartupNotify=false
EOF

if [[ ! -f $HOME/.config/omarchy-tv/apps.json ]]; then
  cp "$root/config/apps.example.json" "$HOME/.config/omarchy-tv/apps.json"
fi

if [[ ${1:-} == --bind ]]; then
  if [[ -f $bindings ]] && ! grep -q "$marker" "$bindings"; then
    cp "$bindings" "$bindings.bak.$(date +%s)"
    printf '\no.bind("SUPER + ALT + T", "Omarchy TV", "%s") %s\n' "$root/bin/omarchy-tv" "$marker" >>"$bindings"
    hyprctl reload >/dev/null 2>&1 || true
    if hyprctl configerrors 2>/dev/null | grep -q .; then
      hyprctl configerrors
    fi
    echo "Bound Super+Alt+T to Omarchy TV."
  fi
fi

echo "Omarchy TV installed. Start it from the app launcher, or run: omarchy-tv"

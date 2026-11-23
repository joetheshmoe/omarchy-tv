pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The Omarchy palette, read live from the current theme: switching themes on
// the desktop (or from TV Settings) recolors the TV at once.
Singleton {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string themeDir: home + "/.local/state/omarchy/current/theme"
  readonly property string backgroundPath: home + "/.local/state/omarchy/current/background"

  // Design units: the UI is laid out for 1920x1080 and multiplied by `s`.
  // `zoom` is the user's TV text/UI size, `safe` the overscan margin.
  property real screenHeight: 1080
  property real zoom: 1.0
  property real safe: 0.04
  readonly property real s: (screenHeight / 1080) * zoom
  function px(n) { return Math.round(n * s) }

  property color background: "#1a1b26"
  property color backgroundDark: "#13141c"
  property color surface: "#24283b"
  property color foreground: "#c0caf5"
  property color dim: "#a9b1d6"
  property color muted: "#565f89"
  property color accent: "#7aa2f7"
  property color urgent: "#f7768e"
  property color good: "#9ece6a"
  property color warn: "#e0af68"
  property bool light: false
  property int generation: 0 // bumps on every theme switch

  // Omarchy's font (`omarchy font set ...`): whatever `monospace` resolves to.
  property string font: "JetBrainsMono Nerd Font"
  readonly property string glyphFont: font

  // Corners follow the desktop's Hyprland rounding, as Omarchy's shell does:
  // a sharp-cornered theme gives a sharp-cornered TV.
  property int rounding: 0
  function r(n) { return rounding > 0 ? px(n) : 0 }
  function round(v) { return rounding > 0 ? v : 0 }

  // Shell surface tokens from the theme's shell.toml.
  property color activeBorder: accent
  property color popupBorder: accent
  property real selectedFill: 0.18
  property real focusFill: 0.08

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function resolve(value) {
    // Catalog colors may name a theme role instead of a hex value.
    if (value === "accent") return accent
    if (value === "background") return background
    if (value === "surface") return surface
    return value
  }

  function firstColor(value, fallback) {
    var m = String(value || "").match(/#[0-9a-fA-F]{6,8}|rgba?\([^)]*\)/)
    if (!m) return fallback
    var c = m[0]
    var rgba = c.match(/rgba?\(([0-9a-fA-F]{6,8})\)/) // Hyprland's rgba(rrggbbaa)
    return rgba ? "#" + rgba[1].slice(0, 6) : c
  }

  function parseShell(text) {
    var section = ""
    var map = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var sec = lines[i].match(/^\s*\[([a-z-]+)\]/)
      if (sec) { section = sec[1]; continue }
      var kv = lines[i].match(/^\s*([a-z-]+)\s*=\s*"?([^"#\n]*[^"\s#])"?/)
      if (kv) map[section + "." + kv[1]] = kv[2]
    }
    function resolve(v) { return map[v] !== undefined ? map[v] : v }
    activeBorder = firstColor(resolve(map["hyprland.active-border"]), accent)
    popupBorder = firstColor(resolve(map["popups.border"] || "hyprland.active-border"), activeBorder)
    var sf = parseFloat(map["controls.selected-fill-alpha"]); if (isFinite(sf)) selectedFill = sf
    var ff = parseFloat(map["controls.focus-fill-alpha"]); if (isFinite(ff)) focusFill = ff
  }

  function parse(text) {
    var map = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([a-z_]+)\s*=\s*"([^"]*)"/)
      if (m) map[m[1]] = m[2]
    }
    function pick(k, f) { return map[k] && map[k].length ? map[k] : f }
    background = pick("background", background)
    backgroundDark = pick("darker_background", pick("dark_background", background))
    surface = pick("lighter_background", pick("selection", surface))
    foreground = pick("bright_foreground", pick("foreground", foreground))
    dim = pick("foreground", foreground)
    muted = pick("dark_foreground", pick("muted", muted))
    accent = pick("accent", accent)
    urgent = pick("red", urgent)
    good = pick("green", good)
    warn = pick("yellow", warn)
    light = map["mode"] === "light"
    generation++
  }

  FileView {
    id: colorsFile
    path: root.themeDir + "/colors.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.parse(text())
  }

  FileView {
    id: shellFile
    path: root.themeDir + "/shell.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseShell(text())
  }

  Process {
    id: fontProc
    running: true
    command: ["fc-match", "-f", "%{family[0]}", "monospace"]
    stdout: StdioCollector { onStreamFinished: if (text.trim()) root.font = text.trim() }
  }

  // The desktop's rounding (the TV compositor itself runs with none).
  Process {
    id: roundingProc
    running: true
    command: ["sh", "-c", "sig=$(cat \"$OMARCHY_TV_STATE/host.env\" 2>/dev/null); HYPRLAND_INSTANCE_SIGNATURE=${sig:-$HYPRLAND_INSTANCE_SIGNATURE} hyprctl -j getoption decoration:rounding"]
    stdout: StdioCollector { onStreamFinished: { try { root.rounding = JSON.parse(text).int || 0 } catch (e) {} } }
  }

  // A theme switch swaps the whole directory; Omarchy bumps this file when it
  // does, which catches the swap even when the old watch went with the files.
  FileView {
    path: root.home + "/.local/state/omarchy/current/theme.generation"
    watchChanges: true
    onFileChanged: { reload(); colorsFile.reload(); shellFile.reload(); fontProc.running = true; roundingProc.running = true }
  }
}

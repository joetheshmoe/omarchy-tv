pragma Singleton
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io

// Interface sounds: a short blip for moving, a chirp for OK, a swoosh when an
// app opens. Settings › Sound picks the pack (or Off) and the volume. Packs
// live in sounds/<pack>/ and ~/.config/omarchy-tv/sounds/<pack>/, one wav
// per event; a pack missing an event borrows it from "soft".
Singleton {
  id: root

  readonly property var events: ["move", "select", "back", "open", "close", "toggle", "guide", "type", "error", "notify"]
  readonly property var builtinPacks: ["soft", "retro", "glass"]
  property var userPacks: []
  readonly property var packs: builtinPacks.concat(userPacks.filter(function(p) { return builtinPacks.indexOf(p) < 0 }))

  readonly property string pack: Tv.settings.sounds === undefined ? "soft" : String(Tv.settings.sounds)
  readonly property bool enabled: pack !== "off" && pack !== ""
  readonly property real volume: Tv.settings.soundVolume === undefined ? 0.6 : Tv.settings.soundVolume
  readonly property string userDir: Tv.configDir + "/sounds"

  function packLabel(p) {
    var names = { off: "Off", soft: "Soft", retro: "Retro", glass: "Glass" }
    return names[p] || p
  }

  function fileFor(event) {
    var dir = userPacks.indexOf(pack) >= 0 ? userDir + "/" + pack : Tv.tvRoot + "/sounds/" + pack
    return "file://" + dir + "/" + event + ".wav"
  }

  // One preloaded effect per event; switching packs just swaps sources.
  property var players: ({})
  Instantiator {
    model: root.events
    delegate: SoundEffect {
      required property string modelData
      source: root.enabled ? root.fileFor(modelData) : ""
      // Hidden test and demo sessions stay silent (the demo's audio is
      // rebuilt from the log instead).
      volume: root.silent ? 0 : root.volume
      Component.onCompleted: { var p = root.players; p[modelData] = this; root.players = p }
      onStatusChanged: {
        // A user pack without this event falls back to the soft one.
        if (status === SoundEffect.Error && String(source).indexOf("/sounds/soft/") < 0)
          source = "file://" + Tv.tvRoot + "/sounds/soft/" + modelData + ".wav"
      }
    }
  }

  readonly property bool silent: !!Quickshell.env("OMARCHY_TV_TEST")
  property var lastAt: ({})
  property real lastAny: 0
  function play(event) {
    if (!enabled) return
    var now = Date.now()
    // A notification right on top of another sound would only clutter it.
    if (event === "notify" && now - lastAny < 250) return
    lastAny = now
    // Key repeat and quick bursts: one blip per 35 ms per event.
    if (now - (lastAt[event] || 0) < 35) return
    lastAt[event] = now
    var p = players[event]
    if (p) p.play()
    if (demo) logEvent(event, now)
  }

  // Recording a demo: note every sound with its time, so the video's audio
  // track can be built from the same sounds afterwards.
  readonly property bool demo: !!Quickshell.env("OMARCHY_TV_DEMO")
  property string log: ""
  FileView { id: logFile; path: Tv.stateDir + "/sfx.log"; printErrors: false }
  function logEvent(event, now) {
    log += now + " " + pack + " " + event + "\n"
    logFile.setText(log)
  }

  // Your own packs: any folder in ~/.config/omarchy-tv/sounds.
  Process {
    running: true
    command: ["sh", "-c", "for d in \"$1\"/*/; do [ -d \"$d\" ] && basename \"$d\"; done", "sh", root.userDir]
    stdout: StdioCollector {
      onStreamFinished: root.userPacks = text.split("\n").filter(function(s) { return /^[A-Za-z0-9 _.-]+$/.test(s) })
    }
  }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Typing, pointing and talking for the TV:
//  - the on-screen keyboard, popped up by tv-ime when an app focuses a text
//    field, or summoned with a button
//  - mouse mode (the gamepad bridge's virtual mouse; arrows for remotes)
//  - voice through Superwhisper (omarchy-tv-voice)
Singleton {
  id: root

  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Tv.home + "/.cache")) + "/omarchy-tv"

  // ------------------------------------------------------------ keyboard
  property bool keyboardShown: false
  property string keyboardTarget: "app" // app | assistant
  property bool keyboardSecret: false
  property string keyboardInitial: ""
  property real keyboardHiddenAt: 0
  signal keyboardOpened()

  // tv-ime state
  property bool imeReady: false
  property bool imeActive: false
  property int imePurpose: 0

  property string keyboardApp: "" // the app the keyboard types into
  function showKeyboard(target, secret) {
    keyboardTarget = target || "app"
    keyboardApp = Tv.frontApp || Tv.lastApp
    keyboardSecret = !!secret
    keyboardInitial = ""
    keyboardShown = true
    keyboardOpened()
  }

  function hideKeyboard() {
    keyboardShown = false
    keyboardHiddenAt = Date.now()
  }

  function toggleKeyboard() {
    if (keyboardShown) { hideKeyboard(); return }
    if (Tv.assistantShown) { showKeyboard("assistant"); return }
    showKeyboard("app", imeActive && imePurpose === 8)
  }

  // Done on the keyboard: hand the text to whoever asked for it.
  function keyboardDone(text, submit) {
    var target = keyboardTarget
    hideKeyboard()
    if (!text.length && !submit) return
    if (target === "assistant") { Assistant.ask(text); return }
    sendToApp(text, submit, keyboardApp)
  }

  // Type into the app in front. Prefer the input method (exact Unicode, into
  // the focused field); fall back to a virtual keyboard for apps without
  // text-input support. The field gets focus back a beat after the overlay
  // goes, so wait for that first.
  property string pendingText: ""
  property bool pendingSubmit: false
  property string pendingApp: ""
  // `forApp`: the app the text was meant for. If a different app (or an
  // overlay) is in front by the time it's ready, nothing is typed.
  function sendToApp(text, submit, forApp) {
    pendingText = text
    pendingSubmit = !!submit
    pendingApp = forApp || ""
    sendTimer.restart()
  }
  function stillFor(app) {
    return !!app && Tv.frontApp === app && !Tv.homeShown && !Tv.guideShown && !Tv.assistantShown && !keyboardShown
  }
  Timer {
    id: sendTimer
    interval: 350
    onTriggered: {
      var text = root.pendingText
      if (!root.stillFor(root.pendingApp)) {
        if (text.length) Tv.toast("Not typed: " + Tv.appFor(root.pendingApp).name + " is no longer in front", "warn")
        root.pendingText = ""
        return
      }
      if (text.length) {
        if (root.imeActive && ime.running) {
          ime.write("commit " + text.replace(/\\/g, "\\\\").replace(/\n/g, "\\n") + "\n")
        } else {
          Quickshell.execDetached(["wtype", "--", text])
        }
      }
      if (root.pendingSubmit) { root.enterApp = root.pendingApp; enterTimer.restart() }
      root.pendingText = ""
    }
  }
  property string enterApp: ""
  Timer { id: enterTimer; interval: 150; onTriggered: if (root.stillFor(root.enterApp)) Quickshell.execDetached(["wtype", "-k", "Return"]) }

  // Pop the keyboard up when a field gains focus in the app in front (not
  // right after the viewer dismissed it, and not for controller games).
  function onImeActivated() {
    if (Tv.settings.autoKeyboard === false) return
    if (keyboardShown || Tv.homeShown || Tv.guideShown || Tv.assistantShown) return
    if (!Tv.frontApp || Tv.appFor(Tv.frontApp).input === "gamepad") return
    if (Date.now() - keyboardHiddenAt < 1500) return
    showKeyboard("app", imePurpose === 8)
  }

  Process {
    id: build
    running: true
    command: [Tv.tvRoot + "/bin/omarchy-tv-build"]
    onExited: function(code) { if (code === 0) ime.running = true; else console.warn("tv-ime: build failed; keyboard will not pop up by itself") }
  }

  Process {
    id: ime
    command: [root.cacheDir + "/tv-ime"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        var parts = line.trim().split(/\s+/)
        if (parts[0] === "ready") root.imeReady = true
        else if (parts[0] === "active") {
          var was = root.imeActive
          root.imePurpose = parseInt(parts[1] || "0")
          root.imeActive = true
          if (!was) root.onImeActivated()
        } else if (parts[0] === "inactive") root.imeActive = false
        else if (parts[0] === "unavailable") console.warn("tv-ime: another input method owns the seat")
      }
    }
    // Restart it if it dies (compositor hiccup), but not in a tight loop.
    onExited: if (root.imeReady) imeRestart.restart()
  }
  Timer { id: imeRestart; interval: 3000; onTriggered: ime.running = true }

  // ------------------------------------------------------------ mouse mode
  property bool pointerForced: false
  property bool pointerKeys: false // arrows drive the pointer (remotes)

  function togglePointer(fromKeys) {
    if (Tv.homeShown || !Tv.frontApp) {
      Tv.toast("Mouse mode works inside apps")
      return
    }
    var on = !(pointerForced || appWantsPointer)
    if (!on && appWantsPointer) {
      // An app that wants the mouse: the toggle flips it back to the remote.
      pointerSuppressed = Tv.frontApp
      pointerForced = false
    } else {
      pointerSuppressed = ""
      pointerForced = on
    }
    setPointerKeys(pointerActive && !!fromKeys)
    Tv.toast(pointerActive
      ? (fromKeys ? "Mouse mode: arrows move, OK clicks, Menu right-clicks, Back leaves" : "Mouse mode: stick moves, A clicks, X right-clicks, right stick scrolls")
      : "Mouse mode off")
  }

  function setPointerKeys(on) {
    if (pointerKeys === on) return
    pointerKeys = on
    Hyprland.dispatch(on ? 'hl.dsp.submap("tv-pointer")' : 'hl.dsp.submap("reset")')
  }

  property string pointerSuppressed: ""
  readonly property bool appWantsPointer: !!Tv.frontApp && Tv.appFor(Tv.frontApp).input === "pointer" && pointerSuppressed !== Tv.frontApp
  readonly property bool overlayUp: Tv.homeShown || Tv.guideShown || Tv.assistantShown || keyboardShown
  readonly property bool pointerActive: !overlayUp && !!Tv.frontApp && (pointerForced || appWantsPointer)

  // Leaving the app (or opening an overlay) ends arrow-driven mouse mode.
  onPointerActiveChanged: if (!pointerActive) setPointerKeys(false)
  Connections {
    target: Tv
    function onFrontAppChanged() { root.pointerForced = false; root.setPointerKeys(false) }
  }

  // ------------------------------------------------------------ voice
  property bool talking: false
  property bool transcribing: false
  property string talkTarget: "app" // app | keyboard | assistant
  property string talkApp: ""       // the app in front when talking started
  property real talkStartedAt: 0
  property bool talkHeld: false
  property bool voiceAvailable: false
  signal heard(string text, string target)

  // A recorder left over from a shell that crashed mid-recording is stopped
  // as soon as the shell comes back.
  Component.onCompleted: Quickshell.execDetached([Tv.tvRoot + "/bin/omarchy-tv-voice", "cancel"])

  Process {
    id: voiceCheck
    running: true
    command: [Tv.tvRoot + "/bin/omarchy-tv-voice", "check"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.voiceAvailable = JSON.parse(text).available === true } catch (e) {} }
    }
  }

  // Tap: start, tap again: stop. Hold: talk while held.
  function talkPressed() {
    if (talking) { stopTalking(); return }
    startTalking()
    talkHeld = true
  }
  function talkReleased() {
    talkHeld = false
    if (talking && Date.now() - talkStartedAt > 600) stopTalking()
  }

  function startTalking(target) {
    if (!voiceAvailable) { Tv.toast("Voice needs Superwhisper", "warn"); return }
    if (talking || transcribing) return
    talkTarget = target || (keyboardShown ? "keyboard" : Tv.assistantShown ? "assistant" : (Tv.frontApp && !Tv.homeShown && !Tv.guideShown) ? "app" : "assistant")
    talking = true
    talkApp = Tv.frontApp
    talkStartedAt = Date.now()
    Quickshell.execDetached([Tv.tvRoot + "/bin/omarchy-tv-voice", "start"])
  }

  function stopTalking() {
    if (!talking) return
    talking = false
    transcribing = true
    voiceStop.running = true
  }

  function cancelTalking() {
    if (!talking) return
    talking = false
    Quickshell.execDetached([Tv.tvRoot + "/bin/omarchy-tv-voice", "cancel"])
  }

  Process {
    id: voiceStop
    command: [Tv.tvRoot + "/bin/omarchy-tv-voice", "stop"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.transcribing = false
        var r = {}
        try { r = JSON.parse(text) } catch (e) { r = { text: "", warning: "Superwhisper did not answer" } }
        var said = String(r.text || "").trim()
        if (!said) { Tv.toast(r.warning || "Didn't catch that", "warn"); return }
        root.deliver(said)
      }
    }
  }

  function deliver(said) {
    var target = talkTarget
    heard(said, target)
    if (target === "keyboard") return // the keyboard listens to heard()
    if (target === "assistant") { Assistant.show(); Assistant.ask(said); return }
    sendToApp(said, false, talkApp)
  }
}

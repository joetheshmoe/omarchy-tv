import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Omarchy TV shell. Four layer surfaces, each mapped only while it is needed:
//   Home   (top layer)      the 10-foot UI; unmapped while an app is in front
//   Guide  (overlay layer)  Home pressed inside an app
//   OSD    (overlay layer)  volume and output changes
//   Toast  (overlay layer)  short messages
// While an app is in front none of them exist on screen, so the shell costs
// the app nothing.
ShellRoot {
  id: shell

  readonly property var tvScreen: {
    var wanted = Quickshell.env("OMARCHY_TV_OUTPUT") || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (screens[i].name === wanted) return screens[i]
    return screens.length ? screens[0] : null
  }

  Binding { target: Theme; property: "screenHeight"; value: shell.tvScreen ? shell.tvScreen.height : 1080 }
  Binding { target: Theme; property: "zoom"; value: Tv.settings.zoom || 1.0 }
  Binding { target: Theme; property: "safe"; value: Tv.settings.safe === undefined ? 0.04 : Tv.settings.safe }

  // ------------------------------------------------------------------ Home
  PanelWindow {
    id: homeWindow
    screen: shell.tvScreen
    visible: Tv.homeShown
    color: Theme.backgroundDark
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "omarchy-tv-home"
    WlrLayershell.keyboardFocus: (Input.keyboardShown || Tv.assistantShown) ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

    Backdrop { anchors.fill: parent; dim: Tv.screen === "home" ? 0.74 : 0.88 }

    FocusScope {
      id: content
      anchors.fill: parent
      // Media keys on Home drive the app that was last in front.
      Keys.onPressed: function(e) {
        if (e.key === Qt.Key_MediaPlay || e.key === Qt.Key_MediaPause || e.key === Qt.Key_MediaTogglePlayPause) Tv.mediaKey("play-pause")
        else if (e.key === Qt.Key_MediaNext) Tv.mediaKey("next")
        else if (e.key === Qt.Key_MediaPrevious) Tv.mediaKey("previous")
        else if (e.key === Qt.Key_MediaStop) Tv.mediaKey("stop")
        else return
        e.accepted = true
      }
      anchors.leftMargin: Math.round(parent.width * (Theme.safe + 0.03))
      anchors.rightMargin: Math.round(parent.width * (Theme.safe + 0.03))
      anchors.topMargin: Math.round(parent.height * (Theme.safe + 0.015))
      anchors.bottomMargin: Math.round(parent.height * (Theme.safe + 0.01))
      focus: true

      HomeScreen {
        id: homeScreen
        anchors.fill: parent
        live: homeWindow.visible && Tv.screen === "home"
        visible: Tv.screen === "home"
        focus: Tv.screen === "home"
      }

      Loader {
        id: screenLoader
        anchors.fill: parent
        active: Tv.screen !== "home"
        focus: active
        sourceComponent: {
          switch (Tv.screen) {
          case "settings": return settingsScreen
          case "power": return powerScreen
          case "allapps": return allAppsScreen
          case "media": return mediaScreen
          case "omarchymenu": return omarchyMenuScreen
          case "addapp": return addAppScreen
          }
          return null
        }
        onLoaded: { item.focus = true; if (item.reset) item.reset() }
      }
    }

    Component { id: settingsScreen; SettingsScreen {} }
    Component { id: powerScreen; PowerScreen {} }
    Component { id: allAppsScreen; AllAppsScreen {} }
    Component { id: mediaScreen; MediaScreen {} }
    Component { id: omarchyMenuScreen; OmarchyMenuScreen {} }
    Component { id: addAppScreen; AddAppScreen {} }

    Splash {
      id: splash
      anchors.fill: parent
      visible: !!Tv.launching
      app: Tv.appFor(Tv.launching)
    }

    Tutorial {
      id: tutorial
      anchors.fill: parent
      visible: Tv.tutorialShown
      onFinished: Tv.finishTutorial()
      onVisibleChanged: if (visible) Qt.callLater(tutorial.reset); else Qt.callLater(homeWindow.refocus)
    }

    // Splash and screensaver take every key while they are up.
    Item {
      id: catcher
      anchors.fill: parent
      visible: splash.visible || Tv.ambient
      Ambient { anchors.fill: parent; visible: Tv.ambient }
      Keys.onPressed: function(e) {
        if (Tv.ambient) Tv.ambient = false
        else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Back || e.key === Qt.Key_Backspace) Tv.cancelLaunch()
        e.accepted = true
      }
    }

    function refocus() {
      if (tutorial.visible) { tutorial.forceActiveFocus(); return }
      if (catcher.visible) { catcher.forceActiveFocus(); return }
      if (Tv.screen === "home") homeScreen.forceActiveFocus()
      else if (screenLoader.item) screenLoader.item.forceActiveFocus()
    }
    onVisibleChanged: if (visible) Qt.callLater(refocus)
    Connections {
      target: Tv
      function onAmbientChanged() { Qt.callLater(homeWindow.refocus) }
      function onLaunchingChanged() { Qt.callLater(homeWindow.refocus) }
      function onScreenChanged() { Qt.callLater(homeWindow.refocus) }
    }
  }

  // Screensaver after a while on Home with nothing playing (apps that play
  // video hold an idle inhibitor, which this respects).
  IdleMonitor {
    enabled: Tv.homeShown && !Tv.launching && (Tv.settings.ambientMinutes || 0) > 0
    timeout: Math.max(60, (Tv.settings.ambientMinutes || 10) * 60)
    respectInhibitors: true
    onIsIdleChanged: if (isIdle && Tv.homeShown) Tv.ambient = true
  }

  // ------------------------------------------------------------------ Guide
  PanelWindow {
    id: guideWindow
    screen: shell.tvScreen
    visible: Tv.guideShown
    color: Theme.alpha(Theme.backgroundDark, 0.45)
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-tv-guide"
    WlrLayershell.keyboardFocus: Input.keyboardShown ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

    Guide { id: guide; anchors.fill: parent; focus: true }
    onVisibleChanged: if (visible) Qt.callLater(guide.reset)
  }

  // ------------------------------------------------------------------ Assistant
  PanelWindow {
    id: assistantWindow
    screen: shell.tvScreen
    visible: Tv.assistantShown
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-tv-assistant"
    WlrLayershell.keyboardFocus: Input.keyboardShown ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

    AssistantPanel { id: assistantPanel; anchors.fill: parent; focus: true }
    onVisibleChanged: if (visible) Qt.callLater(assistantPanel.reset)
    Connections {
      target: Input
      function onKeyboardShownChanged() { if (!Input.keyboardShown && assistantWindow.visible) Qt.callLater(assistantPanel.reset) }
    }
  }

  // ------------------------------------------------------------------ On-screen keyboard
  // A sheet along the bottom, over whatever is in front. Text goes into the
  // app's focused field (or the assistant) when you choose Send.
  PanelWindow {
    id: keyboardWindow
    screen: shell.tvScreen
    visible: Input.keyboardShown
    color: "transparent"
    anchors { bottom: true; left: true; right: true }
    implicitHeight: sheet.implicitHeight
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-tv-keyboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      id: sheet
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      implicitHeight: sheetColumn.implicitHeight + Theme.px(80)
      color: Theme.alpha(Theme.background, 0.98)
      Rectangle { anchors.top: parent.top; width: parent.width; height: Theme.px(2); color: Theme.popupBorder }

      Column {
        id: sheetColumn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.px(36)
        width: Math.min(parent.width - Theme.px(200), Theme.px(1300))
        spacing: Theme.px(20)
        Label {
          text: Input.keyboardTarget === "assistant" ? "Ask " + (Assistant.agentName || "the assistant")
              : ((Tv.frontApp || Tv.lastApp) ? "Typing into " + Tv.appFor(Tv.frontApp || Tv.lastApp).name : "Keyboard") + (Input.keyboardSecret ? " (password)" : "")
          size: 28
          strong: true
          color: Theme.dim
        }
        Keyboard {
          id: osk
          width: parent.width
          focus: true
          actions: true
          secret: Input.keyboardSecret
          doneLabel: Input.keyboardTarget === "assistant" ? "Ask" : "Send"
          placeholder: Input.keyboardTarget === "assistant" ? "Your question" : "Type, or choose Speak"
          onAccepted: function(text) { Input.keyboardDone(text, false) }
          onSubmitted: function(text) { Input.keyboardDone(text, Input.keyboardTarget !== "assistant") }
          onSpeak: { if (Input.talking) Input.stopTalking(); else Input.startTalking("keyboard") }
          onCancelled: { Input.cancelTalking(); Input.hideKeyboard() }
        }
      }
    }
    Connections {
      target: Input
      function onKeyboardOpened() { Qt.callLater(function() { osk.reset(Input.keyboardInitial) }) }
    }
  }

  // ------------------------------------------------------------------ Listening
  PanelWindow {
    screen: shell.tvScreen
    visible: Input.talking || Input.transcribing
    color: "transparent"
    anchors { bottom: true }
    margins { bottom: Input.keyboardShown ? keyboardWindow.implicitHeight + Theme.px(30) : Theme.px(80) }
    implicitWidth: Theme.px(560)
    implicitHeight: Theme.px(96)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-tv-listening"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Rectangle {
      anchors.fill: parent
      radius: Theme.round(height / 2)
      color: Theme.alpha(Theme.background, 0.96)
      border.width: Theme.px(3)
      border.color: Input.talking ? Theme.urgent : Theme.accent
      Row {
        anchors.centerIn: parent
        spacing: Theme.px(18)
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.px(22); height: width; radius: width / 2
          color: Input.talking ? Theme.urgent : Theme.accent
          SequentialAnimation on opacity {
            running: Input.talking || Input.transcribing
            loops: Animation.Infinite
            NumberAnimation { to: 0.3; duration: 500 }
            NumberAnimation { to: 1; duration: 500 }
          }
        }
        Label {
          anchors.verticalCenter: parent.verticalCenter
          text: Input.talking ? (Input.talkHeld ? "Listening… release to finish" : "Listening… press again to finish") : "Superwhisper is writing…"
          size: 26
          strong: true
        }
      }
    }
  }

  // ------------------------------------------------------------------ Mouse mode
  PanelWindow {
    screen: shell.tvScreen
    visible: Input.pointerActive
    color: "transparent"
    anchors { bottom: true; right: true }
    margins { bottom: Theme.px(40); right: Theme.px(40) }
    implicitWidth: Theme.px(460)
    implicitHeight: Theme.px(56)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-tv-pointer"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Rectangle {
      id: pointerPill
      anchors.right: parent.right
      width: pointerRow.implicitWidth + Theme.px(40)
      height: parent.height
      radius: Theme.round(height / 2)
      color: Theme.alpha(Theme.background, 0.85)
      opacity: 0.85
      Row {
        id: pointerRow
        anchors.centerIn: parent
        spacing: Theme.px(10)
        Glyph { text: "󰍽"; size: 24; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
        Label { text: Input.pointerKeys ? "Mouse mode · Back leaves" : "Mouse mode · Select leaves"; size: 20; color: Theme.dim; anchors.verticalCenter: parent.verticalCenter }
      }
    }
  }

  // ------------------------------------------------------------------ OSD
  PanelWindow {
    screen: shell.tvScreen
    visible: Tv.osdShown
    color: "transparent"
    anchors { top: true; right: true }
    margins { top: Theme.px(60); right: Theme.px(80) }
    implicitWidth: Theme.px(520)
    implicitHeight: Theme.px(110)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-tv-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Rectangle {
      anchors.fill: parent
      radius: Theme.round(height / 2)
      color: Theme.alpha(Theme.background, 0.94)
      border.width: Theme.px(2)
      border.color: Theme.popupBorder

      Glyph {
        id: osdGlyph
        anchors.left: parent.left
        anchors.leftMargin: Theme.px(34)
        anchors.verticalCenter: parent.verticalCenter
        text: Tv.osdKind === "output" ? "󰕾" : Tv.muted ? "󰖁" : Tv.volume > 0.5 ? "󰕾" : "󰖀"
        size: 40
        color: Tv.muted ? Theme.urgent : Theme.foreground
      }
      Rectangle {
        visible: Tv.osdKind === "volume"
        anchors.left: osdGlyph.right
        anchors.leftMargin: Theme.px(26)
        anchors.right: osdValue.left
        anchors.rightMargin: Theme.px(22)
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.px(12)
        radius: Theme.round(height / 2)
        color: Theme.alpha(Theme.foreground, 0.18)
        Rectangle {
          width: parent.width * (Tv.muted ? 0 : Tv.volume)
          height: parent.height
          radius: parent.radius
          color: Theme.accent
          Behavior on width { NumberAnimation { duration: 90 } }
        }
      }
      Label {
        id: osdValue
        visible: Tv.osdKind === "volume"
        anchors.right: parent.right
        anchors.rightMargin: Theme.px(36)
        anchors.verticalCenter: parent.verticalCenter
        text: Tv.muted ? "Muted" : Math.round(Tv.volume * 100)
        size: 30
        strong: true
      }
      Label {
        visible: Tv.osdKind === "output"
        anchors.left: osdGlyph.right
        anchors.leftMargin: Theme.px(24)
        anchors.right: parent.right
        anchors.rightMargin: Theme.px(36)
        anchors.verticalCenter: parent.verticalCenter
        text: Tv.sink ? (Tv.sink.description || Tv.sink.name) : ""
        size: 26
      }
    }
  }

  // ------------------------------------------------------------------ Toasts
  PanelWindow {
    screen: shell.tvScreen
    visible: Tv.toastsVisible && Tv.toasts.length > 0
    color: "transparent"
    anchors { top: true }
    margins { top: Theme.px(60) }
    // A fixed size: a surface sized by its content starts as a sliver the
    // compositor stretches, which flashes a solid block.
    implicitWidth: Theme.px(1000)
    implicitHeight: Theme.px(3 * 76 + 2 * 12)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-tv-toast"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Column {
      id: toastColumn
      width: parent.width
      spacing: Theme.px(12)
      Repeater {
        model: Tv.toasts
        delegate: Rectangle {
          required property var modelData
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(Theme.px(1000), toastText.implicitWidth + Theme.px(90))
          height: Theme.px(76)
          radius: Theme.round(height / 2)
          color: Theme.alpha(Theme.background, 0.95)
          border.width: Theme.px(2)
          border.color: modelData.kind === "error" ? Theme.urgent : modelData.kind === "warn" ? Theme.warn : Theme.popupBorder
          Label {
            id: toastText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, Theme.px(910))
            text: modelData.text
            size: 26
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------ keys from the compositor
  GlobalShortcut { appid: "omarchy-tv"; name: "home"; onPressed: Tv.homeKey() }
  GlobalShortcut { appid: "omarchy-tv"; name: "guide"; onPressed: Tv.guideKey() }
  GlobalShortcut { appid: "omarchy-tv"; name: "close"; onPressed: Tv.closeApp(Tv.frontApp || Tv.focusedApp, false) }
  GlobalShortcut { appid: "omarchy-tv"; name: "force-quit"; onPressed: Tv.closeApp(Tv.frontApp || Tv.focusedApp, true) }
  GlobalShortcut { appid: "omarchy-tv"; name: "next-app"; onPressed: Tv.nextApp() }
  GlobalShortcut { appid: "omarchy-tv"; name: "volume-up"; onPressed: Tv.changeVolume(0.05) }
  GlobalShortcut { appid: "omarchy-tv"; name: "volume-down"; onPressed: Tv.changeVolume(-0.05) }
  GlobalShortcut { appid: "omarchy-tv"; name: "mute"; onPressed: Tv.toggleMute() }
  GlobalShortcut { appid: "omarchy-tv"; name: "play-pause"; onPressed: Tv.mediaKey("play-pause") }
  GlobalShortcut { appid: "omarchy-tv"; name: "next"; onPressed: Tv.mediaKey("next") }
  GlobalShortcut { appid: "omarchy-tv"; name: "previous"; onPressed: Tv.mediaKey("previous") }
  GlobalShortcut { appid: "omarchy-tv"; name: "stop"; onPressed: Tv.mediaKey("stop") }
  GlobalShortcut { appid: "omarchy-tv"; name: "power"; onPressed: Tv.show("power") }
  GlobalShortcut { appid: "omarchy-tv"; name: "keyboard"; onPressed: Input.toggleKeyboard() }
  GlobalShortcut { appid: "omarchy-tv"; name: "pointer"; onPressed: Input.togglePointer(false) }
  GlobalShortcut { appid: "omarchy-tv"; name: "pointer-keys"; onPressed: Input.togglePointer(true) }
  GlobalShortcut { appid: "omarchy-tv"; name: "assistant"; onPressed: Tv.assistantShown ? Assistant.hide() : Assistant.show() }
  GlobalShortcut { appid: "omarchy-tv"; name: "talk"; onPressed: Input.talkPressed() }
  GlobalShortcut { appid: "omarchy-tv"; name: "talk-end"; onPressed: Input.talkReleased() }

  // ------------------------------------------------------------------ scripting
  // qs -p <shell> ipc call tv <fn> — for CEC bridges, phone remotes, tests.
  IpcHandler {
    target: "tv"
    function home(): void { Tv.homeKey() }
    function back(): void { Tv.back() }
    function open(id: string): void { Tv.open(Tv.appFor(id)) }
    function close(id: string): void { Tv.closeApp(id || Tv.frontApp, false) }
    function screen(name: string): void { Tv.show(name) }
    function volume(delta: real): void { Tv.changeVolume(delta) }
    function keyboard(): void { Input.toggleKeyboard() }
    function pointer(): void { Input.togglePointer(true) }
    function ask(question: string): void { Assistant.ask(question) }
    function assistant(): void { Assistant.show() }
    function talk(): void { Input.talkPressed() }
    function sfx(): string {
      var out = []
      for (var k in Sfx.players) out.push(k + ":" + Sfx.players[k].status)
      return Sfx.pack + " enabled=" + Sfx.enabled + " vol=" + Sfx.volume + " " + out.join(",")
    }
    function focus(): string { return "toggles=" + tutorial.togglesFocused + " page=" + tutorial.page + " tut=" + tutorial.activeFocus + " tutVis=" + tutorial.visible + " content=" + content.activeFocus + " home=" + homeScreen.activeFocus + " contentItem=" + homeWindow.contentItem + " focusItem=" + (homeWindow.contentItem ? homeWindow.contentItem.activeFocus : "?") }
    function state(): string {
      return JSON.stringify({ home: Tv.homeShown, guide: Tv.guideShown, screen: Tv.screen, front: Tv.frontApp, focused: Tv.focusedApp, last: Tv.lastApp,
                              launching: Tv.launching, running: Tv.running, keyboard: Input.keyboardShown, ime: Input.imeActive, imeReady: Input.imeReady, pointer: Input.pointerActive, mode: Tv.inputMode, assistant: Tv.assistantShown, agent: Assistant.agent, answer: Assistant.answer, busy: Assistant.busy, voice: Input.voiceAvailable, apps: Tv.apps.map(function(a) { return a.id }) })
    }
  }
}

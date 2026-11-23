import QtQuick
import qs.core
import "Nav.js" as Nav

// The guide: Home pressed inside an app slides this over it. Everything to
// leave, switch or close the app is one or two presses away.
FocusScope {
  id: guide

  readonly property string appId: Tv.focusedApp
  readonly property var app: Tv.appFor(appId)

  readonly property var items: {
    var list = [
      { key: "resume", label: "Back to " + app.name, glyph: "󰐊" },
      { key: "home", label: "Home", glyph: "󰋜", detail: "Press Home again to get here" }
    ]
    var others = Tv.running.filter(function(id) { return id !== guide.appId })
    if (others.length) list.push({ kind: "header", label: "Switch to" })
    for (var i = 0; i < others.length; i++) {
      var o = Tv.appFor(others[i])
      list.push({ key: "switch", id: others[i], label: o.name, glyph: o.glyph || "󰀻" })
    }
    list.push({ kind: "header", label: app.name })
    list.push({ key: "close", label: "Close " + app.name, glyph: "󰅖" })
    list.push({ key: "kill", label: "Force quit", glyph: "󰅜", danger: true, detail: "For an app that stopped responding" })
    list.push({ kind: "header", label: "Tools" })
    list.push({ key: "keyboard", label: "Keyboard", glyph: "\udb80\udf0c", detail: "L3 on a controller, Super+K" })
    list.push({ key: "pointer", kind: "toggle", label: "Mouse mode", glyph: "\udb80\udf7d", on: Input.pointerForced || Input.appWantsPointer, detail: "Select on a controller, Super+M" })
    if (Input.voiceAvailable) list.push({ key: "dictate", label: "Dictate", glyph: "\udb80\udf6c", detail: "Speak into the app · hold R3 anywhere" })
    if (Assistant.agent) list.push({ key: "ask", label: "Ask " + Assistant.agentName, glyph: "\udb81\udea9", detail: "Hold Guide anywhere" })
    list.push({ kind: "header", label: "Sound" })
    list.push({ key: "volume", kind: "slider", label: "Volume", glyph: Tv.muted ? "󰖁" : "󰕾", level: Tv.volume, detail: Tv.muted ? "Muted" : Math.round(Tv.volume * 100) + "%" })
    list.push({ key: "mute", kind: "toggle", label: "Mute", glyph: "󰖁", on: Tv.muted })
    list.push({ kind: "header", label: "System" })
    list.push({ key: "power", label: "Power", glyph: "󰐥" })
    return list
  }

  function reset() { menu.currentIndex = 0; menu.forceActiveFocus() }

  Rectangle {
    id: panel
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    width: Theme.px(640)
    color: Theme.alpha(Theme.background, 0.97)

    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Theme.px(2)
      color: Theme.popupBorder
    }

    Row {
      id: head
      x: Theme.px(48)
      y: Theme.px(56)
      spacing: Theme.px(20)
      Rectangle {
        width: Theme.px(84); height: width; radius: Theme.r(18)
        gradient: Gradient {
          GradientStop { position: 0; color: Theme.resolve((guide.app.colors || ["surface"])[0]) }
          GradientStop { position: 1; color: Theme.resolve((guide.app.colors || ["surface", "#101010"])[1] || "#101010") }
        }
        Glyph { anchors.centerIn: parent; text: guide.app.glyph || "󰀻"; size: 44; color: "white" }
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Label { text: guide.app.name; size: 38; strong: true; width: Theme.px(420) }
        Label { text: "Playing now"; size: 22; color: Theme.dim }
      }
    }

    MenuList {
      id: menu
      anchors.top: head.bottom
      anchors.topMargin: Theme.px(34)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Theme.px(36)
      anchors.rightMargin: Theme.px(36)
      anchors.bottomMargin: Theme.px(40)
      rowHeight: 78
      focus: true
      items: guide.items
      onActivated: function(item) {
        if (item.key === "resume") Tv.resume(guide.appId)
        else if (item.key === "home") Tv.goHome()
        else if (item.key === "switch") Tv.resume(item.id)
        else if (item.key === "close") Tv.closeApp(guide.appId, false)
        else if (item.key === "kill") Tv.closeApp(guide.appId, true)
        else if (item.key === "mute") Tv.toggleMute()
        else if (item.key === "power") Tv.show("power")
        else if (item.key === "keyboard") { Tv.guideShown = false; Input.showKeyboard("app", Input.imeActive && Input.imePurpose === 8) }
        else if (item.key === "pointer") {
          Tv.guideShown = false
          // Once the guide is gone the toggle sees the app; from a remote,
          // arrows drive the pointer.
          Qt.callLater(function() { Input.togglePointer(true) })
        }
        else if (item.key === "dictate") { Tv.guideShown = false; Qt.callLater(function() { Input.startTalking("app") }) }
        else if (item.key === "ask") Assistant.show()
      }
      onAdjust: function(item, step) { if (item.key === "volume") Tv.changeVolume(step * 0.05) }
      Keys.onPressed: function(e) {
        if (Nav.isBack(e) || Nav.isMenu(e)) { Tv.guideShown = false; e.accepted = true }
      }
    }
  }
}

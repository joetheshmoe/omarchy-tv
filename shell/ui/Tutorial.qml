import QtQuick
import qs.core
import "Nav.js" as Nav

// First run: a few screens on how the TV works, ending with whether it
// should open by itself at login and after sleep. Right/OK goes on, Left/Back
// goes back. Settings › About shows it again.
FocusScope {
  id: tut

  property int page: 0
  readonly property bool togglesFocused: toggles.activeFocus
  signal finished()

  readonly property var pages: [
    {
      glyph: "󰔂", title: "Your PC is a console now",
      body: "Omarchy TV turns this machine into a living-room media station: streaming, music, games and your Omarchy apps, all driven from the couch with a remote, a controller or a keyboard.",
      rows: [["󰐊", "Every app opens full screen in its own container"], ["󰅖", "Closing an app always closes all of it"], ["󰏘", "It wears your Omarchy theme, live"]]
    },
    {
      glyph: "󰊗", title: "Getting around",
      body: "Arrows to move, OK to open, Back to go back. On Home, Back jumps to the app you were just in.",
      rows: [["󰊗", "Controller: D-pad or stick, A to open, B to go back"], ["󰄞", "Remote: arrows, OK, Back, Home"], ["󰌌", "Keyboard: arrows, Enter, Esc, tap Super for Home"]]
    },
    {
      glyph: "󰋜", title: "Home and the guide",
      body: "Press Home inside any app and the guide slides in: switch apps, close one, force quit one that's stuck, change the volume. Press Home again to go all the way Home.",
      rows: [["󰋜", "Home / Guide button / Super: the guide"], ["󰅖", "Super+Q closes the app in front"], ["󰐥", "Power: sleep, restart, or back to the desktop"]]
    },
    {
      glyph: "󰚩", title: "Type, point, talk",
      body: "Text fields bring up the on-screen keyboard by themselves. Apps that want a mouse get one on the stick.",
      rows: [["󰌌", "Keyboard: L3, or Super+K"], ["󰍽", "Mouse mode: Select, or Super+M"], ["󰍬", "Talk (Superwhisper): hold R3, or hold Super+T"], ["󰚩", "Ask your Omarchy agent: hold Guide, or Super+A"]]
    },
    {
      glyph: "󰆾", title: "Make it yours",
      body: "Everything on Home can move. Press Menu on any tile.",
      rows: [["󰆾", "Move: carry a tile anywhere, across rows"], ["󰐕", "Add to Home: apps, websites, terminal programs"], ["󰇚", "Install: Omarchy's install menu, right here"], ["󰒓", "Settings › Advanced: Omarchy Control"]]
    },
    { glyph: "󰍹", title: "Start like a console", body: "Have Omarchy TV take over the screen by itself. You can change this in Settings › Display.", toggles: true }
  ]
  readonly property var current: pages[page]

  readonly property var toggleItems: [
    { key: "login", kind: "toggle", label: "Open when I log in", glyph: "󰐥", on: !!Tv.settings.startOnLogin, detail: "Boot straight into the TV" },
    { key: "wake", kind: "toggle", label: "Open when it wakes from sleep", glyph: "󰒲", on: !!Tv.settings.startOnWake, detail: "Pick up the remote, press a key, you're on the TV" },
    { key: "done", label: "Start watching", glyph: "󰐊" }
  ]

  function reset() { page = 0; forceActiveFocus() }
  function nextPage() { if (page < pages.length - 1) page++; else finished() }
  function prevPage() { if (page > 0) page-- }

  // The toggle list becomes visible with the page; focus it once it is.
  onPageChanged: if (pages[page].toggles) focusToggles.restart(); else tut.forceActiveFocus()
  Timer { id: focusToggles; interval: 30; onTriggered: { toggles.currentIndex = 0; toggles.forceActiveFocus() } }

  Keys.onPressed: function(e) {
    if (e.key === Qt.Key_Right || Nav.isSelect(e)) { nextPage(); e.accepted = true }
    else if (e.key === Qt.Key_Left || Nav.isBack(e)) { prevPage(); e.accepted = true }
    else if (Nav.isMenu(e)) { finished(); e.accepted = true }
  }

  Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.backgroundDark, 0.94) }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - Theme.px(200), Theme.px(1240))
    height: column.implicitHeight + Theme.px(120)
    color: Theme.background
    radius: Theme.r(18)
    border.width: Theme.px(2)
    border.color: Theme.popupBorder

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.px(60)
      spacing: Theme.px(26)

      Row {
        spacing: Theme.px(24)
        Glyph { text: tut.current.glyph; size: 64; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
        Label { text: tut.current.title; size: 54; strong: true; anchors.verticalCenter: parent.verticalCenter }
      }
      Label {
        width: parent.width
        text: tut.current.body
        size: 30
        color: Theme.dim
        wrapMode: Text.WordWrap
      }

      Column {
        visible: !tut.current.toggles
        width: parent.width
        spacing: Theme.px(14)
        topPadding: Theme.px(10)
        Repeater {
          model: tut.current.rows || []
          delegate: Row {
            required property var modelData
            spacing: Theme.px(20)
            Glyph { width: Theme.px(44); text: modelData[0]; size: 30; color: Theme.activeBorder; anchors.verticalCenter: parent.verticalCenter }
            Label { text: modelData[1]; size: 28; anchors.verticalCenter: parent.verticalCenter }
          }
        }
      }

      MenuList {
        id: toggles
        visible: !!tut.current.toggles
        width: parent.width
        height: visible ? Theme.px(3 * 92) : 0
        items: tut.toggleItems
        onActivated: function(item) {
          if (item.key === "done") { tut.finished(); return }
          Tv.setSetting(item.key === "login" ? "startOnLogin" : "startOnWake", !item.on)
          Tv.syncAutostart()
        }
        Keys.onPressed: function(e) {
          if (e.key === Qt.Key_Left || Nav.isBack(e)) { tut.prevPage(); e.accepted = true }
        }
      }

      // Progress and hints
      Item {
        width: parent.width
        height: Theme.px(44)
        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.px(12)
          Repeater {
            model: tut.pages.length
            delegate: Rectangle {
              required property int index
              width: index === tut.page ? Theme.px(40) : Theme.px(14)
              height: Theme.px(14)
              radius: Theme.round(height / 2)
              color: index === tut.page ? Theme.activeBorder : Theme.alpha(Theme.foreground, 0.25)
              Behavior on width { NumberAnimation { duration: 140 } }
            }
          }
        }
        Label {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: tut.current.toggles ? "OK toggles · Back: previous" : "OK / Right: next · Left: back · Menu: skip"
          size: 22
          color: Theme.muted
        }
      }
    }
  }
}

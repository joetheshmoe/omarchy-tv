import QtQuick
import qs.core
import "Nav.js" as Nav

// Power: sleep, leave the TV, restart, shut down. The last two ask first.
FocusScope {
  id: power
  property string confirm: ""

  readonly property var items: confirm ? [
    { kind: "header", label: confirm === "reboot" ? "Restart the computer?" : "Shut down the computer?" },
    { key: "yes", label: confirm === "reboot" ? "Restart" : "Shut down", glyph: "󰐥", danger: true, detail: Tv.running.length ? Tv.running.length + " open app(s) will close" : "" },
    { key: "no", label: "Cancel", glyph: "󰅖" }
  ] : [
    { key: "suspend", label: "Sleep", glyph: "󰒲", detail: "Any key on the remote wakes it" },
    { key: "exit", label: "Leave TV mode", glyph: "󰍃", detail: "Close TV apps and return to the desktop" },
    { key: "lock", label: "Lock", glyph: "󰌾", detail: "Locks the desktop session too" },
    { key: "reboot", label: "Restart", glyph: "󰜉" },
    { key: "shutdown", label: "Shut down", glyph: "󰐥", danger: true }
  ]

  function reset() { confirm = ""; menu.currentIndex = 0; menu.forceActiveFocus() }

  ScreenHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: "Power"
    glyph: "󰐥"
  }

  MenuList {
    id: menu
    anchors.top: header.bottom
    anchors.topMargin: Theme.px(40)
    anchors.horizontalCenter: parent.horizontalCenter
    width: Theme.px(860)
    height: Theme.px(700)
    focus: true
    items: power.items
    onActivated: function(item) {
      if (item.key === "reboot" || item.key === "shutdown") { power.confirm = item.key; return }
      if (item.key === "no") { power.confirm = ""; return }
      if (item.key === "yes") { Tv.power(power.confirm); power.confirm = ""; return }
      Tv.power(item.key)
    }
    Keys.onPressed: function(e) {
      if (Nav.isBack(e)) {
        if (power.confirm) power.confirm = ""
        else Tv.back()
        e.accepted = true
      }
    }
  }
}

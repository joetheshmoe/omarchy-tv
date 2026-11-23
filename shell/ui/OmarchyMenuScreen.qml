import QtQuick
import Quickshell.Io
import qs.core
import "Nav.js" as Nav

// Omarchy's own menu, from the couch: the same rows as Super+Alt+Space
// (Install, Remove, ...), read from the same files, with the same checks for
// what's installed. Picking a row runs its action in the TV.
FocusScope {
  id: screen

  property var stack: [] // routes walked into
  property string route: Tv.screenArgs.route || "install"
  property string title: ""
  property var items: []
  property bool loading: true

  // Shown again with new arguments (Settings › Install vs › Remove).
  Connections { target: Tv; function onScreenArgsChanged() { Qt.callLater(screen.reset) } }

  function reset() { stack = []; load(Tv.screenArgs.route || "install"); menu.forceActiveFocus() }

  function load(r) {
    route = r
    loading = true
    lister.command = [Tv.tvRoot + "/bin/omarchy-tv-menu", "list", r]
    lister.running = true
  }

  Process {
    id: lister
    stdout: StdioCollector {
      onStreamFinished: {
        screen.loading = false
        try {
          var data = JSON.parse(text)
          screen.title = data.title
          screen.items = data.items
        } catch (e) { screen.items = [] }
        menu.currentIndex = 0
      }
    }
  }

  readonly property var rows: items.map(function(it) {
    return {
      key: it.submenu ? "open" : "run",
      item: it,
      label: it.label,
      glyph: it.icon,
      glyphFont: it.iconFont || "",
      detail: it.description || "",
      value: it.disabled ? "Installed ✓" : it.checked ? "✓" : it.submenu ? "›" : "",
      enabled: !it.disabled
    }
  })

  ScreenHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: screen.title || "Omarchy"
    glyph: "󰔂"
  }

  Label {
    id: crumb
    anchors.top: header.bottom
    anchors.left: parent.left
    text: "Omarchy menu › " + screen.route.split(".").join(" › ")
    size: 22
    color: Theme.muted
  }

  MenuList {
    id: menu
    anchors.top: crumb.bottom
    anchors.topMargin: Theme.px(26)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    width: Math.min(parent.width, Theme.px(1200))
    focus: true
    items: screen.rows
    onActivated: function(row) {
      if (row.key === "open") {
        screen.stack = screen.stack.concat([screen.route])
        screen.load(row.item.route)
      } else {
        Tv.runMenuAction(row.item)
      }
    }
    Keys.onPressed: function(e) {
      if (Nav.isBack(e)) {
        if (screen.stack.length) {
          var prev = screen.stack[screen.stack.length - 1]
          screen.stack = screen.stack.slice(0, -1)
          screen.load(prev)
        } else Tv.back()
        e.accepted = true
      }
    }
  }

  Label {
    anchors.centerIn: menu
    visible: screen.loading || (!screen.items.length)
    text: screen.loading ? "Loading…" : "Nothing here"
    size: 30
    color: Theme.dim
  }
}

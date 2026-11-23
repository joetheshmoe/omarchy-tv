import QtQuick
import qs.core
import "Nav.js" as Nav

// Every app in the launcher, as a grid. Each runs in its own scope like the
// TV apps, scaled up for the couch. Up from the top row (or just typing)
// searches.
FocusScope {
  id: all
  property string query: ""
  property bool searching: false

  readonly property var results: {
    var q = query.trim().toLowerCase()
    var list = Tv.desktopApps
    if (!q) return list
    return list.filter(function(a) { return a.name.toLowerCase().indexOf(q) >= 0 || String(a.blurb).toLowerCase().indexOf(q) >= 0 })
  }

  function reset() { query = ""; searching = false; grid.currentIndex = 0; grid.forceActiveFocus() }
  function startSearch() { searching = true; keyboard.reset(query) }

  ScreenHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: all.query ? "“" + all.query + "”" : "All apps"
    glyph: "󰀻"
    hint: "Menu: add to Home · Up: search · Back: return"
  }

  GridView {
    id: grid
    anchors.top: header.bottom
    anchors.topMargin: Theme.px(40)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Theme.px(12)
    cellWidth: Theme.px(220 + 42)
    cellHeight: Theme.px(140 + 46)
    focus: true
    clip: false
    interactive: false
    keyNavigationEnabled: true
    model: all.results
    highlightMoveDuration: 150
    highlightRangeMode: GridView.ApplyRange
    preferredHighlightBegin: Theme.px(20)
    preferredHighlightEnd: height - Theme.px(200)
    reuseItems: true
    cacheBuffer: Theme.px(400)

    delegate: Tile {
      required property var modelData
      required property int index
      compact: true
      app: modelData
      focused: GridView.isCurrentItem && grid.activeFocus
    }

    Keys.onPressed: function(e) {
      if (e.key === Qt.Key_Up && grid.currentIndex < Math.floor(grid.width / grid.cellWidth)) { all.startSearch(); e.accepted = true }
      else if (Nav.isSelect(e) && all.results[grid.currentIndex]) { Tv.open(all.results[grid.currentIndex]); e.accepted = true }
      else if (Nav.isMenu(e) && all.results[grid.currentIndex]) {
        // Put it on Home: straight to choosing the row.
        Tv.show("addapp", { preset: all.results[grid.currentIndex] }); e.accepted = true
      }
      else if (Nav.isBack(e)) {
        if (all.query) { all.query = ""; grid.currentIndex = 0 } else Tv.back()
        e.accepted = true
      }
      else if (e.text && /^[a-z0-9]$/i.test(e.text) && !(e.modifiers & Qt.ControlModifier)) {
        all.startSearch(); keyboard.type(e.text); e.accepted = true
      }
    }
  }

  Label {
    anchors.centerIn: grid
    visible: all.results.length === 0
    text: "Nothing matches “" + all.query + "”"
    size: 34
    color: Theme.dim
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -Theme.px(200)
    visible: all.searching
    color: Theme.alpha(Theme.backgroundDark, 0.9)
    Keyboard {
      id: keyboard
      anchors.centerIn: parent
      width: Theme.px(1200)
      live: true
      placeholder: "Search apps"
      onEdited: function(text) { all.query = text; grid.currentIndex = 0 }
      onAccepted: function(text) { all.query = text; all.searching = false; grid.forceActiveFocus() }
      onCancelled: { all.searching = false; grid.forceActiveFocus() }
    }
  }
}

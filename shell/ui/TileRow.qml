import QtQuick
import qs.core
import "Nav.js" as Nav

// A titled, horizontally scrolling row of tiles. Left/Right move along it;
// Up/Down fall through to the list of rows.
FocusScope {
  id: row

  property var model: []
  property string title: ""
  property bool current: false
  property string liftedId: "" // the tile being moved
  property bool lifted: false  // the whole row is being moved
  property alias currentIndex: list.currentIndex
  readonly property var currentApp: model[list.currentIndex] || null

  signal activated(var app)
  signal menuRequested(var app)

  height: Theme.px(58) + Theme.px(180) + Theme.px(40)

  Label {
    id: heading
    x: Theme.px(40)
    text: row.lifted ? "⇅  " + row.title : row.title
    size: 30
    strong: true
    color: row.lifted ? Theme.accent : row.current ? Theme.foreground : Theme.dim
    opacity: row.current ? 1 : 0.75
  }

  ListView {
    id: list
    anchors.top: heading.bottom
    anchors.topMargin: Theme.px(18)
    anchors.left: parent.left
    anchors.right: parent.right
    height: Theme.px(180) + Theme.px(30)
    orientation: ListView.Horizontal
    spacing: Theme.px(34)
    focus: true
    clip: false
    model: row.model
    keyNavigationWraps: false
    boundsBehavior: Flickable.StopAtBounds
    interactive: false
    keyNavigationEnabled: true
    reuseItems: true
    cacheBuffer: Theme.px(400)
    highlightMoveDuration: 160
    highlightRangeMode: ListView.ApplyRange
    preferredHighlightBegin: Theme.px(40)
    preferredHighlightEnd: width - Theme.px(360)
    leftMargin: Theme.px(40)

    delegate: Tile {
      required property var modelData
      required property int index
      y: Theme.px(10)
      app: modelData
      focused: row.current && ListView.isCurrentItem
      lifted: row.liftedId === modelData.id
    }

    onCurrentIndexChanged: if (activeFocus) Sfx.play("move")

    Keys.onPressed: function(e) {
      if (Nav.isSelect(e)) { row.activated(row.currentApp); e.accepted = true }
      else if (Nav.isMenu(e)) { row.menuRequested(row.currentApp); e.accepted = true }
    }
  }
}

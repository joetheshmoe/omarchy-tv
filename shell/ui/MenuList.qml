import QtQuick
import qs.core
import "Nav.js" as Nav

// A vertical list for the remote: Up/Down to move, OK to pick, Left/Right to
// change a value. Items are plain objects:
//   { key, label, value?, glyph?, kind?: "action"|"toggle"|"slider"|"header",
//     on?: bool, level?: 0..1, enabled?: bool, danger?: bool, detail? }
// The owner reacts to activated(item) and adjust(item, step).
FocusScope {
  id: menu

  property var items: []
  property real rowHeight: 84
  // Keep showing which row is selected while focus is elsewhere (a category
  // list beside its page).
  property bool keepHighlight: false
  property alias currentIndex: list.currentIndex
  property alias list: list
  readonly property var currentItem: items[list.currentIndex] || null

  signal activated(var item)
  signal adjust(var item, int step)

  function selectable(i) { var it = items[i]; return it && it.kind !== "header" && it.enabled !== false }
  function step(dir) {
    var i = list.currentIndex + dir
    while (i >= 0 && i < items.length && !selectable(i)) i += dir
    if (i >= 0 && i < items.length) { if (i !== list.currentIndex) Sfx.play("move"); list.currentIndex = i }
  }
  onItemsChanged: if (!selectable(list.currentIndex)) { list.currentIndex = -1; step(1) }

  ListView {
    id: list
    anchors.fill: parent
    focus: true
    clip: true
    model: menu.items
    interactive: false
    spacing: Theme.px(8)
    highlightMoveDuration: 140
    highlightRangeMode: ListView.ApplyRange
    preferredHighlightBegin: height * 0.25
    preferredHighlightEnd: height * 0.75
    keyNavigationEnabled: false

    Keys.onPressed: function(e) {
      var it = menu.currentItem
      if (e.key === Qt.Key_Down) { menu.step(1); e.accepted = true }
      else if (e.key === Qt.Key_Up) { menu.step(-1); e.accepted = true }
      else if (e.key === Qt.Key_PageDown) { for (var i = 0; i < 6; i++) menu.step(1); e.accepted = true }
      else if (e.key === Qt.Key_PageUp) { for (var j = 0; j < 6; j++) menu.step(-1); e.accepted = true }
      else if (it && (e.key === Qt.Key_Left || e.key === Qt.Key_Right) && (it.kind === "slider" || it.kind === "choice")) {
        Sfx.play("toggle"); menu.adjust(it, e.key === Qt.Key_Right ? 1 : -1); e.accepted = true
      }
      else if (it && Nav.isSelect(e)) { Sfx.play(it.kind === "toggle" ? "toggle" : "select"); menu.activated(it); e.accepted = true }
    }

    delegate: Item {
      id: rowItem
      required property var modelData
      required property int index
      readonly property bool header: modelData.kind === "header"
      readonly property bool current: ListView.isCurrentItem && menu.activeFocus
      readonly property bool selected: ListView.isCurrentItem && !menu.activeFocus && menu.keepHighlight
      width: list.width
      height: header ? Theme.px(62) : Theme.px(menu.rowHeight)

      Label {
        visible: rowItem.header
        anchors.left: parent.left
        anchors.leftMargin: Theme.px(8)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.px(8)
        text: rowItem.modelData.label || ""
        size: 22
        strong: true
        color: Theme.accent
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.px(2)
      }

      Rectangle {
        id: plate
        visible: !rowItem.header
        anchors.fill: parent
        radius: Theme.r(14)
        // Omarchy's control states: a tinted fill and the active border for
        // focus, a quiet outline otherwise.
        color: rowItem.current ? Theme.alpha(Theme.activeBorder, Math.max(0.28, Theme.selectedFill + 0.1)) : rowItem.selected ? Theme.alpha(Theme.activeBorder, Theme.selectedFill) : Theme.alpha(Theme.surface, 0.55)
        border.width: rowItem.current ? Theme.px(3) : rowItem.selected ? Theme.px(2) : Theme.px(1)
        border.color: rowItem.current || rowItem.selected ? Theme.activeBorder : Theme.alpha(Theme.foreground, 0.1)
        opacity: rowItem.modelData.enabled === false ? 0.45 : 1
        Behavior on color { ColorAnimation { duration: 100 } }

        readonly property color ink: rowItem.modelData.danger ? Theme.urgent : Theme.foreground

        Glyph {
          id: g
          visible: !!rowItem.modelData.glyph
          anchors.left: parent.left
          anchors.leftMargin: Theme.px(24)
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.px(40)
          text: rowItem.modelData.glyph || ""
          font.family: rowItem.modelData.glyphFont || Theme.glyphFont
          size: 30
          color: plate.ink
        }
        Column {
          anchors.left: g.visible ? g.right : parent.left
          anchors.leftMargin: Theme.px(g.visible ? 18 : 26)
          anchors.right: value.left
          anchors.rightMargin: Theme.px(16)
          anchors.verticalCenter: parent.verticalCenter
          Label {
            width: parent.width
            text: rowItem.modelData.label || ""
            size: 28
            strong: rowItem.current
            color: plate.ink
          }
          Label {
            visible: !!rowItem.modelData.detail
            width: parent.width
            text: rowItem.modelData.detail || ""
            size: 20
            color: plate.ink
            opacity: 0.7
          }
        }

        Item {
          id: value
          anchors.right: parent.right
          anchors.rightMargin: Theme.px(24)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(toggle.visible ? toggle.width : 0, slider.visible ? slider.implicitWidth : 0, valueRow.visible ? valueRow.implicitWidth : 0)
          height: parent.height

          // toggle
          Rectangle {
            id: toggle
            anchors.right: parent.right
            visible: rowItem.modelData.kind === "toggle"
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.px(76); height: Theme.px(40); radius: Theme.round(height / 2)
            color: rowItem.modelData.on ? Theme.accent : Theme.alpha(plate.ink, 0.25)
            Rectangle {
              width: Theme.px(30); height: width; radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              x: rowItem.modelData.on ? parent.width - width - Theme.px(5) : Theme.px(5)
              color: "white"
              Behavior on x { NumberAnimation { duration: 120 } }
            }
          }
          // slider
          Row {
            id: slider
            anchors.right: parent.right
            visible: rowItem.modelData.kind === "slider"
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(16)
            Glyph { text: ""; size: 26; color: plate.ink; opacity: rowItem.current ? 1 : 0 }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(Theme.px(300), plate.width * 0.3); height: Theme.px(10); radius: Theme.round(height / 2)
              color: Theme.alpha(plate.ink, 0.25)
              Rectangle {
                width: parent.width * Math.max(0, Math.min(1, rowItem.modelData.level || 0))
                height: parent.height; radius: parent.radius
                color: Theme.activeBorder
              }
            }
            Glyph { text: ""; size: 26; color: plate.ink; opacity: rowItem.current ? 1 : 0 }
          }
          // value / choice
          Row {
            id: valueRow
            anchors.right: parent.right
            visible: rowItem.modelData.value !== undefined && rowItem.modelData.value !== "" && rowItem.modelData.kind !== "toggle"
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.px(12)
            Glyph { visible: rowItem.modelData.kind === "choice"; text: ""; size: 26; color: plate.ink; opacity: rowItem.current ? 1 : 0 }
            Label {
              text: String(rowItem.modelData.value === undefined ? "" : rowItem.modelData.value)
              size: 26
              color: plate.ink
              opacity: 0.85
            }
            Glyph { visible: rowItem.modelData.kind === "choice"; text: ""; size: 26; color: plate.ink; opacity: rowItem.current ? 1 : 0 }
          }
        }
      }
    }
  }
}

import QtQuick
import qs.core

// Title of a full screen, with the hint for getting back.
Item {
  property string title: ""
  property string glyph: ""
  property string hint: "Back to return"
  height: Theme.px(110)

  Row {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.px(22)
    Glyph { visible: !!glyph; text: glyph; size: 52; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
    Label { text: title; size: 56; strong: true; anchors.verticalCenter: parent.verticalCenter }
  }
  Label {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: hint
    size: 22
    color: Theme.muted
  }
}

import QtQuick
import Quickshell
import qs.core

// One app on Home: a colored card with the app's glyph (or icon) and name.
// Focus grows it and rings it in the theme accent; nothing else animates.
Item {
  id: tile

  property var app: ({})
  property bool focused: false
  property bool compact: false
  property bool lifted: false // being moved
  readonly property bool running: Tv.isRunning(app.id)
  readonly property bool launching: Tv.launching === app.id
  readonly property var colors: (app.colors || ["surface", "#101010"]).map(function(c) { return Theme.resolve(c) })
  readonly property string iconSource: app.icon ? Quickshell.iconPath(app.icon, true) : ""

  signal activated()

  width: Theme.px(compact ? 220 : 320)
  height: Theme.px(compact ? 140 : 180)
  z: focused ? 2 : 1

  Item {
    id: card
    anchors.fill: parent
    scale: tile.lifted ? 1.16 : tile.focused ? 1.1 : 1.0
    rotation: tile.lifted ? -2 : 0
    Behavior on rotation { NumberAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // Focus ring sits outside the card so the art never shifts.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -Theme.px(6)
      radius: Theme.r(20)
      color: "transparent"
      border.width: Theme.px(4)
      border.color: tile.lifted ? Theme.accent : Theme.activeBorder
      opacity: tile.focused || tile.lifted ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Rectangle {
      id: face
      anchors.fill: parent
      radius: Theme.r(14)
      clip: true
      gradient: Gradient {
        orientation: Gradient.Vertical
        GradientStop { position: 0; color: tile.colors[0] }
        GradientStop { position: 1; color: tile.colors[1] || tile.colors[0] }
      }

      Glyph {
        visible: !tile.iconSource
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Theme.px(tile.compact ? 14 : 18)
        text: tile.app.glyph || "󰀻"
        size: tile.compact ? 56 : 76
        color: "white"
      }

      Image {
        visible: !!tile.iconSource
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Theme.px(tile.compact ? 14 : 18)
        source: tile.iconSource
        width: Theme.px(tile.compact ? 64 : 84)
        height: width
        sourceSize.width: width
        sourceSize.height: width
        asynchronous: true
        cache: true
        smooth: true
      }

      Label {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.px(14)
        horizontalAlignment: Text.AlignHCenter
        text: tile.app.name || ""
        size: tile.compact ? 21 : 25
        strong: true
        color: "white"
      }

      // Running: a dot. Launching: the dot breathes.
      Rectangle {
        visible: tile.running || tile.launching
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.px(14)
        width: Theme.px(14)
        height: width
        radius: width / 2
        color: tile.launching ? Theme.warn : Theme.good
        SequentialAnimation on opacity {
          running: tile.launching
          loops: Animation.Infinite
          NumberAnimation { to: 0.25; duration: 500 }
          NumberAnimation { to: 1; duration: 500 }
        }
      }
    }
  }
}

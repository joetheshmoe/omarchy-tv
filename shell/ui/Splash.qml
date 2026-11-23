import QtQuick
import qs.core

// Shown while an app starts, so the viewer sees the app's own colors instead
// of a browser painting itself. Back cancels.
Rectangle {
  id: splash
  property var app: ({})
  readonly property var colors: (app.colors || ["surface", "#101010"]).map(function(c) { return Theme.resolve(c) })

  gradient: Gradient {
    GradientStop { position: 0; color: splash.colors[0] }
    GradientStop { position: 1; color: splash.colors[1] || splash.colors[0] }
  }

  Column {
    anchors.centerIn: parent
    spacing: Theme.px(30)
    Glyph {
      anchors.horizontalCenter: parent.horizontalCenter
      text: splash.app.glyph || "󰀻"
      size: 180
      color: "white"
      SequentialAnimation on opacity {
        running: splash.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
      }
    }
    Label {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Opening " + (splash.app.name || "") + "…"
      size: 40
      strong: true
      color: "white"
    }
    Label {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Back to cancel"
      size: 22
      color: "white"
      opacity: 0.7
    }
  }
}

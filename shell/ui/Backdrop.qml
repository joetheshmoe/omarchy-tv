import QtQuick
import qs.core

// The current Omarchy wallpaper, decoded once at screen size and darkened so
// text stays readable from across the room. No blur: it costs a pass per frame.
Item {
  id: backdrop
  property real dim: 0.72

  Rectangle { anchors.fill: parent; color: Theme.backgroundDark }

  Image {
    id: wall
    anchors.fill: parent
    // The symlink keeps its name when the background changes, so a query
    // string tied to the theme generation makes Qt read it again.
    source: "file://" + Theme.backgroundPath + "?g=" + Theme.generation
    sourceSize.width: backdrop.width
    sourceSize.height: backdrop.height
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    smooth: true
    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 400 } }
  }

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: Theme.alpha(Theme.backgroundDark, backdrop.dim - 0.12) }
      GradientStop { position: 0.45; color: Theme.alpha(Theme.backgroundDark, backdrop.dim) }
      GradientStop { position: 1.0; color: Theme.alpha(Theme.backgroundDark, Math.min(1, backdrop.dim + 0.2)) }
    }
  }
}

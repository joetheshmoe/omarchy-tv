import QtQuick
import qs.core

// A Nerd Font icon.
Text {
  textFormat: Text.PlainText
  property real size: 32
  font.family: Theme.glyphFont
  font.pixelSize: Theme.px(size)
  color: Theme.foreground
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
  renderType: Text.NativeRendering
}

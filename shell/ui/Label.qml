import QtQuick
import qs.core

Text {
  property real size: 28
  property bool strong: false
  font.family: Theme.font
  font.pixelSize: Theme.px(size)
  font.weight: strong ? Font.DemiBold : Font.Normal
  color: Theme.foreground
  elide: Text.ElideRight
  renderType: Text.NativeRendering
}

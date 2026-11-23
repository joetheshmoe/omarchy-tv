import QtQuick
import qs.Commons
import qs.Ui

// Omarchy TV on the Omarchy bar: left click opens the TV (or brings it back),
// right click closes it and every TV app.
BarWidget {
  id: root
  moduleName: "joetheshmoe.tv"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // This plugin folder is the Omarchy TV checkout itself.
  readonly property string tv: String(Qt.resolvedUrl("bin/omarchy-tv")).replace(/^file:\/\//, "")

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰔂"
    tooltipText: strings.t("tooltip")
    onPressed: function(mouseButton) {
      var quoted = "'" + root.tv.replace(/'/g, "'\\''") + "'"
      root.bar.run(quoted + (mouseButton === Qt.RightButton ? " stop" : " start"))
    }
  }
}

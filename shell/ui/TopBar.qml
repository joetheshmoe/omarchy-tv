import QtQuick
import Quickshell.Bluetooth
import Quickshell.Networking
import qs.core

// Clock and the few states worth seeing from the couch: what is playing,
// sound, Bluetooth and network.
Item {
  id: bar
  height: Theme.px(84)

  property bool live: true
  property date now: new Date()
  Timer {
    running: bar.live
    repeat: true
    triggeredOnStart: true
    // Wake on the minute, not every second.
    interval: (60 - new Date().getSeconds()) * 1000
    onTriggered: { bar.now = new Date(); interval = (60 - bar.now.getSeconds()) * 1000 + 50 }
  }

  readonly property bool btConnected: {
    var ds = Bluetooth.devices.values
    for (var i = 0; i < ds.length; i++) if (ds[i].connected) return true
    return false
  }
  readonly property var wifi: {
    var ds = Networking.devices.values
    for (var i = 0; i < ds.length; i++) if (ds[i].type === DeviceType.Wifi) return ds[i]
    return null
  }
  readonly property string netGlyph: {
    var ds = Networking.devices.values
    for (var i = 0; i < ds.length; i++) if (ds[i].connected && ds[i].type !== DeviceType.Wifi) return "󰈀"
    return wifi && wifi.connected ? "󰖩" : "󰖪"
  }

  Row {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.px(18)
    Glyph {
      anchors.verticalCenter: parent.verticalCenter
      text: "\udb81\udd02"
      size: 38
      color: Theme.accent
    }
    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: "Omarchy TV"
      size: 30
      strong: true
    }
  }

  Row {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.px(30)

    Row {
      visible: !!Tv.nowPlaying
      spacing: Theme.px(10)
      anchors.verticalCenter: parent.verticalCenter
      Glyph { text: "󰝚"; size: 26; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
      Label {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Theme.px(420))
        text: Tv.nowPlaying ? [Tv.nowPlaying.trackTitle, Tv.nowPlaying.trackArtist].filter(function(s) { return !!s }).join(" · ") : ""
        size: 24
        color: Theme.dim
      }
    }
    Glyph {
      anchors.verticalCenter: parent.verticalCenter
      text: Tv.muted ? "󰖁" : "󰕾"
      size: 30
      color: Tv.muted ? Theme.urgent : Theme.dim
    }
    Glyph {
      visible: bar.btConnected
      anchors.verticalCenter: parent.verticalCenter
      text: "󰂱"
      size: 30
      color: Theme.dim
    }
    Glyph {
      anchors.verticalCenter: parent.verticalCenter
      text: bar.netGlyph
      size: 30
      color: Theme.dim
    }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      Label {
        anchors.right: parent.right
        text: Qt.formatTime(bar.now, Qt.locale().timeFormat(Locale.ShortFormat))
        size: 40
        strong: true
      }
      Label {
        anchors.right: parent.right
        text: Qt.formatDate(bar.now, "dddd d MMMM")
        size: 20
        color: Theme.dim
      }
    }
  }
}

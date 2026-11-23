import QtQuick
import qs.core

// Screensaver: a dim clock that hops to a new spot every minute, so nothing
// burns into an OLED, and nothing animates between hops (no GPU work).
Rectangle {
  id: ambient
  color: "black"

  property date now: new Date()
  property real fx: 0.3
  property real fy: 0.4

  Timer {
    running: ambient.visible
    interval: 60000
    repeat: true
    triggeredOnStart: true
    onTriggered: { ambient.now = new Date(); ambient.fx = 0.1 + Math.random() * 0.55; ambient.fy = 0.1 + Math.random() * 0.6 }
  }

  Column {
    x: (ambient.width - width) * ambient.fx
    y: (ambient.height - height) * ambient.fy
    spacing: Theme.px(6)
    opacity: 0.55
    Label { text: Qt.formatTime(ambient.now, Qt.locale().timeFormat(Locale.ShortFormat)); size: 150; color: "white" }
    Label { text: Qt.formatDate(ambient.now, "dddd d MMMM"); size: 34; color: "white"; opacity: 0.8 }
    Label {
      visible: !!Tv.nowPlaying
      text: Tv.nowPlaying ? [Tv.nowPlaying.trackTitle, Tv.nowPlaying.trackArtist].filter(function(s) { return !!s }).join(" · ") : ""
      size: 28
      color: Theme.accent
    }
  }
}

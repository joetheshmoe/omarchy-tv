import QtQuick
import qs.core
import "Nav.js" as Nav

// Ask the agent: talk or type a question, read the answer from the couch.
// Left/Right pick an action, OK does it, Back closes.
FocusScope {
  id: panel

  property int index: 0
  readonly property var actions: {
    var list = []
    if (Input.voiceAvailable) list.push({ key: "talk", label: Input.talking ? "Stop" : "Talk", glyph: "󰍬" })
    list.push({ key: "type", label: "Type", glyph: "󰌌" })
    if (Assistant.agent) list.push({ key: "agent", label: "Open " + Assistant.agentName, glyph: "󰆍" })
    list.push({ key: "close", label: "Close", glyph: "󰅖" })
    return list
  }

  function reset() { index = 0; forceActiveFocus() }

  function activate(key) {
    if (key === "talk") { if (Input.talking) Input.stopTalking(); else Input.startTalking("assistant") }
    else if (key === "type") Input.showKeyboard("assistant")
    else if (key === "agent") { Assistant.hide(); Tv.open(Tv.appIndex["agent"] || { id: "agent" }) }
    else if (key === "close") Assistant.hide()
  }

  Keys.onPressed: function(e) {
    if (e.key === Qt.Key_Left) { Sfx.play("move"); index = Math.max(0, index - 1); e.accepted = true }
    else if (e.key === Qt.Key_Right) { Sfx.play("move"); index = Math.min(actions.length - 1, index + 1); e.accepted = true }
    else if (Nav.isSelect(e)) { Sfx.play("select"); activate(actions[index].key); e.accepted = true }
    else if (Nav.isBack(e)) { if (Input.talking) Input.cancelTalking(); else Assistant.hide(); e.accepted = true }
    else if (e.text && /^[a-z0-9]$/i.test(e.text) && !(e.modifiers & Qt.ControlModifier)) {
      // A real keyboard just starts typing the question.
      Input.showKeyboard("assistant"); e.accepted = true
    }
  }

  Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.backgroundDark, 0.95) }

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width - Theme.px(240), Theme.px(1400))
    spacing: Theme.px(36)

    Row {
      spacing: Theme.px(22)
      Glyph { text: "󰚩"; size: 56; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
      Label {
        anchors.verticalCenter: parent.verticalCenter
        text: Assistant.agent ? "Ask " + Assistant.agentName : "Assistant"
        size: 54
        strong: true
      }
    }

    // The question
    Label {
      width: parent.width
      visible: !!Assistant.question || Input.talking || Input.transcribing
      text: Input.talking ? "Listening…" : Input.transcribing ? "…" : "“" + Assistant.question + "”"
      size: 34
      color: Theme.dim
      wrapMode: Text.WordWrap
      maximumLineCount: 3
      font.italic: !Input.talking
    }

    // The answer
    Item {
      width: parent.width
      height: Math.max(Theme.px(220), answer.implicitHeight)
      Label {
        id: answer
        width: parent.width
        text: Assistant.busy ? "Thinking…" : (Assistant.answer || (Input.voiceAvailable ? "Press OK and ask anything. “Put on some lofi”, “what's the weather like on Mars”, “turn it down to 30”." : "Choose Type and ask anything."))
        size: Assistant.answer && !Assistant.busy ? 40 : 32
        color: Assistant.answer && !Assistant.busy ? Theme.foreground : Theme.muted
        wrapMode: Text.WordWrap
        maximumLineCount: 9
        elide: Text.ElideRight
        SequentialAnimation on opacity {
          running: Assistant.busy
          loops: Animation.Infinite
          NumberAnimation { to: 0.4; duration: 600 }
          NumberAnimation { to: 1; duration: 600 }
          onRunningChanged: if (!running) answer.opacity = 1
        }
      }
    }

    Label {
      visible: !!Assistant.action
      text: "󰐊  " + Assistant.action
      size: 26
      color: Theme.accent
    }

    Row {
      spacing: Theme.px(20)
      Repeater {
        model: panel.actions
        delegate: Rectangle {
          required property var modelData
          required property int index
          readonly property bool current: panel.activeFocus && panel.index === index
          width: content.implicitWidth + Theme.px(56)
          height: Theme.px(80)
          radius: Theme.round(height / 2)
          color: current ? Theme.alpha(Theme.activeBorder, Math.max(0.28, Theme.selectedFill + 0.1)) : Theme.alpha(Theme.surface, 0.8)
          border.width: current ? Theme.px(3) : Theme.px(1)
          border.color: current ? Theme.activeBorder : Theme.alpha(Theme.foreground, 0.12)
          Row {
            id: content
            anchors.centerIn: parent
            spacing: Theme.px(12)
            Glyph { text: modelData.glyph; size: 28; color: Theme.foreground; anchors.verticalCenter: parent.verticalCenter }
            Label { text: modelData.label; size: 28; strong: true; color: Theme.foreground; anchors.verticalCenter: parent.verticalCenter }
          }
        }
      }
    }
  }
}

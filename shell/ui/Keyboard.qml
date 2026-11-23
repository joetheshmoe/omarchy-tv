import QtQuick
import qs.core
import "Nav.js" as Nav

// On-screen keyboard for the remote. Arrows pick a key, OK types it. A real
// keyboard types straight in. Emits accepted(text) or cancelled().
FocusScope {
  id: kb

  property string text: ""
  property string placeholder: "Type"
  property bool secret: false
  property bool shift: false
  property bool symbols: false
  property bool live: false // emit edited() on every change (search)
  property bool actions: false // the Speak / Cancel / Send + Enter row
  property string doneLabel: "Done"
  property int col: 0
  property int row: 0
  // Typing on a real keyboard (or a suggestion already filled in): Enter then
  // sends, rather than pressing the highlighted key. Moving with the arrows
  // hands Enter back to the grid.
  property bool physical: false

  signal accepted(string text)
  signal submitted(string text) // Send + Enter
  signal speak()
  signal cancelled()
  signal edited(string text)

  readonly property var letters: [
    "1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.-"
  ]
  readonly property var syms: [
    "1234567890", "!@#$%^&*()", "_+=/\\?:;\"", "<>[]{}~`|·"
  ]
  readonly property var keys: {
    var src = symbols ? syms : letters
    var out = src.map(function(r) { return r.split("").map(function(c) { return { t: kb.shift ? c.toUpperCase() : c, k: "char" } }) })
    out.push([
      { t: "Shift", k: "shift", w: 2 }, { t: symbols ? "abc" : "#+=", k: "symbols", w: 2 },
      { t: "Space", k: "space", w: 4 }, { t: "Delete", k: "delete", w: 2 }
    ])
    if (actions) {
      var row = []
      if (Input.voiceAvailable) row.push({ t: Input.talking ? "Listening… (OK to stop)" : "Speak", k: "speak", w: 3 })
      row.push({ t: "Cancel", k: "cancel", w: 2 }, { t: "Send + Enter", k: "enter", w: 2 }, { t: doneLabel, k: "done", w: 3 })
      out.push(row)
    } else {
      out[out.length - 1].push({ t: doneLabel, k: "done", w: 2 })
    }
    return out
  }

  Connections {
    target: Input
    function onHeard(said, target) {
      if (target !== "keyboard" || !kb.visible) return
      kb.text += (kb.text.length && !/\s$/.test(kb.text) ? " " : "") + said
      if (kb.live) kb.edited(kb.text)
    }
  }

  function reset(initial) { text = initial || ""; row = 1; col = 0; shift = false; symbols = false; physical = !!initial; forceActiveFocus() }

  function press(key) {
    Sfx.play(key.k === "done" || key.k === "enter" ? "select" : "type")
    if (key.k === "char") type(key.t)
    else if (key.k === "space") type(" ")
    else if (key.k === "delete") erase()
    else if (key.k === "shift") shift = !shift
    else if (key.k === "symbols") symbols = !symbols
    else if (key.k === "done") accepted(text)
    else if (key.k === "enter") submitted(text)
    else if (key.k === "cancel") cancelled()
    else if (key.k === "speak") speak()
  }
  function type(c) { text += c; if (shift) shift = false; if (live) edited(text) }
  function erase() { text = text.slice(0, -1); if (live) edited(text) }

  function move(dr, dc) {
    Sfx.play("move")
    row = Math.max(0, Math.min(keys.length - 1, row + dr))
    col = Math.max(0, Math.min(keys[row].length - 1, dr !== 0 ? Math.round(col * (keys[row].length - 1) / Math.max(1, keys[row - dr] ? keys[row - dr].length - 1 : 1)) : col + dc))
  }

  Keys.onPressed: function(e) {
    if (e.key === Qt.Key_Left) { physical = false; move(0, -1); e.accepted = true }
    else if (e.key === Qt.Key_Right) { physical = false; move(0, 1); e.accepted = true }
    else if (e.key === Qt.Key_Up) { physical = false; move(-1, 0); e.accepted = true }
    else if (e.key === Qt.Key_Down) { physical = false; move(1, 0); e.accepted = true }
    else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && physical) { (e.modifiers & Qt.ShiftModifier) ? submitted(text) : accepted(text); e.accepted = true }
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Select) { press(keys[row][col]); e.accepted = true }
    else if (e.key === Qt.Key_Backspace) { if (text.length) erase(); else cancelled(); e.accepted = true }
    else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Back) { cancelled(); e.accepted = true }
    else if (e.text && e.text.length === 1 && e.text >= " " && !(e.modifiers & Qt.ControlModifier)) { physical = true; type(e.text); e.accepted = true }
  }

  onKeysChanged: { row = Math.min(row, keys.length - 1); col = Math.min(col, keys[row].length - 1) }

  implicitHeight: field.height + grid.height + Theme.px(28)

  Rectangle {
    id: field
    width: parent.width
    height: Theme.px(84)
    radius: Theme.r(14)
    color: Theme.alpha(Theme.surface, 0.8)
    border.width: Theme.px(2)
    border.color: Theme.accent
    Label {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Theme.px(26)
      text: kb.text.length ? (kb.secret ? "•".repeat(kb.text.length) : kb.text) + "▏" : kb.placeholder
      color: kb.text.length ? Theme.foreground : Theme.muted
      size: 34
      elide: Text.ElideLeft
    }
  }

  Column {
    id: grid
    anchors.top: field.bottom
    anchors.topMargin: Theme.px(28)
    width: parent.width
    spacing: Theme.px(10)
    Repeater {
      model: kb.keys
      delegate: Row {
        id: keyRow
        required property var modelData
        required property int index
        readonly property int units: modelData.reduce(function(s, k) { return s + (k.w || 1) }, 0)
        readonly property real unit: (grid.width - spacing * (modelData.length - 1)) / units
        // Shift / Space / Send rows are slimmer than the letters, so the
        // letters stay the biggest targets.
        readonly property bool special: modelData.some(function(k) { return k.k !== "char" })
        spacing: Theme.px(10)
        Repeater {
          model: keyRow.modelData
          delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool current: kb.activeFocus && kb.row === keyRow.index && kb.col === index
            width: keyRow.unit * (modelData.w || 1) + keyRow.spacing * ((modelData.w || 1) - 1)
            height: keyRow.special ? Theme.px(50) : Theme.px(70)
            radius: Theme.r(12)
            color: current ? Theme.alpha(Theme.activeBorder, Math.max(0.28, Theme.selectedFill + 0.1)) : (modelData.k === "shift" && kb.shift ? Theme.alpha(Theme.accent, 0.4) : Theme.alpha(Theme.surface, 0.7))
            border.width: current ? Theme.px(3) : Theme.px(1)
            border.color: current ? Theme.activeBorder : Theme.alpha(Theme.foreground, 0.1)
            Text {
              anchors.centerIn: parent
              text: parent.modelData.t
              font.family: Theme.font
              font.pixelSize: Theme.px(parent.modelData.k === "char" ? 30 : 20)
              color: Theme.foreground
            }
          }
        }
      }
    }
  }
}

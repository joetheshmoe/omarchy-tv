import QtQuick
import qs.core
import "Nav.js" as Nav

// Add something to Home: an installed app, a website, a terminal program or a
// command. Then pick the row (or make a new one). It's saved to
// ~/.config/omarchy-tv/apps.json, which you can also edit by hand.
FocusScope {
  id: add

  property string step: "kind" // kind | installed | text | row
  property var draft: ({})
  property var asks: []        // text prompts still to fill: [{ field, label, placeholder }]
  property string targetRow: Tv.screenArgs.targetRow || ""

  function reset() {
    step = "kind"
    draft = ({})
    asks = []
    targetRow = Tv.screenArgs.targetRow || ""
    menu.currentIndex = 0
    menu.forceActiveFocus()
    // From All apps: the app is chosen already; only the row is left.
    if (Tv.screenArgs.preset) pickInstalled(Tv.screenArgs.preset)
  }

  function pickInstalled(a) {
    draft = { type: "desktop", name: a.name, exec: a.exec, icon: a.icon, blurb: a.blurb, scale: 1.5, colors: ["surface", "#101010"], fromDesktop: a.id }
    asks = []
    next()
  }
  Connections { target: Tv; function onScreenArgsChanged() { if (Tv.screen === "addapp") Qt.callLater(add.reset) } }

  readonly property var kinds: [
    { key: "installed", label: "An installed app", glyph: "󰀻", detail: "Anything in the app launcher" },
    { key: "web", label: "A website", glyph: "󰖟", detail: "Opens full screen in its own browser profile" },
    { key: "terminal", label: "A terminal program", glyph: "", detail: "A TUI like btop or cliamp, full screen and big" },
    { key: "command", label: "A command", glyph: "󰆍", detail: "Any program, run in its own container" },
    { key: "omarchy", label: "Install something new", glyph: "󰇚", detail: "Omarchy's install menu" }
  ]

  readonly property var items: {
    if (step === "kind") return kinds
    if (step === "installed") return Tv.desktopApps.map(function(a) {
      return { key: "pick", app: a, label: a.name, detail: a.blurb, value: Tv.appIndex[a.id] ? "On Home" : "" }
    })
    if (step === "row") {
      var rows = Tv.rowDefs.map(function(r) { return { key: "row", id: r.id, label: r.title, value: r.id === add.targetRow ? "Here" : "" } })
      rows.push({ key: "newrow", label: "A new row…", glyph: "󰐕" })
      return rows
    }
    return []
  }

  function next() {
    if (asks.length) {
      step = "text"
      kb.placeholder = asks[0].placeholder
      kb.reset(asks[0].initial || "")
      return
    }
    if (draft.newRow !== undefined) { step = "text"; return }
    step = "row"
    menu.currentIndex = Math.max(0, Tv.rowDefs.findIndex(function(r) { return r.id === add.targetRow }))
    menu.forceActiveFocus()
  }

  function pickKind(k) {
    if (k === "omarchy") { Tv.show("omarchymenu", { route: "install" }); return }
    if (k === "installed") { step = "installed"; menu.currentIndex = 0; return }
    if (k === "web") {
      draft = { type: "web", input: "pointer", kiosk: true, scale: 1.25, glyph: "󰖟", colors: ["surface", "#101010"] }
      asks = [{ field: "url", label: "Website address", placeholder: "example.com" }, { field: "name", label: "Name on Home", placeholder: "Name" }]
    } else if (k === "terminal") {
      draft = { type: "terminal", glyph: "", colors: ["#2b2f3a", "#0d0f14"] }
      asks = [{ field: "cmd", label: "Program to run", placeholder: "btop" }, { field: "name", label: "Name on Home", placeholder: "Name" }]
    } else if (k === "command") {
      draft = { type: "native", glyph: "󰆍", colors: ["#2b2f3a", "#0d0f14"] }
      asks = [{ field: "cmd", label: "Command", placeholder: "kodi --standalone" }, { field: "name", label: "Name on Home", placeholder: "Name" }]
    }
    next()
  }

  function answer(text) {
    text = text.trim()
    if (draft.newRow !== undefined) {
      if (text) targetRow = Tv.addRow(text)
      var d = Object.assign({}, draft); delete d.newRow; draft = d
      finish()
      return
    }
    if (!text) return
    var ask = asks[0]
    var d2 = Object.assign({}, draft)
    if (ask.field === "url") {
      d2.url = /^[a-z]+:\/\//i.test(text) ? text : "https://" + text
      var host = d2.url.replace(/^[a-z]+:\/\//i, "").split(/[\/?#]/)[0].replace(/^www\./, "")
      var guess = host.split(".")[0]
      asks = asks.slice(1)
      if (asks.length) asks[0].initial = guess.charAt(0).toUpperCase() + guess.slice(1)
    } else if (ask.field === "cmd") {
      d2.exec = ["bash", "-c", text]
      d2.needs = [text.split(/\s+/)[0]]
      asks = asks.slice(1)
      if (asks.length) asks[0].initial = text.split(/\s+/)[0]
    } else {
      d2[ask.field] = text
      asks = asks.slice(1)
    }
    asks = asks.slice() // notify
    draft = d2
    next()
  }

  function finish() {
    var app = Object.assign({}, draft)
    app.id = Tv.uniqueId(app.name)
    Tv.addApp(app, targetRow || "apps")
    Tv.show("home")
  }

  ScreenHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: add.step === "row" ? "Which row?" : add.step === "installed" ? "Pick an app" : add.step === "text" ? (add.draft.newRow !== undefined ? "Name the row" : (add.asks[0] ? add.asks[0].label : "")) : "Add to Home"
    glyph: "󰐕"
  }

  MenuList {
    id: menu
    visible: add.step !== "text"
    anchors.top: header.bottom
    anchors.topMargin: Theme.px(30)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    width: Math.min(parent.width, Theme.px(1100))
    focus: add.step !== "text"
    items: add.items
    onActivated: function(item) {
      if (item.key === "pick") add.pickInstalled(item.app)
      else if (item.key === "row") { add.targetRow = item.id; add.finish() }
      else if (item.key === "newrow") {
        add.draft = Object.assign({}, add.draft, { newRow: "" })
        add.step = "text"
        kb.placeholder = "Row name"
        kb.reset("")
      }
      else add.pickKind(item.key)
    }
    Keys.onPressed: function(e) {
      if (Nav.isBack(e)) {
        if (add.step === "kind" || Tv.screenArgs.preset) Tv.show(Tv.screenArgs.preset ? "allapps" : "home")
        else add.reset()
        e.accepted = true
      }
    }
  }

  Keyboard {
    id: kb
    visible: add.step === "text"
    focus: add.step === "text"
    anchors.top: header.bottom
    anchors.topMargin: Theme.px(40)
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(parent.width, Theme.px(1200))
    actions: true
    doneLabel: "Next"
    onAccepted: function(text) { add.answer(text) }
    onSubmitted: function(text) { add.answer(text) }
    onSpeak: { if (Input.talking) Input.stopTalking(); else Input.startTalking("keyboard") }
    onCancelled: add.reset()
  }
}

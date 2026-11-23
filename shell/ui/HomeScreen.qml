import QtQuick
import qs.core
import "Nav.js" as Nav

// Home: the hero for the focused app, then rows of tiles.
FocusScope {
  id: home

  property bool live: true
  property var menuApp: null
  readonly property var rowModel: Tv.rows
  readonly property var currentRow: rows.currentItem
  readonly property var focusedApp: currentRow ? currentRow.currentApp : null

  function openMenu(app) {
    if (!app) return
    menuRow = Tv.rows[rows.currentIndex] ? Tv.rows[rows.currentIndex].id : ""
    menuApp = app
    menu.currentIndex = 0
    menu.forceActiveFocus()
  }
  function closeMenu() { menuApp = null; rows.forceActiveFocus() }

  property string menuRow: ""
  function menuItems(app) {
    if (!app) return []
    var running = Tv.isRunning(app.id)
    var list = [{ key: "open", label: running ? "Resume" : "Open", glyph: "\udb81\udc0a" }]
    if (running) {
      list.push({ key: "close", label: "Close", glyph: "\udb80\udd56", detail: "Ask it to quit, then make sure it did" })
      list.push({ key: "kill", label: "Force quit", glyph: "\udb80\udd5c", danger: true, detail: "End it now, with everything it started" })
    }
    if (menuRow !== "running") {
      list.push({ key: "move", label: "Move", glyph: "\udb80\uddbe", detail: "Arrows carry it, across rows too; OK drops it" })
      list.push({ key: "moverow", label: "Move this row", glyph: "\udb81\udce2", detail: "Up and Down move the whole row" })
      list.push({ key: "remove", label: Tv.isCustom(app.id) ? "Remove from Home" : "Hide from Home", glyph: "\udb80\uddb4", danger: Tv.isCustom(app.id),
                  detail: Tv.isCustom(app.id) ? "Deletes your entry; the app stays installed" : "Settings › Home brings it back" })
    }
    list.push({ key: "add", label: "Add to Home…", glyph: "\udb81\udc15" })
    return list
  }

  // ---------------------------------------------------------------- moving
  // "app": the tile under focus is lifted and follows the arrows.
  // "row": the whole row moves up and down.
  property string moving: ""
  property string movingId: ""
  property var follow: null // { row, app } to refocus after the model changes

  function startMove(kind, rowId, appId) {
    moving = kind
    movingId = kind === "row" ? rowId : appId
    mover.forceActiveFocus()
  }
  function endMove() {
    moving = ""
    movingId = ""
    rows.forceActiveFocus()
  }

  function refocus() {
    if (!follow) return
    var model = Tv.rows
    for (var r = 0; r < model.length; r++) {
      if (model[r].id !== follow.row) continue
      rows.currentIndex = r
      var a = follow.app ? model[r].apps.findIndex(function(x) { return x.id === follow.app }) : -1
      if (rows.currentItem && a >= 0) rows.currentItem.currentIndex = a
    }
  }
  Connections {
    target: Tv
    function onRowsChanged() { Qt.callLater(home.refocus) }
  }

  FocusScope {
    id: mover
    Keys.onPressed: function(e) {
      var rowId = home.currentRow ? Tv.rows[rows.currentIndex].id : ""
      if (Nav.isSelect(e) || Nav.isBack(e) || Nav.isMenu(e)) { home.endMove(); e.accepted = true; return }
      var dx = e.key === Qt.Key_Left ? -1 : e.key === Qt.Key_Right ? 1 : 0
      var dy = e.key === Qt.Key_Up ? -1 : e.key === Qt.Key_Down ? 1 : 0
      if (!dx && !dy) return
      e.accepted = true
      if (home.moving === "app") {
        var to = Tv.moveApp(home.movingId, dx, dx ? 0 : dy)
        home.follow = { row: to, app: home.movingId }
      } else if (home.moving === "row" && dy) {
        Tv.moveRow(home.movingId, dy)
        home.follow = { row: home.movingId, app: home.focusedApp ? home.focusedApp.id : "" }
      }
    }
  }

  TopBar {
    id: top
    live: home.live
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
  }

  // Hero: what OK will open.
  Column {
    id: hero
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: top.bottom
    anchors.topMargin: Theme.px(56)
    height: Theme.px(230)
    spacing: Theme.px(10)

    Label {
      width: parent.width
      text: home.focusedApp ? home.focusedApp.name : "Welcome"
      size: 82
      strong: true
    }
    Label {
      width: parent.width * 0.6
      text: home.focusedApp ? (home.focusedApp.blurb || "") : "Add apps in ~/.config/omarchy-tv/apps.json"
      size: 30
      color: Theme.dim
      wrapMode: Text.WordWrap
      maximumLineCount: 2
    }
    Row {
      spacing: Theme.px(28)
      topPadding: Theme.px(12)
      Repeater {
        model: {
          var a = home.focusedApp
          if (home.moving === "app") return [{ g: "Arrows", t: "Move " + (a ? a.name : "") }, { g: "OK", t: "Drop it here" }]
          if (home.moving === "row") return [{ g: "Up / Down", t: "Move the row" }, { g: "OK", t: "Done" }]
          var hints = [{ g: "OK", t: a && Tv.isRunning(a.id) ? "Resume" : "Open" }, { g: "Menu", t: "Options, move, remove" }]
          if (Tv.lastApp && Tv.isRunning(Tv.lastApp)) hints.push({ g: "Back", t: "Return to " + Tv.appFor(Tv.lastApp).name })
          return hints
        }
        delegate: Row {
          required property var modelData
          spacing: Theme.px(10)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: keyLabel.implicitWidth + Theme.px(20)
            height: Theme.px(36)
            radius: Theme.r(8)
            color: "transparent"
            border.width: Theme.px(2)
            border.color: Theme.muted
            Label { id: keyLabel; anchors.centerIn: parent; text: modelData.g; size: 18; strong: true; color: Theme.dim }
          }
          Label { anchors.verticalCenter: parent.verticalCenter; text: modelData.t; size: 22; color: Theme.dim }
        }
      }
    }
  }

  ListView {
    id: rows
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: hero.bottom
    anchors.topMargin: Theme.px(20)
    anchors.bottom: parent.bottom
    // Room on the left for the focused tile's growth and ring, inside the clip.
    anchors.leftMargin: -Theme.px(40)
    anchors.rightMargin: -Theme.px(40)
    focus: true
    clip: true
    interactive: false
    keyNavigationEnabled: true
    model: home.rowModel
    spacing: Theme.px(6)
    highlightMoveDuration: 220
    highlightRangeMode: ListView.StrictlyEnforceRange
    preferredHighlightBegin: 0
    preferredHighlightEnd: Theme.px(280)
    cacheBuffer: Theme.px(600)

    delegate: TileRow {
      required property var modelData
      required property int index
      width: rows.width
      title: modelData.title
      model: modelData.apps
      current: ListView.isCurrentItem
      focus: ListView.isCurrentItem
      liftedId: home.moving === "app" ? home.movingId : ""
      lifted: home.moving === "row" && modelData.id === home.movingId
      onActivated: function(app) { Tv.open(app) }
      onMenuRequested: function(app) { home.openMenu(app) }
    }

    onCurrentIndexChanged: if (activeFocus) Sfx.play("move")

    Keys.onPressed: function(e) {
      if (Nav.isBack(e)) { Tv.back(); e.accepted = true }
    }
  }

  // Options for one app.
  Rectangle {
    anchors.fill: parent
    visible: !!home.menuApp
    color: Theme.alpha(Theme.backgroundDark, 0.7)

    Rectangle {
      anchors.centerIn: parent
      width: Theme.px(720)
      height: menuTitle.height + menu.height + Theme.px(90)
      radius: Theme.r(24)
      color: Theme.background
      border.width: Theme.px(2)
      border.color: Theme.popupBorder

      Label {
        id: menuTitle
        anchors.top: parent.top
        anchors.topMargin: Theme.px(34)
        anchors.horizontalCenter: parent.horizontalCenter
        text: home.menuApp ? home.menuApp.name : ""
        size: 40
        strong: true
      }
      MenuList {
        id: menu
        anchors.top: menuTitle.bottom
        anchors.topMargin: Theme.px(24)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.px(28)
        height: items.length * Theme.px(92)
        rowHeight: 84
        items: home.menuItems(home.menuApp)
        onActivated: function(item) {
          var app = home.menuApp
          home.closeMenu()
          if (item.key === "open") Tv.open(app)
          else if (item.key === "close") Tv.closeApp(app.id, false)
          else if (item.key === "kill") Tv.closeApp(app.id, true)
          else if (item.key === "remove") Tv.removeApp(app)
          else if (item.key === "move") home.startMove("app", home.menuRow, app.id)
          else if (item.key === "moverow") home.startMove("row", home.menuRow, app.id)
          else if (item.key === "add") Tv.show("addapp", { targetRow: home.menuRow === "running" ? "" : home.menuRow })
        }
        Keys.onPressed: function(e) {
          if (Nav.isBack(e) || Nav.isMenu(e)) { home.closeMenu(); e.accepted = true }
        }
      }
    }
  }
}

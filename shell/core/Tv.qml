pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

// The TV's state and every action the UI can take. Windows and screens only
// read this and call into it.
Singleton {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string tvRoot: Quickshell.env("OMARCHY_TV_ROOT") || (Quickshell.shellDir + "/..")
  readonly property string stateDir: Quickshell.env("OMARCHY_TV_STATE") || (Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-tv")
  readonly property string configDir: home + "/.config/omarchy-tv"
  readonly property string appTool: tvRoot + "/bin/omarchy-tv-app"

  // ---------------------------------------------------------------- UI state
  property bool homeShown: true
  property bool guideShown: false
  property bool assistantShown: false
  property string screen: "home" // home | settings | allapps | power | media
  property var screenArgs: ({})
  property string launching: ""
  property string lastApp: ""
  property bool ambient: false

  // ---------------------------------------------------------------- settings
  property var settings: ({
    zoom: 1.0,
    safe: 0.04,
    pauseOnHome: true,
    ambientMinutes: 10,
    showDesktopRow: false,
    autoKeyboard: true,
    agent: "",
    musicPlayer: "mpv",
    startOnLogin: false,
    startOnWake: false,
    tutorialDone: false,
    layout: ({}),
    hidden: []
  })

  property bool settingsLoaded: false
  // First run: the tutorial, until it's been seen once.
  readonly property bool tutorialShown: settingsLoaded && settings.tutorialDone !== true && !tutorialDismissed
  property bool tutorialDismissed: false
  function finishTutorial() { tutorialDismissed = true; setSetting("tutorialDone", true) }
  function showTutorial() { setSetting("tutorialDone", false); tutorialDismissed = false; if (!homeShown) goHome() }

  // Open at login / after sleep: the user service follows these settings.
  function syncAutostart() { autostartTimer.restart() }
  Timer {
    id: autostartTimer
    interval: 600 // after settings.json is written
    onTriggered: {
      if (Quickshell.env("OMARCHY_TV_TEST")) { root.toast("Test session: autostart not changed"); return }
      Quickshell.execDetached([root.tvRoot + "/bin/omarchy-tv", "autostart", "sync"])
    }
  }

  function setSetting(key, value) {
    var next = Object.assign({}, settings)
    next[key] = value
    settings = next
    settingsFile.setText(JSON.stringify(settings, null, 2) + "\n")
  }

  FileView {
    id: settingsFile
    path: root.configDir + "/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.settings = Object.assign({}, root.settings, JSON.parse(text())) } catch (e) {}
      root.settingsLoaded = true
    }
    onLoadFailed: root.settingsLoaded = true // first run: no file yet
  }

  // ---------------------------------------------------------------- catalog
  property var baseCatalog: ({ rows: [], apps: [] })
  property var userCatalog: ({ rows: [], apps: [] })
  property var present: ({}) // command -> true, from the probe
  property bool probed: false

  FileView {
    path: root.tvRoot + "/apps/catalog.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.baseCatalog = JSON.parse(text()) } catch (e) { console.warn("catalog:", e) } }
  }

  FileView {
    id: userCatalogFile
    path: root.configDir + "/apps.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.userCatalog = JSON.parse(text()) } catch (e) { root.toast("~/.config/omarchy-tv/apps.json: " + e) } }
  }

  readonly property var browsers: ["chromium", "google-chrome-stable", "google-chrome", "brave", "helium-browser"]

  readonly property var mergedApps: {
    var byId = {}
    var order = []
    var lists = [baseCatalog.apps || [], userCatalog.apps || []]
    for (var l = 0; l < lists.length; l++) {
      for (var i = 0; i < lists[l].length; i++) {
        var a = lists[l][i]
        if (!a || !a.id) continue
        if (!byId[a.id]) order.push(a.id)
        byId[a.id] = Object.assign({}, byId[a.id] || {}, a)
      }
    }
    return order.map(function(id) { return byId[id] })
  }

  function available(app) {
    if (!probed) return !app.needs
    if (app.hidden || (settings.hidden || []).indexOf(app.id) >= 0) return false
    var needs = app.needs || []
    for (var i = 0; i < needs.length; i++) if (!present[needs[i]]) return false
    if (app.type === "web" || app.type === "vibes") {
      var any = false
      for (var b = 0; b < browsers.length; b++) if (present[browsers[b]]) any = true
      if (!any) return false
    }
    if (app.type === "media" && !present["mpv"]) return false
    return true
  }

  readonly property var apps: mergedApps.filter(function(a) { return root.available(a) })

  readonly property var appIndex: {
    var map = {}
    for (var i = 0; i < apps.length; i++) map[apps[i].id] = apps[i]
    return map
  }

  // ---------------------------------------------------------------- layout
  // Rows and the apps in them, in the viewer's order. settings.layout holds
  // { rowOrder: [row ids], rows: { row id: [app ids] }, hiddenRows: [ids] };
  // anything it doesn't mention keeps the catalog's place, so new apps still
  // show up.
  readonly property var rowDefs: {
    var defs = ((userCatalog.rows && userCatalog.rows.length) ? userCatalog.rows : (baseCatalog.rows || [])).slice()
    var extra = (settings.layout && settings.layout.extraRows) || []
    for (var e = 0; e < extra.length; e++) if (!defs.some(function(d) { return d.id === extra[e].id })) defs.push(extra[e])
    var order = (settings.layout && settings.layout.rowOrder) || []
    var base = defs.slice()
    // The engine's sort isn't stable: break ties on the catalog's order.
    defs.sort(function(a, b) {
      var ia = order.indexOf(a.id), ib = order.indexOf(b.id)
      return ((ia < 0 ? 1000 : ia) - (ib < 0 ? 1000 : ib)) || (base.indexOf(a) - base.indexOf(b))
    })
    return defs
  }

  function rowOf(app) {
    var rows = (settings.layout && settings.layout.rows) || {}
    for (var r in rows) if (rows[r].indexOf(app.id) >= 0) return r
    return app.row || "apps"
  }

  readonly property var layoutRows: {
    var placed = (settings.layout && settings.layout.rows) || {}
    var hiddenRows = (settings.layout && settings.layout.hiddenRows) || []
    var out = []
    for (var r = 0; r < rowDefs.length; r++) {
      var def = rowDefs[r]
      var list = apps.filter(function(a) { return root.rowOf(a) === def.id })
      if (def.id === "apps" && settings.showDesktopRow) {
        var have = list.map(function(a) { return a.id })
        list = list.concat(desktopApps.filter(function(d) { return have.indexOf(d.id) < 0 }).slice(0, 18))
      }
      var order = placed[def.id] || []
      var base = list.slice()
      list.sort(function(a, b) {
        var ia = order.indexOf(a.id), ib = order.indexOf(b.id)
        if (ia >= 0 && ib >= 0) return ia - ib
        if (ia >= 0) return -1
        if (ib >= 0) return 1
        return base.indexOf(a) - base.indexOf(b)
      })
      out.push({ id: def.id, title: def.title, apps: list, hidden: hiddenRows.indexOf(def.id) >= 0 })
    }
    return out
  }

  readonly property var rows: {
    var out = []
    if (running.length > 0) {
      out.push({ id: "running", title: "Open now", apps: running.map(function(id) { return root.appFor(id) }) })
    }
    for (var r = 0; r < layoutRows.length; r++) {
      var row = layoutRows[r]
      if (!row.hidden && row.apps.length) out.push(row)
    }
    return out
  }

  // The full layout as it stands, to edit and save back.
  function snapshotLayout() {
    var rows = {}
    for (var r = 0; r < layoutRows.length; r++) rows[layoutRows[r].id] = layoutRows[r].apps.map(function(a) { return a.id })
    return {
      rowOrder: layoutRows.map(function(r) { return r.id }),
      rows: rows,
      hiddenRows: ((settings.layout && settings.layout.hiddenRows) || []).slice(),
      extraRows: ((settings.layout && settings.layout.extraRows) || []).slice()
    }
  }

  // Move an app one step left/right in its row (dx), or to the row above or
  // below (dy). Returns the row it ended up in.
  function moveApp(appId, dx, dy) {
    var l = snapshotLayout()
    var from = null
    for (var r in l.rows) if (l.rows[r].indexOf(appId) >= 0) from = r
    if (!from) return ""
    var list = l.rows[from]
    var i = list.indexOf(appId)
    if (dx) {
      var j = Math.max(0, Math.min(list.length - 1, i + dx))
      list.splice(i, 1); list.splice(j, 0, appId)
      setSetting("layout", l)
      return from
    }
    // Rows that are shown, in order; skip hidden ones.
    var visible = l.rowOrder.filter(function(id) { return l.hiddenRows.indexOf(id) < 0 })
    var k = visible.indexOf(from) + dy
    if (k < 0 || k >= visible.length) return from
    var to = visible[k]
    list.splice(i, 1)
    l.rows[to].splice(Math.min(i, l.rows[to].length), 0, appId)
    setSetting("layout", l)
    return to
  }

  function moveRow(rowId, dy) {
    var l = snapshotLayout()
    var i = l.rowOrder.indexOf(rowId)
    var j = Math.max(0, Math.min(l.rowOrder.length - 1, i + dy))
    // Step over hidden rows so one press always moves it visibly.
    while (j !== i && l.hiddenRows.indexOf(l.rowOrder[j]) >= 0 && j + dy >= 0 && j + dy < l.rowOrder.length) j += dy
    l.rowOrder.splice(i, 1); l.rowOrder.splice(j, 0, rowId)
    setSetting("layout", l)
  }

  function setRowHidden(rowId, hidden) {
    var l = snapshotLayout()
    l.hiddenRows = l.hiddenRows.filter(function(id) { return id !== rowId })
    if (hidden) l.hiddenRows.push(rowId)
    setSetting("layout", l)
  }

  function addRow(title) {
    var l = snapshotLayout()
    var id = "row_" + slug(title) + "_" + Date.now().toString(36).slice(-4)
    l.extraRows.push({ id: id, title: title })
    l.rowOrder.push(id)
    l.rows[id] = []
    setSetting("layout", l)
    return id
  }

  function resetLayout() { setSetting("layout", {}) }

  // ---------------------------------------------------------------- your apps
  // Apps you add live in ~/.config/omarchy-tv/apps.json, the same file you can
  // edit by hand.
  function isCustom(id) {
    var list = userCatalog.apps || []
    var base = baseCatalog.apps || []
    return list.some(function(a) { return a.id === id }) && !base.some(function(a) { return a.id === id })
  }

  function writeUserCatalog(next) {
    userCatalog = next
    userCatalogFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function addApp(app, rowId) {
    var next = Object.assign({}, userCatalog)
    var list = (next.apps || []).filter(function(a) { return a.id !== app.id })
    app.row = rowId || app.row || "apps"
    list.push(app)
    next.apps = list
    writeUserCatalog(next)
    // Put it at the end of its row and make sure it isn't hidden.
    if ((settings.hidden || []).indexOf(app.id) >= 0) setSetting("hidden", settings.hidden.filter(function(id) { return id !== app.id }))
    toast(app.name + " added to " + ((rowDefs.find(function(r) { return r.id === app.row }) || {}).title || "Home"))
  }

  function removeApp(app) {
    if (isCustom(app.id)) {
      var next = Object.assign({}, userCatalog)
      next.apps = (next.apps || []).filter(function(a) { return a.id !== app.id })
      writeUserCatalog(next)
      toast(app.name + " removed")
    } else {
      setSetting("hidden", (settings.hidden || []).concat([app.id]))
      toast(app.name + " hidden. Settings › Home brings it back.")
    }
  }

  function uniqueId(name) {
    var base = slug(name) || "app"
    var id = base
    for (var n = 2; mergedApps.some(function(a) { return a.id === id }); n++) id = base + "_" + n
    return id
  }

  // The probe: which of the commands the catalog names are installed.
  Process {
    id: probe
    running: false
    command: {
      var names = root.browsers.concat(["mpv", "steam"])
      for (var i = 0; i < root.mergedApps.length; i++) names = names.concat(root.mergedApps[i].needs || [])
      return ["sh", "-c", "for c in \"$@\"; do command -v \"$c\" >/dev/null 2>&1 && echo \"$c\"; done", "probe"].concat(names)
    }
    stdout: StdioCollector {
      onStreamFinished: {
        var map = {}
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) if (lines[i]) map[lines[i]] = true
        root.present = map
        root.probed = true
      }
    }
  }
  onMergedAppsChanged: probeTimer.restart()
  Timer { id: probeTimer; interval: 150; onTriggered: probe.running = true }

  // ---------------------------------------------------------------- desktop apps
  function slug(s) { return String(s).toLowerCase().replace(/\.desktop$/, "").replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 40) }

  readonly property var desktopApps: {
    var list = DesktopEntries.applications.values.filter(function(e) { return !e.noDisplay && !e.runInTerminal })
    list.sort(function(a, b) { return a.name.localeCompare(b.name) })
    return list.map(function(e) {
      return {
        id: "desk_" + root.slug(e.id),
        name: e.name,
        type: "desktop",
        exec: e.command,
        icon: e.icon,
        blurb: e.comment || e.genericName || "",
        scale: 1.5,
        colors: ["surface", "#101010"]
      }
    })
  }

  readonly property var desktopIndex: {
    var map = {}
    for (var i = 0; i < desktopApps.length; i++) map[desktopApps[i].id] = desktopApps[i]
    return map
  }

  function appFor(id) {
    return appIndex[id] || desktopIndex[id] || { id: id, name: id === "other" ? "Other windows" : id === "omarchy" ? "Omarchy" : id, glyph: "󰀻", colors: ["surface", "#101010"], type: "native" }
  }

  // ---------------------------------------------------------------- running apps
  // An app is running while its workspace "tv-<id>" holds a window; the
  // compositor puts each app's windows there.
  readonly property var running: {
    var out = []
    var spaces = Hyprland.workspaces.values
    for (var i = 0; i < spaces.length; i++) {
      var w = spaces[i]
      var name = String(w.name || "")
      if (name.indexOf("tv-") === 0 && w.toplevels.values.length > 0) out.push(name.slice(3))
    }
    return out
  }

  readonly property string focusedApp: {
    var w = Hyprland.focusedWorkspace
    var name = w ? String(w.name || "") : ""
    return name.indexOf("tv-") === 0 ? name.slice(3) : ""
  }
  // The app the viewer is looking at (none while Home covers the screen).
  readonly property string frontApp: homeShown ? "" : focusedApp

  function isRunning(id) { return running.indexOf(id) >= 0 }

  onRunningChanged: {
    if (launching && isRunning(launching)) {
      var id = launching
      launching = ""
      launchTimeout.stop()
      resume(id)
    }
    // The app in front quit (or crashed): back to Home rather than a void.
    if (!homeShown && focusedApp && !isRunning(focusedApp)) goHome()
    if (!homeShown && !focusedApp && running.length === 0) goHome()
    if (lastApp && !isRunning(lastApp)) lastApp = running.length ? running[running.length - 1] : ""
    if (relaunch && !isRunning(relaunch.id)) relaunchTimer.restart()
    if (expecting && isRunning(expecting)) { var x = expecting; expecting = ""; resume(x) }
    if (!isRunning("omarchy") && omarchyWasRunning) reprobeTimer.restart()
    omarchyWasRunning = isRunning("omarchy")
  }
  // The window goes before the rest of the app has exited.
  Timer {
    id: relaunchTimer
    interval: 1500
    onTriggered: if (root.relaunch) { var r = root.relaunch; root.relaunch = null; root.launch(r) }
  }

  onFocusedAppChanged: if (!homeShown && !focusedApp) goHome()

  // ---------------------------------------------------------------- input mode
  // The gamepad bridge steps aside while a controller-native app is in front.
  readonly property string inputMode: Input.pointerActive ? "pointer"
    : (frontApp && !guideShown && !assistantShown && !Input.keyboardShown && appFor(frontApp).input === "gamepad") ? "gamepad"
    : "remote"
  onInputModeChanged: modeFile.setText(inputMode + "\n")
  FileView { id: modeFile; path: root.stateDir + "/input-mode"; printErrors: false }

  // ---------------------------------------------------------------- actions
  function open(app) {
    if (!app) return
    if (app.type === "builtin" && app.screen === "assistant") { Assistant.show(); return }
    if (app.type === "builtin") { show(app.screen, app); return }
    if (app.type === "media" && !app.file) { show("media", { app: app, folder: app.folder }); return }
    if (isRunning(app.id)) { resume(app.id); return }
    launch(app)
  }

  // Open an app at a given address (the assistant's YouTube searches). A
  // running copy is closed first, since a kiosk window can't be navigated.
  property var relaunch: null
  property bool omarchyWasRunning: false
  function openWithUrl(app, url) { openWith(app, { url: url }) }
  function openWith(app, overrides) {
    var next = Object.assign({}, app, overrides)
    if (isRunning(app.id)) { relaunch = next; closeApp(app.id, false); return }
    launch(next)
  }

  function launch(app) {
    var spec = Object.assign({}, app)
    delete spec.colors
    launching = app.id
    launchTimeout.restart()
    var proc = runner.createObject(root, { appId: app.id, command: [appTool, "run", JSON.stringify(spec)] })
    proc.running = true
  }

  Component {
    id: runner
    Process {
      id: proc
      property string appId
      stderr: StdioCollector { id: err }
      onExited: function(code) {
        Qt.callLater(function() {
          if (code !== 0) {
            root.toast(String(err.text || "").trim().split("\n").pop() || "Could not open " + root.appFor(proc.appId).name, "error")
            if (root.launching === proc.appId) root.launching = ""
          }
          proc.destroy()
        })
      }
    }
  }

  Timer {
    id: launchTimeout
    interval: 45000
    onTriggered: {
      if (!root.launching) return
      root.toast(root.appFor(root.launching).name + " is taking a long time to open", "warn")
      root.launching = ""
    }
  }

  // Run a row of Omarchy's menu (Install, Remove, ...). Most open a terminal,
  // which the shims keep in the TV; when a window shows up, bring it forward.
  property string expecting: ""
  function runMenuAction(item) {
    if (isRunning("omarchy")) { resume("omarchy"); toast("Finish the running one first"); return }
    expecting = "omarchy"
    expectTimer.restart()
    toast(item.label + "…")
    var proc = runner.createObject(root, { appId: "omarchy", command: [appTool, "run", JSON.stringify({ id: "omarchy", name: item.label, type: "menu", route: item.route })] })
    proc.running = true
    reprobeTimer.restart()
  }
  Timer { id: expectTimer; interval: 30000; onTriggered: root.expecting = "" }
  // After an install, look again for what's there.
  Timer { id: reprobeTimer; interval: 6000; onTriggered: probe.running = true }
  function reprobe() { probe.running = true }

  function cancelLaunch() {
    if (!launching) return
    Quickshell.execDetached([appTool, "kill", launching])
    launching = ""
    launchTimeout.stop()
  }

  function resume(id) {
    if (!isRunning(id)) return
    if (lastApp && lastApp !== id) background(lastApp)
    // A field that was already focused gets focus back; that isn't a reason
    // to pop the keyboard up.
    Input.keyboardHiddenAt = Date.now()
    Hyprland.dispatch('hl.dsp.focus({ workspace = "name:tv-' + id + '" })')
    Quickshell.execDetached([appTool, "fg", id])
    lastApp = id
    guideShown = false
    homeShown = false
    ambient = false
  }

  function background(id) {
    if (!id || !isRunning(id)) return
    var app = appFor(id)
    Quickshell.execDetached([appTool, "bg", id, app.freeze ? "true" : "false"])
  }

  function goHome(leaving) {
    var front = frontApp || (homeShown ? "" : focusedApp)
    // `leaving`: the app is being closed, so neither pause nor freeze it.
    if (front && !leaving) {
      lastApp = front
      if (settings.pauseOnHome) pauseApp(front)
      background(front)
    }
    guideShown = false
    homeShown = true
    screen = "home"
    // An empty workspace under Home: the compositor stops drawing the app.
    Hyprland.dispatch("hl.dsp.focus({ workspace = 1 })")
  }

  function show(name, args) {
    if (!homeShown) goHome()
    screenArgs = args || {}
    screen = name
  }

  function back() {
    if (ambient) { ambient = false; return }
    if (launching) { cancelLaunch(); return }
    if (screen !== "home") { screen = "home"; return }
    // Back on Home returns to the app you came from, as a TV does.
    if (lastApp && isRunning(lastApp)) resume(lastApp)
  }

  function closeApp(id, force) {
    if (!id) return
    toast((force ? "Force quitting " : "Closing ") + appFor(id).name)
    if (lastApp === id) lastApp = ""
    if (frontApp === id || guideShown) goHome(true)
    Quickshell.execDetached([appTool, force ? "kill" : "close", id])
  }

  function nextApp() {
    if (running.length === 0) return
    var cur = frontApp || lastApp
    var i = running.indexOf(cur)
    resume(running[(i + 1) % running.length])
  }

  // Remote Home key: inside an app it opens the guide; pressed again (or on
  // Home itself) it goes all the way Home.
  function homeKey() {
    if (ambient) { ambient = false; return }
    if (guideShown) { goHome(); return }
    if (!homeShown && frontApp) { guideShown = true; return }
    if (screen !== "home") { screen = "home"; return }
    if (!homeShown) goHome()
  }

  function guideKey() {
    if (guideShown) { guideShown = false; return }
    if (!homeShown && frontApp) guideShown = true
    else homeKey()
  }

  function power(action) {
    var cmds = {
      suspend: ["systemctl", "suspend"],
      reboot: ["omarchy", "system", "reboot"],
      shutdown: ["omarchy", "system", "shutdown"],
      exit: ["setsid", tvRoot + "/bin/omarchy-tv", "stop"],
      lock: ["omarchy", "system", "lock"]
    }
    if (cmds[action]) Quickshell.execDetached(cmds[action])
  }

  // ---------------------------------------------------------------- audio
  readonly property var sink: Pipewire.defaultAudioSink
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  property bool osdShown: false
  property string osdKind: "volume"

  function changeVolume(delta) {
    if (!sink || !sink.audio) return
    sink.audio.muted = false
    sink.audio.volume = Math.max(0, Math.min(1.0, Math.round((sink.audio.volume + delta) * 100) / 100))
    flashOsd("volume")
  }
  function toggleMute() {
    if (!sink || !sink.audio) return
    sink.audio.muted = !sink.audio.muted
    flashOsd("volume")
  }
  function flashOsd(kind) { osdKind = kind; osdShown = true; osdTimer.restart() }
  Timer { id: osdTimer; interval: 1400; onTriggered: root.osdShown = false }

  readonly property var sinks: Pipewire.nodes.values.filter(function(n) { return n.isSink && !n.isStream && n.audio })
  function setSink(node) { Pipewire.preferredDefaultAudioSink = node; flashOsd("output") }

  // ---------------------------------------------------------------- media
  // Players are matched to an app by pid (Chromium names its MPRIS bus after
  // it), so the TV never pauses music playing on the desktop.
  function pidsFor(id) {
    var pids = []
    var w = Hyprland.workspaces.values.find(function(s) { return s.name === "tv-" + id })
    if (!w) return pids
    var tops = w.toplevels.values
    for (var i = 0; i < tops.length; i++) {
      var o = tops[i].lastIpcObject
      if (o && o.pid) pids.push(String(o.pid))
    }
    return pids
  }

  function playersFor(id) {
    var pids = pidsFor(id)
    return Mpris.players.values.filter(function(p) {
      var bus = String(p.dbusName || "")
      for (var i = 0; i < pids.length; i++) if (bus.indexOf(pids[i]) >= 0) return true
      return id === "videos" || id === "music" ? bus.indexOf("mpv") >= 0 : false
    })
  }

  function pauseApp(id) {
    var ps = playersFor(id)
    for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying && ps[i].canPause) ps[i].pause()
  }

  readonly property var nowPlaying: {
    // Recording a demo: keep whatever the desktop is playing off screen.
    if (Quickshell.env("OMARCHY_TV_DEMO")) return null
    var ps = Mpris.players.values
    for (var i = 0; i < ps.length; i++) if (ps[i].isPlaying) return ps[i]
    return null
  }

  function mediaKey(action) {
    var target = lastApp ? playersFor(lastApp) : []
    var p = target.length ? target[0] : nowPlaying
    if (!p) return
    if (action === "play-pause" && p.canTogglePlaying) p.togglePlaying()
    else if (action === "next" && p.canGoNext) p.next()
    else if (action === "previous" && p.canGoPrevious) p.previous()
    else if (action === "stop") p.stop()
  }

  // ---------------------------------------------------------------- toasts
  property var toasts: []
  // The toast surface is hidden before its last message is cleared, so it
  // never draws an empty frame on the way out.
  property bool toastsVisible: false
  function toast(text, kind) {
    var t = { text: String(text), kind: kind || "info", at: Date.now() }
    toasts = toasts.concat([t]).slice(-3)
    toastsVisible = true
    toastTimer.restart()
  }
  Timer {
    id: toastTimer
    interval: 3500
    onTriggered: {
      if (root.toasts.length <= 1) { root.toastsVisible = false; toastClear.restart(); return }
      root.toasts = root.toasts.slice(1)
      restart()
    }
  }
  Timer { id: toastClear; interval: 150; onTriggered: if (!root.toastsVisible) root.toasts = [] }

  Component.onCompleted: {
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    modeFile.setText("remote\n")
  }
}

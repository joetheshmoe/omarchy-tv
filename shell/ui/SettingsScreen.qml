import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import qs.core
import "Nav.js" as Nav

// Settings, two panes: categories on the left, their controls on the right.
// Right from a category goes into it; Back comes out.
FocusScope {
  id: settings

  property string category: "sound"
  property var themes: []
  property string currentTheme: ""
  property string version: ""
  property var pskFor: null // a Wi-Fi network waiting for its password

  readonly property var categories: [
    { key: "sound", label: "Sound", glyph: "󰕾" },
    { key: "bluetooth", label: "Bluetooth", glyph: "󰂯", detail: "Remotes, controllers, speakers" },
    { key: "wifi", label: "Wi-Fi", glyph: "󰖩" },
    { key: "display", label: "Display", glyph: "󰍹", detail: "Size, overscan, screensaver" },
    { key: "theme", label: "Theme", glyph: "󰏘", detail: "Omarchy themes, live" },
    { key: "apps", label: "Apps", glyph: "󰀻" },
    { key: "home", label: "Home", glyph: "\udb80\udedc", detail: "Rows, order, hidden apps" },
    { key: "assistant", label: "Assistant", glyph: "\udb81\udea9", detail: "Which agent answers" },
    { key: "advanced", label: "Advanced", glyph: "\udb81\udc93", detail: "Omarchy Control, install, remove" },
    { key: "about", label: "About", glyph: "󰋼" }
  ]

  function reset() { catMenu.currentIndex = 0; category = "sound"; catMenu.forceActiveFocus(); themeProc.running = true; versionProc.running = true }

  // ---------------------------------------------------------------- data
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var wifi: {
    var ds = Networking.devices.values
    for (var i = 0; i < ds.length; i++) if (ds[i].type === DeviceType.Wifi) return ds[i]
    return null
  }
  // Scan for networks only while the Wi-Fi page is open.
  Binding { when: !!settings.wifi; target: settings.wifi; property: "scannerEnabled"; value: settings.visible && settings.category === "wifi" }

  Process {
    id: themeProc
    command: ["sh", "-c", "omarchy theme current; echo ---; omarchy theme list"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = text.split("---")
        settings.currentTheme = (parts[0] || "").trim()
        settings.themes = (parts[1] || "").split("\n").map(function(s) { return s.trim() }).filter(function(s) { return s.length })
      }
    }
  }
  Process {
    id: versionProc
    command: ["omarchy", "version"]
    stdout: StdioCollector { onStreamFinished: settings.version = text.trim() }
  }

  function pct(v) { return Math.round(v * 100) + "%" }

  readonly property var detailItems: {
    var c = category
    var list = []
    if (c === "sound") {
      list.push({ key: "volume", kind: "slider", label: "Volume", level: Tv.volume, detail: Tv.muted ? "Muted" : pct(Tv.volume) })
      list.push({ key: "mute", kind: "toggle", label: "Mute", on: Tv.muted })
      list.push({ kind: "header", label: "Play sound on" })
      var sinks = Tv.sinks
      for (var i = 0; i < sinks.length; i++) {
        var current = Tv.sink && sinks[i].id === Tv.sink.id
        list.push({ key: "sink", node: sinks[i], label: sinks[i].description || sinks[i].nickname || sinks[i].name, glyph: current ? "󰄬" : "", value: current ? "In use" : "" })
      }
    } else if (c === "bluetooth") {
      if (!adapter) return [{ kind: "header", label: "No Bluetooth adapter" }]
      list.push({ key: "bt-power", kind: "toggle", label: "Bluetooth", on: adapter.enabled })
      list.push({ key: "bt-scan", kind: "toggle", label: "Find new devices", on: adapter.discovering, enabled: adapter.enabled, detail: "Put the remote or controller in pairing mode" })
      var devs = adapter.devices.values.slice().sort(function(a, b) { return (b.paired - a.paired) || (b.connected - a.connected) || a.name.localeCompare(b.name) })
      var shownHeader = { paired: false, nearby: false }
      for (var d = 0; d < devs.length; d++) {
        var dev = devs[d]
        if (!dev.paired && (!dev.name || /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(dev.name))) continue
        var group = dev.paired ? "paired" : "nearby"
        if (!shownHeader[group]) { list.push({ kind: "header", label: dev.paired ? "My devices" : "Nearby" }); shownHeader[group] = true }
        var state = dev.pairing ? "Pairing…" : dev.connected ? "Connected" : dev.paired ? "Not connected" : "Pair"
        if (dev.batteryAvailable) state += " · " + pct(dev.battery)
        list.push({ key: "bt-device", device: dev, label: dev.name, glyph: btGlyph(dev.icon), value: state })
      }
    } else if (c === "wifi") {
      list.push({ key: "wifi-power", kind: "toggle", label: "Wi-Fi", on: Networking.wifiEnabled })
      if (wifi && Networking.wifiEnabled) {
        var nets = wifi.networks.values.slice().sort(function(a, b) { return (b.connected - a.connected) || (b.signalStrength - a.signalStrength) })
        if (nets.length) list.push({ kind: "header", label: "Networks" })
        for (var n = 0; n < Math.min(nets.length, 14); n++) {
          var net = nets[n]
          var open = net.security === WifiSecurityType.Open || net.security === WifiSecurityType.Owe
          list.push({ key: "wifi-net", network: net, label: net.name, glyph: wifiGlyph(net.signalStrength),
                      value: net.connected ? "Connected" : net.stateChanging ? "Connecting…" : net.known ? "Saved" : (open ? "Open" : "󰌾") })
        }
      }
    } else if (c === "display") {
      list.push({ key: "zoom", kind: "choice", label: "Size of everything", value: pct(Tv.settings.zoom), detail: "Bigger if you sit further away" })
      list.push({ key: "safe", kind: "choice", label: "Overscan margin", value: pct(Tv.settings.safe), detail: "Raise it if the edges are cut off" })
      list.push({ key: "login", kind: "toggle", label: "Open when I log in", on: !!Tv.settings.startOnLogin, detail: "Boot straight into the TV, full screen" })
      list.push({ key: "wake", kind: "toggle", label: "Open when it wakes from sleep", on: !!Tv.settings.startOnWake })
      list.push({ key: "ambient", kind: "choice", label: "Screensaver", value: Tv.settings.ambientMinutes > 0 ? Tv.settings.ambientMinutes + " min" : "Off", detail: "A dim clock on Home, against burn-in" })
    } else if (c === "theme") {
      for (var t = 0; t < themes.length; t++) {
        var on = themes[t] === currentTheme
        list.push({ key: "theme", name: themes[t], label: themes[t], glyph: on ? "󰄬" : "", value: on ? "Current" : "" })
      }
      if (!themes.length) list.push({ kind: "header", label: "Loading themes…" })
    } else if (c === "apps") {
      list.push({ key: "pause", kind: "toggle", label: "Pause when going Home", on: !!Tv.settings.pauseOnHome })
      list.push({ key: "deskrow", kind: "toggle", label: "Desktop apps on Home", on: !!Tv.settings.showDesktopRow, detail: "Otherwise they live in All apps" })
      list.push({ key: "music", kind: "choice", label: "Play music files with", value: (Tv.settings.musicPlayer === "cliamp" ? "cliamp" : "mpv"), detail: "For the Music folder; cliamp is also its own tile" })
      list.push({ key: "autokb", kind: "toggle", label: "Keyboard pops up for text fields", on: Tv.settings.autoKeyboard !== false, detail: Input.imeReady ? "Or summon it: L3, Super+K, or the guide" : "Input method not running; summon it with L3 or Super+K" })
      list.push({ kind: "header", label: "Add your own" })
      list.push({ key: "none", label: "~/.config/omarchy-tv/apps.json", detail: "Same format as apps/catalog.json; reloads live", enabled: false })
    } else if (c === "home") {
      list.push({ key: "addapp", label: "Add to Home…", glyph: "\udb81\udc15", detail: "An installed app, a website, a terminal program or a command" })
      list.push({ key: "none", label: "To reorder: Menu on any tile › Move", detail: "Move carries a tile across rows; Move this row shifts the row", enabled: false })
      list.push({ kind: "header", label: "Rows (OK shows or hides)" })
      for (var lr = 0; lr < Tv.layoutRows.length; lr++) {
        var row = Tv.layoutRows[lr]
        list.push({ key: "rowtoggle", kind: "toggle", id: row.id, label: row.title, on: !row.hidden, detail: row.apps.length + " apps" })
      }
      var hiddenApps = Tv.settings.hidden || []
      if (hiddenApps.length) list.push({ kind: "header", label: "Hidden apps (OK shows again)" })
      for (var ha = 0; ha < hiddenApps.length; ha++) {
        var happ = Tv.mergedApps.find(function(a) { return a.id === hiddenApps[ha] })
        list.push({ key: "unhide", id: hiddenApps[ha], label: happ ? happ.name : hiddenApps[ha], glyph: "\udb80\ude08" })
      }
      list.push({ kind: "header", label: "Start over" })
      list.push({ key: "resetlayout", label: "Reset the Home layout", glyph: "\udb81\udf09", detail: "Back to the catalog's order; your added apps stay" })
    } else if (c === "assistant") {
      list.push({ kind: "header", label: "The TV assistant answers with" })
      var follow = !Tv.settings.agent
      list.push({ key: "tvagent", id: "", label: "Omarchy's default", glyph: follow ? "\udb80\udd2c" : "",
                  detail: follow ? "Now: " + (Assistant.agentName || "none that can answer") : "" })
      var ags = Assistant.agents.filter(function(a) { return a.installed && a.headless })
      for (var g = 0; g < ags.length; g++) {
        var chosen = Tv.settings.agent === ags[g].id
        list.push({ key: "tvagent", id: ags[g].id, label: ags[g].label, glyph: chosen ? "\udb80\udd2c" : "", value: chosen ? "Answering" : "" })
      }
      list.push({ kind: "header", label: "Omarchy's default agent (Agent tile, desktop)" })
      var all = Assistant.agents.filter(function(a) { return a.installed })
      for (var h = 0; h < all.length; h++) {
        list.push({ key: "omarchyagent", id: all[h].id, label: all[h].label, glyph: all[h].icon, glyphFont: all[h].iconFont || "",
                    value: all[h].default ? "Default ✓" : "", detail: all[h].headless ? "" : "Agent tile only (no quick answers)" })
      }
      list.push({ key: "installai", label: "Install more agents…", glyph: "\udb80\uddda", detail: "Omarchy's install menu › AI" })
    } else if (c === "advanced") {
      list.push({ kind: "header", label: "Omarchy Control" })
      var pages = [["appearance", "Appearance"], ["displays", "Displays"], ["sound", "Sound"], ["network", "Network"], ["input", "Input"],
                   ["power", "Power"], ["apps", "Apps"], ["desktop", "Desktop"], ["accounts", "Accounts"], ["system", "System"], ["advanced", "Advanced"], ["about", "About"]]
      list.push({ key: "control", page: "", label: "Open Omarchy Control", glyph: "\udb81\udc93" })
      for (var pg = 0; pg < pages.length; pg++) list.push({ key: "control", page: pages[pg][0], label: pages[pg][1], value: "›" })
      list.push({ kind: "header", label: "Software (Omarchy menus)" })
      list.push({ key: "menu", route: "install", label: "Install", glyph: "\udb80\uddda" })
      list.push({ key: "menu", route: "remove", label: "Remove", glyph: "\udb80\uddb4" })
      list.push({ key: "menu", route: "update", label: "Update", glyph: "\udb81\udf09" })
    } else if (c === "about") {
      list.push({ key: "none", label: "Omarchy", value: version, enabled: false })
      list.push({ key: "none", label: "Open apps", value: String(Tv.running.length), enabled: false })
      list.push({ key: "none", label: "Assistant", value: Assistant.agentName || "None installed", enabled: false })
      list.push({ key: "none", label: "Voice", value: Input.voiceAvailable ? "Superwhisper" : "Install Superwhisper", enabled: false })
      list.push({ key: "tutorial", label: "Show the tutorial again", glyph: "\udb80\udefc" })
      list.push({ kind: "header", label: "Remote" })
      list.push({ key: "none", label: "Home", detail: "Guide inside an app, twice for Home", enabled: false })
      list.push({ key: "none", label: "Menu", detail: "Options for the focused app", enabled: false })
      list.push({ key: "none", label: "Back", detail: "On Home, returns to the last app", enabled: false })
      list.push({ key: "none", label: "Controller", detail: "Select mouse · L3 keyboard · hold R3 talk · hold Guide assistant", enabled: false })
      list.push({ key: "none", label: "Keyboard", detail: "Super+K keyboard · Super+M mouse · hold Super+T talk · Super+A assistant", enabled: false })
      list.push({ key: "none", label: "Ctrl+Alt+Shift+Esc", detail: "Leave the TV, whatever state it is in", enabled: false })
    }
    return list
  }

  function btGlyph(icon) {
    var i = String(icon || "")
    if (i.indexOf("input-gaming") >= 0) return "󰊗"
    if (i.indexOf("audio") >= 0) return "󰋋"
    if (i.indexOf("input-keyboard") >= 0) return "󰌌"
    if (i.indexOf("input-mouse") >= 0) return "󰍽"
    if (i.indexOf("phone") >= 0) return "󰍲"
    return "󰂯"
  }
  function wifiGlyph(s) { return s > 0.75 ? "󰤨" : s > 0.5 ? "󰤥" : s > 0.25 ? "󰤢" : "󰤟" }

  function cycle(list, current, step) {
    var i = 0
    for (var k = 0; k < list.length; k++) if (Math.abs(list[k] - current) < 0.001) i = k
    return list[Math.max(0, Math.min(list.length - 1, i + step))]
  }

  function act(item) {
    switch (item.key) {
    case "mute": Tv.toggleMute(); break
    case "sink": Tv.setSink(item.node); break
    case "bt-power": adapter.enabled = !adapter.enabled; break
    case "bt-scan": adapter.discovering = !adapter.discovering; break
    case "bt-device":
      var dev = item.device
      if (dev.connected) dev.disconnect()
      else if (dev.paired) dev.connect()
      else { dev.trusted = true; dev.pair() }
      break
    case "wifi-power": Networking.wifiEnabled = !Networking.wifiEnabled; break
    case "wifi-net":
      var net = item.network
      if (net.connected) net.disconnect()
      else if (net.known || net.security === WifiSecurityType.Open || net.security === WifiSecurityType.Owe) net.connect()
      else { pskFor = net; keyboard.reset(""); }
      break
    case "zoom": case "safe": case "ambient": adjust(item, 1); break
    case "theme":
      Quickshell.execDetached(["omarchy", "theme", "set", item.name])
      currentTheme = item.name
      Tv.toast("Applying " + item.name)
      break
    case "pause": Tv.setSetting("pauseOnHome", !Tv.settings.pauseOnHome); break
    case "deskrow": Tv.setSetting("showDesktopRow", !Tv.settings.showDesktopRow); break
    case "music": adjust(item, 1); break
    case "login": Tv.setSetting("startOnLogin", !item.on); Tv.syncAutostart(); break
    case "wake": Tv.setSetting("startOnWake", !item.on); Tv.syncAutostart(); break
    case "tutorial": Tv.showTutorial(); break
    case "addapp": Tv.show("addapp", {}); break
    case "rowtoggle": Tv.setRowHidden(item.id, item.on); break
    case "resetlayout": Tv.resetLayout(); Tv.toast("Home is back in its original order"); break
    case "tvagent": Tv.setSetting("agent", item.id); break
    case "omarchyagent": Assistant.setOmarchyDefault(item.id); break
    case "installai": Tv.show("omarchymenu", { route: "install.ai" }); break
    case "menu": Tv.show("omarchymenu", { route: item.route }); break
    case "control":
      var ctl = Tv.appIndex["control"]
      if (!ctl) { Tv.toast("Omarchy Control is not installed", "error"); break }
      Tv.openWith(ctl, { exec: item.page ? ["omarchy-control", "open", "--page", item.page] : ["omarchy-control", "open"] })
      break
    case "autokb": Tv.setSetting("autoKeyboard", Tv.settings.autoKeyboard === false); break
    case "unhide": Tv.setSetting("hidden", (Tv.settings.hidden || []).filter(function(id) { return id !== item.id })); break
    }
  }

  function adjust(item, step) {
    if (item.key === "volume") Tv.changeVolume(step * 0.05)
    else if (item.key === "zoom") Tv.setSetting("zoom", cycle([0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4], Tv.settings.zoom, step))
    else if (item.key === "safe") Tv.setSetting("safe", cycle([0, 0.02, 0.03, 0.04, 0.05, 0.06, 0.08], Tv.settings.safe, step))
    else if (item.key === "music") Tv.setSetting("musicPlayer", Tv.settings.musicPlayer === "cliamp" ? "mpv" : "cliamp")
    else if (item.key === "ambient") Tv.setSetting("ambientMinutes", cycle([0, 5, 10, 20, 30, 60], Tv.settings.ambientMinutes, step))
  }

  // ---------------------------------------------------------------- layout
  ScreenHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: "Settings"
    glyph: "󰒓"
  }

  MenuList {
    id: catMenu
    anchors.top: header.bottom
    anchors.topMargin: Theme.px(30)
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    width: Theme.px(520)
    focus: true
    keepHighlight: true
    items: settings.categories
    onCurrentItemChanged: if (currentItem) settings.category = currentItem.key
    onActivated: detail.forceActiveFocus()
    Keys.onPressed: function(e) {
      if (e.key === Qt.Key_Right) { detail.forceActiveFocus(); e.accepted = true }
      else if (Nav.isBack(e)) { Tv.back(); e.accepted = true }
    }
  }

  MenuList {
    id: detail
    anchors.top: header.bottom
    anchors.topMargin: Theme.px(30)
    anchors.left: catMenu.right
    anchors.leftMargin: Theme.px(50)
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    opacity: activeFocus ? 1 : 0.8
    items: settings.detailItems
    onActivated: function(item) { settings.act(item) }
    onAdjust: function(item, step) { settings.adjust(item, step) }
    Keys.onPressed: function(e) {
      if (e.key === Qt.Key_Left || Nav.isBack(e)) { catMenu.forceActiveFocus(); e.accepted = true }
    }
  }

  // Wi-Fi password entry.
  Rectangle {
    anchors.fill: parent
    anchors.margins: -Theme.px(200)
    visible: !!settings.pskFor
    color: Theme.alpha(Theme.backgroundDark, 0.92)
    Column {
      anchors.centerIn: parent
      width: Theme.px(1200)
      spacing: Theme.px(30)
      Label { text: settings.pskFor ? "Password for " + settings.pskFor.name : ""; size: 40; strong: true }
      Keyboard {
        id: keyboard
        width: parent.width
        secret: true
        placeholder: "Wi-Fi password"
        onAccepted: function(text) {
          var net = settings.pskFor
          settings.pskFor = null
          if (net && text.length) net.connectWithPsk(text)
          detail.forceActiveFocus()
        }
        onCancelled: { settings.pskFor = null; detail.forceActiveFocus() }
      }
    }
  }
}

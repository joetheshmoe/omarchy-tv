pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Ask your Omarchy agent from the couch. Questions come by voice or the
// on-screen keyboard; the answer shows large. An agent may end its answer with
// a "TV:" line, and only the commands listed in act() are ever carried out.
Singleton {
  id: root

  property string agent: ""
  readonly property string agentName: agentLabel(agent)
  property string question: ""
  property string answer: ""
  property string action: ""
  property bool busy: false

  // Which agent answers: TV Settings › Assistant, else Omarchy's default.
  property var agents: []
  function refresh() { which.running = true; list.running = true }
  Process {
    id: which
    running: true
    environment: ({ OMARCHY_TV_AGENT: Tv.settings.agent || "" })
    command: [Tv.tvRoot + "/bin/omarchy-tv-ask", "agent"]
    stdout: StdioCollector { onStreamFinished: root.agent = text.trim() }
  }
  Process {
    id: list
    running: true
    command: [Tv.tvRoot + "/bin/omarchy-tv-ask", "agents"]
    stdout: StdioCollector { onStreamFinished: { try { root.agents = JSON.parse(text) } catch (e) {} } }
  }
  Connections {
    target: Tv
    function onSettingsChanged() { if (root.lastAgentSetting !== (Tv.settings.agent || "")) { root.lastAgentSetting = Tv.settings.agent || ""; root.refresh() } }
  }
  property string lastAgentSetting: ""

  // Make an agent Omarchy's default (the Agent tile and the desktop use it).
  function setOmarchyDefault(id) {
    Quickshell.execDetached(["omarchy-default-agent", id])
    Tv.toast("Omarchy's default agent is now " + (agentLabel(id)))
    Qt.callLater(refresh)
    refreshLater.restart()
  }
  Timer { id: refreshLater; interval: 800; onTriggered: root.refresh() }
  function agentLabel(id) {
    var a = agents.find(function(x) { return x.id === id })
    return a ? a.label : id
  }

  function show() {
    Tv.assistantShown = true
    if (Tv.guideShown) Tv.guideShown = false
  }
  function hide() {
    Tv.assistantShown = false
    if (asker.running) asker.signal(15)
    busy = false
  }

  function ask(text) {
    text = String(text || "").trim()
    if (!text) return
    if (!agent) { show(); answer = "No agent is installed to answer. Install one with: omarchy install ai"; return }
    show()
    if (asker.running) asker.signal(15)
    question = text
    answer = ""
    action = ""
    busy = true
    asker.command = [Tv.tvRoot + "/bin/omarchy-tv-ask", text]
    asker.running = true
  }

  Process {
    id: asker
    environment: ({ OMARCHY_TV_AGENT: Tv.settings.agent || "", OMARCHY_TV_APPS: Tv.apps.filter(function(a) { return a.type !== "builtin" }).map(function(a) { return a.id }).join(" ") })
    stdout: StdioCollector {
      onStreamFinished: {
        root.busy = false
        var lines = String(text || "").trim().split("\n")
        var tv = ""
        for (var i = lines.length - 1; i >= 0; i--) {
          var m = lines[i].match(/^\s*TV:\s*(.+?)\s*$/)
          if (m) { tv = m[1]; lines.splice(i, 1); break }
        }
        root.answer = lines.join("\n").trim() || (tv ? "On it." : "No answer came back.")
        Sfx.play("notify")
        root.action = tv
        if (tv) actTimer.restart()
      }
    }
  }

  // Give the viewer a moment to read the reply, then do it.
  Timer { id: actTimer; interval: 1800; onTriggered: root.act(root.action) }

  function act(cmd) {
    var m
    if ((m = cmd.match(/^open\s+([a-z0-9_]+)$/i))) {
      var app = Tv.appIndex[m[1].toLowerCase()]
      if (!app) { Tv.toast("No app called " + m[1]); return }
      hide(); Tv.open(app)
    } else if ((m = cmd.match(/^youtube\s+(.+)$/i))) {
      var yt = Tv.appIndex["youtube"]
      if (!yt) { Tv.toast("YouTube isn't set up"); return }
      hide()
      Tv.openWithUrl(yt, "https://www.youtube.com/tv#/search?q=" + encodeURIComponent(m[1]))
    } else if (/^close$/i.test(cmd)) {
      hide(); Tv.closeApp(Tv.lastApp || Tv.focusedApp, false)
    } else if (/^home$/i.test(cmd)) {
      hide(); Tv.goHome()
    } else if ((m = cmd.match(/^volume\s+(\d{1,3})$/i))) {
      if (Tv.sink && Tv.sink.audio && !Tv.audioLocked) { Tv.sink.audio.muted = false; Tv.sink.audio.volume = Math.min(100, parseInt(m[1])) / 100; Tv.flashOsd("volume") }
    } else if (/^settings$/i.test(cmd)) {
      hide(); Tv.show("settings")
    } else {
      Tv.toast("Not something the TV can do: " + cmd)
    }
  }
}

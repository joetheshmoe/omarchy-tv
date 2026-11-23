import QtQuick
import Qt.labs.folderlistmodel
import qs.core
import "Nav.js" as Nav

// Browse a folder of videos or music and play with mpv (hardware decoding,
// remote keys, resumes where you stopped).
FocusScope {
  id: media

  property var app: Tv.screenArgs.app || ({})
  property string rootFolder: String(Tv.screenArgs.folder || "~/Videos").replace(/^~/, Tv.home)
  property string folder: rootFolder

  readonly property var exts: ["mkv", "mp4", "webm", "avi", "mov", "m4v", "ts", "mpg", "mpeg", "wmv", "flv",
                               "mp3", "flac", "ogg", "opus", "m4a", "wav", "aac", "alac", "wma"]

  function reset() { folder = rootFolder; list.currentIndex = 0; list.forceActiveFocus() }
  onRootFolderChanged: folder = rootFolder

  FolderListModel {
    id: files
    folder: "file://" + media.folder
    showDirsFirst: true
    showHidden: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name
    nameFilters: media.exts.map(function(e) { return "*." + e }).concat(media.exts.map(function(e) { return "*." + e.toUpperCase() }))
  }

  ScreenHeader {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    title: media.app.name || "Media"
    glyph: media.app.glyph || "󰎁"
  }

  Label {
    id: crumb
    anchors.top: header.bottom
    anchors.left: parent.left
    text: media.folder.replace(Tv.home, "~")
    size: 24
    color: Theme.muted
  }

  ListView {
    id: list
    anchors.top: crumb.bottom
    anchors.topMargin: Theme.px(26)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    focus: true
    clip: true
    interactive: false
    keyNavigationEnabled: true
    model: files
    spacing: Theme.px(8)
    highlightMoveDuration: 120
    highlightRangeMode: ListView.ApplyRange
    preferredHighlightBegin: height * 0.3
    preferredHighlightEnd: height * 0.7
    reuseItems: true

    delegate: Rectangle {
      required property string fileName
      required property string filePath
      required property bool fileIsDir
      required property int index
      readonly property bool current: ListView.isCurrentItem && list.activeFocus
      width: list.width
      height: Theme.px(78)
      radius: Theme.r(14)
      color: current ? Theme.alpha(Theme.activeBorder, Math.max(0.28, Theme.selectedFill + 0.1)) : Theme.alpha(Theme.surface, 0.5)
      border.width: current ? Theme.px(3) : Theme.px(1)
      border.color: current ? Theme.activeBorder : Theme.alpha(Theme.foreground, 0.1)
      Glyph {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: Theme.px(24)
        anchors.verticalCenter: parent.verticalCenter
        text: parent.fileIsDir ? "󰉋" : /\.(mp3|flac|ogg|opus|m4a|wav|aac|alac|wma)$/i.test(parent.fileName) ? "󰝚" : "󰎁"
        size: 32
        color: Theme.accent
      }
      Label {
        anchors.left: icon.right
        anchors.leftMargin: Theme.px(20)
        anchors.right: parent.right
        anchors.rightMargin: Theme.px(24)
        anchors.verticalCenter: parent.verticalCenter
        text: parent.fileName.replace(/\.[^.]+$/, "").replace(/[._]+/g, " ")
        size: 28
        color: Theme.foreground
      }
    }

    onCurrentIndexChanged: if (activeFocus) Sfx.play("move")

    Keys.onPressed: function(e) {
      if (Nav.isSelect(e) && list.currentIndex >= 0) {
        var path = files.get(list.currentIndex, "filePath")
        if (files.get(list.currentIndex, "fileIsDir")) { media.folder = path; list.currentIndex = 0 }
        else Tv.launch(Object.assign({}, media.app, { file: path, name: files.get(list.currentIndex, "fileName"), player: Tv.settings.musicPlayer || "mpv" }))
        e.accepted = true
      } else if (Nav.isBack(e)) {
        if (media.folder !== media.rootFolder) {
          media.folder = media.folder.replace(/\/[^\/]+\/?$/, "") || media.rootFolder
          list.currentIndex = 0
        } else Tv.back()
        e.accepted = true
      }
    }
  }

  Label {
    anchors.centerIn: list
    visible: files.status === FolderListModel.Ready && files.count === 0
    text: "Nothing to play in " + media.folder.replace(Tv.home, "~")
    size: 32
    color: Theme.dim
  }
}

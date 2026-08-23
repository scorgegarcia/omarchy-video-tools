import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "I18n.js" as I18n

// A deliberately self-contained panel: the shell owns the window and this
// plugin only invokes ffprobe/ffmpeg for the file the user dropped on it.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string videoPath: ""
  property string outputPath: ""
  readonly property string systemLanguageCode: root.systemLanguage()
  readonly property string language: persisted.languageOverride !== "" ? persisted.languageOverride : root.systemLanguageCode
  property int sourceWidth: 0
  property int sourceHeight: 0
  property int trimStart: 0
  property int trimEnd: 0
  property bool hasSelection: cropRect.width > 8 && cropRect.height > 8
  property bool exporting: false
  property bool fileDialogOpen: false
  property string status: ""
  property color surface: Color.popups.background
  property color foreground: Color.popups.text
  property color border: Color.popups.border
  property color accent: Color.accent
  property color selected: Color.menu.selectedBackground
  property string fontFamily: Style.font.family

  PersistentProperties {
    id: persisted
    reloadableId: "jvi-video-tools"
    property string languageOverride: ""
  }

  function t(key) { return I18n.text(root.language, key) }

  readonly property var languageOptions: [
    { label: root.t("system"), value: "" },
    { label: "English", value: "en" },
    { label: "Español", value: "es" },
    { label: "Português", value: "pt" },
    { label: "Français", value: "fr" },
    { label: "Deutsch", value: "de" },
    { label: "Italiano", value: "it" },
    { label: "日本語", value: "ja" },
    { label: "한국어", value: "ko" },
    { label: "中文", value: "zh" },
    { label: "Русский", value: "ru" }
  ]

  function languageIndex() {
    var selected = persisted.languageOverride
    if (selected === "") return 0
    for (var i = 0; i < root.languageOptions.length; i++)
      if (root.languageOptions[i].value === selected) return i
    return 0
  }

  function setLanguage(value) {
    persisted.languageOverride = String(value || "")
  }

  function systemLanguage() {
    var candidates = [Quickshell.env("LANGUAGE"), Quickshell.env("LANG"), Quickshell.env("LC_MESSAGES"), Qt.locale().name]
    for (var i = 0; i < candidates.length; i++) {
      var raw = String(candidates[i] || "").split(":")[0]
      var value = raw.toLowerCase().split("_")[0].split("-")[0]
      if (value !== "" && value !== "c" && value !== "posix") return value
    }
    return "en"
  }

  function localPath(value) {
    if (value && typeof value.toLocalFile === "function") {
      var nativePath = value.toLocalFile()
      if (nativePath) return nativePath
    }
    var text = String(value || "")
    if (text.indexOf("file://") === 0) text = text.replace(/^file:\/\//, "")
    try { return decodeURIComponent(text) } catch (e) { return text }
  }

  function fileUrl(path) {
    var parts = String(path || "").split("/")
    var encoded = []
    for (var i = 0; i < parts.length; i++) encoded.push(encodeURIComponent(parts[i]))
    return "file://" + (String(path || "").indexOf("/") === 0 ? "/" : "") + encoded.join("/")
  }

  function fileName(path) {
    var bits = path.split("/")
    return bits.length ? bits[bits.length - 1] : path
  }

  function stem(path) {
    var name = fileName(path)
    return name.replace(/\.[^.]+$/, "")
  }

  function open(payloadJson) {
    root.opened = true
    root.status = ""
    Qt.callLater(function() { dropFocus.forceActiveFocus() })
  }

  function close() {
    if (root.exporting) return
    player.stop()
    root.opened = false
    root.videoPath = ""
    root.outputPath = ""
    root.sourceWidth = 0
    root.sourceHeight = 0
    root.trimStart = 0
    root.trimEnd = 0
    root.status = ""
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "jvi.video-tools")
    else root.close()
  }

  function loadVideo(path) {
    if (!path || root.exporting) return
    root.videoPath = path
    root.outputPath = path.replace(/\.[^.]+$/, "") + "-edited.mp4"
    root.sourceWidth = 0
    root.sourceHeight = 0
    root.trimStart = 0
    root.trimEnd = 0
    root.status = root.t("preparing")
    player.source = root.fileUrl(path)
    player.play()
    probe.command = ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", path]
    probe.running = true
  }

  function formatTime(ms) {
    var total = Math.max(0, Math.floor(ms / 1000))
    var m = Math.floor(total / 60)
    var s = total % 60
    return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
  }

  function cropFilter() {
    if (!root.hasSelection || root.sourceWidth <= 0 || root.sourceHeight <= 0) return ""
    // PreserveAspectFit can leave letterbox margins inside videoSurface. Map
    // only the intersection with VideoOutput.contentRect, never the black
    // margins, and clamp the result to the real source dimensions.
    var content = videoOutput.contentRect
    if (content.width <= 0 || content.height <= 0) return ""
    var left = Math.max(cropRect.x, content.x)
    var top = Math.max(cropRect.y, content.y)
    var right = Math.min(cropRect.x + cropRect.width, content.x + content.width)
    var bottom = Math.min(cropRect.y + cropRect.height, content.y + content.height)
    if (right - left < 2 || bottom - top < 2) return ""

    var x = Math.floor((left - content.x) / content.width * root.sourceWidth)
    var y = Math.floor((top - content.y) / content.height * root.sourceHeight)
    var w = Math.floor((right - left) / content.width * root.sourceWidth)
    var h = Math.floor((bottom - top) / content.height * root.sourceHeight)
    x = Math.max(0, Math.min(root.sourceWidth - 2, x))
    y = Math.max(0, Math.min(root.sourceHeight - 2, y))
    w = Math.max(2, Math.min(root.sourceWidth - x, w))
    h = Math.max(2, Math.min(root.sourceHeight - y, h))
    x = x - (x % 2); y = y - (y % 2); w = w - (w % 2); h = h - (h % 2)
    if (w < 2 || h < 2) return ""
    return "crop=" + w + ":" + h + ":" + x + ":" + y
  }

  function exportVideo() {
    if (!root.videoPath || root.exporting) return
    var finish = root.trimEnd > 0 ? root.trimEnd : player.duration
    if (finish <= root.trimStart) finish = player.duration
    var args = ["ffmpeg", "-y", "-i", root.videoPath, "-ss", (root.trimStart / 1000).toFixed(3), "-to", (finish / 1000).toFixed(3)]
    var filter = root.cropFilter()
    if (filter !== "") args.push("-vf", filter)
    args.push("-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-c:a", "aac", root.outputPath)
    root.status = root.t("exporting")
    root.exporting = true
    exportProc.command = args
    exportProc.running = true
  }

  function resetCrop() {
    cropRect.x = 0; cropRect.y = 0
    cropRect.width = 0; cropRect.height = 0
  }

  function openVideoDialog() {
    root.fileDialogOpen = true
    videoDialog.open()
  }

  Process {
    id: probe
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split("x")
        if (parts.length === 2) {
          root.sourceWidth = Number(parts[0])
          root.sourceHeight = Number(parts[1])
        }
      }
    }
    onExited: function(exitCode) { if (exitCode === 0) root.status = root.t("ready") }
  }

  Process {
    id: exportProc
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.exporting = false
      if (exitCode === 0) {
        root.status = root.t("saved") + root.fileName(root.outputPath)
        notify.command = ["notify-send", root.t("app"), root.t("saved") + root.outputPath]
        notify.running = true
      } else {
        root.status = root.t("exportError")
      }
    }
  }

  Process { id: notify }

  FileDialog {
    id: videoDialog
    title: root.t("chooseVideo")
    fileMode: FileDialog.OpenFile
    nameFilters: [
      root.t("videoFiles") + " (*.mp4 *.mkv *.mov *.webm *.avi *.m4v *.wmv *.flv)",
      root.t("allFiles") + " (*)"
    ]
    onAccepted: {
      root.fileDialogOpen = false
      var chosen = selectedFile
      if ((!chosen || chosen.toString() === "") && selectedFiles.length > 0) chosen = selectedFiles[0]
      root.loadVideo(root.localPath(chosen))
    }
    onRejected: root.fileDialogOpen = false
    onVisibleChanged: if (!visible) root.fileDialogOpen = false
  }

  MediaPlayer {
    id: player
    videoOutput: videoOutput
    audioOutput: AudioOutput { volume: 0.8 }
    onDurationChanged: if (root.trimEnd === 0) root.trimEnd = duration
  }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "jvi-video-tools"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    // Keep only the editor card interactive. When the native file dialog is
    // open, remove the region entirely so the dialog can receive clicks even
    // though this panel remains on the overlay layer.
    mask: Region { item: root.fileDialogOpen ? null : dropFocus }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.08)
      // Do not dismiss on outside clicks. Native file dialogs temporarily
      // move focus outside this layer-surface; closing here would destroy the
      // editor while the user is choosing a file. ESC remains the close action.
      MouseArea { anchors.fill: parent; onClicked: {} }
    }

    Item {
      id: dropFocus
      anchors.centerIn: parent
      width: Math.min(Style.space(720), parent.width - Style.space(36))
      height: Math.min(Style.space(560), parent.height - Style.space(36))
      focus: true
      Keys.onEscapePressed: root.dismiss()

      Rectangle {
        anchors.fill: parent
        color: root.surface
        radius: Style.cornerRadius
        border.width: 1
        border.color: root.border
        MouseArea { anchors.fill: parent; onClicked: {} }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(18)
        spacing: Style.space(12)

        RowLayout {
          Layout.fillWidth: true
          Text { text: root.t("title"); color: root.foreground; font.family: root.fontFamily; font.bold: true; font.letterSpacing: 2; font.pixelSize: Style.font.title }
          Item { Layout.fillWidth: true }
          ComboBox {
            id: languageBox
            model: root.languageOptions
            textRole: "label"
            currentIndex: root.languageIndex()
            implicitWidth: Style.space(112)
            implicitHeight: Style.space(28)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            onActivated: function(index) { root.setLanguage(root.languageOptions[index].value) }
            Connections {
              target: root
              function onLanguageChanged() { languageBox.currentIndex = root.languageIndex() }
            }
          }
          Text { text: root.t("close"); color: Qt.alpha(root.foreground, 0.55); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        }

        Rectangle {
          id: videoSurface
          Layout.fillWidth: true
          Layout.fillHeight: true
          color: Qt.darker(root.surface, 1.35)
          radius: Style.cornerRadius
          border.width: 1
          border.color: root.border

          VideoOutput {
            id: videoOutput
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
          }

          DropArea {
            anchors.fill: parent
            onDropped: function(drop) {
              if (drop.hasUrls && drop.urls.length > 0) root.loadVideo(root.localPath(drop.urls[0]))
            }
            Rectangle {
              anchors.centerIn: parent
              width: Math.min(parent.width - 40, 330)
              height: 78
              visible: !root.videoPath
              color: Qt.alpha(root.surface, 0.92)
              radius: Style.cornerRadius
              border.width: 1
              border.color: root.accent
              Text { anchors.centerIn: parent; text: root.t("dropHint"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
              TapHandler { onTapped: root.openVideoDialog() }
            }
          }

          Rectangle {
            id: cropRect
            x: 0; y: 0; width: 0; height: 0
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            border.width: 2; border.color: root.accent
            visible: root.hasSelection
          }

          MouseArea {
            anchors.fill: parent
            enabled: !!root.videoPath && !root.exporting
            property real startX: 0
            property real startY: 0
            onPressed: function(mouse) { startX = mouse.x; startY = mouse.y; cropRect.x = startX; cropRect.y = startY; cropRect.width = 0; cropRect.height = 0 }
            onPositionChanged: function(mouse) { if (pressed) { cropRect.x = Math.min(startX, mouse.x); cropRect.y = Math.min(startY, mouse.y); cropRect.width = Math.abs(mouse.x - startX); cropRect.height = Math.abs(mouse.y - startY) } }
          }
        }

        Slider {
          Layout.fillWidth: true
          from: 0; to: Math.max(1, player.duration); value: player.position
          onMoved: player.position = value
          enabled: !!root.videoPath && !root.exporting
        }

        // Visual trim range. The normal playback slider above stays free for
        // scrubbing; this second track makes the punch-in/punch-out points
        // persistent and easy to verify before exporting.
        Item {
          Layout.fillWidth: true
          height: Style.space(34)
          visible: root.videoPath !== "" && player.duration > 0

          Rectangle {
            id: trimTrack
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(5)
            radius: height / 2
            color: Qt.alpha(root.foreground, 0.22)
          }

          Rectangle {
            anchors.verticalCenter: trimTrack.verticalCenter
            x: trimTrack.width * root.trimStart / Math.max(1, player.duration)
            width: Math.max(0, trimTrack.width * (Math.max(root.trimStart, root.trimEnd) - root.trimStart) / Math.max(1, player.duration))
            height: trimTrack.height
            radius: height / 2
            color: Qt.alpha(root.accent, 0.52)
          }

          Rectangle {
            id: inMarker
            x: Math.max(0, Math.min(trimTrack.width - width, trimTrack.width * root.trimStart / Math.max(1, player.duration) - width / 2))
            anchors.verticalCenter: trimTrack.verticalCenter
            width: Style.space(3)
            height: Style.space(24)
            radius: width / 2
            color: root.accent
          }

          Rectangle {
            id: outMarker
            x: Math.max(0, Math.min(trimTrack.width - width, trimTrack.width * (root.trimEnd > 0 ? root.trimEnd : player.duration) / Math.max(1, player.duration) - width / 2))
            anchors.verticalCenter: trimTrack.verticalCenter
            width: Style.space(3)
            height: Style.space(24)
            radius: width / 2
            color: root.accent
          }

          Text {
            anchors.bottom: trimTrack.top
            anchors.left: inMarker.right
            anchors.leftMargin: Style.space(4)
            text: "IN " + root.formatTime(root.trimStart)
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            anchors.bottom: trimTrack.top
            anchors.right: outMarker.left
            anchors.rightMargin: Style.space(4)
            text: "OUT " + root.formatTime(root.trimEnd > 0 ? root.trimEnd : player.duration)
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Text { text: root.formatTime(player.position) + " / " + root.formatTime(player.duration); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          Item { Layout.fillWidth: true }
          Text { text: root.status; color: Qt.alpha(root.foreground, 0.7); elide: Text.ElideMiddle; Layout.maximumWidth: Style.space(380); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Button { text: player.playbackState === MediaPlayer.PlayingState ? root.t("pause") : root.t("play"); enabled: !!root.videoPath; onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
          Button { text: root.t("markStart"); enabled: !!root.videoPath; onClicked: root.trimStart = player.position }
          Button { text: root.t("markEnd"); enabled: !!root.videoPath; onClicked: root.trimEnd = player.position }
          Button { text: root.t("clearCrop"); enabled: root.hasSelection; onClicked: root.resetCrop() }
          Item { Layout.fillWidth: true }
          Button { text: root.exporting ? root.t("exporting") : root.t("save"); enabled: !!root.videoPath && !root.exporting; onClicked: root.exportVideo() }
        }
      }
    }
  }
}

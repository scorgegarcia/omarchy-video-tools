import QtQuick
import QtQuick.Controls
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
  readonly property string language: root.systemLanguage()
  property int sourceWidth: 0
  property int sourceHeight: 0
  property int trimStart: 0
  property int trimEnd: 0
  property bool hasSelection: cropRect.width > 8 && cropRect.height > 8
  property bool exporting: false
  property string status: I18n.text(language, "drop")
  property color surface: Color.popups.background
  property color foreground: Color.popups.text
  property color border: Color.popups.border
  property color accent: Color.accent
  property color selected: Color.menu.selectedBackground
  property string fontFamily: Style.font.family

  function t(key) { return I18n.text(root.language, key) }

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
    var text = String(value || "")
    if (text.indexOf("file://") === 0) text = text.replace(/^file:\/\//, "")
    try { return decodeURIComponent(text) } catch (e) { return text }
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
    root.status = root.t("drop")
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
    root.status = root.t("drop")
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
    player.source = Qt.resolvedUrl("file://" + path)
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
    var x = Math.max(0, Math.floor(cropRect.x / videoSurface.width * root.sourceWidth))
    var y = Math.max(0, Math.floor(cropRect.y / videoSurface.height * root.sourceHeight))
    var w = Math.max(2, Math.floor(cropRect.width / videoSurface.width * root.sourceWidth))
    var h = Math.max(2, Math.floor(cropRect.height / videoSurface.height * root.sourceHeight))
    x = x - (x % 2); y = y - (y % 2); w = w - (w % 2); h = h - (h % 2)
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
    onExited: if (exitCode === 0) root.status = root.t("ready")
  }

  Process {
    id: exportProc
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.50)
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
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

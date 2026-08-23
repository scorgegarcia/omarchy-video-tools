import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "I18n.js" as I18n

Item {
  id: root
  property var bar: null
  property string moduleName: "jvi.video-tools"
  property var settings: ({})

  property string savedLanguage: ""
  readonly property string language: root.savedLanguage !== "" ? root.savedLanguage : "en"
  readonly property string label: I18n.text(language, "app")
  readonly property bool revealed: !root.bar || root.bar.centerSectionRevealHeld === true

  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/video-tools/settings.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.savedLanguage = String(JSON.parse(text()).language || "") } catch (e) { root.savedLanguage = "" }
    }
    onFileChanged: reload()
  }

  visible: revealed
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰕧"
    tooltipText: root.label
    horizontalMargin: 6
    verticalPadding: 6
    fontSize: Style.font.body
    onPressed: function() {
      if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
        root.bar.shell.summon("jvi.video-tools", "{}")
    }
  }
}

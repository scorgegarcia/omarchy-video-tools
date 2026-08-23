import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import "I18n.js" as I18n

Item {
  id: root
  property var bar: null
  property string moduleName: "jvi.video-tools"
  property var settings: ({})

  readonly property string language: root.systemLanguage()
  readonly property string label: I18n.text(language, "app")
  readonly property bool revealed: !root.bar || root.bar.centerSectionRevealHeld === true

  visible: revealed
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  function systemLanguage() {
    var candidates = [Quickshell.env("LANGUAGE"), Quickshell.env("LANG"), Quickshell.env("LC_MESSAGES"), Qt.locale().name]
    for (var i = 0; i < candidates.length; i++) {
      var raw = String(candidates[i] || "").split(":")[0]
      var value = raw.toLowerCase().split("_")[0].split("-")[0]
      if (value !== "" && value !== "c" && value !== "posix") return value
    }
    return "en"
  }

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

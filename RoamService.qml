import QtQuick
import Quickshell
import Quickshell.Io
import "WifiSettings.js" as Model

// Headless half of the plugin: runs `wifi-settings roam` once a minute, which
// moves to a higher-priority saved Wi-Fi network when one comes into range.
// The decision logic, the hold rules and the on/off switch all live in the
// helper; this only schedules it and forwards what it says to the shell log.
Item {
  id: root

  property var shell: null

  readonly property string script: Model.pathFromUrl(Qt.resolvedUrl("wifi-settings"))
  readonly property int interval: 60000

  Timer {
    // The first check waits a little so it does not compete with shell start
    // and NetworkManager's own autoconnect after login or resume.
    interval: 20000
    running: true
    onTriggered: roamTimer.start()
  }

  Timer {
    id: roamTimer
    interval: root.interval
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!roamProc.running) roamProc.running = true
  }

  Process {
    id: roamProc
    command: ["bash", root.script, "roam"]
    stdout: SplitParser {
      onRead: function(line) { if (line !== "") console.log("wifi-settings roam: " + line) }
    }
    stderr: SplitParser {
      onRead: function(line) { if (line !== "") console.warn("wifi-settings roam: " + line) }
    }
  }
}

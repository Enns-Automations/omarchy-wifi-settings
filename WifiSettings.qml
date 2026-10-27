import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "WifiSettings.js" as Model

// Saved Wi-Fi settings card, layered over the network panel's content: a
// popup inside the popup. Two views share it: the saved-network list (header
// gear) and one network's settings (row gear, or a pick from the list).
// Everything goes through the `wifi-settings` helper beside this file, by
// profile UUID. The password only enters shell memory on an explicit reveal
// and is dropped again on close or when the card moves to another network.
Item {
  id: root

  required property var bar
  signal changed()

  readonly property string script: Model.pathFromUrl(Qt.resolvedUrl("wifi-settings"))

  property bool opened: false
  property string view: "list"        // "list" | "detail"
  property bool fromList: false
  property string uuid: ""
  property string pendingSsid: ""
  property var rows: []
  property var profile: null
  property bool loading: false
  property string error: ""
  property string notice: ""

  property string password: ""
  property bool passwordVisible: false
  property string pwRequestUuid: ""

  property string actionKind: ""      // "autoconnect" | "priority" | "forget"
  property bool confirmForget: false

  // Whether RoamService acts; read and written through `wifi-settings roaming`.
  property bool roaming: true

  property bool cursorActive: false
  property int listIndex: 0
  property int detailIndex: 0
  readonly property var actions: Model.detailActions(profile)
  readonly property string cursorAction: cursorActive && detailIndex >= 0 && detailIndex < actions.length ? actions[detailIndex] : ""
  readonly property bool busy: actionKind !== ""
  readonly property real nowSeconds: clock.now

  // Height the panel must grow to so the card never clips.
  readonly property real requiredHeight: card.implicitHeight + Style.space(16)

  visible: opened
  focus: opened

  function nowSec() { return Math.floor(Date.now() / 1000) }

  function openList() {
    reset()
    view = "list"
    fromList = false
    opened = true
    loadList()
    loadRoaming()
    grabFocus()
  }

  function loadRoaming() {
    if (roamingProc.running) return
    roamingProc.command = ["bash", script, "roaming"]
    roamingProc.running = true
  }

  function setRoaming(on) {
    if (roamingProc.running) return
    roaming = on
    roamingProc.command = ["bash", script, "roaming", on ? "on" : "off"]
    roamingProc.running = true
  }

  function openSsid(ssid) {
    reset()
    view = "detail"
    fromList = false
    pendingSsid = ssid
    opened = true
    loadList()
    grabFocus()
  }

  function openUuid(nextUuid) {
    dropPassword()
    confirmForget = false
    error = ""
    notice = ""
    uuid = nextUuid
    profile = null
    view = "detail"
    detailIndex = 0
    loadDetail()
  }

  function back() {
    if (view === "detail" && fromList) {
      dropPassword()
      confirmForget = false
      error = ""
      view = "list"
      uuid = ""
      profile = null
      loadList()
      return
    }
    close()
  }

  function close() {
    opened = false
    reset()
  }

  function reset() {
    dropPassword()
    uuid = ""
    pendingSsid = ""
    profile = null
    rows = []
    error = ""
    notice = ""
    confirmForget = false
    cursorActive = false
    listIndex = 0
    detailIndex = 0
  }

  function dropPassword() {
    if (pwProc.running) pwProc.running = false
    pwRequestUuid = ""
    password = ""
    passwordVisible = false
  }

  function grabFocus() {
    Qt.callLater(function() { if (root.opened) root.forceActiveFocus() })
  }

  function loadList() {
    if (listProc.running) return
    loading = true
    listProc.command = ["bash", script, "list"]
    listProc.running = true
  }

  function loadDetail() {
    if (!uuid || showProc.running) return
    loading = true
    showProc.command = ["bash", script, "show", uuid]
    showProc.running = true
  }

  function setAutoconnect(on) {
    if (!profile || busy) return
    actionKind = "autoconnect"
    error = ""
    actionProc.command = ["bash", script, "autoconnect", uuid, on ? "yes" : "no"]
    actionProc.running = true
  }

  function setPriority(value) {
    if (!profile || busy) return
    var next = Model.clampPriority(value)
    if (next === profile.priority) return
    actionKind = "priority"
    error = ""
    actionProc.command = ["bash", script, "priority", uuid, String(next)]
    actionProc.running = true
  }

  function forget() {
    if (!profile || busy) return
    if (!confirmForget) {
      confirmForget = true
      return
    }
    confirmForget = false
    actionKind = "forget"
    error = ""
    actionProc.command = ["bash", script, "forget", uuid]
    actionProc.running = true
  }

  function togglePassword() {
    if (passwordVisible) { passwordVisible = false; return }
    if (password !== "") { passwordVisible = true; return }
    if (pwProc.running || !uuid) return
    error = ""
    pwRequestUuid = uuid
    pwProc.command = ["bash", script, "password", uuid]
    pwProc.running = true
  }

  // Straight from nmcli to the clipboard: the secret never passes through
  // QML or an argv.
  function copyPassword() {
    if (!uuid || copyProc.running) return
    error = ""
    copyProc.command = ["bash", "-c", "set -o pipefail; bash \"$0\" password \"$1\" | wl-copy --trim-newline --sensitive", script, uuid]
    copyProc.running = true
  }

  function activate(action) {
    if (action === "autoconnect") setAutoconnect(!profile.autoconnect)
    else if (action === "lower") setPriority(profile.priority - 1)
    else if (action === "raise") setPriority(profile.priority + 1)
    else if (action === "reveal") togglePassword()
    else if (action === "copy") copyPassword()
    else if (action === "forget") forget()
  }

  function moveCursor(delta) {
    if (!cursorActive) { cursorActive = true; return }
    if (view === "list") {
      // One stop past the last row is the roaming switch.
      listIndex = Math.max(0, Math.min(rows.length, listIndex + delta))
      if (listIndex < rows.length) listView.positionViewAtIndex(listIndex, ListView.Contain)
    } else {
      detailIndex = Math.max(0, Math.min(actions.length - 1, detailIndex + delta))
      if (cursorAction !== "forget") confirmForget = false
    }
  }

  Keys.onPressed: function(event) {
    if (!opened) return
    event.accepted = true
    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace || event.text === "h") {
      if (confirmForget) confirmForget = false
      else back()
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.text === "j") {
      moveCursor(1)
    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || event.text === "k") {
      moveCursor(-1)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space || event.text === "l") {
      if (!cursorActive) { cursorActive = true; return }
      if (view === "list") {
        if (listIndex === rows.length) {
          setRoaming(!roaming)
        } else if (listIndex >= 0 && listIndex < rows.length) {
          fromList = true
          openUuid(rows[listIndex].uuid)
        }
      } else {
        activate(cursorAction)
      }
    }
  }

  // Ticks the "used N min ago" captions while the card is up.
  QtObject {
    id: clock
    property real now: root.nowSec()
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: clock.now = root.nowSec()
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.opened) return
        root.rows = Model.parseList(text)
        clock.now = root.nowSec()
        if (root.listIndex > root.rows.length) root.listIndex = root.rows.length
        if (root.pendingSsid !== "") {
          var found = Model.uuidForSsid(root.rows, root.pendingSsid)
          root.pendingSsid = ""
          if (found) root.openUuid(found)
          else root.error = "No saved profile for this network"
        }
      }
    }
    onExited: root.loading = showProc.running
  }

  Process {
    id: roamingProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (value === "on" || value === "off") root.roaming = value === "on"
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.opened) root.error = "Could not change roaming"
    }
  }

  Process {
    id: showProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.opened) return
        var next = Model.parseShow(text)
        if (next && next.uuid === root.uuid) root.profile = next
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.opened && String(text).trim() !== "") root.error = String(text).trim()
    }
    onExited: {
      root.loading = listProc.running
      if (root.detailIndex >= root.actions.length) root.detailIndex = 0
    }
  }

  Process {
    id: pwProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.opened || root.pwRequestUuid !== root.uuid) return
        root.password = String(text || "").replace(/\n$/, "")
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.opened && String(text).trim() !== "") root.error = String(text).trim()
    }
    onExited: function(exitCode) {
      if (!root.opened || root.pwRequestUuid !== root.uuid) return
      if (exitCode === 0 && root.password !== "") root.passwordVisible = true
      else if (root.error === "") root.error = "Could not read the password"
    }
  }

  Process {
    id: copyProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.opened && String(text).trim() !== "") root.error = String(text).trim()
    }
    onExited: function(exitCode) {
      if (!root.opened) return
      if (exitCode === 0) {
        root.notice = "Password copied"
        noticeTimer.restart()
      } else if (root.error === "") {
        root.error = "Could not copy the password"
      }
    }
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var kind = root.actionKind
      root.actionKind = ""
      if (exitCode !== 0) {
        root.error = String(actionStderr.text || "").trim()
          || (kind === "forget" ? "Could not forget the network"
            : kind === "priority" ? "Could not change the priority"
            : "Could not change auto-connect")
        root.loadDetail()
        return
      }
      root.changed()
      if (kind === "forget") {
        if (root.fromList) root.back()
        else root.close()
      } else {
        root.loadDetail()
      }
    }
  }

  Timer {
    id: noticeTimer
    interval: 2000
    onTriggered: root.notice = ""
  }

  // Scrim over the panel content. A click on it backs out one level.
  Rectangle {
    anchors.fill: parent
    color: Util.alpha(Commons.Color.popups.background, 0.82)
    radius: Style.cornerRadius

    MouseArea {
      anchors.fill: parent
      onClicked: root.back()
    }
  }

  BorderSurface {
    id: card
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(8)
    implicitHeight: content.implicitHeight + card.contentTopInset + card.contentBottomInset
    height: implicitHeight
    color: Commons.Color.popups.background
    borderSpec: Border.flat(Commons.Color.accent, Style.normalBorderWidth)
    padding: Style.space(14)
    radius: Style.cornerRadius

    // Swallow clicks so only the scrim outside the card backs out.
    MouseArea { anchors.fill: parent; onClicked: {} }

    ColumnLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: card.contentTopInset
      anchors.leftMargin: card.contentLeftInset
      anchors.rightMargin: card.contentRightInset
      spacing: Style.space(10)

      // ---------- Title row ----------
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        PanelActionButton {
          visible: root.view === "detail" && root.fromList
          iconText: "󰁍"
          tooltipText: "Back"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.back()
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.view === "list"
              ? "Saved networks"
              : (root.profile ? (root.profile.ssid || "Hidden network") : "Wi-Fi settings")
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.view === "list"
              ? (root.rows.length === 1 ? "1 PROFILE" : root.rows.length + " PROFILES")
              : Model.statusLine(root.profile, root.nowSeconds).toUpperCase()
            visible: text !== ""
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
          }
        }

        PanelActionButton {
          iconText: "󰅖"
          tooltipText: "Close"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          Layout.alignment: Qt.AlignTop
          onClicked: root.close()
        }
      }

      PanelSeparator {
        Layout.fillWidth: true
        foreground: root.bar.foreground
      }

      // ---------- List view ----------
      Text {
        visible: root.view === "list" && !root.loading && root.rows.length === 0
        text: "No saved Wi-Fi networks"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      ListView {
        id: listView
        visible: root.view === "list" && root.rows.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, Style.space(260))
        spacing: Style.space(4)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        model: root.view === "list" ? root.rows : []

        delegate: CursorSurface {
          id: savedRow
          required property var modelData
          required property int index

          width: ListView.view.width
          implicitHeight: savedBody.implicitHeight + Style.spacing.rowPaddingX
          hasCursor: root.cursorActive && root.listIndex === index
          current: modelData.active
          foreground: root.bar.foreground

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.listIndex = savedRow.index }
            onClicked: {
              root.fromList = true
              root.openUuid(savedRow.modelData.uuid)
            }
          }

          RowLayout {
            id: savedBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(1)

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: savedRow.modelData.ssid || "Hidden network"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: Model.listCaption(savedRow.modelData, root.nowSeconds)
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "󰅂"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
            }
          }
        }
      }

      PanelSeparator {
        visible: root.view === "list"
        Layout.fillWidth: true
        foreground: root.bar.foreground
      }

      RowLayout {
        visible: root.view === "list"
        Layout.fillWidth: true
        spacing: Style.space(8)

        SettingLabel {
          Layout.fillWidth: true
          text: "Switch to higher priority"
        }

        ToggleSwitch {
          id: roamSwitch
          checked: root.roaming
          hasCursor: root.cursorActive && root.listIndex === root.rows.length
          foreground: root.bar.foreground
          onToggled: root.setRoaming(!checked)
          onHovered: function(on) { if (on) { root.cursorActive = true; root.listIndex = root.rows.length } }

          PanelToolTip {
            visible: roamSwitch.containsMouse
            text: "When a saved network with a higher priority comes into range, move to it"
            fontFamily: root.bar.fontFamily
          }
        }
      }

      // ---------- Detail view ----------
      GridLayout {
        visible: root.view === "detail" && !!root.profile
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Style.space(12)
        rowSpacing: Style.space(10)

        SettingLabel { text: "Security" }
        Text {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: root.profile ? Model.securityLabel(root.profile.keyMgmt) + (root.profile.hidden ? " · Hidden" : "") : ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        SettingLabel { text: "Auto-connect" }
        Item {
          Layout.fillWidth: true
          implicitHeight: autoSwitch.implicitHeight

          ToggleSwitch {
            id: autoSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.profile ? root.profile.autoconnect : false
            busy: root.actionKind === "autoconnect"
            hasCursor: root.cursorAction === "autoconnect"
            foreground: root.bar.foreground
            onToggled: root.setAutoconnect(!checked)
            onHovered: function(on) {
              if (!on) return
              root.cursorActive = true
              root.detailIndex = root.actions.indexOf("autoconnect")
            }

            PanelToolTip {
              visible: autoSwitch.containsMouse
              text: autoSwitch.checked ? "Stop joining this network on its own" : "Join this network when in range"
              fontFamily: root.bar.fontFamily
            }
          }
        }

        // Higher wins: NetworkManager picks it first, and the roaming service moves to
        // it from a lower one when it comes into range (RoamService.qml).
        SettingLabel { text: "Priority" }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(4)

          Item { Layout.fillWidth: true }

          PanelActionButton {
            iconText: "󰍴"
            tooltipText: "Lower priority"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            enabled: !root.busy
            hasCursor: root.cursorAction === "lower"
            onHovered: function(on) { if (on) { root.cursorActive = true; root.detailIndex = root.actions.indexOf("lower") } }
            onClicked: root.setPriority(root.profile.priority - 1)
          }

          Text {
            id: priorityValue
            Layout.minimumWidth: Style.space(28)
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.profile ? String(root.profile.priority) : ""
            color: root.bar.foreground
            opacity: root.actionKind === "priority" ? 0.5 : 1
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true

            MouseArea {
              id: priorityMouse
              anchors.fill: parent
              hoverEnabled: true
            }

            PanelToolTip {
              visible: priorityMouse.containsMouse
              text: "Higher wins. In range, a higher-priority network takes over from a lower one."
              fontFamily: root.bar.fontFamily
            }
          }

          PanelActionButton {
            iconText: "󰐕"
            tooltipText: "Raise priority"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            enabled: !root.busy
            hasCursor: root.cursorAction === "raise"
            onHovered: function(on) { if (on) { root.cursorActive = true; root.detailIndex = root.actions.indexOf("raise") } }
            onClicked: root.setPriority(root.profile.priority + 1)
          }
        }

        SettingLabel {
          visible: root.profile ? Model.hasPassword(root.profile.keyMgmt) : false
          text: "Password"
        }
        RowLayout {
          visible: root.profile ? Model.hasPassword(root.profile.keyMgmt) : false
          Layout.fillWidth: true
          spacing: Style.space(4)

          Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: root.passwordVisible ? root.password : "••••••••"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideLeft
          }

          PanelActionButton {
            iconText: root.passwordVisible ? "󰈉" : "󰈈"
            tooltipText: root.passwordVisible ? "Hide password" : "Show password"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorAction === "reveal"
            onHovered: function(on) { if (on) { root.cursorActive = true; root.detailIndex = root.actions.indexOf("reveal") } }
            onClicked: root.togglePassword()
          }

          PanelActionButton {
            iconText: "󰆏"
            tooltipText: "Copy password"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorAction === "copy"
            onHovered: function(on) { if (on) { root.cursorActive = true; root.detailIndex = root.actions.indexOf("copy") } }
            onClicked: root.copyPassword()
          }
        }
      }

      PanelSeparator {
        visible: root.view === "detail" && !!root.profile
        Layout.fillWidth: true
        foreground: root.bar.foreground
      }

      Button {
        id: forgetButton
        visible: root.view === "detail" && !!root.profile
        Layout.fillWidth: true
        text: root.actionKind === "forget" ? "Forgetting…"
          : root.confirmForget
            ? (root.profile && root.profile.active ? "Disconnect and forget?" : "Click again to forget")
            : "Forget network"
        iconText: "󰆴"
        fontSize: Style.font.bodySmall
        foreground: root.bar.urgent
        fontFamily: root.bar.fontFamily
        bordered: true
        active: root.confirmForget
        hasCursor: root.cursorAction === "forget"
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
        onHovered: function(on) {
          if (on) { root.cursorActive = true; root.detailIndex = root.actions.indexOf("forget") }
          else if (root.cursorAction !== "forget") root.confirmForget = false
        }
        onClicked: root.forget()
      }

      Text {
        visible: root.loading && (root.view === "list" ? root.rows.length === 0 : !root.profile)
        text: "Loading…"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: text !== ""
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: root.error !== "" ? root.error : root.notice
        color: root.error !== "" ? root.bar.urgent : root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }
  }

  component SettingLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}

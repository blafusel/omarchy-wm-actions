import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "io.github.blafusel.wm-actions"
  ipcTarget: "io.github.blafusel.wm-actions"

  // ---- action grid catalog, grouped by function ----
  // type "exec"  -> cmd is argv passed straight to Quickshell.execDetached
  // type "key"   -> key is a keysym name injected via a down/up send_key_state pair
  readonly property var actionSections: [
    {
      title: "LAUNCH",
      items: [
        { icon: "󱂬", label: "Launcher", type: "exec", cmd: ["omarchy-menu", "toggle"] },
        { icon: "󰖟", label: "Browser",  type: "exec", cmd: ["omarchy-launch-browser"] },
        { icon: "", label: "Terminal", type: "exec", cmd: ["omarchy-launch-terminal"] }
      ]
    },
    {
      title: "WINDOW",
      items: [
        { icon: "󰘖", label: "Scratchpad", type: "exec", cmd: ["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special('scratchpad')"] },
        { icon: "󰹗", label: "Float",      type: "exec", cmd: ["hyprctl", "dispatch", "hl.dsp.window.float({ action = 'toggle' })"] },
        { icon: "󰊓", label: "Fullscreen", type: "exec", cmd: ["hyprctl", "dispatch", "hl.dsp.window.fullscreen({ mode = 'fullscreen' })"] }
      ]
    },
    {
      title: "KEYS",
      items: [
        { icon: "⎋", label: "Escape", type: "key", key: "Escape" },
        { icon: "⏎", label: "Return", type: "key", key: "Return" }
      ]
    },
    {
      title: "SYSTEM",
      items: [
        { icon: "󰄀", label: "Screenshot",  type: "exec", cmd: ["omarchy-capture-screenshot"] },
        { icon: "󰥻", label: "Keybindings", type: "exec", cmd: ["omarchy-menu-keybindings"] }
      ]
    }
  ]

  // Windows on the currently-visible workspace of the focused monitor, each
  // as { address, title, class }.
  property var windows: []
  property int currentWorkspaceId: 0

  function runAction(action) {
    if (action.type === "key") sendKey(action.key)
    else Quickshell.execDetached(action.cmd)
    root.close()
  }

  // send_key_state (down, then up ~50ms later) instead of send_shortcut --
  // mirrors Omarchy's own "Universal cut" bind in
  // default/hypr/bindings/clipboard.lua, adopted there specifically to avoid
  // a Hyprland send_shortcut stuck-key bug (hyprwm/Hyprland#14099).
  function sendKey(key) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.send_key_state({ mods = '', key = '" + key + "', state = 'down' })"])
    keyUpTimer.pendingKey = key
    keyUpTimer.restart()
  }

  Timer {
    id: keyUpTimer
    interval: 50
    repeat: false
    property string pendingKey: ""
    onTriggered: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.send_key_state({ mods = '', key = '" + pendingKey + "', state = 'up' })"])
  }

  function refreshWindows() {
    if (!monitorsProc.running) monitorsProc.running = true
  }

  function handleMonitors(raw) {
    var data
    try { data = JSON.parse(raw) } catch (e) { return }
    if (!Array.isArray(data)) return
    var focused = data.find(function(m) { return m.focused === true })
    if (!focused) return
    var special = focused.specialWorkspace
    var active = focused.activeWorkspace
    root.currentWorkspaceId = (special && special.id) ? special.id : (active ? active.id : 0)
    if (!clientsProc.running) clientsProc.running = true
  }

  // Character-based truncation -- Button's own Text has no elide support, so
  // an untruncated title just overflows the button's fixed width instead of
  // wrapping or clipping.
  readonly property int titleMaxChars: 28

  function truncateTitle(text) {
    if (text.length <= titleMaxChars) return text
    return text.slice(0, titleMaxChars - 1) + "…"
  }

  function handleClients(raw) {
    var data
    try { data = JSON.parse(raw) } catch (e) { return }
    if (!Array.isArray(data)) return
    root.windows = data
      .filter(function(c) { return c.workspace && c.workspace.id === root.currentWorkspaceId })
      .map(function(c) { return { address: c.address, title: root.truncateTitle(c.title || c.class), class: c.class } })
  }

  function focusWindow(address) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = 'address:" + address + "' })"])
    root.close()
  }

  function closeWindow(address) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.close({ window = 'address:" + address + "' })"])
    closeRefreshTimer.restart()
  }

  Timer {
    id: closeRefreshTimer
    interval: 300
    repeat: false
    onTriggered: root.refreshWindows()
  }

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleMonitors(text) }
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleClients(text) }
  }

  onOpenedChanged: if (opened) refreshWindows()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍜"
    tooltipText: "WM Actions"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Repeater {
          model: root.actionSections
          delegate: Column {
            id: sectionColumn
            required property var modelData
            width: column.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: sectionColumn.modelData.title
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            GridLayout {
              width: parent.width
              columns: 3
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(8)

              Repeater {
                model: sectionColumn.modelData.items
                delegate: Button {
                  required property var modelData
                  Layout.fillWidth: true
                  iconText: modelData.icon
                  text: modelData.label
                  fontSize: Style.font.bodySmall
                  iconSize: Style.font.title
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  bordered: true
                  horizontalPadding: Style.spacing.controlPaddingX
                  verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
                  onClicked: root.runAction(modelData)
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "WINDOWS — THIS WORKSPACE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            visible: root.windows.length === 0
            text: "No other windows"
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.windows
            delegate: Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(6)

              Button {
                width: parent.width - closeBtn.width - parent.spacing
                leftAlign: true
                text: modelData.title
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.focusWindow(modelData.address)
              }

              Button {
                id: closeBtn
                iconText: "✕"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.closeWindow(modelData.address)
              }
            }
          }
        }
      }
    }
  }
}

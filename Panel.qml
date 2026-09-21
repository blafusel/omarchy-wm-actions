import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import qs.Commons

// Standalone PanelWindow instead of the usual KeyboardPanel-anchored
// click-away popup. Two problems this fixes that a pin toggle on
// KeyboardPanel couldn't:
//   1. WlrKeyboardFocus.None below means opening/clicking this panel never
//      steals keyboard focus -- the window you were using just keeps focus
//      the whole time (verified live: a synthetic keypress reaches a
//      focused terminal while the panel is open).
//   2. There's no full-screen click-catcher, so clicking other windows while
//      this panel is open reaches them normally instead of being swallowed.
// Tradeoff: no click-away-to-dismiss, no fade animation, and no mutual
// exclusion with other bar popups (opening this doesn't close another popup
// and vice versa) -- KeyboardPanel owned all of that internally.
// Previous KeyboardPanel-based version: tag v1.0.0 (or the pre-1.1.0 commits).
Panel {
  id: root
  moduleName: "io.github.blafusel.wm-actions"
  ipcTarget: "io.github.blafusel.wm-actions"

  // Pin: keeps the panel open after firing a grid action. Outside clicks and
  // the bar icon never close it regardless (see header note), so this only
  // still governs the post-action auto-close.
  property bool sticky: false

  // Overrides the base Panel's close() -- same pattern omarchy.network's
  // Panel.qml uses (root.controller is the public alias for the base's
  // internal PanelController) -- to gate every close path on `sticky`.
  function close() {
    if (root.sticky) return
    root.controller.hide()
  }

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
      title: "CLIPBOARD",
      items: [
        // SUPER mods reuses Omarchy's own "Universal copy/paste/cut" binds
        // (default/hypr/bindings/clipboard.lua), which pick the right raw
        // key per-app (e.g. Ctrl+Insert in terminals) -- so these stay
        // correct instead of just blasting Ctrl+C into a shell.
        { icon: "󰆏", label: "Copy",  type: "key", key: "C", mods: "SUPER" },
        { icon: "󰆒", label: "Paste", type: "key", key: "V", mods: "SUPER" },
        { icon: "󰆐", label: "Cut",   type: "key", key: "X", mods: "SUPER" }
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

  // Voxtype dictation state, streamed continuously (not gated on the panel
  // being open) so the switch already shows the right state the moment the
  // panel opens, same as the bar's own Dictation indicator.
  property string dictationState: "idle"
  readonly property bool dictationRecording: dictationState === "recording"
  readonly property bool dictationTranscribing: dictationState === "transcribing"

  function handleDictationStatus(raw) {
    var data = Util.parseModuleJson(raw)
    root.dictationState = String(data.alt || data.class || "idle")
  }

  function toggleDictation() {
    Quickshell.execDetached(["voxtype", "record", "toggle"])
  }

  // The window that had keyboard focus right before this panel opened.
  // sendKey() below targets it explicitly via send_key_state's `window`
  // field rather than trusting ambient seat focus -- clicking a button in
  // this panel is a real pointer event on its surface, and empirically that
  // was enough to disrupt which window Hyprland considered keyboard-focused
  // at the moment the synthetic key landed (KEYS/CLIPBOARD actions fire
  // ~0ms after the click; dictation's own trigger doesn't need focus at all,
  // which is why only KEYS/CLIPBOARD showed the symptom). Captured on every
  // open (button press and IPC/keyboard summon alike).
  property string lastFocusedAddress: ""

  function captureFocusedWindow() {
    if (!activeWindowProc.running) activeWindowProc.running = true
  }

  function handleActiveWindow(raw) {
    var data
    try { data = JSON.parse(raw) } catch (e) { return }
    if (data && data.address) root.lastFocusedAddress = data.address
  }

  Process {
    id: activeWindowProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleActiveWindow(text) }
  }

  Process {
    command: ["bash", "-c", "omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.handleDictationStatus(data) }
    }
  }

  function runAction(action) {
    if (action.type === "key") sendKey(action.key, action.mods || "")
    else Quickshell.execDetached(action.cmd)
    root.close()
  }

  // send_key_state (down, then up ~50ms later) instead of send_shortcut --
  // mirrors Omarchy's own "Universal cut" bind in
  // default/hypr/bindings/clipboard.lua, adopted there specifically to avoid
  // a Hyprland send_shortcut stuck-key bug (hyprwm/Hyprland#14099). The
  // `window` field targets the captured pre-open window explicitly instead
  // of trusting ambient seat focus (see lastFocusedAddress above); falls
  // back to no `window` field (ambient focus) if nothing was captured.
  function windowClause() {
    return root.lastFocusedAddress ? (", window = 'address:" + root.lastFocusedAddress + "'") : ""
  }

  function sendKey(key, mods) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.send_key_state({ mods = '" + mods + "', key = '" + key + "', state = 'down'" + root.windowClause() + " })"])
    keyUpTimer.pendingKey = key
    keyUpTimer.pendingMods = mods
    keyUpTimer.restart()
  }

  Timer {
    id: keyUpTimer
    interval: 50
    repeat: false
    property string pendingKey: ""
    property string pendingMods: ""
    onTriggered: Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.send_key_state({ mods = '" + pendingMods + "', key = '" + pendingKey + "', state = 'up'" + root.windowClause() + " })"])
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

  // Covers every way the panel can open: the bar-icon press below fires
  // before root.toggle() runs (earliest, most reliable capture), and this
  // catches IPC/keyboard-summoned opens that skip the button entirely.
  onOpenedChanged: {
    if (opened) {
      refreshWindows()
      captureFocusedWindow()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍜"
    tooltipText: "WM Actions"
    onPressed: function(b) {
      if (!root.opened) root.captureFocusedWindow()
      root.toggle()
    }
  }

  // Same window the bar-icon button renders in, used only to pick the right
  // monitor for the floating panel below (multi-monitor: each screen has its
  // own bar instance).
  readonly property var anchorWindow: button.QsWindow ? button.QsWindow.window : null

  PanelWindow {
    id: floatWin
    visible: root.opened
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-wm-actions-float"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never take keyboard focus -- every control here is mouse-only (grid
    // buttons, a switch), so there's nothing that needs it, and leaving it
    // None is what keeps this panel from stealing focus off whatever window
    // you were using (see header note).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property int gap: Style.gapsOut
    readonly property int hostBarSize: root.bar ? root.bar.barSize : 0
    readonly property string barPos: root.bar ? root.bar.position : "top"

    anchors {
      top: barPos !== "bottom"
      bottom: barPos === "bottom"
      left: barPos === "left"
      right: barPos !== "left"
    }
    margins {
      top: (barPos === "top" ? hostBarSize : 0) + gap
      bottom: (barPos === "bottom" ? hostBarSize : 0) + gap
      left: (barPos === "left" ? hostBarSize : 0) + gap
      right: (barPos === "right" ? hostBarSize : 0) + gap
    }

    readonly property real maxCardHeight: Math.max(120, (screen ? screen.height : 900) - margins.top - margins.bottom)

    implicitWidth: card.width
    implicitHeight: card.height

    BorderSurface {
      id: card
      width: Style.space(300)
      height: Math.min(contentColumn.implicitHeight + contentTopInset + contentBottomInset, floatWin.maxCardHeight)
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      Column {
        id: contentColumn
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        spacing: Style.space(14)

        Toggle {
          width: contentColumn.width
          label: "Keep panel open"
          description: "Don't close after firing an action"
          checked: root.sticky
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.sticky = !root.sticky
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Repeater {
          model: root.actionSections
          delegate: Column {
            id: sectionColumn
            required property var modelData
            width: contentColumn.width
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

        Column {
          width: contentColumn.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "DICTATION"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          // Standalone (not in actionSections): it's a stateful switch, not
          // a fire-and-forget action, so it needs its own icon/label/active
          // binding and must not close the panel on click.
          Button {
            width: parent.width
            leftAlign: true
            iconText: root.dictationRecording ? "󰓛" : "󰍬"
            iconSpinning: root.dictationTranscribing
            text: root.dictationRecording ? "Stop dictation" : (root.dictationTranscribing ? "Transcribing…" : "Start dictation")
            fontSize: Style.font.bodySmall
            iconSize: Style.font.title
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            active: root.dictationRecording
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
            onClicked: root.toggleDictation()
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: contentColumn.width
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

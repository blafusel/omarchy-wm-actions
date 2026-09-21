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

  // The panel never auto-closes after firing an action (outside clicks and
  // the bar icon don't close it either -- see header note), so it only
  // closes via an explicit bar-icon click or IPC close. Base Panel's own
  // close()/toggle() handle that; nothing to override here.

  // ---- action grid catalog, grouped by function ----
  // type "exec"  -> cmd is argv passed straight to Quickshell.execDetached
  // type "key"   -> key is a keysym name injected via a down/up send_key_state pair
  // id           -> stable key for the favorites list; never rename/reuse.
  readonly property var actionSections: [
    {
      title: "CLIPBOARD",
      items: [
        // SUPER mods reuses Omarchy's own "Universal copy/paste/cut" binds
        // (default/hypr/bindings/clipboard.lua), which pick the right raw
        // key per-app (e.g. Ctrl+Insert in terminals) -- so these stay
        // correct instead of just blasting Ctrl+C into a shell.
        { id: "clipboard.copy",  icon: "󰆏", label: "Copy",  type: "key", key: "C", mods: "SUPER" },
        { id: "clipboard.paste", icon: "󰆒", label: "Paste", type: "key", key: "V", mods: "SUPER" },
        { id: "clipboard.cut",   icon: "󰆐", label: "Cut",   type: "key", key: "X", mods: "SUPER" }
      ]
    },
    {
      title: "KEYS",
      items: [
        { id: "keys.escape", icon: "⎋", label: "Escape", type: "key", key: "Escape" },
        { id: "keys.return", icon: "⏎", label: "Return", type: "key", key: "Return" }
      ]
    },
    {
      title: "LAUNCH",
      items: [
        { id: "launch.launcher", icon: "󱂬", label: "Launcher", type: "exec", cmd: ["omarchy-menu", "toggle"] },
        { id: "launch.browser",  icon: "󰖟", label: "Browser",  type: "exec", cmd: ["omarchy-launch-browser"] },
        { id: "launch.terminal", icon: "", label: "Terminal", type: "exec", cmd: ["omarchy-launch-terminal"] }
      ]
    },
    {
      title: "SYSTEM",
      items: [
        { id: "system.screenshot",  icon: "󰄀", label: "Screenshot",  type: "exec", cmd: ["omarchy-capture-screenshot"] },
        { id: "system.keybindings", icon: "󰥻", label: "Keybindings", type: "exec", cmd: ["omarchy-menu-keybindings"] }
      ]
    }
  ]

  // ---- favorites ----
  // Persisted into this widget's shell.json entry via bar.shell.updateEntryInline
  // (same mechanism the tray uses for pinned items), so they survive shell
  // restarts. `favorites` and `favoritesOnly` are derived straight from
  // `settings` (reactive: re-reads whenever the entry changes), so no local
  // copy to keep in sync -- toggling just writes through and the read-side
  // updates itself.
  readonly property var favorites: root.setting("favorites", [])
  readonly property bool favoritesOnly: root.setting("favoritesOnly", false)

  function isFavorite(favId) {
    return root.favorites.indexOf(favId) !== -1
  }

  function persistSettings(patch) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var merged = {}
    for (var k in root.settings) merged[k] = root.settings[k]
    for (var k2 in patch) merged[k2] = patch[k2]
    root.bar.shell.updateEntryInline(root.moduleName, merged)
  }

  function toggleFavorite(favId) {
    var next = root.favorites.slice()
    var idx = next.indexOf(favId)
    if (idx !== -1) next.splice(idx, 1)
    else next.push(favId)
    root.persistSettings({ favorites: next })
  }

  function toggleFavoritesOnly() {
    root.persistSettings({ favoritesOnly: !root.favoritesOnly })
  }

  readonly property var windowSectionFavIds: ["window.scratchpad", "window.float", "window.fullscreen", "window.close", "window.stash"]
  readonly property bool windowSectionHasVisibleItems: !root.favoritesOnly || root.windowSectionFavIds.some(function(favId) { return root.isFavorite(favId) })

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

  // Workspace name of that same captured window ("2", "special:scratchpad",
  // ...), used to decide which WINDOW button to show (Send to Scratchpad vs.
  // Send to Desktop) and, combined with scratchpadOrigins below, to send a
  // window back to the workspace it actually came from instead of just
  // "whatever workspace is current" when it's pulled back out.
  property string lastFocusedWorkspaceName: ""
  readonly property bool lastFocusedInScratchpad: root.lastFocusedWorkspaceName === "special:scratchpad"

  // address -> origin workspace name, recorded right before a window is sent
  // to the scratchpad so "Send to Desktop" can restore it precisely.
  property var scratchpadOrigins: ({})

  function captureFocusedWindow() {
    if (!activeWindowProc.running) activeWindowProc.running = true
  }

  function handleActiveWindow(raw) {
    var data
    try { data = JSON.parse(raw) } catch (e) { return }
    if (data && data.address) {
      root.lastFocusedAddress = data.address
      root.lastFocusedWorkspaceName = (data.workspace && data.workspace.name) ? data.workspace.name : ""
    }
  }

  Process {
    id: activeWindowProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleActiveWindow(text) }
  }

  function closeActiveWindow() {
    if (root.lastFocusedAddress) {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.close({ window = 'address:" + root.lastFocusedAddress + "' })"])
    }
  }

  function sendActiveToScratchpad() {
    var addr = root.lastFocusedAddress
    if (addr) {
      root.scratchpadOrigins[addr] = root.lastFocusedWorkspaceName
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ window = 'address:" + addr + "', workspace = 'special:scratchpad' })"])
    }
  }

  function sendActiveToDesktop() {
    var addr = root.lastFocusedAddress
    if (addr) {
      var origin = root.scratchpadOrigins[addr]
      if (origin && origin !== "special:scratchpad") {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ window = 'address:" + addr + "', workspace = '" + origin + "' })"])
      } else {
        // No remembered origin (fresh session, or it never went through
        // "Send to Scratchpad" here) -- fall back to just showing the
        // scratchpad special workspace, same as the toggle button below.
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special('scratchpad')"])
      }
      delete root.scratchpadOrigins[addr]
    }
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

  // Clicking a panel button flips window activation away from the target
  // (see windowClause note above) and back -- fine for a terminal, but a
  // web app whose chat/input box blurs (and its own JS collapses or resets
  // it) on window-blur may not re-focus that same element the instant
  // activation returns. An explicit hl.dsp.focus plus a short settle delay
  // before the actual keypress gives that kind of app's own refocus-on-
  // activate logic (if it has any) a chance to run first. This is a
  // best-effort mitigation, not a guarantee -- it can't fix a page whose JS
  // never restores focus on window activation at all.
  function sendKey(key, mods) {
    if (root.lastFocusedAddress) {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = 'address:" + root.lastFocusedAddress + "' })"])
    }
    keyDownTimer.pendingKey = key
    keyDownTimer.pendingMods = mods
    keyDownTimer.restart()
  }

  Timer {
    id: keyDownTimer
    interval: 60
    repeat: false
    property string pendingKey: ""
    property string pendingMods: ""
    onTriggered: {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.send_key_state({ mods = '" + pendingMods + "', key = '" + pendingKey + "', state = 'down'" + root.windowClause() + " })"])
      keyUpTimer.pendingKey = pendingKey
      keyUpTimer.pendingMods = pendingMods
      keyUpTimer.restart()
    }
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
          label: "Favorites only"
          description: "Hide everything except starred buttons"
          checked: root.favoritesOnly
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.toggleFavoritesOnly()
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: contentColumn.width
          spacing: Style.space(8)
          visible: root.windowSectionHasVisibleItems

          PanelSectionHeader {
            text: "WINDOW"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          // Hand-written, not in actionSections: Close/Send-to-Scratchpad/
          // Send-to-Desktop all need the pre-open captured window address,
          // and the scratchpad button's icon/label/handler swap depending on
          // whether that window is currently in the scratchpad.
          GridLayout {
            width: parent.width
            columns: 3
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)

            FavButton {
              Layout.fillWidth: true
              visible: !root.favoritesOnly || root.isFavorite("window.scratchpad")
              iconText: "󰘖"
              text: "Scratchpad"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              isFavorite: root.isFavorite("window.scratchpad")
              onFavoriteToggled: root.toggleFavorite("window.scratchpad")
              onClicked: root.runAction({ type: "exec", cmd: ["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special('scratchpad')"] })
            }

            FavButton {
              Layout.fillWidth: true
              visible: !root.favoritesOnly || root.isFavorite("window.float")
              iconText: "󰹗"
              text: "Float"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              isFavorite: root.isFavorite("window.float")
              onFavoriteToggled: root.toggleFavorite("window.float")
              onClicked: root.runAction({ type: "exec", cmd: ["hyprctl", "dispatch", "hl.dsp.window.float({ action = 'toggle' })"] })
            }

            FavButton {
              Layout.fillWidth: true
              visible: !root.favoritesOnly || root.isFavorite("window.fullscreen")
              iconText: "󰊓"
              text: "Fullscreen"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              isFavorite: root.isFavorite("window.fullscreen")
              onFavoriteToggled: root.toggleFavorite("window.fullscreen")
              onClicked: root.runAction({ type: "exec", cmd: ["hyprctl", "dispatch", "hl.dsp.window.fullscreen({ mode = 'fullscreen' })"] })
            }

            FavButton {
              Layout.fillWidth: true
              visible: !root.favoritesOnly || root.isFavorite("window.close")
              iconText: "󰖭"
              text: "Close"
              tooltipText: "Close window"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              isFavorite: root.isFavorite("window.close")
              onFavoriteToggled: root.toggleFavorite("window.close")
              onClicked: root.closeActiveWindow()
            }

            FavButton {
              Layout.fillWidth: true
              visible: !root.favoritesOnly || root.isFavorite("window.stash")
              iconText: root.lastFocusedInScratchpad ? "󰄝" : "󰄠"
              text: root.lastFocusedInScratchpad ? "Restore" : "Stash"
              tooltipText: root.lastFocusedInScratchpad ? "Send back to its original workspace" : "Send to scratchpad"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              isFavorite: root.isFavorite("window.stash")
              onFavoriteToggled: root.toggleFavorite("window.stash")
              onClicked: root.lastFocusedInScratchpad ? root.sendActiveToDesktop() : root.sendActiveToScratchpad()
            }
          }
        }

        Repeater {
          model: root.actionSections
          delegate: Column {
            id: sectionColumn
            required property var modelData
            width: contentColumn.width
            spacing: Style.space(8)
            visible: !root.favoritesOnly || sectionColumn.modelData.items.some(function(it) { return root.isFavorite(it.id) })

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
                delegate: FavButton {
                  required property var modelData
                  Layout.fillWidth: true
                  visible: !root.favoritesOnly || root.isFavorite(modelData.id)
                  iconText: modelData.icon
                  text: modelData.label
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  isFavorite: root.isFavorite(modelData.id)
                  onFavoriteToggled: root.toggleFavorite(modelData.id)
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

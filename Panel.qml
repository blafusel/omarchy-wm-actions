import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
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

  IpcHandler {
    target: "io.github.blafusel.wm-actions.debug"
    function callSendKey(key: string, mods: string): void {
      root.sendKey(key, mods)
    }
  }

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
        // See copySelection/cutSelection/pasteClipboard: these no longer go
        // through Hyprland's "Universal clipboard" SUPER+C/V/X binds, which
        // never fire for synthetic input.
        { id: "clipboard.copy",  icon: "󰆏", label: "Copy",  type: "copy" },
        { id: "clipboard.paste", icon: "󰆒", label: "Paste", type: "paste" },
        { id: "clipboard.cut",   icon: "󰆐", label: "Cut",   type: "cut" }
      ]
    },
    {
      title: "KEYS",
      items: [
        { id: "keys.escape",    icon: "⎋", label: "Escape",    type: "key", key: "Escape" },
        { id: "keys.up",        icon: "󰁝", label: "Up",        type: "key", key: "Up", repeat: true },
        { id: "keys.return",    icon: "⏎", label: "Return",    type: "key", key: "Return" },
        { id: "keys.backspace", icon: "󰁮", label: "10x Ctrl+Backspace", tooltip: "Fires Ctrl+Backspace 10x fast -- deletes everything in the current text field", type: "burst", key: "BackSpace", mods: "CTRL", count: 10, intervalMs: 60 },
        { id: "keys.ctrl_c",    icon: "󰓛", label: "Ctrl+C",    type: "key", key: "C", mods: "CTRL" }
      ]
    },
    {
      title: "LAUNCH",
      items: [
        { id: "launch.launcher", icon: "󱂬", label: "Launcher", type: "exec", cmd: ["omarchy-menu", "toggle"] },
        { id: "launch.browser",  icon: "󰖟", label: "Browser",  type: "exec", cmd: ["omarchy-launch-browser"] },
        { id: "launch.terminal", icon: "󰆍", label: "Terminal", type: "exec", cmd: ["omarchy-launch-terminal"] },
        // gtk-launch (not a hardcoded binary path) so this works regardless
        // of install method (snap/flatpak/native) -- the desktop file id is
        // the .desktop filename without its extension.
        { id: "launch.plex",     icon: "󰚺", label: "Plex",     type: "exec", cmd: ["gtk-launch", "plex-desktop_plex-desktop"] },
        { id: "launch.claude",   icon: "󰚩", label: "Claude",   type: "exec", cmd: ["gtk-launch", "com.anthropic.Claude"] },
        // No .desktop file -- CLI tool, so it needs a terminal to run in
        // (its own TUI, same as the Add-new-app terminal below).
        { id: "launch.herdr",    icon: "󰳆", label: "Herdr",    type: "exec", cmd: ["omarchy-launch-terminal", "herdr"] }
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

  // Collapsed section titles, persisted in shell.json like favorites so
  // collapse state survives shell restarts.
  readonly property var collapsedSections: root.setting("collapsedSections", [])

  function isCollapsed(title) {
    return root.collapsedSections.indexOf(title) !== -1
  }

  // Reorderable sections. sectionOrder is the persisted order, normalized so
  // unknown ids are dropped and any new/missing section is appended in
  // default order. dragOrder overrides it live while a header is being
  // dragged and is only written to settings on release.
  readonly property var defaultSectionOrder: ["WINDOW"].concat(root.actionSections.map(function(s) { return s.title }), ["WINDOWS", "STASHED"])
  readonly property var sectionOrder: {
    var saved = root.setting("sectionOrder", [])
    var out = saved.filter(function(id) { return root.defaultSectionOrder.indexOf(id) !== -1 })
    root.defaultSectionOrder.forEach(function(id) { if (out.indexOf(id) === -1) out.push(id) })
    return out
  }
  property var dragOrder: null
  property string draggingId: ""

  function sectionRow(id) {
    var i = (root.dragOrder || root.sectionOrder).indexOf(id)
    return i < 0 ? 999 : i
  }

  // Moves `id` to wherever the pointer (gy, in sectionsGrid coordinates)
  // currently is, by swapping into the visible section under it.
  function dragSection(id, gy) {
    root.draggingId = id
    var order = (root.dragOrder || root.sectionOrder).slice()
    var cur = order.indexOf(id)
    var kids = sectionsGrid.children
    for (var i = 0; i < kids.length; i++) {
      var k = kids[i]
      if (!k.sectionId || k.sectionId === id || !k.visible) continue
      if (gy >= k.y && gy < k.y + k.height) {
        var target = order.indexOf(k.sectionId)
        if (target !== -1 && target !== cur) {
          order.splice(cur, 1)
          order.splice(target, 0, id)
          root.dragOrder = order
        }
        break
      }
    }
  }

  function endDrag() {
    if (root.dragOrder) root.persistSettings({ sectionOrder: root.dragOrder })
    root.dragOrder = null
    root.draggingId = ""
  }

  function toggleCollapsed(title) {
    var next = root.collapsedSections.slice()
    var idx = next.indexOf(title)
    if (idx !== -1) next.splice(idx, 1)
    else next.push(title)
    root.persistSettings({ collapsedSections: next })
  }

  readonly property var windowSectionFavIds: ["window.scratchpad", "window.float", "window.fullscreen", "window.close", "window.stash", "window.group", "window.ungroup"]
  readonly property bool windowSectionHasVisibleItems: !root.favoritesOnly || root.windowSectionFavIds.some(function(favId) { return root.isFavorite(favId) })

  // ---- settings menu ----
  // settingsOpen is local UI state (not persisted -- it's just whether the
  // menu is expanded right now). showWindowsOverview/showStashOverview and
  // disabledActionIds persist the same way favorites do.
  property bool settingsOpen: false

  readonly property bool showWindowsOverview: root.setting("showWindowsOverview", true)
  readonly property bool showStashOverview: root.setting("showStashOverview", true)

  function toggleShowWindowsOverview() {
    root.persistSettings({ showWindowsOverview: !root.showWindowsOverview })
  }

  function toggleShowStashOverview() {
    root.persistSettings({ showStashOverview: !root.showStashOverview })
  }

  readonly property bool singleColumn: root.setting("singleColumn", false)

  function toggleSingleColumn() {
    root.persistSettings({ singleColumn: !root.singleColumn })
  }

  // Pin: open automatically on shell (re)start instead of waiting for a
  // bar-icon click, like a pinned/always-present widget. Closing it
  // manually afterward still works as normal -- this only affects what
  // happens at startup.
  readonly property bool pinned: root.setting("pinned", false)

  function togglePinned() {
    root.persistSettings({ pinned: !root.pinned })
  }

  // `settings` starts as {} and is filled in by the host shell after this
  // plugin is instantiated, asynchronously -- Component.onCompleted read it
  // too early (pinned always looked false right at startup). Apply once,
  // the first time real settings land, instead: a guarded onSettingsChanged
  // so later toggles (e.g. flipping Favorites only while the panel is
  // closed) don't re-open it out from under a manual close.
  //
  // Even with settings populated, calling open() right away still silently
  // gets reverted a moment later -- something elsewhere in shell startup
  // (outside this plugin) resets panel state during its own init window.
  // Confirmed live: the exact same open() call sticks fine once issued well
  // after startup. Retry on a beat instead of guessing one fixed delay,
  // stopping as soon as it actually sticks (checked one tick later, since
  // the revert isn't instant either) or after a bounded number of tries.
  property bool _pinApplied: false
  property int _pinOpenAttempts: 0
  onSettingsChanged: {
    if (!root._pinApplied && Object.keys(root.settings).length > 0) {
      root._pinApplied = true

      // Self-heal follow_mouse corruption left over from a session that got
      // killed (omarchy restart shell) while this panel was forcing
      // follow_mouse=0 for its click-targeting. Normally
      // disableFollowMouse()/restoreFollowMouse() run in open/close pairs,
      // but a killed process never reaches the close side -- and since the
      // pin below reopens the panel unconditionally, the next
      // disableFollowMouse() just sees followMouseForced already true and
      // reasserts 0 again rather than restoring, so it stays stuck at 0
      // forever across every subsequent restart until something closes the
      // panel by hand. Don't trust the persisted followMouseOriginal to
      // restore to either -- a session that captured its "original" while
      // already stuck at 0 (the exact same restart-while-forced trap, one
      // level up) poisons it to 0 too, confirmed live: shell.json held
      // followMouseForced: false, followMouseOriginal: 0 simultaneously,
      // which should be impossible if original were ever trustworthy.
      // Re-derive the correct value from DP-1's actual current width
      // instead -- the same width-based rule input.lua's
      // omarchy-monitor-profile-sync keeps live, kept in sync here too so
      // this doesn't drift from it: 1 at full 5120 width, 2 at split 2560.
      // Also decides whether to pin-reopen the panel this start -- see its
      // own comment for why that's no longer unconditional here.
      selfHealProc.running = true
    }
  }

  Timer {
    id: pinOpenTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root._pinOpenAttempts += 1
      root.captureFocusedWindow()
      root.open()
      pinOpenCheckTimer.restart()
    }
  }

  Timer {
    id: pinOpenCheckTimer
    interval: 400
    repeat: false
    onTriggered: {
      if (root.opened || root._pinOpenAttempts >= 8) pinOpenTimer.stop()
    }
  }

  // In single-column mode the panel narrows to fit the widest visible
  // button instead of staying at the fixed 3-column card width -- read
  // from each grid's own implicitWidth (its natural, unstretched content
  // size), not the stretched width it's actually drawn at.
  function widestButtonWidth() {
    var maxW = windowGrid.implicitWidth
    for (var i = 0; i < sectionsRepeater.count; i++) {
      var item = sectionsRepeater.itemAt(i)
      if (item && item.visible && item.gridImplicitWidth > maxW) maxW = item.gridImplicitWidth
    }
    return maxW
  }

  // Per-button disable, covering every actionSections item across all
  // categories (CLIPBOARD/KEYS/LAUNCH/SYSTEM) -- hides a button from the
  // grid without touching actionSections itself.
  readonly property var disabledActionIds: root.setting("disabledActionIds", [])

  function isActionDisabled(actionId) {
    return root.disabledActionIds.indexOf(actionId) !== -1
  }

  function toggleActionDisabled(actionId) {
    var next = root.disabledActionIds.slice()
    var idx = next.indexOf(actionId)
    if (idx !== -1) next.splice(idx, 1)
    else next.push(actionId)
    root.persistSettings({ disabledActionIds: next })
  }

  // Adding a new LAUNCH app (picking its .desktop id, an icon, and where it
  // goes) is exactly the kind of change this plugin's own development has
  // been done as -- see e.g. the Plex button -- so hand it to a fresh Claude
  // Code session in this plugin's directory instead of building a mouse-only
  // form for something that's really a small code change. Runs in a real
  // terminal since Claude Code needs a keyboard/TTY, unlike the rest of this
  // mouse-only panel.
  function launchAddAppAssistant() {
    var prompt = "Add a new app button to the LAUNCH section of the WM Actions Omarchy plugin in this directory (Panel.qml's actionSections). Ask me which app I want added. Then: find its .desktop file id (use gtk-launch with that id, not a hardcoded binary path -- see the Plex button for the pattern), pick a fitting Nerd Font glyph the same way the existing icons were chosen, insert it into the LAUNCH items in a sensible order, bump manifest.json's version, add a README.md changelog entry, restart the omarchy shell and confirm no QML errors, then follow this repo's existing git commit/tag/push conventions (check recent git log and CLAUDE.md before committing)."
    Quickshell.execDetached(["omarchy-launch-terminal", "bash", "-c",
      "cd ~/.config/omarchy/plugins/blafusel.wm-actions && exec claude \"$1\"", "_", prompt])
  }

  // Windows on the currently-visible workspace of the focused monitor, each
  // as { address, title, class }.
  property var windows: []
  property int currentWorkspaceId: 0
  property int activeWorkspaceId: 0
  property var stashedWindows: []

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

  // Distinct from the toggle button's "stop" action: stop+toggle stops
  // recording AND transcribes/outputs it, while cancel discards the
  // recording (or in-flight transcription) with no output at all -- for
  // when you started dictating and changed your mind mid-sentence.
  function cancelDictation() {
    Quickshell.execDetached(["voxtype", "record", "cancel"])
  }

  // Compact mode: shows only a tiny top-right floating widget with the
  // dictation switch instead of the full action grid, for when the grid
  // isn't needed and screen space matters. Persisted the same way as
  // favoritesOnly, so the bar icon reopens in whichever mode (full or
  // audio-only) was last active instead of always defaulting back to full.
  readonly property bool audioOnlyMode: root.setting("audioOnlyMode", false)

  function enterAudioOnlyMode() {
    root.persistSettings({ audioOnlyMode: true })
  }

  // The compact widget's close button: both closes the panel (setting
  // audioOnlyMode alone would flip visibility straight to the full grid
  // instead of dismissing anything, since floatWin/audioWin are gated on
  // `opened`, not just the mode) and resets the persisted mode back to
  // full, so a plain bar-icon reopen after this lands on the full grid --
  // distinct from just bar-icon-closing an open audio-only panel, which
  // keeps remembering audio-only for next time.
  function exitAudioOnlyMode() {
    root.persistSettings({ audioOnlyMode: false })
    root.close()
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

  // Workspace name of that same captured window ("2", "special:scratchpad", ...).
  property string lastFocusedWorkspaceName: ""

  // Same window's Hyprland window-rule tags (e.g. "terminal*"), used to pick
  // Ctrl+V vs. Shift+Insert for Paste -- see pasteClipboard() below.
  property bool lastFocusedIsTerminal: false

  // Whether the captured window is currently part of a group ("grouped" is
  // a non-empty array of member addresses, including itself, once grouped).
  // Lets Group/Ungroup each be a one-way action instead of both sharing
  // Hyprland's own single toggle dispatcher -- see groupActiveWindow()/
  // ungroupActiveWindow() below.
  property bool lastFocusedIsGrouped: false

  // address -> origin workspace name, recorded right before a window is sent
  // to the scratchpad so Restore can send it back precisely. Session-only
  // (not persisted): a window stashed in an earlier session, or by some
  // other means (keybind), has no entry here -- restoreWindow() below falls
  // back to the current workspace in that case.
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
      // Dynamic tags carry a trailing "*" (see Omarchy's own
      // active_window_is_terminal() in default/hypr/bindings/clipboard.lua).
      root.lastFocusedIsTerminal = Array.isArray(data.tags) && data.tags.some(function(t) {
        return String(t).replace(/\*$/, "") === "terminal"
      })
      root.lastFocusedIsGrouped = Array.isArray(data.grouped) && data.grouped.length > 0
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

  // Hyprland only exposes grouping as a single toggle (hl.dsp.group.toggle
  // -- confirmed live: same call on the same window flips "grouped": []
  // to "grouped": [self] and back). Group reads lastFocusedIsGrouped first
  // so it's a one-way action (no-op if already grouped) instead of flipping
  // the wrong way depending on current state. Re-captures afterward so the
  // cached state (and the next click) reflects the change. Toggle only
  // ever grouped/ungrouped a lone window in testing, so it's fine here.
  function groupActiveWindow() {
    if (root.lastFocusedAddress && !root.lastFocusedIsGrouped) {
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.group.toggle({ window = 'address:" + root.lastFocusedAddress + "' })"])
      groupRefreshTimer.restart()
    }
  }

  // NOT hl.dsp.group.toggle here -- confirmed live on a real multi-window
  // group: toggle targeted at one member's address dissolved the entire
  // group (every member came back ungrouped), not just that one window.
  // HL.Group:remove(window) (via `hyprctl eval`, the one hyprctl entry
  // point that runs arbitrary Lua rather than a single dispatcher
  // expression) is the primitive that actually removes just the one
  // window and leaves the rest of the group intact -- verified live on a
  // disposable 3-window group (removed window ends up ungrouped, the
  // other two stay grouped with each other).
  function moveActiveWindow(dir) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ direction = '" + dir + "'" + root.windowClause() + " })"])
  }

  function ungroupActiveWindow() {
    if (root.lastFocusedAddress && root.lastFocusedIsGrouped) {
      Quickshell.execDetached(["hyprctl", "eval",
        "local gw = hl.get_window('address:" + root.lastFocusedAddress + "'); if gw and gw.group then gw.group:remove(gw) end"])
      groupRefreshTimer.restart()
    }
  }

  Timer {
    id: groupRefreshTimer
    interval: 150
    repeat: false
    onTriggered: root.captureFocusedWindow()
  }

  // Stashes whatever was focused right before the panel opened. Restoring
  // is deliberately NOT the same button/click -- by the time you come back
  // for a window you stashed "for later", focus has long since moved on to
  // something else, so there's nothing meaningful left to toggle back on
  // this button. Restore instead happens per-window from the STASHED list
  // below, which works off the actual scratchpad contents, not ambient focus.
  function stashActiveWindow() {
    var addr = root.lastFocusedAddress
    if (addr) {
      root.scratchpadOrigins[addr] = root.lastFocusedWorkspaceName
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ window = 'address:" + addr + "', workspace = 'special:scratchpad' })"])
    }
  }

  function restoreWindow(address) {
    var origin = root.scratchpadOrigins[address]
    var target = (origin && origin !== "special:scratchpad") ? origin : String(root.activeWorkspaceId)
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.move({ window = 'address:" + address + "', workspace = '" + target + "' })"])
    delete root.scratchpadOrigins[address]
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
    else if (action.type === "copy") copySelection()
    else if (action.type === "cut") cutSelection()
    else if (action.type === "paste") pasteClipboard()
    else if (action.type === "burst") burstKey(action.key, action.mods || "", action.count || 1, action.intervalMs || 60)
    else Quickshell.execDetached(action.cmd)
  }

  // Fires one key N times fast on a single click (e.g. 10x Ctrl+Backspace
  // to clear a field) -- distinct from repeatOnHold, which fires once per
  // held-down tick instead of a fixed count on one click. First press goes
  // through sendKey() (explicit refocus + settle, same as every other
  // first press); the rest use sendKeyFast's lighter ~25ms cycle, same as
  // FavButton's own repeat ticks. 60ms spacing leaves comfortable headroom
  // over that ~25ms cycle -- see sendKeyFast's own comment on the
  // starvation risk of scheduling faster than a cycle completes.
  property var burstState: ({ key: "", mods: "", remaining: 0 })

  function burstKey(key, mods, count, intervalMs) {
    root.sendKey(key, mods)
    root.burstState = { key: key, mods: mods, remaining: count - 1 }
    if (root.burstState.remaining > 0) {
      burstTimer.interval = intervalMs
      burstTimer.restart()
    }
  }

  Timer {
    id: burstTimer
    repeat: true
    onTriggered: {
      root.sendKeyFast(root.burstState.key, root.burstState.mods)
      root.burstState.remaining -= 1
      if (root.burstState.remaining <= 0) burstTimer.stop()
    }
  }

  // Copy/Cut/Paste used to send SUPER+C/V/X hoping Hyprland's global
  // "Universal clipboard" binds (default/hypr/bindings/clipboard.lua) would
  // fire and translate to the right raw shortcut per app. They never did --
  // verified directly: even SUPER+S (toggle scratchpad, a trivial bind)
  // silently no-ops when sent via send_key_state, workspace never changes.
  // Global keybinds apparently only respond to real hardware input, not
  // synthetic virtual-keyboard events -- likely a deliberate wlroots/
  // Hyprland boundary against exactly this kind of automation, not
  // something we can route around with cleverer key sequencing.
  //
  // Copy/Cut instead read the Wayland PRIMARY SELECTION -- auto-populated
  // by most apps/terminals whenever text is selected, independent of any
  // keypress at all (confirmed live: selecting text in the Claude desktop
  // app populated it with zero synthetic input involved). Paste falls back
  // to a plain Ctrl+V/Shift+Insert: an ordinary app/terminal-level
  // shortcut, not a compositor bind, so send_key_state delivers it
  // reliably the same way it does Escape/Return.
  function copySelection() {
    Quickshell.execDetached(["bash", "-c", "wl-paste --primary --no-newline 2>/dev/null | wl-copy"])
  }

  function cutSelection() {
    Quickshell.execDetached(["bash", "-c", "wl-paste --primary --no-newline 2>/dev/null | wl-copy"])
    sendKey("Delete", "")
  }

  function pasteClipboard() {
    sendKey(root.lastFocusedIsTerminal ? "Insert" : "V", root.lastFocusedIsTerminal ? "SHIFT" : "CTRL")
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

  // Fast path for FavButton's auto-repeat ticks (e.g. holding Backspace):
  // skips sendKey's explicit hl.dsp.focus + 60ms settle, since those exist
  // to recover from a click disrupting focus -- already handled by the
  // first press of the hold, which does go through sendKey(). Still
  // window-targeted via windowClause(), just no re-settle each tick. Total
  // cycle ~25ms, comfortably inside FavButton's 75ms repeat interval.
  function sendKeyFast(key, mods) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.send_key_state({ mods = '" + mods + "', key = '" + key + "', state = 'down'" + root.windowClause() + " })"])
    keyFastUpTimer.pendingKey = key
    keyFastUpTimer.pendingMods = mods
    keyFastUpTimer.restart()
  }

  Timer {
    id: keyFastUpTimer
    interval: 25
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
    // Always the plain (non-special) workspace, even while the scratchpad is
    // shown -- restoreWindow()'s fallback needs a real destination, never
    // the special workspace itself.
    root.activeWorkspaceId = active ? active.id : 0
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
    root.stashedWindows = data
      .filter(function(c) { return c.workspace && c.workspace.name === "special:scratchpad" })
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
      root.disableFollowMouse()
      root.setNoWarps(true)
    } else {
      root.restoreFollowMouse()
      root.setNoWarps(false)
    }
  }

  // Panel actions focus their target window (hl.dsp.focus), which makes
  // Hyprland warp the cursor to that window's center. cursor:no_warps stops
  // that, but only while the panel is up so keybind-driven focus changes
  // keep warping normally. Restored to false (Hyprland's default, and this
  // setup's live value) rather than captured: no persisted state needed,
  // and a killed session is healed by the startup self-heal, which resets it.
  function setNoWarps(on) {
    Quickshell.execDetached(["hyprctl", "eval", "hl.config({ cursor = { no_warps = " + (on ? "true" : "false") + " } })"])
  }

  // Every button click is a real pointer event -- with focus-follows-mouse
  // on, moving the cursor across the panel to click something steals
  // keyboard focus from whatever window CLIPBOARD/KEYS/the dictation
  // switch is supposed to be targeting, out from under the panel's own
  // explicit window-targeting (windowClause() etc.). Without this, none of
  // that targeting actually holds up. `opened` alone covers both the full
  // grid and the audio-only widget (see floatWin/audioWin's visible
  // bindings above -- exactly one is up whenever opened is true), so this
  // one flag is the right single signal for "the panel is up in some
  // form". Restored to whatever it actually was, not hardcoded back to 1,
  // in case the user runs with it already off (or set to 2) normally.
  //
  // The captured value has to be persisted (shell.json), not just a plain
  // property -- `omarchy restart shell` kills the process outright, so
  // restoreFollowMouse() from the previous session never runs while
  // pinned (always open). A plain property would then get re-captured on
  // the pin's auto-reopen with the CURRENT value, which is already the
  // disabled 0 from before the restart -- trapping 0 as the "original" to
  // restore to, forever, on every subsequent restart. followMouseForced
  // (also persisted) guards against exactly that: only actually capture
  // while nothing has it force-disabled yet.
  readonly property int followMouseOriginal: root.setting("followMouseOriginal", 1)
  readonly property bool followMouseForced: root.setting("followMouseForced", false)

  function disableFollowMouse() {
    if (root.followMouseForced) {
      // Already forced (e.g. a killed-and-restarted pinned session) --
      // reassert 0 without touching the persisted original.
      Quickshell.execDetached(["hyprctl", "eval", "hl.config({ input = { follow_mouse = 0 } })"])
    } else if (!followMouseProc.running) {
      followMouseProc.running = true
    }
  }

  function handleFollowMouseOption(raw) {
    var data
    try { data = JSON.parse(raw) } catch (e) { data = null }
    var value = (data && typeof data.int === "number") ? data.int : 1
    root.persistSettings({ followMouseOriginal: value, followMouseForced: true })
    Quickshell.execDetached(["hyprctl", "eval", "hl.config({ input = { follow_mouse = 0 } })"])
  }

  function restoreFollowMouse() {
    Quickshell.execDetached(["hyprctl", "eval", "hl.config({ input = { follow_mouse = " + root.followMouseOriginal + " } })"])
    root.persistSettings({ followMouseForced: false })
  }

  Process {
    id: followMouseProc
    command: ["hyprctl", "-j", "getoption", "input:follow_mouse"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleFollowMouseOption(text) }
  }

  // One-shot startup self-heal -- see onSettingsChanged above. Re-derives
  // the correct follow_mouse value from DP-1's live width (same rule as
  // omarchy-monitor-profile-sync) and forces it, instead of trusting
  // whatever this plugin's own persisted state claims right now.
  //
  // Also decides whether the pin should reopen the panel this start. Pinned
  // used to mean "reopen on every shell start, unconditionally" -- but
  // flipping DP-1's OSD switch forces a full Hyprland restart (see
  // omarchy-set-resolution), which restarts this shell too, so the panel
  // was popping open on EVERY resolution switch in either direction, and on
  // any unrelated restart besides. Narrowed to one specific transition:
  // open only when DP-1's width just went from 5120 (wide) to 2560 (split)
  // since the last time this ran -- not wide->split->wide round trips, not
  // restarts where the width didn't change at all. lastKnownWidth is
  // persisted (shell.json) so this survives the process restart it's
  // detecting across; first run ever (no persisted value) has nothing to
  // compare against, so it just records the width without opening.
  function handleSelfHealMonitors(raw) {
    var monitors, dp1
    try { monitors = JSON.parse(raw) } catch (e) { monitors = null }
    if (monitors) {
      for (var i = 0; i < monitors.length; i++) {
        if (monitors[i] && monitors[i].name === "DP-1") { dp1 = monitors[i]; break }
      }
    }
    var width = dp1 && typeof dp1.width === "number" ? dp1.width : 0
    var correct = width >= 5120 ? 1 : 2
    Quickshell.execDetached(["hyprctl", "eval", "hl.config({ input = { follow_mouse = " + correct + " } })"])
    root.setNoWarps(false)

    var previousWidth = typeof root.settings.lastKnownWidth === "number" ? root.settings.lastKnownWidth : width
    var switchedToSplit = previousWidth >= 5120 && width > 0 && width < 5120
    root.persistSettings({ followMouseForced: false, followMouseOriginal: correct, lastKnownWidth: width })

    if (switchedToSplit && root.settings.pinned === true) pinOpenTimer.restart()
  }

  Process {
    id: selfHealProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.handleSelfHealMonitors(text) }
  }

  // The panel no longer auto-closes, so it can sit open across workspace
  // switches, window moves, and focus changes -- refresh live instead of
  // leaving the windows list and the captured target window (which drives
  // CLIPBOARD/KEYS targeting and the WINDOW section's Stash/Restore label)
  // stuck on whatever was true at the moment the panel first opened.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.opened || !event || !event.name) return
      var name = String(event.name)
      if (name === "workspace" || name === "workspacev2" || name === "focusedmon" || name === "focusedmonv2"
          || name === "activewindow" || name === "activewindowv2"
          || name === "openwindow" || name === "closewindow"
          || name === "movewindow" || name === "movewindowv2") {
        root.refreshWindows()
        root.captureFocusedWindow()
      }
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
      if (b === Qt.MiddleButton) {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special('scratchpad')"])
        return
      }
      if (b === Qt.RightButton) {
        root.enterAudioOnlyMode()
        if (!root.opened) root.open()
        return
      }
      // Plain open/close toggle -- which view appears (full grid or the
      // compact audio-only widget) follows the persisted audioOnlyMode
      // property below, same as favoritesOnly already did.
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
    visible: root.opened && !root.audioOnlyMode
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    color: "transparent"
    // Pinned reserves real screen space (tiled windows get pushed clear of
    // it, dock-style) instead of just floating on top where anything can
    // still tile underneath/behind it.
    exclusionMode: root.pinned ? ExclusionMode.Auto : ExclusionMode.Ignore

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

    // Pinned also anchors the opposite vertical edge, spanning the full
    // height of its side of the screen instead of just a corner -- a
    // real wlr-layer-shell exclusive zone reserves space along the whole
    // length of an anchored edge, so ExclusionMode.Auto below can't compute
    // a sane reservation from a corner anchor (two edges, no single "this
    // is the dock edge" to measure from). The card itself still only
    // occupies its natural content height at the top; the rest of the
    // anchored strip stays transparent but keeps the reservation live.
    anchors {
      top: barPos !== "bottom" || root.pinned
      bottom: barPos === "bottom" || root.pinned
      left: barPos === "left"
      right: barPos !== "left"
    }
    // Pinned needs a *different* margin shape, not just a smaller one: once
    // ExclusionMode.Auto makes this surface respect other layers' reserved
    // zones (Ignore doesn't), the compositor already pushes it clear of the
    // bar's own 26px reservation on its own. Manually adding hostBarSize to
    // the margin on top of that double-counts the bar's height -- confirmed
    // live (margins.top computed 26 as intended, but the surface still
    // rendered at y=52, exactly hostBarSize + the compositor's own
    // bar-respecting push). Ignore mode (not pinned) never got that
    // compositor push, so it still needs the full self-computed margin.
    margins {
      top: root.pinned ? 0 : ((barPos === "top" ? hostBarSize : 0) + gap)
      bottom: root.pinned ? 0 : ((barPos === "bottom" ? hostBarSize : 0) + gap)
      left: root.pinned ? 0 : ((barPos === "left" ? hostBarSize : 0) + gap)
      right: root.pinned ? 0 : ((barPos === "right" ? hostBarSize : 0) + gap)
    }

    readonly property real maxCardHeight: Math.max(120, (screen ? screen.height : 900) - margins.top - margins.bottom)

    implicitWidth: card.width
    implicitHeight: card.height

    BorderSurface {
      id: card
      // Floored at 240: the Favorites-only/Settings Toggle rows have a fixed
      // implicitWidth of Style.space(240) (Toggle.qml) regardless of their
      // label/description text, so anything narrower truncates/overlaps them.
      width: root.singleColumn
        ? Math.max(Style.space(240), root.widestButtonWidth() + contentLeftInset + contentRightInset)
        : Style.space(300)
      height: Math.min(contentColumn.implicitHeight + dictationBar.height + Style.space(14) + contentTopInset + contentBottomInset, floatWin.maxCardHeight)
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      // Sticky: lives outside the ScrollView so it stays pinned at the top
      // while the rest of the panel scrolls underneath.
      Column {
        id: dictationBar
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        spacing: Style.space(8)

        PanelSectionHeader {
          text: "DICTATION"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        // Standalone (not in actionSections): it's a stateful switch, not
        // a fire-and-forget action, so it needs its own icon/label/active
        // binding and must not close the panel on click.
        Row {
          width: parent.width
          spacing: Style.space(6)

          Button {
            width: parent.width - audioOnlyBtn.width - (cancelBtn.visible ? cancelBtn.width + parent.spacing : 0) - parent.spacing
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

          // Only shown mid-recording/transcription -- nothing to cancel
          // otherwise. Discards instead of stopping-and-transcribing, for
          // when you change your mind partway through dictating.
          Button {
            id: cancelBtn
            visible: root.dictationRecording || root.dictationTranscribing
            iconText: "󰍭"
            fontSize: Style.font.bodySmall
            iconSize: Style.font.title
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
            onClicked: root.cancelDictation()
          }

          Button {
            id: audioOnlyBtn
            iconText: "󰋋"
            fontSize: Style.font.bodySmall
            iconSize: Style.font.title
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
            onClicked: root.enterAudioOnlyMode()
          }

          WrappedTooltip {
            hoverSource: cancelBtn.visible && cancelBtn.hot
            text: "Cancel dictation -- discard, no transcription"
            fontFamily: root.bar.fontFamily
          }

          WrappedTooltip {
            hoverSource: audioOnlyBtn.hot
            text: "Audio only -- shrink to just the dictation switch, top-right corner"
            fontFamily: root.bar.fontFamily
          }
        }

        Toggle {
          width: parent.width
          label: "Favorites only"
          checked: root.favoritesOnly
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.toggleFavoritesOnly()
        }
      }

      // ScrollView is a no-op wrapper when content fits (no scrollbar,
      // no flicking) -- only kicks in once contentColumn's natural height
      // (everything stacked single-column, say) exceeds the card's own
      // height cap (floatWin.maxCardHeight above), which a plain Column
      // would otherwise just silently overflow past the card's bottom edge.
      ScrollView {
        id: scrollArea
        x: card.contentLeftInset
        y: card.contentTopInset + dictationBar.height + Style.space(14)
        width: card.width - card.contentLeftInset - card.contentRightInset
        height: card.height - (y + card.contentBottomInset)
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: contentColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
        id: contentColumn
        width: scrollArea.availableWidth
        spacing: Style.space(14)

        Button {
          id: settingsBtn
          width: contentColumn.width
          leftAlign: true
          iconText: "󰒓"
          text: "Settings"
          fontSize: Style.font.bodySmall
          iconSize: Style.font.title
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          active: root.settingsOpen
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
          onClicked: root.settingsOpen = !root.settingsOpen
        }

        WrappedTooltip {
          hoverSource: settingsBtn.hot
          text: root.settingsOpen ? "Collapse settings" : "Windows/stash overview, per-app toggles, add a new app"
          fontFamily: root.bar.fontFamily
        }

        Column {
          width: contentColumn.width
          spacing: Style.space(8)
          visible: root.settingsOpen

          Toggle {
            width: parent.width
            label: "Windows overview"
            description: "Show the WINDOWS -- THIS WORKSPACE list below"
            checked: root.showWindowsOverview
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.toggleShowWindowsOverview()
          }

          Toggle {
            width: parent.width
            label: "Stash overview"
            description: "Show the STASHED list below"
            checked: root.showStashOverview
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.toggleShowStashOverview()
          }

          Toggle {
            width: parent.width
            label: "Single column"
            description: "Stack the action grid one button per row instead of three"
            checked: root.singleColumn
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.toggleSingleColumn()
          }

          Toggle {
            width: parent.width
            label: "Pin panel"
            description: "Reserve screen space (tiled windows won't overlap it) and reopen automatically on shell restart"
            checked: root.pinned
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.togglePinned()
          }

          Repeater {
            model: root.actionSections
            delegate: Column {
              id: settingsSectionColumn
              required property var modelData
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: settingsSectionColumn.modelData.title
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }

              Repeater {
                model: settingsSectionColumn.modelData.items
                delegate: Row {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    width: parent.width - appToggleBtn.width - parent.spacing
                    height: appToggleBtn.height
                    text: modelData.icon + "  " + modelData.label
                    color: root.bar.foreground
                    opacity: root.isActionDisabled(modelData.id) ? 0.4 : 1.0
                    verticalAlignment: Text.AlignVCenter
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Button {
                    id: appToggleBtn
                    text: root.isActionDisabled(modelData.id) ? "Enable" : "Disable"
                    fontSize: Style.font.bodySmall
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    bordered: true
                    horizontalPadding: Style.spacing.controlPaddingX
                    verticalPadding: Style.spacing.controlPaddingY
                    onClicked: root.toggleActionDisabled(modelData.id)
                  }
                }
              }
            }
          }

          Button {
            id: addAppBtn
            width: parent.width
            leftAlign: true
            iconText: "󰐙"
            text: "Add new app…"
            fontSize: Style.font.bodySmall
            iconSize: Style.font.title
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
            onClicked: root.launchAddAppAssistant()
          }

          WrappedTooltip {
            hoverSource: addAppBtn.hot
            text: "Opens Claude Code in a terminal to add a LAUNCH button -- name, icon, and placement"
            fontFamily: root.bar.fontFamily
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // Reorderable sections. Row placement comes from Layout.row (driven by
        // the persisted sectionOrder), so reordering never touches the
        // declaration order below.
        GridLayout {
          id: sectionsGrid
          width: contentColumn.width
          columns: 1
          rowSpacing: Style.space(14)

        Column {
          property string sectionId: "WINDOW"
          opacity: root.draggingId === sectionId ? 0.55 : 1
          Layout.fillWidth: true
          Layout.column: 0
          Layout.row: root.sectionRow("WINDOW")
          spacing: Style.space(8)
          visible: root.windowSectionHasVisibleItems

          CollapsibleHeader {
            text: "WINDOW"
            collapsed: root.isCollapsed("WINDOW")
            onToggled: root.toggleCollapsed("WINDOW")
            onDragMoved: function(my) { root.dragSection("WINDOW", mapToItem(sectionsGrid, 0, my).y) }
            onDragFinished: root.endDrag()
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          // Hand-written, not in actionSections: Close/Send-to-Scratchpad/
          // Send-to-Desktop all need the pre-open captured window address,
          // and the scratchpad button's icon/label/handler swap depending on
          // whether that window is currently in the scratchpad.
          GridLayout {
            id: windowGrid
            visible: !root.isCollapsed("WINDOW")
            width: parent.width
            columns: root.singleColumn ? 1 : 3
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
              iconText: "󰄠"
              text: "Move to Scratchpad"
              tooltipText: "Move the focused window to the scratchpad -- restore it later from the STASHED list below"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              isFavorite: root.isFavorite("window.stash")
              onFavoriteToggled: root.toggleFavorite("window.stash")
              onClicked: root.stashActiveWindow()
            }

            FavButton {
              Layout.fillWidth: true
              visible: !root.favoritesOnly || root.isFavorite("window.group")
              iconText: "󰋃"
              text: "Group"
              tooltipText: "Group the focused window with its neighbor -- no-op if it's already grouped"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              isFavorite: root.isFavorite("window.group")
              onFavoriteToggled: root.toggleFavorite("window.group")
              onClicked: root.groupActiveWindow()
            }

            FavButton {
              Layout.fillWidth: true
              visible: !root.favoritesOnly || root.isFavorite("window.ungroup")
              iconText: "󰕐"
              text: "Ungroup"
              tooltipText: "Remove the focused window from its group -- no-op if it's not grouped"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              isFavorite: root.isFavorite("window.ungroup")
              onFavoriteToggled: root.toggleFavorite("window.ungroup")
              onClicked: root.ungroupActiveWindow()
            }

            FavButton {
              Layout.fillWidth: true
              visible: !root.favoritesOnly || root.isFavorite("window.moveleft")
              iconText: "󰁍"
              text: "Move Left"
              tooltipText: "Move the focused window left in the layout"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              isFavorite: root.isFavorite("window.moveleft")
              onFavoriteToggled: root.toggleFavorite("window.moveleft")
              onClicked: root.moveActiveWindow("l")
            }

            FavButton {
              Layout.fillWidth: true
              visible: !root.favoritesOnly || root.isFavorite("window.moveright")
              iconText: "󰁔"
              text: "Move Right"
              tooltipText: "Move the focused window right in the layout"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              isFavorite: root.isFavorite("window.moveright")
              onFavoriteToggled: root.toggleFavorite("window.moveright")
              onClicked: root.moveActiveWindow("r")
            }
          }
        }

        Repeater {
          id: sectionsRepeater
          model: root.actionSections
          delegate: Column {
            id: sectionColumn
            required property var modelData
            readonly property real gridImplicitWidth: sectionGrid.implicitWidth
            property string sectionId: modelData.title
            opacity: root.draggingId === sectionId ? 0.55 : 1
            Layout.fillWidth: true
            Layout.column: 0
            Layout.row: root.sectionRow(modelData.title)
            spacing: Style.space(8)
            visible: !root.favoritesOnly || sectionColumn.modelData.items.some(function(it) { return root.isFavorite(it.id) })

            CollapsibleHeader {
              text: sectionColumn.modelData.title
              collapsed: root.isCollapsed(sectionColumn.modelData.title)
              onToggled: root.toggleCollapsed(sectionColumn.modelData.title)
              onDragMoved: function(my) { root.dragSection(sectionColumn.modelData.title, mapToItem(sectionsGrid, 0, my).y) }
              onDragFinished: root.endDrag()
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            GridLayout {
              id: sectionGrid
              visible: !root.isCollapsed(sectionColumn.modelData.title)
              width: parent.width
              columns: root.singleColumn ? 1 : 3
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(8)

              Repeater {
                model: sectionColumn.modelData.items
                delegate: FavButton {
                  required property var modelData
                  Layout.fillWidth: true
                  visible: (!root.favoritesOnly || root.isFavorite(modelData.id)) && !root.isActionDisabled(modelData.id)
                  iconText: modelData.icon
                  text: modelData.label
                  tooltipText: modelData.tooltip || ""
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  isFavorite: root.isFavorite(modelData.id)
                  repeatOnHold: !!modelData.repeat
                  onFavoriteToggled: root.toggleFavorite(modelData.id)
                  onClicked: root.runAction(modelData)
                  onRepeated: root.sendKeyFast(modelData.key, modelData.mods || "")
                }
              }
            }
          }
        }

        Column {
          property string sectionId: "WINDOWS"
          opacity: root.draggingId === sectionId ? 0.55 : 1
          Layout.fillWidth: true
          Layout.column: 0
          Layout.row: root.sectionRow("WINDOWS")
          spacing: Style.space(8)
          visible: root.showWindowsOverview

          CollapsibleHeader {
            text: "WINDOWS — THIS WORKSPACE"
            collapsed: root.isCollapsed("WINDOWS")
            onToggled: root.toggleCollapsed("WINDOWS")
            onDragMoved: function(my) { root.dragSection("WINDOWS", mapToItem(sectionsGrid, 0, my).y) }
            onDragFinished: root.endDrag()
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            visible: root.windows.length === 0 && !root.isCollapsed("WINDOWS")
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
              visible: !root.isCollapsed("WINDOWS")
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

        Column {
          property string sectionId: "STASHED"
          opacity: root.draggingId === sectionId ? 0.55 : 1
          Layout.fillWidth: true
          Layout.column: 0
          Layout.row: root.sectionRow("STASHED")
          spacing: Style.space(8)
          visible: root.showStashOverview

          CollapsibleHeader {
            text: "STASHED"
            collapsed: root.isCollapsed("STASHED")
            onToggled: root.toggleCollapsed("STASHED")
            onDragMoved: function(my) { root.dragSection("STASHED", mapToItem(sectionsGrid, 0, my).y) }
            onDragFinished: root.endDrag()
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            visible: root.stashedWindows.length === 0 && !root.isCollapsed("STASHED")
            text: "Nothing stashed"
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // Restores this specific window regardless of what's currently
          // focused -- unlike WINDOW > Stash above, which only acts on the
          // window that had focus right before the panel opened.
          Repeater {
            model: root.stashedWindows
            delegate: Row {
              required property var modelData
              visible: !root.isCollapsed("STASHED")
              width: parent.width
              spacing: Style.space(6)

              Button {
                id: restoreBtn
                width: parent.width - stashedCloseBtn.width - parent.spacing
                leftAlign: true
                iconText: "󰄝"
                text: modelData.title
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.restoreWindow(modelData.address)
              }

              WrappedTooltip {
                hoverSource: restoreBtn.hot
                text: "Restore to its original workspace"
                fontFamily: root.bar.fontFamily
              }

              Button {
                id: stashedCloseBtn
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
  }

  // Compact widget for audioOnlyMode: just the dictation switch, always
  // top-right regardless of bar position -- unlike floatWin above, this one
  // isn't meant to sit next to the bar, just stay out of the way.
  PanelWindow {
    id: audioWin
    visible: root.opened && root.audioOnlyMode
    screen: root.anchorWindow ? root.anchorWindow.screen : null
    color: "transparent"
    exclusionMode: root.pinned ? ExclusionMode.Auto : ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-wm-actions-audio-only"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      right: true
    }
    margins {
      top: Style.gapsOut
      right: Style.gapsOut
    }

    implicitWidth: audioCard.width
    implicitHeight: audioCard.height

    BorderSurface {
      id: audioCard
      width: audioRow.implicitWidth + contentLeftInset + contentRightInset
      height: audioRow.implicitHeight + contentTopInset + contentBottomInset
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.popupPadding
      radius: Style.cornerRadius

      Row {
        id: audioRow
        x: audioCard.contentLeftInset
        y: audioCard.contentTopInset
        spacing: Style.space(6)

        Button {
          id: audioBtn
          iconText: root.dictationRecording ? "󰓛" : "󰍬"
          iconSpinning: root.dictationTranscribing
          // No tooltipText: this sits in its own tiny top-right window, so
          // the hover popup has nowhere to go but overlap the buttons.
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

        // Same discard-not-transcribe cancel as the full panel's DICTATION
        // row -- only shown mid-recording/transcription.
        Button {
          visible: root.dictationRecording || root.dictationTranscribing
          iconText: "󰍭"
          fontSize: Style.font.bodySmall
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
          onClicked: root.cancelDictation()
        }

        Button {
          iconText: "✕"
          fontSize: Style.font.bodySmall
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(4)
          onClicked: root.exitAudioOnlyMode()
        }
      }
    }
  }
}

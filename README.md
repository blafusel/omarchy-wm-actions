# WM Actions

A compact Omarchy bar widget: a mouse-only floating panel of common Hyprland actions, clipboard, dictation, plus a switcher for windows on the current workspace.

Click the bar icon to open the panel. It's a standalone floating window (`PanelWindow`, `WlrKeyboardFocus.None`), not the usual click-away-to-dismiss bar popup:

- **It never steals keyboard focus.** Opening it or clicking its buttons doesn't touch whatever window you were using — verified live (a synthetic keypress reaches a focused terminal while the panel is open). This is what makes the DICTATION switch actually work: the window you're dictating into keeps focus the whole time.
- **It doesn't swallow clicks.** There's no full-screen catcher, so clicking another window while this panel is open reaches that window normally, and the panel never auto-closes after firing an action — it only closes via the bar icon or IPC.
- Tradeoff versus a standard bar popup: no fade animation, no click-away-to-dismiss, and no mutual exclusion with other bar popups.

![WM Actions panel on the Omarchy bar](preview.png)

## Why

Built for dual-monitor setups where one screen is driven from a different PC and the keyboard is switched over to it (KVM, Bluetooth, whatever). Reaching for a Hyprland keybind on the Omarchy side then means reconnecting the keyboard first. This widget puts the common actions and a workspace window switcher behind mouse clicks instead, so you don't have to switch input back just to float a window, open an app, or check a keybinding.

## Actions

- **WINDOW** - Scratchpad toggle, Float toggle, Fullscreen toggle, Close, Stash/Restore
- **CLIPBOARD** - Copy, Paste, Cut (sent as Omarchy's universal SUPER+C/V/X, terminal-aware)
- **KEYS** - Escape, Return (sent as synthetic key presses)
- **LAUNCH** - Launcher, Browser, Terminal
- **SYSTEM** - Screenshot, Keybindings cheat sheet
- **DICTATION** - Start/stop switch for Voxtype dictation (`voxtype record toggle`), live state pulled from `omarchy-voxtype-status`

WINDOW's last two buttons act on whatever window had focus right before the panel opened: **Close** closes it, and the last button toggles between **Stash** (send it to the scratchpad, remembering which workspace it came from) and **Restore** (send it back to that exact workspace — shown automatically whenever that window is currently in the scratchpad). This is a per-window move, different from the **Scratchpad** button above it, which just toggles the whole special scratchpad workspace's visibility without moving anything.

Since the panel stays open across workspace switches, the captured window (and the windows list below) stay live too — driven off Hyprland's own event stream, not just a one-time snapshot from when the panel opened. Switch workspaces, move a window into the scratchpad some other way, or focus a different window, and Stash/Restore and the windows list update to match without needing to close and reopen the panel.

CLIPBOARD and KEYS target the window that had focus right before the panel opened explicitly (via `send_key_state`'s `window` field), rather than relying on ambient seat focus — clicking a button in the panel is itself a pointer event on the panel's own surface, which was enough to disrupt plain ambient-focus delivery for these two groups.

## Favorites

Every button in WINDOW/CLIPBOARD/KEYS/LAUNCH/SYSTEM has a small star in its corner — click it to favorite that button, independently of the button's own action. A "Favorites only" switch at the top of the panel hides everything except starred buttons (and hides a section entirely once nothing in it is starred). DICTATION and the window switcher below are always shown, filter or not. Favorites persist in `~/.config/omarchy/shell.json` (this widget's own bar-layout entry), so they survive shell restarts.

## Windows - this workspace

Below the action grid, the panel lists every window on the currently focused workspace (title, truncated to fit). Click a window to focus it, or the ✕ next to it to close it. The list refreshes automatically whenever the panel opens.

## Requirements

- [Omarchy](https://omarchy.org/) (shell plugins)
- Hyprland (all actions dispatch through `hyprctl`)
- Voxtype (`omarchy voxtype install`) for the DICTATION switch; without it the button just no-ops

## Install

```bash
omarchy plugin add https://github.com/blafusel/omarchy-wm-actions.git --enable
```

## Configure

The widget defaults to the **right** section of the bar. To move it:

```bash
omarchy bar move io.github.blafusel.wm-actions --section <left|center|right>
```

## Remove

```bash
omarchy plugin remove io.github.blafusel.wm-actions
```

To disable it but keep the files:

```bash
omarchy plugin disable io.github.blafusel.wm-actions
```

## Changelog

- **1.3.1** — The windows list and the WINDOW section's Stash/Restore button now update live while the panel stays open (workspace switches, window open/close/move, focus changes), driven off Hyprland's event stream instead of a one-time snapshot from when the panel opened.
- **1.3.0** — Added favorites: a star on every WINDOW/CLIPBOARD/KEYS/LAUNCH/SYSTEM button, plus a "Favorites only" filter. Persisted via `bar.shell.updateEntryInline` (same mechanism the tray uses for pinned items) into this widget's shell.json entry.
- **1.2.2** — Reordered sections: WINDOW, CLIPBOARD, KEYS, LAUNCH, SYSTEM.
- **1.2.1** — Removed the "Keep panel open" pin: the panel already never auto-closes after firing an action, so the toggle was redundant. It now closes only via the bar icon or IPC.
- **1.2.0** — Added WINDOW > Close and Stash/Restore (send the focused window to/from the scratchpad, remembering its origin workspace). Fixed Return/Escape/CLIPBOARD not reaching apps whose own JS resets focus on window-blur (e.g. web-based chat inputs): explicit refocus + a short settle delay before the synthetic keypress.
- **1.1.0** — Standalone floating panel (`PanelWindow`, `WlrKeyboardFocus.None`) replacing the click-away bar popup, so the panel never steals keyboard focus and never swallows clicks meant for other windows. Added CLIPBOARD (Copy/Paste/Cut), DICTATION, and the "Keep panel open" pin. CLIPBOARD/KEYS now target the pre-open focused window explicitly via `send_key_state`'s `window` field.
- **1.0.0** — Initial release: LAUNCH/WINDOW/KEYS/SYSTEM action grid plus the current-workspace window switcher.

## License

MIT. See [LICENSE](LICENSE).

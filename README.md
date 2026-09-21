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

- **WINDOW** - Scratchpad toggle, Float toggle, Fullscreen toggle, Close, Stash
- **CLIPBOARD** - Copy, Paste, Cut
- **KEYS** - Escape, Return, Backspace (hold to repeat) (sent as synthetic key presses)
- **LAUNCH** - Launcher, Browser, Terminal
- **SYSTEM** - Screenshot, Keybindings cheat sheet
- **DICTATION** - Start/stop switch for Voxtype dictation (`voxtype record toggle`), live state pulled from `omarchy-voxtype-status`

WINDOW's last two buttons act on whatever window had focus right before the panel opened: **Close** closes it, and **Stash** sends it to the scratchpad, remembering which workspace it came from. This is a per-window move, different from the **Scratchpad** button above it, which just toggles the whole special scratchpad workspace's visibility without moving anything.

Bringing a window back out is a separate step, on purpose: by the time you come back for something you stashed "for later," focus has moved on, so there's nothing meaningful left for a single Stash/Restore toggle to act on. Instead, every window actually sitting in the scratchpad shows up in its own **STASHED** list further down — click one to restore it (to its remembered origin workspace, or the current workspace if it got into the scratchpad some other way), or ✕ to close it outright.

Since the panel stays open across workspace switches, the captured window, the STASHED list, and the windows list below all stay live too — driven off Hyprland's own event stream, not just a one-time snapshot from when the panel opened.

KEYS targets the window that had focus right before the panel opened explicitly (via `send_key_state`'s `window` field), rather than relying on ambient seat focus — clicking a button in the panel is itself a pointer event on the panel's own surface, which was enough to disrupt plain ambient-focus delivery.

**Backspace** repeats while held down, like a real key: an initial ~450ms delay, then fires roughly every 75ms until released. The first press is a full-weight dispatch (explicit refocus, then a settled down/up `send_key_state` pair) same as Escape/Return; every repeat tick after that uses a lighter, faster path with no refocus/settle (focus is already correct once you're holding a button down) — that's what lets the repeat rate go this fast without the repeats just resetting each other's timers into never firing at all.

CLIPBOARD doesn't send SUPER+C/V/X anymore. Hyprland's global "Universal clipboard" binds never fire for synthetic virtual-keyboard input at all — confirmed directly: even `SUPER+S` (toggle scratchpad) silently no-ops when sent this way, the workspace never changes. Global keybinds apparently only respond to real hardware input, likely a deliberate compositor-level boundary. Copy/Cut instead read the Wayland **primary selection** (auto-populated by most apps/terminals whenever text is selected, no keypress involved at all) and write it to the clipboard directly; Cut then removes the selection with a plain Delete key. Paste sends an ordinary Ctrl+V (Shift+Insert in a terminal, where Ctrl+V usually means something else) — a normal app/terminal-level shortcut, not a compositor bind, so it's delivered reliably the same way Escape/Return are.

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

- **1.4.4** — Backspace repeats roughly twice as fast (~75ms instead of ~150ms): repeat ticks now use a lighter dispatch path that skips the explicit refocus/settle the first press still does, since focus is already correct once you're holding a button down.
- **1.4.3** — Backspace now repeats while held down (initial ~450ms delay, then every ~150ms) instead of needing one click per character.
- **1.4.2** — Added KEYS > Backspace.
- **1.4.1** — Fixed CLIPBOARD: Copy/Paste/Cut sent SUPER+C/V/X expecting Hyprland's global "Universal clipboard" binds to fire, but those never respond to synthetic input at all (confirmed directly: even `SUPER+S` silently no-ops the same way). Copy/Cut now read the Wayland primary selection instead (no keypress involved); Paste sends a plain Ctrl+V/Shift+Insert.
- **1.3.2** — Fixed Restore: the old single Stash/Restore toggle button only ever tracked the last-focused window, so it broke the moment focus moved on (the entire point of stashing something "for later"). Replaced with a dedicated STASHED list showing every window actually in the scratchpad, each independently restorable to its remembered origin workspace (or the current one, if it got there some other way).
- **1.3.1** — The windows list and the WINDOW section's Stash/Restore button now update live while the panel stays open (workspace switches, window open/close/move, focus changes), driven off Hyprland's event stream instead of a one-time snapshot from when the panel opened.
- **1.3.0** — Added favorites: a star on every WINDOW/CLIPBOARD/KEYS/LAUNCH/SYSTEM button, plus a "Favorites only" filter. Persisted via `bar.shell.updateEntryInline` (same mechanism the tray uses for pinned items) into this widget's shell.json entry.
- **1.2.2** — Reordered sections: WINDOW, CLIPBOARD, KEYS, LAUNCH, SYSTEM.
- **1.2.1** — Removed the "Keep panel open" pin: the panel already never auto-closes after firing an action, so the toggle was redundant. It now closes only via the bar icon or IPC.
- **1.2.0** — Added WINDOW > Close and Stash/Restore (send the focused window to/from the scratchpad, remembering its origin workspace). Fixed Return/Escape/CLIPBOARD not reaching apps whose own JS resets focus on window-blur (e.g. web-based chat inputs): explicit refocus + a short settle delay before the synthetic keypress.
- **1.1.0** — Standalone floating panel (`PanelWindow`, `WlrKeyboardFocus.None`) replacing the click-away bar popup, so the panel never steals keyboard focus and never swallows clicks meant for other windows. Added CLIPBOARD (Copy/Paste/Cut), DICTATION, and the "Keep panel open" pin. CLIPBOARD/KEYS now target the pre-open focused window explicitly via `send_key_state`'s `window` field.
- **1.0.0** — Initial release: LAUNCH/WINDOW/KEYS/SYSTEM action grid plus the current-workspace window switcher.

## License

MIT. See [LICENSE](LICENSE).

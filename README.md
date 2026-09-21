# WM Actions

A compact Omarchy bar widget: a mouse-only floating panel of common Hyprland actions, clipboard, dictation, plus a switcher for windows on the current workspace.

Click the bar icon to open the panel. It's a standalone floating window (`PanelWindow`, `WlrKeyboardFocus.None`), not the usual click-away-to-dismiss bar popup:

- **It never steals keyboard focus.** Opening it or clicking its buttons doesn't touch whatever window you were using — verified live (a synthetic keypress reaches a focused terminal while the panel is open). This is what makes the DICTATION switch actually work: the window you're dictating into keeps focus the whole time.
- **It doesn't swallow clicks.** There's no full-screen catcher, so clicking another window while this panel is open reaches that window normally, and the panel just stays open until you explicitly close it (bar icon, or an action button when not pinned).
- Tradeoff versus a standard bar popup: no fade animation, no click-away-to-dismiss, and no mutual exclusion with other bar popups.

![WM Actions panel on the Omarchy bar](preview.png)

## Why

Built for dual-monitor setups where one screen is driven from a different PC and the keyboard is switched over to it (KVM, Bluetooth, whatever). Reaching for a Hyprland keybind on the Omarchy side then means reconnecting the keyboard first. This widget puts the common actions and a workspace window switcher behind mouse clicks instead, so you don't have to switch input back just to float a window, open an app, or check a keybinding.

## Keep panel open

A "Keep panel open" switch sits at the top of the panel. Pin it to fire off several grid actions in a row without the panel closing between clicks. Outside clicks and the bar icon never close the panel either way (see above), so this only governs the post-action auto-close.

## Actions

- **LAUNCH** - Launcher, Browser, Terminal
- **WINDOW** - Scratchpad toggle, Float toggle, Fullscreen toggle
- **CLIPBOARD** - Copy, Paste, Cut (sent as Omarchy's universal SUPER+C/V/X, terminal-aware)
- **KEYS** - Escape, Return (sent as synthetic key presses)
- **SYSTEM** - Screenshot, Keybindings cheat sheet
- **DICTATION** - Start/stop switch for Voxtype dictation (`voxtype record toggle`), live state pulled from `omarchy-voxtype-status`

CLIPBOARD and KEYS target the window that had focus right before the panel opened explicitly (via `send_key_state`'s `window` field), rather than relying on ambient seat focus — clicking a button in the panel is itself a pointer event on the panel's own surface, which was enough to disrupt plain ambient-focus delivery for these two groups.

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

- **1.1.0** — Standalone floating panel (`PanelWindow`, `WlrKeyboardFocus.None`) replacing the click-away bar popup, so the panel never steals keyboard focus and never swallows clicks meant for other windows. Added CLIPBOARD (Copy/Paste/Cut), DICTATION, and the "Keep panel open" pin. CLIPBOARD/KEYS now target the pre-open focused window explicitly via `send_key_state`'s `window` field.
- **1.0.0** — Initial release: LAUNCH/WINDOW/KEYS/SYSTEM action grid plus the current-workspace window switcher.

## License

MIT. See [LICENSE](LICENSE).

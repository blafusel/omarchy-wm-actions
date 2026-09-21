# WM Actions

A compact Omarchy bar widget: a mouse-only grid of common Hyprland actions plus a switcher for windows on the current workspace.

Click the bar icon to open a panel with four action groups and a live list of windows on the focused workspace.

![WM Actions panel on the Omarchy bar](preview.png)

## Why

Built for dual-monitor setups where one screen is driven from a different PC and the keyboard is switched over to it (KVM, Bluetooth, whatever). Reaching for a Hyprland keybind on the Omarchy side then means reconnecting the keyboard first. This widget puts the common actions and a workspace window switcher behind mouse clicks instead, so you don't have to switch input back just to float a window, open an app, or check a keybinding.

## Standalone floating panel

This branch replaces the usual click-away-to-dismiss bar popup with its own floating window (`PanelWindow`, `WlrKeyboardFocus.None`). Two things follow from that:

- **It never steals keyboard focus.** Opening it or clicking its buttons doesn't touch whatever window you were using — that's what makes the DICTATION switch actually work: the window you're dictating into keeps focus the whole time, panel open or not.
- **It doesn't swallow clicks.** There's no full-screen catcher, so clicking another window while this panel is open reaches that window normally, and the panel just stays open until you explicitly close it (bar icon, or an action button when not pinned).

A "Keep panel open" switch at the top controls only the post-action auto-close now (outside clicks and the bar icon never close it either way) — pin it to fire off several grid actions in a row without the panel closing between clicks.

Tradeoff versus the standard popup: no fade animation, and no mutual exclusion with other bar popups (opening this doesn't close another one, and vice versa).

**Rollback:** this is the `floating-window` branch. If it misbehaves, go back to the previous (KeyboardPanel-based, click-away-dismiss) version with:

```bash
git -C ~/.config/omarchy/plugins/blafusel.wm-actions checkout master
```

## Actions

- **LAUNCH** - Launcher, Browser, Terminal
- **WINDOW** - Scratchpad toggle, Float toggle, Fullscreen toggle
- **CLIPBOARD** - Copy, Paste, Cut (sent as Omarchy's universal SUPER+C/V/X, terminal-aware)
- **KEYS** - Escape, Return (sent as synthetic key presses)
- **SYSTEM** - Screenshot, Keybindings cheat sheet
- **DICTATION** - Start/stop switch for Voxtype dictation (`voxtype record toggle`), live state pulled from `omarchy-voxtype-status`

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

## License

MIT. See [LICENSE](LICENSE).

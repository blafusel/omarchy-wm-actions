# WM Actions

A compact Omarchy bar widget: a mouse-only grid of common Hyprland actions plus a switcher for windows on the current workspace.

Click the bar icon to open a panel with four action groups and a live list of windows on the focused workspace.

![WM Actions panel on the Omarchy bar](preview.png)

## Why

Built for dual-monitor setups where one screen is driven from a different PC and the keyboard is switched over to it (KVM, Bluetooth, whatever). Reaching for a Hyprland keybind on the Omarchy side then means reconnecting the keyboard first. This widget puts the common actions and a workspace window switcher behind mouse clicks instead, so you don't have to switch input back just to float a window, open an app, or check a keybinding.

## Keep panel open

A "Keep panel open" switch sits at the top of the panel. Pin it and the panel ignores outside clicks, the bar icon, Escape, and the auto-close after an action — so you can fire off several actions in a row or leave it parked on screen. It's a pin, not a free-floating window: the panel still stays docked at its usual spot next to the bar icon, not draggable. Unpin the switch to let normal closing behavior resume.

## Actions

- **LAUNCH** - Launcher, Browser, Terminal
- **WINDOW** - Scratchpad toggle, Float toggle, Fullscreen toggle
- **CLIPBOARD** - Copy, Paste, Cut (sent as Omarchy's universal SUPER+C/V/X, terminal-aware)
- **KEYS** - Escape, Return (sent as synthetic key presses)
- **SYSTEM** - Screenshot, Keybindings cheat sheet
- **DICTATION** - Start/stop switch for Voxtype dictation (`voxtype record toggle`), live state pulled from `omarchy-voxtype-status`. Clicking it always refocuses the window that had focus before the panel opened and closes the panel (even while pinned) before starting/stopping the recording — otherwise the transcript has nowhere to go, since opening the panel steals keyboard focus

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

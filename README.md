# WM Actions

A compact Omarchy bar widget: a mouse-only grid of common Hyprland actions plus a switcher for windows on the current workspace.

Click the bar icon to open a panel with four action groups and a live list of windows on the focused workspace.

![WM Actions panel on the Omarchy bar](preview.png)

## Actions

- **LAUNCH** — Launcher, Browser, Terminal
- **WINDOW** — Scratchpad toggle, Float toggle, Fullscreen toggle
- **KEYS** — Escape, Return (sent as synthetic key presses)
- **SYSTEM** — Screenshot, Keybindings cheat sheet

## Windows — this workspace

Below the action grid, the panel lists every window on the currently focused workspace (title, truncated to fit). Click a window to focus it, or the ✕ next to it to close it. The list refreshes automatically whenever the panel opens.

## Requirements

- [Omarchy](https://omarchy.org/) (shell plugins)
- Hyprland (all actions dispatch through `hyprctl`)

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

# Polybar controls

`config.ini` defines the bar modules and their pointer actions. The i3
`bar-nav.sh` helper makes most of those actions reachable from the keyboard.
This guide describes the controls; the [i3 manual](../i3/MANUAL.md#bar-mode)
explains how bar mode works.

One bar runs per active output. The tray appears on the laptop output, or on
the primary output when there is no laptop panel. The bar starts hidden and
can be shown temporarily or toggled through i3.

## Pointer actions

| Area | Left click | Right click | Wheel |
| --- | --- | --- | --- |
| Workspace number | Switch to that workspace. | — | Scroll through workspaces. |
| Date and time | No click action is configured. | Open Thunderbird mail. | — |
| Volume | Toggle mute. | Open `pavucontrol`. | Adjust volume by 1% per step. |
| Battery | Open XFCE power manager settings. | — | Adjust brightness by 5% per step. |
| Network tray icon | Open its NetworkManager menu. | Open its context menu. | Applet-defined. |
| Bluetooth tray icon | Open its Blueman menu. | Open its context menu. | Applet-defined. |
| Power icon | Expand the power menu. | — | — |

The CPU and memory modules display values only. The power menu offers shut
down, restart, lock, and an exit-i3 submenu. Shut down and restart open a
confirmation dialog; doing nothing cancels it.

In keyboard bar mode, `Enter` on the date toggles the long date and seconds
display through Polybar IPC.

## Keyboard bar mode

| Keys | Action |
| --- | --- |
| `Super+B` | Enter bar mode and reveal the bar if it was hidden. |
| `H` / `L`, or Left / Right | Move the highlight between interactive modules. |
| `J` / `K`, or Down / Up | Apply the module's wheel-down / wheel-up action. |
| `Enter` / `Shift+Enter` | Left-click / right-click the highlighted module. |
| `Escape` | Leave bar mode and restore the bar's previous visibility. |
| `Super+Shift+B` | Toggle bar visibility and resize snapped windows to match. |

The keyboard stops, from left to right, are date, volume, battery, network,
Bluetooth, and power. Workspace numbers use i3's own `Super+number` bindings.
The power menu's entries are selected with the mouse after opening it.

## If the bar needs a refresh

`Super+Shift+I` validates and restarts the i3 session components, including
Polybar. `launch.sh` starts the per-output bars and writes bounded logs under
`$XDG_STATE_HOME/polybar` (or `~/.local/state/polybar`). The standalone
launcher test is `~/.config/polybar/tests/test-launch.sh`.

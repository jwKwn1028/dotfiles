# Polybar controls

One bar per active output, hidden initially; the tray uses the laptop panel
(primary output if absent). `config.ini` defines pointer actions; i3's
[`bar-nav.sh`](../i3/MANUAL.md#bar-mode) provides keyboard access.

## Pointer actions

| Area | Left click | Right click | Wheel |
| --- | --- | --- | --- |
| Group tab | Select that group on both screens. | — | Up/down: previous/next group; no wrap. |
| Workspace | Switch to that slot of the selected group. | — | Up/down: previous/next slot. |
| Date/time | — | Thunderbird mail. | — |
| Volume | Toggle mute. | `pavucontrol`. | ±1%. |
| Battery | XFCE power settings. | — | Brightness ±5%. |
| Network/Bluetooth tray | Applet menu. | Context menu. | Applet-defined. |
| Power | Expand menu. | — | — |

Both bars show tabs for the selected group and groups with windows, then the
selected group's existing slots, e.g. `A [B] C | 1 2 [3] 7 10`: selected group
and focused slot highlighted, a slot visible on the other screen dimmed, and a
hidden group with an urgent window as `C!`. Slot scrolling includes empty slots
and wraps `10↔1`; laptop `1–2`, external `3–10`. A click made just before a
group switch is ignored. The pointer stays in place across monitors. Scrolling
preserves the [top-edge hold](../i3/MANUAL.md#top-edge-peek) until the pointer
moves away. See [Workspace Groups](../i3/MANUAL.md#workspace-groups).

CPU/memory are display-only. Power offers shutdown, restart, lock, and an
exit-i3 submenu; shutdown/restart require confirmation, with timeout cancelling.

## Keyboard bar mode

| Keys | Action |
| --- | --- |
| `Super+B` | Enter bar mode; reveal if hidden. |
| `H/L` or Left/Right | Previous/next interactive module. |
| `J/K` or Down/Up | Wheel down/up action. |
| `Enter` / `Shift+Enter` | Left/right click; date `Enter` toggles long date/seconds. |
| `Escape` | Exit and restore previous visibility. |
| `Super+Shift+B` | Toggle visibility and resize snapped windows. |

Stops: date, volume, battery, network, Bluetooth, power. Use `Super+number` for
workspaces and the mouse for expanded power-menu entries. Window/menu-opening
actions exit bar mode; in-place toggles stay active.

## If the bar needs a refresh

`Super+Shift+I` validates and restarts i3 session components, including Polybar.
`launch.sh` starts the bars and bounds logs in `$XDG_STATE_HOME/polybar`
(default `~/.local/state/polybar`). Launcher check:
`~/.config/polybar/tests/test-launch.sh`. See the
[i3 integration reference](../i3/MANUAL.md#polybar-integration) for lifecycle,
peek gestures, and log overrides.

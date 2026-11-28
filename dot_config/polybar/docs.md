# Polybar controls

One bar per active output, hidden initially; the tray uses the laptop panel
(primary output if absent). `config.ini` defines pointer actions; i3's
[`bar-nav.sh`](../i3/MANUAL.md#bar-mode) provides keyboard access.

## Pointer actions

| Area | Left click | Right click | Wheel |
| --- | --- | --- | --- |
| Group tab | Select that group on both screens. | — | Up/down: previous/next group; no wrap. |
| Workspace | Switch to that slot of the selected group. | — | Up/down: previous/next slot. |
| Date/time | — | Task calendar (`tcal`) in the browser. | — |
| Volume | Toggle mute. | `pavucontrol`. | ±1%. |
| Battery | XFCE power settings. | — | Brightness ±5%. |
| Network/Bluetooth tray | Applet menu. | Context menu. | Applet-defined. |
| Power | Expand menu. | — | — |

Tabs show selected/populated groups and existing slots: `A [B] C | 1 2 [3] 7 10`.
Focused items highlight, the other screen dims, hidden urgency adds `!`.
Slot scrolling includes empties and wraps 10↔1; primary 1–2, external 3–10.
Stale clicks are ignored; scrolling preserves the top-edge hold and pointer position.
See [groups](../i3/MANUAL.md#workspace-groups).

CPU/memory are display-only. Power offers shutdown, restart, lock, and an
exit-i3 submenu; shutdown/restart require confirmation, with timeout cancelling.

Volume shows the loudest channel; scrolling preserves balance and caps at 100%
(keyboard may exceed it). One event-driven watcher feeds both bars and reconnects
after audio restarts; disconnected bars show `unavailable`.

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

Super+Shift+I validates/restarts the session. Logs: `$XDG_STATE_HOME/polybar`
(default `~/.local/state/polybar`). Test: `~/.config/polybar/tests/test-launch.sh`.
See [i3 integration](../i3/MANUAL.md#polybar-integration) for lifecycle/peek options.

Volume watcher checks: `python3 ~/.config/polybar/tests/test-volume.py`.

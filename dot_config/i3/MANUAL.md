# i3 Configuration Manual

i3/X11; Super is `Mod4`, Ctrl/Caps are swapped. See [Polybar](../polybar/docs.md),
[Ghostty](../ghostty/docs.md), and the [GTK theme](../../dot_themes/Ghostty-TokyoNight/README.md).

## Keybinding Reference

### Launchers

| Binding | Action |
| --- | --- |
| `Super+Return` / `Super+Shift+Return` | Ghostty / `xfce4-terminal`. |
| `Copilot` | Toggle the [floating Ghostty](#copilot-terminal). |
| `Super+Space` | Rofi drun (`spotlight` theme); a waiting `sh` lets `pkexec` apps open. |
| `Super+Tab` / `Super+Shift+Tab` | Previous window / Rofi list of all windows. |
| `Super+T` | Thunar; stays resident after the first window. |
| `Super+P` / `XF86Display` | XFCE display settings. |
| `Super+Shift+P` | Refresh display layout, wallpaper, and bars. |
| `Ctrl+Super+Z` / `Ctrl+Shift+Z` | Zed / Zen Browser Flatpak. |
| `Super+G` | Helium, through `helium.desktop`, so any installed AppImage version. |
| `Ctrl+Alt+Escape` (release) / `Ctrl+Shift+Escape` | `xkill` / `xfce4-taskmanager`. |

`Ctrl+Alt+T` belongs to XFCE.

### Copilot Terminal

Copilot (`Super+Shift+F23`, keycode `201`, release) toggles a centered floating
Ghostty on the current monitor. It preserves commands while hidden, spans groups,
and skips banners, snapshots, and focus history. Closing it starts fresh.

### Window Management

| Binding | Action |
| --- | --- |
| `Super+Shift+Q` / `Alt+F4` | Close the focused window. |
| `Ctrl+Super+Shift+Q` / `Ctrl+Alt+F4` | Kill the focused window's client. |
| `Ctrl+Q` | Close apps listed in `QUIT_CLASSES` (`quit-key.py`). |
| `Ctrl+W` | Close OnlyOffice from its start page (`START_TITLES`). |
| `Super+H/J/K/L` / `Super+Arrows` | Focus left/down/up/right. |
| `Super+Shift+M` / `Super+Ctrl+M` | Show scratchpad / move window there. |
| `Super+Shift+N` | Centre a floating window on its output. |
| `Super+Shift+Space` / `Super+F` | Toggle floating / fullscreen. |

### Window Mode

`Super+R` enters sticky window mode and reveals Polybar.

| Binding | Action |
| --- | --- |
| `H/J/K/L` | Move left/down/up/right. |
| `Shift+H/L` / `Shift+J/K` | Shrink/grow width / grow/shrink height by 10 px or ppt. |
| `Tab` | Move to the next output and follow. |
| `Return` / `Escape` | Exit and restore bar visibility. |

Output moves require matching groups and no active restore.

### i3 Control

| Binding | Action |
| --- | --- |
| `Super+Shift+C` | Reload i3 config. |
| `Super+Shift+I` | Validate and restart i3, then [refresh the session](#autostart-and-dependencies). |
| `Super+Shift+E` | Confirm exit through `i3-nagbar`. |
| `Super+Escape` (release) | Lock with `lock.sh`. |

### Workspaces

Numbers select slots 1–10 (`0` = 10) in the current group.

| Binding | Action |
| --- | --- |
| `Super+number` / `Super+Alt+number` | Switch to the slot and peek a hidden bar; the current slot returns to the previous one. |
| `Ctrl+Alt+number` | Same, without a peek. |
| `Super+Shift+number-row` | Move the window there, follow, and peek (layout-independent keycodes). |
| `Super+Alt+H/L` | Previous/next existing slot, cycling. |
| `Super+Ctrl+H/L` | Previous/next slot, including empty ones; stops at 1/10. |
| `Super+Shift+H/L` | Move the window to the previous/next slot and follow; wraps 1↔10. |
| `Super+Ctrl+K/J` | Previous/next group; stops at the ends. |
| `Super+Ctrl+Tab` | Toggle with the last selected group. |
| `Super+Ctrl+1/2/3` | Group A/B/C; `4` onward is reserved. |
| `Super+Ctrl+grave` | Group B (the laptop drops `2` with Caps + Super). |
| `Super+Shift+K/J` | Move the window to the same slot of the previous/next group and follow. |

Slot navigation and moves peek hidden bars. Current-slot clicks and boundary
stops do nothing. XFCE's conflicting `Ctrl+Super+L` / `Super+R` keys are removed.

### Kill Workspace Mode

`Super+X` captures the group and bar visibility.

| Binding | Action |
| --- | --- |
| `1` ... `0` | Close every window on that slot; exit, leaving the bar as is. |
| `Shift+K` / `Shift+A` | Close every window in the group / **all** groups; exit and restore the bar. |
| `Return` / `Escape` | Abort and restore the bar. |

Slot matching is exact. Group kills spare scratchpad/unmanaged windows; switching
groups cancels. A peek counts as hidden when restoring visibility.

### Media, Brightness, and Screenshots

| Binding | Action |
| --- | --- |
| `XF86AudioRaiseVolume` / `XF86AudioLowerVolume` | Volume ±1% (±5% with Shift). |
| `XF86AudioMute` / `XF86AudioPlay` | Toggle mute / play-pause. |
| `XF86AudioNext` / `XF86AudioPrev` | Next/previous track. |
| `XF86MonBrightnessUp` / `XF86MonBrightnessDown` | Brightness ±5%. |
| `Print`, `Shift+Print`, `Alt+Print`, `Super+Shift+S` | Flameshot GUI. |

### Bar, Title Bars, and Desktop

| Binding | Action |
| --- | --- |
| `Super+Shift+B` | Toggle Polybar, raise it, and resnap snapped windows. |
| `Super+B` | [Bar mode](#bar-mode). |
| `Super+Shift+T` | Toggle title bars and resnap. |
| `Super+M` | Toggle the `_desktop` workspace, returning to the captured slot. |

## Workspace Groups

`workspace-groups.json` assigns stable indices: workspace = `index × 10 + slot`
(A: 1–10, B: 11–20, C: 21–30). Polybar shows local slots. Duplicate numbers
block group actions; scratchpad, `_desktop`, and other workspaces are unmanaged.

Switches restore each monitor's view and focus. Only `Super+Shift+K/J` transfers
windows between groups, preserving the slot and checking capacity.

### Focus and Urgency

Window selection never moves windows. History excludes transitions and Copilot.
Hidden-group activation marks urgency (`C!`); background arrivals preserve focus.

### Displays

Slots 1–2 use primary, 3–10 external; one monitor shows all. Switch/reload/hotplug
reconciles placement. Invalid or empty remembered slots reset to 1/3;
disconnection preserves group membership and remembered external views.
`display-setup.sh` owns the layout; `xfsettingsd-start.sh` stops xfsettingsd
applying its own.

### Session Controller

`workspace-groups.py start` replaces the controller and its autotiling, snap,
and overflow workers. It reconnects after restarts and exits 10 s after i3.
IPC failure pauses placement and shows `groups unavailable`. Restores survive an
i3 crash: press `r` on its crash screen (`b` gets no backtrace here), and
`i3-crash-log.py` saves i3's log to `~/.local/state/i3/crash/` (newest 10).

| File | Responsibility |
| --- | --- |
| `workspace_groups.py` | Group identities, session paths and client, snapshot filtering. |
| `group_controller.py` | Views, navigation, moves, focus, kills, overflow, workers. |
| `group_restore.py` | Placement leases, launch identity, placeholders, late arrivals. |
| `workspace-groups.py` | CLI, daemon, Polybar subscription, Rofi window list. |
| `workspace-action.sh` | Fast shell client for bindings and scripts; falls back to the CLI. |

State and logs: `$XDG_RUNTIME_DIR/i3-groups-<hash>/`. Add groups with unused
indices, shortcuts, and output assignments in `config`; existing indices cannot
change. List order controls tabs.

## XFWM-Style Snap System

| Binding | Region |
| --- | --- |
| `Super+A/D` | Left/right half. |
| `Super+W/S` | Upper/lower half. |
| `Super+Q/E/Z/C` | Upper-left/upper-right/lower-left/lower-right quarter. |
| `Super+U` (release) | Unsnap to the original floating geometry or tiling position. |

`tile-snap.sh REGION [CON_ID]` also accepts `full` / `unsnap`. Snap marks retain
original geometry; the watcher shares space and expands survivors. `resnap.sh`
refreshes after bar/title changes. Autotiling skips floating, fullscreen,
stacked, and tabbed layouts.

## Overflow Watcher

Undersized tiled arrivals move once within their group, searching upward with
10→1 wrapping: occupied with room, then empty, else stay and log. Floating,
fullscreen, scratchpad, restored, and rearranged windows are exempt; background
moves preserve focus. Options: `--fraction`/`-f` (0.25), `--no-follow`, `--debug`/`-d`.

## Polybar Integration

One initially hidden bar per output; tray on internal/primary. `display-setup.sh`
owns relaunches. Keep `screenchange-reload` / `wm-restack` off and close fd 9 in
detached children. Group tabs mark urgency with `!`.

Workspace keys or a Super tap peek for `I3_POLYBAR_PEEK_MS` (200 ms); repeats
extend it. Super held alone lasts until release (`I3_SUPER_HOLD_MS`). Peeks never
resnap; toggles cancel them. One volume watcher feeds both bars.

### Bar Mode

`Super+B`: `h/l` or arrows select date/audio/battery/Wi-Fi/Bluetooth/power;
`j/k` scroll, `Return`/`Shift+Return` click left/right, Escape exits. Menus exit;
toggles stay. Visibility is restored; power entries need mouse confirmation.
Wi-Fi docks before Bluetooth. See [pointer actions](../polybar/docs.md#pointer-actions).

### Top-Edge Peek

Reveal within 2 px of the top; release 40 px away. Override with
`I3_POLYBAR_EDGE_ENTER_PX`, `I3_POLYBAR_EDGE_LEAVE_PX`, and
`I3_POLYBAR_EDGE_POLL_MS` (25 ms). Scrolling retains the hold; visible fullscreen
suppresses it until the pointer leaves. Dead holders release within 50 ms.

## Monitors, Wallpaper, and USB

External goes left at `0x0`; laptop stays right, or off with its lid closed.
`I3_LAPTOP_OUTPUT` defaults to `eDP`, then connected `eDP*`/`LVDS*`; no panel
leaves layout unchanged. Reconciles workspaces, dunst, bars, and
`~/.wallpaper-{laptop,external}.png`. `I3_DISPLAY_SETUP_DELAY`: login 1 s, reload 0.

RandR debounce: `I3_RANDR_HOTPLUG_QUIET=0.7`; lid-only changes are silent (0.15 s).
USB inspection: `usb-hotplug.sh --dump`. Overrides: `I3_USB_TYPEC_BUSES`,
`I3_USB_HOTPLUG_QUIET` (0.7), `I3_USB_TYPEC_WINDOW` (3 s),
`I3_USB_TOAST_DETAIL=full|compact`, `I3_TOAST_WRAP`.

## Floating Rules

See `config`. Settings/utilities float centered; KakaoTalk floats at 420×760,
with a watcher preventing Wine from retiling it.

## i3-Resurrect Save and Restore

Single-group profiles use the selected group; override with `--group=B`.

| Profile | Save (release) | Restore | State / metadata |
| --- | --- | --- | --- |
| Main | `Super+Ctrl+A` | `Super+Ctrl+R` | `resurrect` / `resurrect-meta` |
| B | `Super+Ctrl+B` | `Super+Ctrl+S` | `resurrect-b` / `resurrect-meta-b` |
| C | `Super+Ctrl+C` | `Super+Ctrl+T` | `resurrect-c` / `resurrect-meta-c` |
| All groups | `Super+Ctrl+Y` | `Super+Ctrl+P` | `resurrect-session` / `resurrect-meta-session` |

Autosave runs at shutdown, exit, and every 15 minutes with browser automation
off. Existing snapshots stay protected until this login saves or restores
successfully. Failed autosaves are reported at restore.

Snapshots publish atomically; profiles share a display lock. Keep `resurrect*`
private. Validate with `--check`; recover the prior generation with `restore --previous`.

| Application | State and limits |
| --- | --- |
| Zathura | File and page when readable. |
| Zen/Helium | Address-bar URL or browser session file. Ambiguous windows launch plain. |
| Ghostty | Directory and first tmux, `hpc`, or `hpcz` session per window. Local tmux restores once before attach, including each window's focused pane. |

`ZEN_LIVE_URL_CAPTURE=0` disables automation. `ZEN_PROFILE_ROOTS`,
`HELIUM_PROFILE_ROOTS` and `I3_RESURRECT_PROC_ROOT` override lookup roots.

Free saved slots stay. Collisions use the nearest free slot on the same display,
then any free slot, else share the original. Only launched windows move. A saved
`labroute on` runs in the background; `hpc`/`hpcz`, including in restored tmux
panes, wait for it, and failures notify. All groups launch before the shared wait
(`I3_RESURRECT_SESSION_WAIT=45`); switching groups cancels pending launches.
Placement and reattach details: `last-restore.json`.

Other defaults: `I3_RESURRECT_WAIT_ATTEMPTS=120`, `I3_RESURRECT_POLL_INTERVAL=0.25`,
`I3_RESURRECT_LABROUTE_TIMEOUT=45`. Override helpers with
`I3_RESURRECT_REMOTE_HELPERS` / `I3_RESURRECT_TMUX_RESTORE` (empty disables early
restore), paths with `I3_RESURRECT_STATE_DIR` / `I3_RESURRECT_META_DIR`.

## Autostart and Dependencies

`session-reload.sh` refreshes changed services, dunst, Picom, displays, wallpaper,
and bars. `lock.sh` prefers i3lock-color. Packages live in `.chezmoidata/packages.toml`;
i3 Python helpers use system Python with i3ipc, Xlib, and lz4.

## Runtime and State Files

Runtime: `i3-groups-<hash>/`, `i3-polybar-*`, `i3-*-mode.restore-hidden`,
`i3-titles.state`, `tile-snap-<id>.lock` under `$XDG_RUNTIME_DIR`.
Logs rotate around 200 KB: `~/.local/state/i3/snap.log`,
`~/.local/state/polybar/polybar-<output>.log`, and `controller.log`
(previous run: `controller.log.1`).

## Maintenance

Keep borders/snap marks aligned across helpers, group indices and assignments
consistent, and Python dependencies paired with the manifest. Use shared
`workspace_groups.py` identities. Snapshot changes may affect `SESSION_PATTERNS`.
Review scoped `chezmoi diff` and `apply --dry-run --force` before applying.

```sh
~/.config/i3/workspace-groups.py status | jq .
less "$(~/.config/i3/workspace-groups.py path)/controller.log"
~/.config/i3/workspace-groups.py start
~/.config/i3/resnap.sh
~/.config/i3/i3-resurrect-restore-all.sh --check --group=B
jq . ~/.config/i3/resurrect-meta/last-restore.json
```

## Tests

`bash dot_config/i3/tests/executable_run-fast.sh` checks syntax, ShellCheck,
config, and units in a temporary tree, in parallel (`TEST_JOBS=1`: serially).
Live tests need Xephyr/xterm (overflow: autotiling too; crash log: xdotool). Stub
`I3_GROUP_PEEK`: Polybar IPC is not display-scoped.

```sh
~/.config/i3/tests/test-workspace-groups-live.py [scratch-only|session-only]
~/.config/i3/tests/test-overflow-live.py
~/.config/i3/tests/test-i3-crash-log-live.py
```

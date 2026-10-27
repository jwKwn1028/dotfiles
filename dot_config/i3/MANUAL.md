# i3 Configuration Manual

Controls and maintenance for i3/X11. See [Polybar](../polybar/docs.md) and
[Ghostty](../ghostty/docs.md). Super is `Mod4`; Ctrl/Caps are swapped. Focus
follows the mouse without wrapping or warping. Borders use `pixel 1`, workspace
history is per group, and application activation uses i3's `smart` policy.

## Keybinding Reference

### Launchers

| Binding | Action |
| --- | --- |
| `Super+Return` / `Super+Shift+Return` | Ghostty / `xfce4-terminal`. |
| `Copilot` | Show/hide the floating Ghostty terminal. |
| `Super+Space` | Rofi drun (`XDG_CURRENT_DESKTOP=XFCE:i3`, `spotlight` theme). |
| `Super+Tab` / `Super+Shift+Tab` | Previous window / Rofi list of all windows; see [Focus and Urgency](#focus-and-urgency). |
| `Super+T` | Thunar. |
| `Super+P` / `XF86Display` | Minimal XFCE display settings. |
| `Super+Shift+P` | Refresh display layout, wallpaper, and Polybars. |
| `Ctrl+Super+Z` / `Ctrl+Shift+Z` | Zed / Zen Browser Flatpak. |
| `Ctrl+Alt+Escape` on release | `xkill`. |
| `Ctrl+Shift+Escape` | `xfce4-taskmanager`. |

`Ctrl+Alt+T` belongs to XFCE; `Super+D` snaps right.

### Copilot Terminal

Copilot (`Super+Shift+F23`, keycode `201`, on release) toggles one floating
Ghostty on the current monitor. Startup settles its size while hidden, then
shows, centers, and focuses it together. Hiding preserves size and commands;
closing starts fresh next time. It skips the Zsh banner, snapshots, and focus
history, and stays shared across groups.

### Window Management

| Binding | Action |
| --- | --- |
| `Super+Shift+Q` / `Alt+F4` | Close focused window. |
| `Ctrl+Q` | Close apps that ignore it, listed in `QUIT_CLASSES` (`quit-key.py`). |
| `Super+H/J/K/L` / `Super+Arrow keys` | Focus left/down/up/right. |
| `Super+Shift+M` / `Super+Ctrl+M` | Show scratchpad / move focused window to scratchpad. |
| `Super+Shift+N` | Centre the focused floating window on its output. |
| `Super+Shift+Space` | Toggle floating. |
| `Super+F` | Toggle fullscreen. |

### Window Mode

`Super+R` (`window-mode.sh open`) enters sticky window mode and reveals Polybar.

| Binding | Action |
| --- | --- |
| `H/J/K/L` | Move left/down/up/right. |
| `Shift+H/L` | Shrink/grow width by 10 px or 10 ppt. |
| `Shift+J/K` | Grow/shrink height by 10 px or 10 ppt. |
| `Tab` | Move to the next output and follow; toggles between two monitors. |
| `Return` / `Escape` | Exit and restore bar visibility. |

Moves are refused while outputs show different groups or the source group
is being restored.

### i3 Control

| Binding | Action |
| --- | --- |
| `Super+Shift+C` | Reload i3 config. |
| `Super+Shift+I` | Validate and restart i3; refresh user services, changed dunst config, Picom, displays, wallpaper, and bars; show one result toast. |
| `Super+Shift+E` | Confirm exit through `i3-nagbar`. |
| `Super+Escape` on release | Lock with `lock.sh`. |

### Workspaces

Number keys address slots `1–10` of the selected [group](#workspace-groups);
`0` is slot `10`.

| Binding | Action |
| --- | --- |
| `Super+number` / `Super+Alt+number` | Switch to the slot and peek Polybar if hidden; repeating the current slot returns to the group's previous slot. |
| `Ctrl+Alt+number` | Same, without a peek. |
| `Super+Shift+number-row` | Move focused window there, follow, and peek (keycodes: layout-independent). |
| `Super+Alt+H/L` | Previous/next existing slot, cycling, and peek. |
| `Super+Ctrl+H/L` | Previous/next slot, including empty ones, and peek; stops at 1/10. |
| `Super+Shift+H/L` | Move to previous/next slot, follow, and peek; wraps 1↔10. |
| `Super+Ctrl+K/J` | Previous/next group; stops at the first/last. |
| `Super+Ctrl+Tab` | Back to the last selected group; repeat to toggle. |
| `Super+Ctrl+1/2/3` | Group A/B/C; `Super+Ctrl+4` onward is reserved for more. |
| `Super+Ctrl+grave` | Group B; the laptop keyboard drops `2` with physical Caps (Ctrl) + Super. |
| `Super+Shift+K/J` | Move focused window to the same slot of the previous/next group and follow; stops at the first/last. |

Boundary stops change nothing and do not peek. Group-tab and focused-slot
clicks are no-ops. See [Workspace Groups](#workspace-groups) for monitor policy.
XFCE's conflicting `Ctrl+Super+L` and `Super+R` shortcuts are removed.

### Kill Workspace Mode

`Super+X` (`kill-workspace-mode.sh open`) captures the group and bar visibility,
then reveals Polybar with `kill workspace (K: group, A: all)`.

| Binding | Action |
| --- | --- |
| `1` ... `0` | Close every window on that slot of the selected group; exit, leaving the bar as is. |
| `Shift+K` | Close every window in the selected group (`kill-group-windows.sh`); exit and restore bar visibility. |
| `Shift+A` | Same for **all** groups (`kill-group-windows.sh all`). |
| `Return` / `Escape` | Abort and restore bar visibility. |

Slot matches are exact: `1` cannot hit `10`, `11`, or `21`. Group/all kills spare
scratchpad and unmanaged windows. Switching groups cancels the mode; a transient
peek counts as hidden when restoring bar visibility.

### Media, Brightness, and Screenshots

| Binding | Action |
| --- | --- |
| `XF86AudioRaiseVolume` / `XF86AudioLowerVolume` | Default sink volume ±5%. |
| `XF86AudioMute` | Toggle mute. |
| `XF86AudioPlay` | Play/pause. |
| `XF86AudioNext` / `XF86AudioPrev` | Next/previous track. |
| `XF86MonBrightnessUp` / `XF86MonBrightnessDown` | Brightness ±5%. |
| `Print`, `Shift+Print`, `Alt+Print`, `Super+Shift+S` | Flameshot GUI. |

### Bar, Title Bars, and Desktop

| Binding | Action |
| --- | --- |
| `Super+Shift+B` | Toggle Polybar visibility and resnap snapped windows. |
| `Super+B` | Enter bar mode: a keyboard cursor over Polybar's clickable items. |
| `Super+Shift+T` | Toggle title bars and resnap snapped windows. |
| `Super+M` | Toggle the `_desktop` workspace; see [Show Desktop](#show-desktop). |

## Workspace Groups

Each group owns ten workspace numbers: `index × 10 + slot`, using stable,
zero-based indices from `workspace-groups.json`.

| Group | Local slots | Internal numbers |
| --- | --- | --- |
| A | 1–10 | 1–10 |
| B | 1–10 | 11–20 |
| C | 1–10 | 21–30 |

Polybar shows local slots: B's `3` means workspace `13`; `13: project` keeps
that identity. Duplicate numbers block group actions. Unnumbered/out-of-range
workspaces, `_desktop`, and scratchpad are unmanaged; empty slots are created
on demand.

### Switching and Moving Between Groups

Switching restores each monitor's slot and the focused output, leaving apps
running. First entry uses primary slot 1/external slot 3; one monitor uses the
last focused slot or 1. Active modes close and the result is verified; screens
may redraw separately.

`Super+Shift+K/J` transfers only the focused window to the adjacent group's same
slot (B:4 → C:4), follows, and stops at endpoints. It clears stale restore/
overflow decisions and checks destination capacity. Other moves stay in-group.

### Focus and Urgency

`Super+Tab` and Rofi select windows globally without moving them. History skips
controller transitions and Copilot. Hidden-group activation requests mark
urgency (`C!`); identified background arrivals preserve the current view.
Other external focus changes reconcile both outputs; raw focus events cannot
establish intent.

### Displays

Slots 1–2 use primary, 3–10 external when connected; all work on one monitor.
The controller applies this policy on switch, reload, and hotplug. Disconnects
show the last focused slot and preserve external-slot memory. Windows keep
their group.

### Session Controller

`workspace-groups.py start` replaces the display/i3-socket controller and old
watchers. It owns `autotiling`, `snap-watcher.sh`, and `overflow-watcher.py`,
reconnects after i3 restarts, and serializes group operations. Failed IPC does
not commit state; unavailable/reconciling groups pause placement and show
`groups unavailable` in Polybar.

| File | Responsibility |
| --- | --- |
| `workspace_groups.py` | Group identities, session paths/client, snapshot filtering. |
| `group_controller.py` | Views, navigation, moves, focus, kills, overflow, worker ownership. |
| `group_restore.py` | Placement leases, launch identity, placeholders, late arrivals. |
| `workspace-groups.py` | CLI, daemon, Polybar subscription, Rofi window list. |

Shell helpers forward to the controller. State, socket, locks, and
`controller.log` live in `$XDG_RUNTIME_DIR/i3-groups-<hash>/`.

### Adding a Group

Add an unused stable index, e.g. `"D": 3`, to `workspace-groups.json`, then add
its direct shortcut and `workspace 31`…`40` output assignments in `config`.
List order controls navigation/tab order. Changing an existing index is refused.

## XFWM-Style Snap System

`tile-snap.sh` floats a window into a workspace region; `Super+U` restores its
original floating geometry or tiling position.

| Binding | Region |
| --- | --- |
| `Super+A/D` | Left/right half. |
| `Super+W/S` | Upper/lower half. |
| `Super+Q/E/Z/C` | Upper-left/upper-right/lower-left/lower-right quarter. |
| `Super+U` on release | Unsnap. |

CLI: `tile-snap.sh REGION [CON_ID]` also accepts `full`/`unsnap`. Placement handles
workspace/output geometry, reserved bars, borders, and size hints. `_snap_*`
marks the region; `_presnap_*`/`_pretiling_*` retain original geometry/anchors
across repeated snaps, falling back to surviving siblings if needed.

`snap-watcher.sh` fills free space, splits occupants, or returns to tiling;
closing windows expands survivors. `resnap.sh` refreshes after bar/title changes,
with per-window placement locks. Title-bar state lives in `i3-titles.state`.

Autotiling splits tall containers vertically and wide ones horizontally, without
a depth limit; floating/fullscreen and stacked/tabbed layouts are skipped.

## Overflow Watcher

New/manually moved tiled windows smaller than a quarter of their workspace may
relocate. Moves are checked after showing the destination to avoid stale hidden
geometry. Search stays within the source group, upward with local 10→1 wrapping:

1. First occupied slot predicted to have room.
2. Otherwise first empty slot.
3. Otherwise stay and log that the group is full.

B:10 may overflow to B:1–9, never A/C; numeric-next at B:10 still does nothing.
Each arrival moves once using predicted capacity; stale source checks reject
moves. Rearrangements, floating/fullscreen/scratch windows, handled arrivals,
and restores are skipped. Background overflow preserves focus; explicit moves
reconsider a full group.

Options: `--fraction`/`-f` defaults to `0.25`; `--no-follow` keeps source focus;
`--debug`/`-d` prints watcher errors. Controller decisions use `controller.log`.

## Polybar Integration

`launch.sh` starts synchronized hidden bars on every output, with one tray on
internal/primary. The `groups` module shows `A [B] C | 1 2 [3] 7 10`; urgent
inactive groups get `!`. Stale slot clicks are ignored. `internal/i3` supplies
mode labels. See [Polybar controls](../polybar/docs.md) for pointer actions.

`Super+Shift+B` toggles, raises, and resnaps. Workspace shortcuts/Super taps
peek for `I3_POLYBAR_PEEK_MS` (200 ms), extended by repeated keys. A Super-only
hold lasts until release; another key cancels it. `I3_SUPER_HOLD_MS` sets the
hold threshold. Peeks preserve persistent visibility and skip resnapping;
explicit toggles cancel peeks.

`display-setup.sh` owns relaunches. Keep Polybar `screenchange-reload` and
`wm-restack` disabled. Launcher locks must not be inherited by detached bars
or applets (`9>&-`); hung processes are killed after a normal stop fails.

### Bar Mode

`Super+B` opens a keyboard cursor; `h/l` or arrows select a stop, `j/k` scroll,
`Return`/`Shift+Return` left/right click, and `Escape` exits. Stops are date,
audio, battery, Wi-Fi, Bluetooth, power. Window/menu actions exit; in-place
toggles stay. Exit restores prior bar visibility, counting a peek as hidden.
Group tabs use their own shortcuts/mouse and are not cursor stops.

Power entries require mouse confirmation. Media keys change volume by 5%;
bar scrolling uses 1%.

### NetworkManager Tray

`nm-applet` provides Wi-Fi; `blueman-applet`/`blueman-tray` provide Bluetooth.
NetworkManager docks first to match the keyboard cursor's order.

### Top-Edge Peek

The pointer reveals a hidden bar within 2 px of each monitor's top, releasing
it beyond 40 px. `I3_POLYBAR_EDGE_ENTER_PX`, `I3_POLYBAR_EDGE_LEAVE_PX`, and
`I3_POLYBAR_EDGE_POLL_MS` (100 ms) override these values. Scrolling preserves
the hold; a visible fullscreen window suppresses it until the pointer leaves.

## Monitor and Wallpaper Setup

`display-setup.sh` puts the first external output at `0x0`, laptop to its right;
laptop-only uses `0x0`. It reconciles workspaces, dunst, wallpaper, and bars.
Defaults: `I3_LAPTOP_OUTPUT=eDP`, `I3_DISPLAY_SETUP_DELAY=1` second.

`randr-hotplug.sh` debounces connections for `I3_RANDR_HOTPLUG_QUIET` (0.7 s),
ignores geometry-only events, and rechecks after setup. Rofi reports connection
changes; manual refresh is silent. Wallpapers: `~/.wallpaper-laptop.png` and
`~/.wallpaper-external.png`.

## USB and Type-C Notices

`usb-hotplug.sh` coalesces USB/Type-C udev bursts and bounces, with silent initial
enumeration. Sysfs identifies connectors; unknown topology is labelled USB.
Inspect with `--dump`; override with `I3_USB_TYPEC_BUSES`. Defaults:
`I3_USB_HOTPLUG_QUIET=0.7`, `I3_USB_TYPEC_WINDOW=3` seconds.
`I3_USB_TOAST_DETAIL=full|compact` controls wattage/mode/speed detail;
`I3_TOAST_WRAP` controls wrapping.

## Show Desktop

`Super+M` toggles `_desktop` and returns to the captured group/slot. Selecting
a group also leaves it. Windows keep running and remembered views survive.
Scratchpad and Copilot remain shared across groups.

## Floating Rules

Settings/admin/input utilities float and center; exact anchored class/instance
patterns and title fallbacks live in `config`. KakaoTalk/Wine windows match
`kakaotalk.exe`, float at `420×760`, and center. Its watcher repairs Wine's
unexpected return to tiling while leaving hidden/fullscreen windows alone.

## i3-Resurrect Save and Restore

Main/B/C store one selected group (or `--group=B`) independently of group names;
any profile can restore into any group.

| Profile | Save (on release) | Restore | State / metadata |
| --- | --- | --- | --- |
| Main | `Super+Ctrl+A` | `Super+Ctrl+R` | `resurrect` / `resurrect-meta` |
| B | `Super+Ctrl+B` | `Super+Ctrl+S` | `resurrect-b` / `resurrect-meta-b` |
| C | `Super+Ctrl+C` | `Super+Ctrl+T` | `resurrect-c` / `resurrect-meta-c` |
| All groups | `Super+Ctrl+Y` | `Super+Ctrl+P` | `resurrect-session` / `resurrect-meta-session` |

All-groups save publishes only after every group succeeds. Restore keeps each
original group, remaps remembered views/focus, and selects the saved group.
All restores prefer empty slots, sharing occupied ones only when full; existing
windows stay in place. Scratchpad/unmanaged windows are excluded.

CLI: `i3-resurrect-session.py save|restore`; `--check` makes no desktop changes,
`restore --previous` uses the last complete snapshot. All profiles share a
nonblocking lock per display. Data includes local paths/URLs/session names;
`resurrect*` stays gitignored.

### Save Script

`i3-resurrect-save-all.sh` captures its group's tree/metadata without moving
windows, checks live identities, and normalizes to slots 1–10 while preserving
arguments, URLs, and paths. Empty groups or failures preserve the old snapshot.

Validation and filesystem flushes precede atomic `snapshot.json` publication.
Current/previous generations are immutable; only valid legacy data is retained
for recovery. `group-format.json` versions slot content; source group is
informational.

### Application State

| Application | Captured/restored state and limits |
| --- | --- |
| Zathura | File/page via X properties/D-Bus; unreadable state retains a plain launch. |
| Zen/Helium | Address-bar URL capture restores clipboard/focus; fallback reads Zen/Firefox sessions. Window IDs pair entries; ambiguous counts retain plain launches. |
| Helium | Resolves transient paths via `helium.desktop`, then the newest matching AppImage. |
| Ghostty | Working directory and first `hpc`/`hpcz` session per window. Tabs/splits are not reconstructed; remaining sessions need manual attachment. |

`ZEN_LIVE_URL_CAPTURE=0` disables live capture; `ZEN_PROFILE_ROOTS` overrides
fallback profiles; `I3_RESURRECT_PROC_ROOT` overrides `/proc`. Remote attaches
are **requested, unverified**; failures/unlaunched sessions say `Reattach by hand`.

### Restore Script

`i3-resurrect-restore-all.sh` validates and prepares temporary copies before
desktop changes. `--check` prints destinations without changing windows,
routing, or bars; `--previous` selects the prior generation. B/C wrappers accept
both. Legacy 1–10 workspaces become slots; invalid formats fail explicitly.

1. Plan lowest empty slots within the destination group, then occupied slots.
2. Build unique launch tokens and owned placeholders. Reject shell-string,
   `gtk-launch`, `xdg-open`, and `dbus-send` launches; resolve missing AppImages.
   Mismatched layout/program counts restore programs without layout.
3. Restore `labroute on` if recorded; failure/timeout aborts before desktop
   changes. Restore never turns it off.
4. Reserve placement, select the group, pause tiling/snap workers, and hide
   visible bars. Route only provably owned new windows; overflow skips arrivals.
5. Verify launched windows and placeholders, restore mapped focus, clear owned
   empty placeholders, resume workers, and restore bar visibility.
   `last-restore.json` records mapping, shared slots, results, and retry guidance.

Switching groups cancels further launches and clears empty placeholders.
Issued launches retain their destinations across cancellation/controller restart
without taking focus; explicit transfers override routing. Records last while
the launcher lives and at least two minutes; dead owners release reservations.
Cleanup never removes populated containers. Ambiguous/single-instance arrivals
report incomplete restores without moving existing windows.

Defaults: `I3_RESURRECT_LAYOUT_DELAY=0.25`, `I3_RESURRECT_WAIT_ATTEMPTS=48`,
`I3_RESURRECT_POLL_INTERVAL=0.25`, `I3_RESURRECT_LABROUTE_TIMEOUT=45`.
`I3_RESURRECT_REMOTE_HELPERS` defaults to `~/.zsh/rc.d/50-remote.zsh`.
`I3_RESURRECT_STATE_DIR` / `I3_RESURRECT_META_DIR` override profile paths.

Example: live A slots `1,4` plus saved `1–5` restore into `2,3,5,6,7`.
Restoring that profile into empty B uses `11–15`, leaving A untouched.

## Autostart and Dependencies

Startup runs XFCE settings/power, keyring, Polkit, Picom, network/Bluetooth,
xss-lock, input setup, and watchers. `session-reload.sh` refreshes user units,
changed dunst config, Picom, displays, wallpaper, and bars with one result toast.
`lock.sh` prefers i3lock-color, falling back to i3lock.

Packages live in `.chezmoidata/packages.toml` under the i3/X11 profile: system
Python with `python3-i3ipc`, `python3-xlib`, `python3-lz4`; pipx autotiling;
`xrandr`, Polybar, X11 tools, `feh`, `jq`, and `flock`.

## Runtime and State Files

Runtime root: `$XDG_RUNTIME_DIR` (fallback `/run/user/$(id -u)`). State:
`i3-groups-<hash>/` for groups, `i3-polybar-*` for bars, `i3-*-mode.restore-hidden`
for prior visibility, `i3-titles.state` for borders, `tile-snap-<id>.lock` for snaps.

Logs: `${XDG_STATE_HOME:-$HOME/.local/state}/i3/snap.log`,
`${XDG_STATE_HOME:-$HOME/.local/state}/polybar/polybar-<output>.log`, and the
session's `controller.log`. Snap/bar logs rotate above roughly 200 KB.
Snapshot generations hold layouts/programs and application/workspace metadata;
profile metadata holds the manifest and last restore report.

## Maintenance and Troubleshooting

- Keep `default_border` and `toggle-titles.sh` aligned; change snap mark formats
  across snap, watcher, resnap, and cleanup helpers together.
- Keep group indices, output policy, config assignments, and new shortcuts
  consistent. Callers use `workspace_groups.py` instead of their own offsets.
- Pair Python/pipx dependency changes with the package manifest. Browser/remote
  launch changes also affect snapshot capture and `SESSION_PATTERNS`.
- Use the controller log for unavailable groups, capacity, restore, and IPC
  errors; restart it with `workspace-groups.py start`.
- Review scoped `chezmoi diff` and `apply --dry-run --force` before deployment;
  unrelated runtime-managed drift is expected.

```sh
~/.config/i3/workspace-groups.py status | jq .
less "$(~/.config/i3/workspace-groups.py path)/controller.log"
~/.config/i3/workspace-groups.py start
~/.config/i3/resnap.sh
~/.config/i3/i3-resurrect-restore-all.sh --check --group=B
~/.config/i3/i3-resurrect-restore-all.sh --previous
jq . ~/.config/i3/resurrect-meta/last-restore.json
```

## Tests

Fast suite: `bash dot_config/i3/tests/executable_run-fast.sh` from source, or
`~/.config/i3/tests/run-fast.sh` after applying. It uses a temporary tree for
syntax, ShellCheck, config parsing, and group/snapshot/snap/bar/hotplug tests.

Live checks use isolated single-/dual-monitor Xephyr sessions with xterm;
overflow also needs autotiling. Stub `I3_GROUP_PEEK` in custom nested tests
because Polybar IPC is not display-scoped.

```sh
~/.config/i3/tests/test-workspace-groups-live.py
~/.config/i3/tests/test-workspace-groups-live.py scratch-only
~/.config/i3/tests/test-workspace-groups-live.py session-only
~/.config/i3/tests/test-overflow-live.py
```

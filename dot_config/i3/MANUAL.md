# i3 Configuration Manual

Reference for the i3/X11 session, workspace groups, floating/snap helpers, and
local snapshots. See also [Polybar controls](../polybar/docs.md) and the
[Ghostty guide](../ghostty/docs.md).

Super is `Mod4`; Ctrl/Caps are swapped. Focus follows the mouse, without focus
wrapping or pointer warping. Borders default to `pixel 1`. Global automatic
back-and-forth is disabled in favor of per-group slot history; application
activation uses i3's `smart` policy.

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

Copilot shows/hides one floating Ghostty on the current workspace/output.
Startup waits for its size to settle while hidden, then shows, centers, and
focuses it in one i3 command. Reopening centers it on the current monitor.
Size and running commands survive hiding; closing opens a
fresh terminal next time. It skips the Zsh banner and is excluded from groups,
snapshots, and focus history. The binding is `Super+Shift+F23` (keycode `201`),
on release.

### Window Management

| Binding | Action |
| --- | --- |
| `Super+Shift+Q` / `Alt+F4` | Close focused window. |
| `Ctrl+Q` | Close apps that ignore it, listed in `QUIT_CLASSES` (`quit-key.py`). |
| `Super+H/J/K/L` / `Super+Arrow keys` | Focus left/down/up/right. |
| `Super+Shift+H/L` | Move to previous/next slot in the group and follow; wrap 1↔10. |
| `Super+Shift+M` / `Super+Ctrl+M` | Show scratchpad / move focused window to scratchpad. |
| `Super+Shift+N` | Centre the focused floating window on its output. |
| `Super+Shift+Space` | Toggle floating. |
| `Super+F` | Toggle fullscreen. |

### Window Mode

`Super+R` enters a sticky mode labelled `hjkl / HJKL / Tab` in Polybar.
`window-mode.sh open` reveals the bar; `Return`/`Escape` restore its prior
visibility and leave the mode.

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

Navigation stays within the group; boundary stops have no move, focus, workspace
creation, or peek. Repeated number keys use per-group history; group-tab and
focused-slot clicks are no-ops. Slots 1–2 use primary, 3–10 external when
connected; all are available on one monitor. See [Workspace Groups](#workspace-groups).
XFCE's conflicting `Ctrl+Super+L` and `Super+R` shortcuts are removed.

### Kill Workspace Mode

`Super+X` (`kill-workspace-mode.sh open`) records the selected group and the
bar's visibility, then reveals the bar. The mode reads
`kill workspace (K: group, A: all)`.

| Binding | Action |
| --- | --- |
| `1` ... `0` | Close every window on that slot of the selected group; exit, leaving the bar as is. |
| `Shift+K` | Close every window in the selected group (`kill-group-windows.sh`); exit and restore bar visibility. |
| `Shift+A` | Same for **all** groups (`kill-group-windows.sh all`). |
| `Return` / `Escape` | Abort and restore bar visibility. |

Slot matches are exact: killing `1` cannot hit `10`, `11`, or `21`. Group/all
kills spare scratchpad and unmanaged windows. A group change cancels kill mode.
Abort and group/all kills restore prior bar visibility; slot kills leave it
visible. A transient peek counts as hidden.

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

Polybar displays local slots: B's `3` addresses workspace `13`. Renaming it to
`13: project` preserves its identity. Duplicate live numbers block group actions;
unnumbered/out-of-range workspaces, `_desktop`, and scratchpad remain unmanaged.
Empty slots are created on demand.

### Switching and Moving Between Groups

Switching restores the group's visible slot per monitor and focused output,
leaving its applications running. First entry uses primary slot 1 and external
slot 3; one monitor uses the last focused slot or 1. Slots remain distinct per
output. The controller closes active binding modes, serializes the switch,
and verifies the result; physical screens may redraw separately.

`Super+Shift+k/j` explicitly transfers only the focused window to the same slot
of the adjacent group and follows it: B:4 → C:4. It stops at group endpoints.
The controller captures and rechecks the source window, discards stale restore/
overflow decisions for it, and runs normal overflow in the destination group.
Ordinary slot moves and window-mode moves stay within their source group.

### Focus and Urgency

`Super+Tab` and the Rofi window list select windows globally, activating their
group without moving them. Focus history ignores controller transitions and
the Copilot terminal. Hidden-group activation requests become urgent (`C!` in
Polybar); identifiable background arrivals retain the selected view. Other
external focus changes are adopted and the remaining output reconciled once.
Raw i3 focus events cannot establish user intent.

### Displays

Slots 1–2 belong to primary and 3–10 to external when available. Config output
assignments affect workspace creation; the controller also moves existing
workspaces to their policy output on switch, reload, and hotplug. Disconnects
show the group's last focused slot on the surviving screen while preserving
external-slot memory for reconnection. Window membership stays in its group.

### Session Controller

`workspace-groups.py start` replaces the controller for the current display/
i3 socket and removes older watcher copies. It owns `autotiling`,
`snap-watcher.sh`, and `overflow-watcher.py`, reconnects after i3 restarts, and
serializes navigation, focus, moves, kills, overflow, and restore operations.
Failed IPC commands do not commit successful state. While unavailable or
reconciling, placement pauses and Polybar shows `groups unavailable`.

| File | Responsibility |
| --- | --- |
| `workspace_groups.py` | Group identities, session paths/client, snapshot filtering. |
| `group_controller.py` | Views, navigation, moves, focus, kills, overflow, worker ownership. |
| `group_restore.py` | Placement leases, launch identity, placeholders, late arrivals. |
| `workspace-groups.py` | CLI, daemon, Polybar subscription, Rofi window list. |

The workspace, move, previous-window, desktop, and focus-tracker shell helpers
forward to this controller. State, socket, locks, and `controller.log` live in
`$XDG_RUNTIME_DIR/i3-groups-<hash>/`, keyed by display and i3 socket.

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

CLI: `tile-snap.sh REGION [CON_ID]` also accepts `full` and `unsnap`.
Geometry uses the target workspace, clamps stale hotplug rectangles to active
outputs, accounts for reserved bar space/borders, and retries size hints.

`_snap_<region>` marks the current region; `_presnap_*` and `_pretiling_*`
preserve original geometry and tiling anchors. Repeated snaps retain that
original state; missing tiling parents fall back to surviving siblings.

On arrival beside snapped windows, `snap-watcher.sh` fills the largest free
region, splits a larger occupant, or returns that workspace to normal tiling.
Closing a snapped window expands survivors without overlap. `resnap.sh`
reapplies regions after bar/title changes; per-window locks serialize placement.

`Super+Shift+T` toggles `pixel 1`/normal borders. State is in
`$XDG_RUNTIME_DIR/i3-titles.state`; the watcher applies it to new windows.
Autotiling has no depth limit: tall containers split vertically, wider ones
horizontally; floating/fullscreen and stacked/tabbed cases are skipped.

## Overflow Watcher

New or manually moved tiled windows smaller than one quarter of their workspace
are considered for relocation. Controller moves are checked after displaying
the destination because hidden geometry can be stale. Search stays within the
window's actual source group, upward with local 10→1 wrapping:

1. First occupied slot predicted to have room.
2. Otherwise first empty slot.
3. Otherwise stay and log that the group is full.

B:10 may overflow to B:1–9, never A/C; numeric-next at B:10 remains a no-op.
Each window moves once using a capacity prediction; hidden layouts prevent a
reliable post-move measurement. Source-container/workspace criteria reject stale
moves. Rearrangements, floating/fullscreen/scratch windows, handled arrivals,
and active restores are skipped. A background group's overflow cannot take
foreground focus. A full group is reconsidered after an explicit workspace move.

Options: `--fraction`/`-f` defaults to `0.25`; `--no-follow` keeps source focus;
`--debug`/`-d` prints watcher errors. Controller decisions use `controller.log`.

## Polybar Integration

`launch.sh` starts synchronized, initially hidden bars on every active output,
with one tray on the internal/primary display. The `groups` module subscribes
to controller changes and shows `A [B] C | 1 2 [3] 7 10`; inactive urgent groups
get `!`. Clicks carry explicit group/slot identities, so stale slot clicks are
ignored. `internal/i3` supplies only binding-mode labels. See
[Polybar controls](../polybar/docs.md) for pointer actions.

`Super+Shift+B` toggles visibility, raises bars, and resnaps. Workspace shortcuts
or a Super-only tap peek for `I3_POLYBAR_PEEK_MS` (200 ms); repeated keys extend
one deadline. A Super-only hold lasts until release; another key cancels it.
`I3_SUPER_HOLD_MS` overrides the hold threshold. Peeks preserve a persistent bar
and skip resnapping; explicit toggles cancel pending peeks.

`display-setup.sh` owns relaunches. Keep Polybar `screenchange-reload` and
`wm-restack` disabled. Launcher locks must not be inherited by detached bars
or applets (`9>&-`); hung processes are killed after a normal stop fails.

### Bar Mode

`Super+B` opens a keyboard cursor; `h/l` or arrows select a stop, `j/k` scroll,
`Return`/`Shift+Return` left/right click, and `Escape` exits. Stops are date,
audio, battery, Wi-Fi, Bluetooth, power. Window/menu actions exit; in-place
toggles stay. Exit restores prior bar visibility, counting a peek as hidden.
Group tabs use their own shortcuts/mouse and are not cursor stops.

Normal stops use identically padded `-sel` module twins. Tray stops use a
click-through highlight from `bar-nav-marker.py`. Power entries require the
mouse and explicit shutdown/restart confirmation. Media keys change volume by
5%; bar scrolling uses 1%.

### NetworkManager Tray

`nm-applet` provides Wi-Fi menus/password prompts; `blueman-applet` and
`blueman-tray` provide Bluetooth. The launcher docks NetworkManager before
restarting the Bluetooth tray, matching the keyboard cursor's order.

### Top-Edge Peek

The pointer reveals a hidden bar within 2 px of each monitor's top, releasing
it beyond 40 px. `I3_POLYBAR_EDGE_ENTER_PX`, `I3_POLYBAR_EDGE_LEAVE_PX`, and
`I3_POLYBAR_EDGE_POLL_MS` (100 ms) override these values. Scrolling preserves
the hold; a visible fullscreen window suppresses it until the pointer leaves.

## Monitor and Wallpaper Setup

`display-setup.sh` places the first connected external output at `0x0` and the
primary laptop to its right; laptop-only uses `0x0`. `I3_LAPTOP_OUTPUT` defaults
to `eDP`; `I3_DISPLAY_SETUP_DELAY` defaults to one second. Setup reconciles
workspaces, dunst's monitor index, wallpaper, and bars.

`randr-hotplug.sh` debounces connected-output changes for 0.7 seconds
(`I3_RANDR_HOTPLUG_QUIET`), ignores geometry-only events, and rechecks after
setup. Shared Rofi notices report connection changes; manual refresh is silent.
Wallpaper files are `~/.wallpaper-laptop.png` and `~/.wallpaper-external.png`.

## USB and Type-C Notices

`usb-hotplug.sh` watches unprivileged USB/Type-C udev events, coalesces hub bursts
and detach/reattach bounces, and keeps initial enumeration silent. Connector
mapping uses sysfs links; unknown topology is labelled USB rather than guessed.
Inspect with `usb-hotplug.sh --dump`; override with `I3_USB_TYPEC_BUSES`.

`I3_USB_HOTPLUG_QUIET` defaults to 0.7 seconds and `I3_USB_TYPEC_WINDOW` to three.
`I3_USB_TOAST_DETAIL=full` includes partner wattage, alternate modes, and speed;
`compact` omits these. `I3_TOAST_WRAP` controls notice wrapping.

## Show Desktop

`Super+M` temporarily shows `_desktop`; repeating returns to the captured group
and slot. Selecting a group also leaves it. Windows are not minimized and
remembered group views are preserved. Scratchpad commands remain shared across
groups; the Copilot terminal is excluded by class even on numbered workspaces.

## Floating Rules

Settings/admin/input utilities float and center; exact anchored class/instance
patterns and title fallbacks live in `config`. KakaoTalk/Wine windows match
`kakaotalk.exe`, float at `420×760`, and center. Its watcher repairs Wine's
unexpected return to tiling while leaving hidden/fullscreen windows alone.

## i3-Resurrect Save and Restore

Profiles are storage slots independent of workspace groups. Each operation
captures its source/destination group once: selected by default, or `--group=B`.
Any profile can save any group and restore into any group.

| Profile | Save (on release) | Restore | State / metadata |
| --- | --- | --- | --- |
| Main | `Super+Ctrl+A` | `Super+Ctrl+R` | `resurrect` / `resurrect-meta` |
| B | `Super+Ctrl+B` | `Super+Ctrl+S` | `resurrect-b` / `resurrect-meta-b` |
| C | `Super+Ctrl+C` | `Super+Ctrl+T` | `resurrect-c` / `resurrect-meta-c` |

All profiles share a nonblocking save/restore lock per display. Snapshot data
contains local paths, URLs, and session names; `resurrect*` stays gitignored.

### Save Script

`i3-resurrect-save-all.sh` captures only its group's tree and application
metadata, excluding scratch/desktop windows without moving them. It saves with
live identities, checks for window changes (titles may change), then normalizes
filenames, layouts, metadata, and generated instance names to slots 1–10.
Arbitrary command arguments, URLs, and paths are preserved. Empty groups fail
without replacing the previous snapshot.

Validation and filesystem flushes precede atomic publication of
`resurrect-meta*/snapshot.json`. Generations are immutable; current and previous
are retained. Failures/interruption preserve the old selection. Valid flat
legacy profiles can become the previous generation; invalid legacy data is
never advertised for recovery. `group-format.json` versions slot content
separately from the generation manifest; recorded source group is informational.

### Application State

| Application | Captured/restored state and limits |
| --- | --- |
| Zathura | File and current page from X properties/D-Bus; restore adds `--page`. Unreadable windows retain plain commands. |
| Zen/Helium | Live address-bar capture, restoring clipboard/focus; fallback reads Zen/Firefox session files. Pairing uses window IDs before normalization. Ambiguous counts retain plain launches. |
| Helium | Replaces transient AppImage paths using `helium.desktop`, falling back to the newest matching AppImage. |
| Ghostty | Per-window working directory and first `hpc`/`hpcz` session, with unique launch identity. Tabs/splits cannot be reconstructed; remaining sessions are listed for manual attachment. |

`ZEN_LIVE_URL_CAPTURE=0` disables address-bar capture. `ZEN_PROFILE_ROOTS`
overrides fallback profile roots. `I3_RESURRECT_PROC_ROOT` overrides `/proc`
for session inspection. Remote attaches are reported as **requested,
unverified**; failed/unlaunched sessions appear under `Reattach by hand`.

### Restore Script

`i3-resurrect-restore-all.sh` resolves/validates one snapshot and prepares
temporary copies before changing windows. `--check` prints its destination plan
without a placement lease or changes to windows, routing, or bars. `--previous`
uses the prior generation; B/C wrappers accept the same options. Legacy 1–10
workspaces read as slots; invalid manifests/unknown formats fail explicitly.

1. Place saved workspaces in the destination group's empty slots, lowest first;
   remaining ones share its occupied slots. Existing windows are never closed
   or moved out. Other groups and unmanaged workspaces are excluded.
2. Build unique launch tokens and operation-owned placeholders whose swallow
   rules match nothing. Shell-string, `gtk-launch`, `xdg-open`, and `dbus-send`
   launches are rejected. Missing AppImages resolve to a newer matching file;
   incompatible layout/program counts restore programs without the layout.
3. Restore `labroute on` if recorded; failure/timeout aborts before desktop
   changes. Restore never turns the route off.
4. Acquire a placement lease, select the destination group, pause autotiling/
   snap-watcher, and hide a visible bar. Pre-existing windows cannot be routed.
5. Launch programs with instance/startup/environment tokens. Only a provably
   owned new window is swapped into its placeholder or sent to its captured
   slot. Overflow skips restore arrivals; readiness requires every launched
   window still in its destination and no empty placeholders.
6. Recheck successes, restore mapped focus, remove owned empty placeholders,
   release the lease, resume workers, and restore prior bar visibility.
   `last-restore.json` records mapping, shared slots, results, and retry guidance.

A group switch cancels further launches and clears empty placeholders. Already
issued launches retain their destination after cancellation/controller restart,
without pulling focus back. Records remain while their launcher lives and for
at least two minutes; dead owners release leases. Explicit transfers supersede
pending routing. Cleanup targets tagged placeholder X windows, never populated
containers. Ambiguous/single-instance application arrivals report incomplete
restores rather than moving an existing window.

Defaults: `I3_RESURRECT_LAYOUT_DELAY=0.25`, `I3_RESURRECT_WAIT_ATTEMPTS=48`,
`I3_RESURRECT_POLL_INTERVAL=0.25`, `I3_RESURRECT_LABROUTE_TIMEOUT=45`.
`I3_RESURRECT_REMOTE_HELPERS` defaults to `~/.zsh/rc.d/50-remote.zsh`.
`I3_RESURRECT_STATE_DIR` / `I3_RESURRECT_META_DIR` override profile paths.

Example: live A slots `1,4` plus saved `1–5` restore into `2,3,5,6,7`.
Restoring that profile into empty B uses `11–15`, leaving A untouched.

## Autostart and Dependencies

Startup provides XFCE settings/power services, keyring, Polkit, Picom,
NetworkManager/Bluetooth, xss-lock, input-device setup, and the group/gesture/
hotplug watchers. `session-reload.sh` refreshes user units, changed dunst
configuration, Picom, displays, wallpaper, and bars, then reports one result.
`lock.sh` uses i3lock-color when available and plain i3lock otherwise.

Packages are declared in `.chezmoidata/packages.toml` under the i3/X11 desktop
profile. Helpers use `/usr/bin/python3` with `python3-i3ipc`, `python3-xlib`,
and `python3-lz4`; autotiling is provisioned through pipx. Display/bar scripts
also use `xrandr`, Polybar, X11 inspection tools, `feh`, `jq`, and `flock`.

## Runtime and State Files

Runtime files use `$XDG_RUNTIME_DIR` (fallback `/run/user/$(id -u)`). Group
state lives in `i3-groups-<hash>/`; `i3-polybar-*` holds visibility/peek/bar-mode
state, `i3-*-mode.restore-hidden` holds prior mode visibility, `i3-titles.state`
holds decorations, and `tile-snap-<id>.lock` serializes each window.

Logs: `${XDG_STATE_HOME:-$HOME/.local/state}/i3/snap.log`,
`${XDG_STATE_HOME:-$HOME/.local/state}/polybar/polybar-<output>.log`, and the
session's `controller.log`. Snap/bar logs rotate above roughly 200 KB.
Snapshot generations contain layouts/programs plus workspace, focused-slot,
route, browser/PDF, and Ghostty metadata; profile metadata holds the manifest
and last restore report.

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

From source: `bash dot_config/i3/tests/executable_run-fast.sh`; from an applied
tree: `~/.config/i3/tests/run-fast.sh`. The runner renders source-state names
into a temporary tree, then runs syntax, ShellCheck, i3 config parsing, and
standalone tests without applying live configuration.

| Checks | Coverage |
| --- | --- |
| Workspace groups | Mapping, boundaries, transfer guards, snapshots across all group pairs, Polybar output, worker recovery. |
| Scratch terminal | New/revealed window centering on offset displays, delayed resizing, hide-only toggles. |
| Snap/overflow | Geometry, capacity, group isolation, marks, unsnap, rebalance, locks. |
| Snapshots | Validation, atomic publication/recovery, interrupted/concurrent saves, metadata, layout-free restore, observed failures. |
| Bar/session/hotplug | Visibility/gesture ownership, navigation, monitor/USB events, reload, lock, launcher, provisioning contracts. |

Live checks require Xephyr/xterm; overflow also needs autotiling. They create
isolated single- and dual-monitor sessions. Set `I3_GROUP_PEEK` to a stub in
custom nested tests: Polybar IPC itself is not display-scoped.

```sh
~/.config/i3/tests/test-workspace-groups-live.py
~/.config/i3/tests/test-workspace-groups-live.py scratch-only
~/.config/i3/tests/test-overflow-live.py
```

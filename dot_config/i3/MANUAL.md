# i3 Configuration Manual

Reference for `~/.config/i3/config`, its helpers, and local i3-resurrect
profiles. See also the [Polybar controls](../polybar/docs.md) and
[Ghostty guide](../ghostty/docs.md).

## Overview

An i3/X11 session with XFCE desktop services and Polybar instead of
`xfce4-panel`. It provides [workspace groups](#workspace-groups) that reuse the
number keys for separate sets of windows, floating snap regions with automatic
fill/rebalance, focus history, overflow handling, three session profiles,
display/USB hotplug notices, and utility-window floating rules.

## Core Session Settings

- Modifier: `Mod4` (Super/Windows); font: `pango:DejaVu Sans 10`.
- Focus follows the mouse; focus wrapping and cursor warping are disabled.
- `workspace_auto_back_and_forth` is off; the group controller keeps
  per-group previous-slot history. `focus_on_window_activation smart` turns a
  hidden group's activation request into urgency, not a group switch.
- Tiled/floating borders default to `pixel 1`; `hide_edge_borders smart` hides
  edge borders. Title bars can be toggled globally.
- Left Ctrl and Caps Lock are swapped with `ctrl:swapcaps`, provisioned in
  `/etc/default/keyboard`.
- Tokyo Night colors: focused border/background/text/indicator/child border
  are `#86be43`, `#1a1b26`, `#c0caf5`, `#86be43`, `#86be43`; unfocused and
  focused-inactive borders/backgrounds use `#16161e`, with text `#565f89`.

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

`Ctrl+Alt+T` belongs to XFCE; `Super+D` snaps right. `Ctrl+Super+H/L` are
reserved for numeric workspace navigation; the old Helium/lock bindings are
disabled. Lock with `Super+Escape`.

### Copilot Terminal

Copilot toggles one floating Ghostty window, regardless of focus. Showing
brings it to the current workspace/output; size, position, and running
commands survive hiding. Closing it makes the next press open a fresh window.

It skips the Zsh banner and needs no extra packages. Saves skip it without
hiding it, and it belongs to no [group](#workspace-groups). Binding: `Super+Shift+F23`
(X11 keycode `201`), on release.

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

i3 has no previous-output command. The controller refuses these moves while
outputs show different groups or the window's group is mid-restore, so they
never cross groups.

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

Navigation never leaves the group; wrapping returns to its own slot 1. A
boundary stop, the current slot or group, a repeat without history, or cycling
one existing slot does nothing (no focus, move, workspace, or peek). For the
bar's tabs and wheel, see [Polybar controls](../polybar/docs.md).
`mouse_warping none` keeps the pointer in place across outputs.

In every group, slots `1–2` use `primary` (laptop) and `3–10` `nonprimary`
(external), or all stay on the laptop without an external output. Output
keywords avoid connector names.

XFCE's conflicting `Ctrl+Super+L` and `Super+R` custom shortcuts are removed;
its default `Ctrl+Alt+L` lock and `Alt+F2` appfinder remain available.

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

Slots match the exact, anchored workspace name, so `1` never closes `10`, `11`,
or `21`. `Shift+K`/`Shift+A` spare the Copilot terminal, the scratchpad, and
unnumbered workspaces. After a group change, the next slot key or `Shift+K`
just cancels the mode. A transient peek counts as hidden; a persistent bar
stays visible on abort or a `Shift+K`/`Shift+A` close. Each `open` rewrites the
restore marker, so an earlier number-key exit leaves no stale state.

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

### Bar Mode

`Super+B` runs `bar-nav.sh` to navigate Polybar from an i3 mode; the X11 dock
itself cannot accept keyboard focus. The mode name is a single space, leaving
the selected module's block as its indicator.

| Binding | Action |
| --- | --- |
| `H/L` / Left/Right | Previous/next interactive module. |
| `J/K` / Down/Up | Wheel down/up action. |
| `Return` / `Shift+Return` | Left/right click. |
| `Escape` | Exit, collapse any power menu, and restore prior bar visibility. |

| Stop, left to right | `Return` | `Shift+Return` | `J/K` |
| --- | --- | --- | --- |
| `date` | Toggle long date/seconds. | — | — |
| `pulseaudio` | Toggle mute. | `pavucontrol`. | Volume −/+1%. |
| `battery` | XFCE power settings. | — | Brightness −/+5%. |
| `wifi` | NetworkManager menu. | Applet context menu. | — |
| `bluetooth` | Blueman menu. | Applet context menu. | — |
| `powermenu` | Expand menu; choose entries with the mouse. | — | — |

Actions opening a window or tray menu exit the mode; in-place toggles remain
active. Exit restores the prior bar visibility, treating a transient peek as
hidden and respecting a bar hidden externally while the mode was open.
Workspaces use the [workspace bindings](#workspaces), not cursor stops.

Regular stops swap an inherited `-sel` twin through Polybar's `module_show` /
`module_hide` IPC. Both twins need identical padding to avoid layout shifts;
`${colors.selection}` provides the highlight. Tray stops use
[`bar-nav-marker.py`](#networkmanager-tray).

The power menu drops the highlight while expanded, stays in bar mode, and
requires the mouse for its entries. `confirm-poweroff.sh` requires explicit
shutdown/restart confirmation; cancellation or timeout does nothing. Lock uses
`lock.sh`, also used by `xss-lock`: styled i3lock-color when installed, otherwise
`i3lock -n -c 292d3e`.

Volume uses 1% steps (`pulseaudio`'s `interval = 1` is a scroll step); media
keys use 5%. See [Polybar controls](../polybar/docs.md) for pointer actions.

## Workspace Groups

i3 has one workspace namespace, so each group owns ten internal numbers,
`index × 10 + slot`, with stable zero-based indices from `workspace-groups.json`:

| Group | Slots | Internal numbers |
| --- | --- | --- |
| A | 1–10 | 1–10 |
| B | 1–10 | 11–20 |
| C | 1–10 | 21–30 |

A keeps plain numeric names, so existing windows and snapshots stay valid.
Polybar shows local labels (B's `3` is workspace `13`). The IPC number is the
identity: a renamed `13: project` is still B:3. Unnumbered workspaces,
out-of-range numbers, `_desktop`, and the scratchpad belong to no group (never
A). Duplicate live numbers block every group action. Empty slots come and go as
usual in i3.

### Switching and Moving Between Groups

A switch shows the group on every output; other groups' windows keep running.
Each group remembers its slot per output and its focused output. First entry
uses slot 1 on primary and 3 on external (one screen: last focused slot or 1),
always distinct per output. The switch is serialized and verified (every
visible workspace in the group); a failed IPC command records nothing, and the
screens still redraw separately. From a mode or bar click, window, bar, or kill
mode is closed through its cleanup first.

`Super+Shift+K/J` is the only path across groups. It moves just the focused
window (not its split) to the same slot and follows: from B:4 it lands on C:4,
while C's other output shows its remembered slot. The window and its source are
captured at the keypress and rechecked before the move, pending restore or
overflow decisions for it are dropped, and it then gets the normal
[overflow](#overflow-watcher) check in the destination group. Slot moves, window mode, overflow,
and restore routing refuse other groups.

### Focus and Urgency

`Super+Tab` (previous window) and `Super+Shift+Tab` (Rofi list of
`group:slot  title` with desktop-entry icons) switch to the window's group and
focus it without moving it; the controller's own transition events never
become the previous window. Under `smart` activation a hidden group's window
turns urgent and Polybar marks the group (`C!`) without switching; background
arrivals keep the selected group visible. Any other focus change into another
group is adopted, with one reconcile of the other output and no switch back.

### Displays

`config` assigns all 30 numbers, but assignments act only when i3 creates a
workspace, so on every switch, reload, output event, and `display-setup.sh`
run the controller moves existing workspaces back to their
[policy output](#workspaces), keeping their group. When a screen disappears the
other shows the group's last focused slot; the external slot is kept for
reconnection.

### Session Controller

`exec_always ... workspace-groups.py start` replaces the controller for the
same display and i3 socket, stopping pre-group watcher copies (including
`focus-tracker.sh`) too. The controller serializes every group, slot, move,
focus, kill, overflow, and restore request over a UNIX socket, and follows
window/workspace/output/mode events, reconnecting after i3 restarts and
reconciling from a fresh tree. It runs `autotiling`, `snap-watcher.sh`, and
`overflow-watcher.py`, restarting them on exit and pausing the first two during
a restore. State lives in `$XDG_RUNTIME_DIR/i3-groups-<hash>/` (hash of
`DISPLAY` and the i3 socket), so nested Xephyr tests never touch the live
session. While it is down or mid-transition, snap/resnap placement is skipped,
Polybar shows `groups unavailable`, and workspace keys report the error.

| File | Role |
| --- | --- |
| `workspace_groups.py` | Definitions, number/slot conversion, session paths, client, snapshot filter. |
| `group_controller.py` | Transitions, view memory, moves, overflow, kill scoping. |
| `group_restore.py` | Restore leases, launch tokens, placeholders, late-window routing. |
| `workspace-groups.py` | `start`/`serve`, CLI, Polybar module, Rofi list. `workspace-action.sh`, `move-to-workspace.sh`, `focus-prev.sh`, `show-desktop.sh`, and `focus-tracker.sh` wrap it. |

```sh
~/.config/i3/workspace-groups.py status    # JSON: group, workspaces, windows
~/.config/i3/workspace-groups.py select B
~/.config/i3/workspace-groups.py switch 3  # slot 3 of the selected group
~/.config/i3/workspace-groups.py start     # restart controller and workers
less "$(~/.config/i3/workspace-groups.py path)/controller.log"
```

### Adding a Group

Add a name and an unused index to `workspace-groups.json` (`"D": 3` → `31–40`).
List order sets tab and `Super+Ctrl+K/J` order. Never change an index: the
controller refuses to start rather than renumber. Then add `Super+Ctrl+4` and
`workspace 31`…`40` output lines to `config`; everything else adapts.

## XFWM-Style Snap System

`tile-snap.sh`, `_snap-common.sh`, `snap-watcher.sh`, and `resnap.sh` implement
snapping: windows become floating, fit a workspace region, and receive an
`_snap_<region>` mark.

### Snap Bindings

| Binding | Region |
| --- | --- |
| `Super+A` | Left half. |
| `Super+D` | Right half. |
| `Super+W` | Upper half. |
| `Super+S` | Lower half. |
| `Super+Q` | Upper-left quadrant. |
| `Super+E` | Upper-right quadrant. |
| `Super+Z` | Lower-left quadrant. |
| `Super+C` | Lower-right quadrant. |
| `Super+U` on release | Unsnap and restore the previous state. |

The script also supports `full` and optional container IDs:

```sh
~/.config/i3/tile-snap.sh full
~/.config/i3/tile-snap.sh left 123456
~/.config/i3/tile-snap.sh unsnap 123456
```

### Snap State and Marks

| Mark | Purpose |
| --- | --- |
| `_snap_<region>` | Current snap region. |
| `_presnap_<x>_<y>_<w>_<h>_<floating>` | Original geometry and floating state. |
| `_pretiling_<parent>_<layout>_<prev>_<next>` | Original tiling-tree position. |
| `_snap_parent_<target>`, `_snap_prev_<target>`, `_snap_next_<target>` | Restore anchors for tiled windows. |

Only the first snap captures original state; resnaps preserve it.

### Geometry Rules

Geometry comes from the target's workspace in `get_tree`, checked against
active outputs in `get_outputs` and clamped during stale/oversized hotplug
layouts. Visible Polybar insets (`xdotool`/`xwininfo`) are added only where i3
has not reserved them. Odd dimensions leave no 1 px gap; borders follow the
current `pixel 1`/`normal` title-bar state.

For applications enforcing size hints, placement retries up to ten times,
shrinking requests by measured overflow to stay inside the region.

### Unsnap Behavior

`Super+U` restores original floating geometry or the saved tiling-tree slot.
If the original parent disappeared, sibling anchors provide a fallback. With
no pre-snap mark, unsnap disables floating and removes snap marks. Tiled
restores reapply the shared autotiling split policy.

### Auto Fill and Rebalance

`snap-watcher.sh` applies the current title-bar default to new windows and
skips already-floating windows. On a workspace with snapped windows, it:

1. Uses the largest free snap region.
2. Otherwise splits an existing larger snapped region to make room.
3. If neither works, unsnaps that workspace and resumes normal tiling.

When a snapped window closes, remaining windows expand into freed quadrants,
trying larger regions first without overlap. A runtime lock prevents duplicate
watchers; it waits through i3 restarts and reconnects after subscription loss.

### Resnap

`resnap.sh` reapplies every `_snap_*` region after bar/title-bar changes. It
runs windows concurrently; `tile-snap.sh` serializes each container with its
own lock to protect marks during repeated actions.

### Shared Snap Runtime Files

`_snap-common.sh` uses `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}` for
`i3-titles.state`. Debug output goes to
`${XDG_STATE_HOME:-$HOME/.local/state}/i3/snap.log`, trimmed above about 200 KB
to the newest 500 lines. See [Runtime and State Files](#runtime-and-state-files).

## Focus History

The [controller](#session-controller) records the current and previous focused
windows, skipping the Copilot terminal and its own transitions. `focus-prev.sh`
(`Super+Tab`) focuses the previous one, switching groups if needed, so repeats
toggle between the two.

## Autotiling Integration

The controller runs `~/.local/bin/autotiling` without a depth limit;
[overflow handling](#overflow-watcher) controls capacity. The shared
`apply_autotiling_split` in `_snap-common.sh` follows the same policy after
snap fallbacks and tiled unsnaps: vertical for taller containers, horizontal
for wider/square ones. Floating/fullscreen windows and stacked/tabbed parents
are skipped.

## Overflow Watcher

`overflow-watcher.py`, an `i3ipc` listener run by the controller, hands over any
newly opened or manually moved window covering less than a quarter of its
workspace. Moves made through the controller (slot moves and
`Super+Shift+K/J`) are checked again once the destination is on screen, since a
hidden workspace still reports the window's old size. The controller searches
only the window's own group (from the live tree, not the selected group),
upward and wrapping `10→1` inside it:

1. First occupied slot with room.
2. Otherwise first empty slot.
3. Otherwise none: the window stays, `controller.log` notes the full group, and
   it is not retried until a workspace key moves it.

So overflow from B:10 (internal 20) may land on B:1–9 (11–19), never A or C,
while `Super+Ctrl+L` does nothing at B:10. Capacity uses the destination's
focus chain; stacked/tabbed insertion parents always have room. The window
moves once, to the first candidate: i3 doesn't lay out hidden workspaces, so
the prediction is trusted, not measured. The move names the container and its
source workspace, so a window moved meanwhile is left alone. Skipped:
same-workspace rearrangements, floating/fullscreen windows, the scratchpad,
handled windows, a running restore's windows, and arrivals mid-transition.

Moves are issued from the source before following, since focusing the
destination first can make a criteria-matched move silently no-op. In the
selected group the window is followed with a Polybar peek; a background group
never switches.

| Option | Effect/default |
| --- | --- |
| `-f`, `--fraction` | Minimum workspace area share, `0.25`. |
| `--no-follow` | Keep focus at the source. |
| `-d`, `--debug` | Watcher errors on stderr; full groups go to `controller.log`. |
| `I3_GROUP_PEEK` | Controller's peek helper; override in nested tests, since Polybar IPC is not display-scoped. |

## Tests

`tests/run-fast.sh` runs the quick checks, Bash syntax, optional ShellCheck,
and `i3 -C`, using `/usr/bin/python3` for Python. From chezmoi source state it
maps `executable_` filenames into a temporary applied tree, testing edits
without touching live config; it also runs directly from `~/.config`.

| Test | Covers |
| --- | --- |
| `run-fast.sh` | All fast checks, source-state mapping, syntax, lint, and i3 config parsing. |
| `test-workspace-groups.py` | Number/slot mapping, group-filtered snapshots, cross-group move refusal, duplicate numbers, all restore pairings, full groups, unsupported launches, layout-free restores, stale AppImages, legacy workers, Polybar text. |
| `test-workspace-groups-live.py` | Xephyr, one and two screens: boundaries, wrapping, transfers, previous group, bar push, remembered views, window selection, show-desktop, stale clicks, kill guard, restore placement, cancellation and late arrivals. Needs `Xephyr`, `xterm`. |
| `test-overflow-watcher.py` | Pure functions of `overflow-watcher.py`, including group-local wrap order; runs in milliseconds. |
| `test-overflow-live.py` | Drives a throwaway Xephyr i3 session and controller through every overflow rule on one and two screens. Needs `Xephyr`, `xterm`, `autotiling`; takes minutes. |
| `test-config-consistency.py` | Controller-owned placement workers, bar-nav arrays/twins, current and safe power commands, shared restore helpers, and system-Python entrypoints. |
| `test-provisioning-contract.py` | System-Python runtime imports remain paired with `python3-i3ipc`, `python3-xlib`, and `python3-lz4` in the desktop apt profile. Skips from an applied tree when the chezmoi package manifest is unavailable. |
| `test-bar-nav.sh` | Bar-mode navigation, selected-module actions, marker state, and prior-visibility restoration. |
| `test-polybar-peek.sh` | Peek show/hide, ownership, debounce, global workspace cycling, and pointer-hold preservation. |
| `test-i3-resurrect-polybar.sh` | Successful, hidden-bar, and early-failure restore paths preserve the bar's prior visibility and raise it when restored. |
| `test-resurrect-state.py` | Snapshot validation, atomic publication, previous-generation recovery, generation pruning, concurrent profiles, interrupted saves, route failures, browser pairing, placement around occupied workspaces, overflow sharing, and observed restore results. |
| `test-randr-hotplug.sh` | Output-event coalescing, connected-set changes, mid-run hotplugs, and connection-status toast selection. |
| `test-usb-hotplug.sh` | Connector classification and its refusal to guess an unrecognized topology, burst coalescing, hub arrivals, bounce suppression, Type-C partner correlation, wattage and alternate-mode detail, detach descriptions taken from cache, and lock handover when the watcher is replaced. |
| `test-dunst-start.sh` | Dunst 1.9 runtime config generation, laptop/primary fallbacks, and restart-on-index-change behavior. |
| `test-i3-restart.sh` | `Super+Shift+I` validates the candidate config before restart and reports validation/IPC failures once. |
| `test-super-polybar-listener.py` | Standalone-Super tap/hold gesture detection. |
| `test-top-edge-peek.py` | Top-edge pointer gesture: hysteresis and per-monitor tops. |
| `test-quit-key.py` | Quit-key targets and grab masks. |
| `test-tile-snap.sh` | Region geometry for all nine snaps including odd-sized workspaces, Polybar inset arithmetic, pseudo-output clamping, size-hint convergence, the `_presnap_`/`_pretiling_` mark protocol, unsnap, and the per-window lock. |
| `test-snap-watcher.sh` | Auto-fill region choice, splitting the largest occupant to make room, the fallback to tiling when nothing can be split, and rebalancing survivors after a snapped window closes. |
| `test-zen-url-state.py` | Session-store parsing for both Zen and Firefox layouts, profile discovery and dedup, i3 tree walking, window-to-page title matching, the gates that keep a headless save out of the live address-bar capture, and its focus checks. |
| `test-window-mode.sh` | Window mode's show-on-entry and restore-prior-Polybar-state contract. |
| `test-session-reload.sh` | Service refresh, changed-dunstrc handling, Picom `SIGUSR1`, and single success/partial-failure toast coordination. |
| `../../polybar/tests/test-launch.sh` | Multi-monitor launch, tray ordering, lock-fd closure, hung-bar kill escalation, log defaults and filename safety, and rotation. |
| `../../polybar/tests/test-confirm-poweroff.sh` | Explicit confirmation and safe cancellation/timeout behavior for every prompt backend, including the no-backend path. |

The live tests never touch the running session:

```sh
~/.config/i3/tests/test-workspace-groups-live.py  # single screen, then dual
~/.config/i3/tests/test-workspace-groups-live.py single
~/.config/i3/tests/test-overflow-live.py          # single screen, then dual
~/.config/i3/tests/test-overflow-live.py single
~/.config/i3/tests/test-overflow-live.py dual
```

## Title-Bar Toggle

`toggle-titles.sh` toggles all workspaces between `off` (`border pixel 1`)
and `on` (`border normal`), stored in `$XDG_RUNTIME_DIR/i3-titles.state`.
Because i3 cannot change `default_border` at runtime, `snap-watcher.sh` applies
the state to new windows. `toggle-titles-resnap.sh` then runs `resnap.sh` to
fit changed decorations.

## Polybar Integration

`~/.config/polybar/launch.sh` starts hidden, synchronized bars on every active
output: `main` on primary, inherited `external` elsewhere, and `tray` on the
internal `eDP*`/`LVDS*` panel (primary fallback). X11 supports one tray owner.

The launcher serializes with `flock`; concurrent requests reuse its processes.
Detached bars and `blueman-tray` must close lock fd 9 (`9>&-`) or later launches
cannot refresh hotplugged outputs. Hung bars are killed after the normal stop
fails. Per-output logs under `${XDG_STATE_HOME:-$HOME/.local/state}/polybar/`
are trimmed above 200 KB to 500 lines; override with `POLYBAR_LOG_DIR`,
`POLYBAR_LOG_MAX_BYTES`, and `POLYBAR_LOG_KEEP_LINES`.

The `groups` module (`workspace-groups.py bar`, one per bar) subscribes to the
controller, which pushes a compact status only on change, and draws with
`[colors]` passed as `env-GROUP_*`. Slot actions carry their group, so a stale
click is ignored. `internal/i3` remains only for the window/kill/bar mode label
(`format = <label-mode>`). Tab and wheel behavior is in
[Polybar controls](../polybar/docs.md).

`display-setup.sh` owns relaunch after session/layout refresh and RandR hotplug.
Keep `screenchange-reload` disabled: Polybar's own reload unhides the bar and
cannot create one for a new output. `wm-restack` is unused because it requires
`override-redirect`; `_polybar-common.sh` raises bar windows explicitly.

`toggle-polybar-resnap.sh [show|hide]` (default: toggle, `Super+Shift+B`):

- Broadcasts visibility over `polybar-msg`; relaunches if show IPC is unavailable.
- Waits up to 800 ms for X visibility, then raises visible bars and resnaps.
  All-fullscreen outputs may keep docks unmapped; do not extend this wait past
  the other controls' two-second lock timeout.
- Serializes toggles and repairs hidden docks still reserved by i3 after
  fullscreen use. The launcher and session restore share this repair.

`polybar_show_persistent` promotes a transient peek for binding modes.
Window mode keeps its own restore marker; session restore hides a previously
visible bar and restores/raises it on exit.

`polybar-peek.sh` and `super-polybar-listener.py` provide keyboard peeks:

- Workspace keys or a Super-only tap reveal a hidden bar for
  `I3_POLYBAR_PEEK_MS` (200 ms); repeated keys extend one deadline.
- A Super-only hold reveals it until release. `I3_SUPER_HOLD_MS` overrides the
  threshold, otherwise it follows the peek duration. Another key cancels the
  standalone gesture.
- Ownership prevents hiding an already persistent bar; `Super+Shift+B`
  cancels pending peeks. Transient peeks skip resnapping.
- The listener observes XI2 raw events without grabbing keys and resolves
  Super keycodes from the active X keymap.

Pointer scrolling preserves the existing hold rather than starting a timed
keyboard peek. See [Bar Mode](#bar-mode) and [Top-Edge Peek](#top-edge-peek).

### NetworkManager Tray

`nm-applet` provides Wi-Fi menus and password prompts; `blueman-applet`
provides the Bluetooth backend and `blueman-tray` its icon. The single tray is
on the laptop/primary bar. `launch.sh` waits for NetworkManager to dock before
restarting `blueman-tray`, matching bar mode's Wi-Fi-then-Bluetooth order.
Other applets, including Fcitx5, keep their arrival order.

Tray icons cannot use Polybar's selected-module twins. `bar-nav.sh` reads each
icon's actual geometry; `bar-nav-marker.py` overlays a full-height,
override-redirect ARGB block in `${colors.selection}`, blended by Picom. Its empty input region passes
clicks through without changing tray layout. The runtime marker contains
`x y width height`; truncation hides it. One painter runs per mode under
`flock` and exits when the navigation index file disappears.

`Return`/`Shift+Return` move the pointer to the icon and send button 1/3.
Either menu exits bar mode and restores previous visibility while the applet
menu remains open. Right-click exposes NetworkManager networking toggles or
Blueman send/setup actions.

### Top-Edge Peek

`top-edge-peek.py` reveals the bar while the pointer rests near a monitor's
top edge, without taking over a persistent bar. Moving away releases the hold;
a dead holder is cleaned up by the peek worker.

| Variable | Default | Meaning |
| --- | --- | --- |
| `I3_POLYBAR_EDGE_ENTER_PX` | `2` | Reveal within this distance of the monitor's top. |
| `I3_POLYBAR_EDGE_LEAVE_PX` | `40` | Hide beyond this distance; allows use of the 28px bar. |
| `I3_POLYBAR_EDGE_POLL_MS` | `100` | Pointer polling interval. |

Each monitor's own top edge is used, including vertically offset outputs.
Polling avoids an input window intercepting clicks or causing reveal/hide
flicker. Scrolling workspaces preserves the hold; entering bar mode promotes
it for that mode, whose exit restores hidden state.

A monitor currently showing a fullscreen window suppresses the gesture, since
i3 cannot map its dock. Only visible workspaces count; hidden fullscreen
workspaces do not block peeks. Fullscreen state is queried on edge entry,
not every poll, and the gesture re-arms after crossing the leave threshold.
The watcher needs system Python's `Xlib` (`python3-xlib`); if missing, it fails
on import and edge peeks do nothing.

## Monitor and Wallpaper Setup

`display-setup.sh` uses `I3_LAPTOP_OUTPUT` (`eDP`), waits
`I3_DISPLAY_SETUP_DELAY` (1 second), then waits up to about five seconds for
the laptop output. The first connected non-laptop output goes at `0x0`; the
laptop stays primary to its right, or at `0x0` when alone. Setup refreshes
wallpaper, dunst's monitor selection, and all bars.

`randr-hotplug.sh` debounces i3 output events for `I3_RANDR_HOTPLUG_QUIET`
(0.7 seconds). It compares sorted *connected* XRandR outputs, ignoring layout
changes to avoid loops, and rechecks after setup to catch intervening hotplugs.
A runtime lock keeps one watcher. Startup records the current set silently.

`I3_DISPLAY_TOAST` selects `Display connected`, `Display disconnected`, or
`Display changed` (same-count replacement), shown after setup completes.
`_toast-common.sh` uses the shared `reload-toast` Rofi theme and pins notices
to primary; `I3_TOAST_MONITOR` accepts any `rofi -m` value. Session start/restart
uses `Welcome`/`i3 reloaded`; `Super+Shift+P` stays silent.

`wallpaper.sh` uses `feh` when available:

```sh
feh --no-fehbg --bg-fill "$HOME/.wallpaper-laptop.png" "$HOME/.wallpaper-external.png"
```

## USB and Type-C Notices

`usb-hotplug.sh` reads unprivileged `udevadm monitor --udev --property` events
for `usb` and `typec` and uses the shared Rofi toast. No root or udev rule is
required. One runtime-locked watcher:

- Coalesces bursts for `I3_USB_HOTPLUG_QUIET` (0.7 seconds); a hub and children
  produce one notice with `+N devices`.
- Seeds a startup cache, keeping login/resume enumeration silent, describing
  removed devices from cache, and suppressing detach/reattach bounces.
- Computes connector mappings at startup using `usbN-portM/connector` links
  when available. Otherwise Type-C mapping
  requires two single-port xHCI root hubs (high/super speed) per
  `/sys/class/typec` port. Unrecognized topology is labelled `USB` without
  guessing. Override with `I3_USB_TYPEC_BUSES`; inspect with `--dump`.
- Correlates Type-C partner and USB events within `I3_USB_TYPEC_WINDOW`
  (3 seconds); chargers/displays without USB enumeration still get notices.

`I3_USB_TOAST_DETAIL=full` includes advertised wattage from the partner's
`usb_power_delivery` source capabilities, active alternate modes, and link
speed; `compact` omits them. Notices name connectors but not physical sides:
that would require both USB-A `physical_location/panel` and Type-C location
data, since firmware `_PLD` mappings may be absent or inaccurate.

The 320px `reload-toast` theme uses explicit wrapping to work around Rofi
1.7.5's multi-line height estimate. `I3_TOAST_WRAP` controls character width;
values/units and separator dots stay together across line breaks.

## Workspace Movement

`move-to-workspace.sh SLOT` moves the focused window to that slot of its own
group and follows; `workspace-action.sh` passes its arguments to
`workspace-groups.py`, which supplies the in-group wrapping for
`Super+Shift+H/L`. The window and its source workspace are captured at the
keypress, and the move happens only if it is still there. The current slot is
a no-op. Overflow may forward a moved window again within the group if it covers
less than a quarter of its destination.

## Show Desktop

`show-desktop.sh` (`Super+M`) records the group and slot, then shows the empty
`_desktop` on the focused output. Pressing it again returns to that group and
slot, not i3's global `back_and_forth`. Selecting a group also leaves it without
touching remembered slots. Windows are not minimized.

Scratchpad commands stay outside group ownership. The Copilot terminal is
excluded by class even when shown on a numbered workspace, so it never counts
toward a group, snapshot, or focus history.

## Floating Rules

Utility windows float and centre. Class/instance patterns are anchored and
case-insensitive, except explicit `.*` patterns; titles have separate fallbacks.
The exact alternations live in `config` (`$float_settings`, `$float_titles`).

| Group | Matching utilities |
| --- | --- |
| Settings | `xfce4-power-manager-settings`, `nm-connection-editor`, `blueman-manager`, `blueman-adapters`, `pavucontrol`. |
| XFCE | `xfce4-display-settings`, `xfce4-settings-manager`, `xfce4-settings-editor`, `xfce4-appearance-settings`, `xfce4-mouse-settings`, `xfce4-keyboard-settings`, `xfce4-notifyd-config`, `xfce4-session-settings`, `thunar-settings`; terminal settings by title. |
| System/admin | `xfce4-taskmanager`, `system-config-printer`, `org.gnome.DiskUtility`, `gnome-disks`, `gufw`, `driver-manager`, `mintsources`, `mintreport`, `mintbackup`, `timeshift`, `timeshift-gtk`, `timeshift-launcher`, `users-admin`, `time-admin`. |
| Input/locale | `fcitx5-configtool`, `fcitx-config-gtk3`, `fcitx5-config-qt`, `mintlocale`, `mintlocale-im`, `im-config`, `ibus-setup-hangul`. |
| Desktop | `light-locker-settings`, `onboard-settings`, `mugshot`, `menulibre`, `rofi-theme-selector`. |
| Updates | Class/instance containing `mintupdate`; English or Korean update-manager titles. |
| KakaoTalk/Wine | Exact `kakaotalk.exe` class/instance: float, resize to `420x760`, centre. Titles mentioning KakaoTalk are not matched. |

## KakaoTalk Float Watcher

`kakaotalk-float-watcher.sh` scans at startup and watches new/floating/fullscreen
events. Visible, non-fullscreen KakaoTalk windows returned to tiling by Wine
are floated, resized to `420x760`, and centred. Minimized/hidden and fullscreen
windows are skipped, so `Super+F` works normally. The watcher locks against
duplicates, reconnects on subscription loss, and logs repairs to `snap.log`.

## i3-Resurrect Save and Restore

Snapshots contain live directories, URLs, PDF paths, and remote session names.
Keep `resurrect*` data local and out of this public repository/documentation.

| Profile | Save (on release) | Restore | State / metadata directories |
| --- | --- | --- | --- |
| Main | `Ctrl+Super+A` | `Ctrl+Super+R` | `resurrect` / `resurrect-meta` |
| B | `Ctrl+Super+B` | `Ctrl+Super+S` | `resurrect-b` / `resurrect-meta-b` |
| C | `Ctrl+Super+C` | `Ctrl+Super+T` | `resurrect-c` / `resurrect-meta-c` |

Profiles are storage slots, not groups: a save captures one
[group](#workspace-groups) and a restore fills one, each the selected group
unless `--group=A|B|C` is given, captured once at start. Any profile can hold
any group and restore into any group. For example, save B into Main, switch to
C, and restore Main: everything lands in C (`21–30`), and A and B are
untouched.

B/C wrappers set `I3_RESURRECT_STATE_DIR` and `I3_RESURRECT_META_DIR`, then exec
the main scripts. All profiles share a nonblocking lock per X display in
`${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`: concurrent operations report busy and
exit rather than queue. `--check` only inspects dependencies/files; other
failures notify with their reason.

### Save Script

`i3-resurrect-save-all.sh` saves every nonempty workspace of one group,
leaving out other groups, `_desktop`, the scratchpad, and the Copilot terminal.
`--check` verifies `i3-msg`, `jq`, `flock`, `sha256sum`, `i3-resurrect`, system
Python, and the shared snapshot helper.

| Setting | Default |
| --- | --- |
| `I3_RESURRECT_STATE_DIR` / `I3_RESURRECT_META_DIR` | `~/.config/i3/resurrect` / `~/.config/i3/resurrect-meta` |
| `I3_RESURRECT_SWALLOW` | `class,instance,title` |
| `I3_RESURRECT_ZEN_HELPER` / `I3_RESURRECT_GHOSTTY_HELPER` | Sibling `zen-url-state.py` / `ghostty-session-state.py` |
| `TAILSCALE_REMOTE_MODE_FILE` | `$XDG_RUNTIME_DIR/tailscale-remote-proxy-required`, created by `labroute on`. |

Each generation under `<state-directory>/snapshots/generation.*` contains
`state/` layouts/programs and `meta/`: sorted `workspaces.txt`,
`focused-workspace.txt`, the group-filtered `tree.json`, `zathura-pages.json`,
`zen-pages.json`, `ghostty-sessions.json`, `labroute.txt`, and
`group-format.json`. The profile metadata directory's `snapshot.json` selects
current and previous generations.

Save takes the operation lock and a restrictive umask, captures one i3 tree
filtered to the source group for identities/application metadata, records
route state, and runs `i3-resurrect save` per workspace under its live number.
Window changes other than titles abort the save; retry once the desktop
settles. It normalizes layouts, ensures Zen
programs exist for placeholders, stabilizes Helium commands, and inserts
captured URLs, PDF pages, and per-window Ghostty launch state.

After validating all layouts, program lists, and present application metadata,
it flushes the generation and atomically publishes the manifest. Failed or
interrupted saves preserve the old selection. The first successful save can
archive a valid legacy flat profile as the previous generation; original files
stay intact and invalid legacy data is never offered for recovery.

Before publishing, save rewrites the generation to logical slots: B's
`13: project` becomes slot `3` in filenames, layouts, `workspaces.txt`, the
focused workspace, application metadata, and Ghostty instance names. Only those
fields change, never digits inside commands, paths, or URLs.
`group-format.json` records version 1, ten slots, and the source group, which
is informational and never routes a restore. A group with no savable windows
fails the save and keeps the previous profile.

Published generations are immutable. Each save keeps only the current and
previous generations, removing older ones and interrupted-save leftovers. A
notification reports the source group and saved workspace count.

Normalization removes Ghostty/Zen/Helium swallow titles and Ghostty's instance;
Ghostty capture then assigns unique per-window instances.

### Zathura Page Capture

For each Zathura window, save gets the PID through `xprop`, queries
`org.pwmt.zathura.PID-<pid>` with `busctl --user`, reads `filename` and zero-based
`pagenumber`, and stores a one-based page. Restore commands receive
`--page=<page>`. Unreadable windows keep their plain command.

### Zen and Helium URL Capture

`zen-url-state.py` first activates each browser with `xdotool`, copies its
address with `Ctrl+L`, `Ctrl+C`, and `xclip`, then restores clipboard and focus.
Keys are sent only while that browser is confirmed active.
Set `ZEN_LIVE_URL_CAPTURE=0` to disable live capture.

Fallback reads Zen/Firefox session files from
`~/.var/app/app.zen_browser.zen/.zen` and `~/.zen` (`ZEN_PROFILE_ROOTS` override),
decoding `jsonlz4` with Python `lz4.block`. It matches normalized titles and
browser classes, consuming same-title candidates in order. Live URLs win for
the same window ID; indistinguishable fallback windows remain best-effort.

JSON preserves window order and null URLs on failure, with workspace, window
ID, title, URL, profile, session file, window index, and browser type when
available. Save joins by window ID before assigning URLs to program slots and
leaves commands unchanged when window/program counts disagree.

### Helium Command Stabilization

Temporary `/tmp/.mount_helium...` commands do not survive reboot. Save replaces
them with the `Exec=` command from `~/.local/share/applications/helium.desktop`
minus field codes such as `%U`, falling back to the newest
`~/Applications/helium*.AppImage`.

### Ghostty Session Capture

`ghostty-session-state.py` reads the i3 tree on stdin and `/proc`
(`I3_RESURRECT_PROC_ROOT` override). It groups surfaces by `WINDOWID`, reads
shell directories below Ghostty's `/bin/sh -c` wrapper, and recognizes
`hpc NAME` (tmux) / `hpcz NAME` (zmx) attaches in `ssh` command lines. Per-window
metadata follows i3-resurrect program order, records every distinct session,
and uses the first session's surface directory or the first surface's directory.

i3 exposes windows, not Ghostty tabs/splits. When captured-window, program, and
placeholder counts agree, save rewrites each launch with:

- `--working-directory=<dir>`; unsafe `"`, `\`, `$`, or backticks in paths
  fall back to the saved directory, then `$HOME`.
- `--x11-instance-name=ghostty-ws<workspace>-<n>` and a matching placeholder.
- `--initial-command=env I3_RESURRECT_REMOTE_SESSION=<kind>:<name> zsh` for
  the first remote session. `50-remote.zsh` attaches before the first prompt
  and adds the command to history; later tabs/splits get plain shells.

Count mismatches retain plain `ghostty` programs. Command-line arguments disable
single-instance mode, so each restored window gets a process that exits with
it. Ghostty has no external split-creation API: only the first session per
window restores, and the notification lists the rest.

### Restore Script

`i3-resurrect-restore-all.sh` resolves and validates the saved workspace list
and restores it into one destination group. State/metadata paths use the
[save defaults](#save-script).

| Setting | Default |
| --- | --- |
| `I3_RESURRECT_LAYOUT_DELAY` | `0.25` seconds. |
| `I3_RESURRECT_WAIT_ATTEMPTS` / `I3_RESURRECT_POLL_INTERVAL` | `48` attempts / `0.25` seconds. |
| `I3_RESURRECT_REMOTE_HELPERS` | `~/.zsh/rc.d/50-remote.zsh`. |
| `I3_RESURRECT_LABROUTE_TIMEOUT` | `45` seconds. |

`--check` validates dependencies/helpers, the complete workspace list, referenced
layout/program JSON, filename collisions, focused workspace, route state, and
present application metadata. It then prints the destination group's slot plan
without taking a placement lease or changing windows, routing, or Polybar.
More than ten nonempty saved workspaces is rejected. Legacy flat data is used
only when no manifest exists; an invalid manifest never silently falls back.
Pre-group snapshots (workspaces `1–10`) read as slots and restore into any
group; an unknown `group-format.json` version is rejected.

`--previous` selects the prior generation; B/C wrappers accept every option:

```sh
~/.config/i3/i3-resurrect-restore-all.sh --previous --check
~/.config/i3/i3-resurrect-restore-all.sh --previous
~/.config/i3/i3-resurrect-restore-all-b.sh --group=C
```

Restore takes the shared lock, resolves one snapshot, validates it, then:

1. Maps saved slots in order to the destination group's empty slots from slot
   1; any tiled/floating window reserves a slot. Leftovers share the group's
   occupied slots, lowest first. Other groups, the scratchpad, and unnumbered
   workspaces are never used; no window is closed or moved out.
2. Builds temporary layout/program copies, leaving the snapshot intact, and
   drops swallow titles (apps such as Zathura set theirs after mapping). Each
   program gets a unique launch token; its placeholder gets an operation mark
   and a swallow rule matching nothing, so it captures no unrelated window.
   Shell-string, `gtk-launch`, `xdg-open`, and `dbus-send` launches are
   rejected before any window changes. A missing `*.AppImage` resolves to the
   newest matching AppImage in its folder (e.g. after a Helium update). A
   workspace whose placeholder and program counts differ can't be paired; its
   programs open without the layout.
3. If `labroute.txt` is `on`, runs `labroute on` through the remote helpers.
   Failure/timeout aborts before touching windows or Polybar; restore never
   turns the route off.
4. Takes a controller placement lease: selects the group, pauses autotiling
   and snap-watcher, and makes existing windows ineligible for routing. Hides a
   visible bar.
5. Per workspace, rechecks that an empty destination is still empty; the
   controller inserts the layout and launches each program. The token goes to
   Ghostty as `--x11-instance-name`, xterm as `-name`, and every launch as
   `DESKTOP_STARTUP_ID` and `I3_GROUP_LAUNCH`. A new window whose instance,
   `_NET_STARTUP_ID`, or environment matches exactly one pending token is
   swapped into its placeholder or moved to its slot, and overflow skips it. A
   failed launch doesn't stop the workspace's others; the workspace is reported
   failed.
   Ready means placeholders filled, expected windows present, and every launch
   matched to a window still in its slot, ignoring pre-existing windows.
6. Rechecks successes, focuses the mapped saved focused workspace if it had
   windows, and releases the lease, which removes the operation's still-empty
   placeholders and resumes the workers. A previously visible bar is
   restored/raised on exit.
7. Writes `last-restore.json`: snapshot, mapping, shared slots, status/reason
   per workspace, and session retry guidance. The notification names the group
   and lists mappings, shared slots, layout-free workspaces, and failures.

A group switch cancels the restore at the next launch boundary, removing its
empty placeholders without pulling focus back. A late window from an issued
launch, even after cancellation or a controller restart, still goes to its
captured slot without switching groups. Launch records last while the launcher
lives and at least two minutes; a dead owner's lease is released. A
`Super+Shift+K/J` transfer drops the window's routing record. Apps that hand a
launch to an already-running process (some single-instance browsers and file
managers) may open windows that can't be proven new; that workspace is reported
incomplete rather than moving an existing window.

Terminal launches report `Remote attach requested (unverified)`, not confirmed
remote login/attachment. Unlaunched sessions and failed-workspace sessions
appear under `Reattach by hand`.

Example: with live windows on A's `1,4`, saved slots `1,2,3,4,5` restore into A
as `2,3,5,6,7`, and nine saved slots as `2,3,5,6,7,8,9,10,1`, sharing only `1`.
Into B, the nine land on `11–19`, leaving A untouched. Same for all profiles.

## Saved Session Profiles

The `resurrect*` directories hold saved layouts and program lists — data written
by the save scripts, not static i3 config. They are local to this machine:
`.gitignore` excludes `dot_config/i3/resurrect*`, so they never enter the
repository and their contents change on every save. This manual therefore does
not snapshot them.

To see what a profile currently holds:

```sh
cd ~/.config/i3
jq . resurrect-meta/snapshot.json         # current and previous generations
snapshot=$(/usr/bin/python3 ./i3-resurrect-state.py resolve resurrect resurrect-meta)
state=$(printf '%s' "$snapshot" | jq -r '.[0]')
meta=$(printf '%s' "$snapshot" | jq -r '.[1]')
cat "$meta/workspaces.txt"                 # which slots will restore
jq . "$meta/group-format.json"             # slot format and source group (absent in legacy)
cat "$meta/focused-workspace.txt"
jq . "$meta/zathura-pages.json"            # captured PDF pages
jq . "$meta/zen-pages.json"                # captured browser URLs
jq . "$meta/ghostty-sessions.json"         # Ghostty dirs and sessions
cat "$meta/labroute.txt"                   # route at save time
jq -r '.[].command | if type=="array" then join(" ") else . end' \
   "$state/workspace_7_programs.json"      # what slot 7 relaunches
jq . resurrect-meta/last-restore.json      # last completed restore attempt
```

Use `resurrect-meta-b` / `resurrect-b` and `resurrect-meta-c` / `resurrect-c`
for the other two profiles.

A legacy state directory can hold files for workspaces absent from its
`workspaces.txt`; those leftovers are not restored or copied into recovery
generations. New generations contain only the workspaces from that save.

## Autostart

One-shot startup runs `gnome-keyring-daemon --start --components=secrets`,
`xrdb -merge ~/.Xresources`, `xsetroot -cursor_name left_ptr`, guarded
`blueman-tray` after two seconds, and idempotent `dropbox start -i`.

The `exec_always` setup:

- Enables Num Lock restoration (remembered state stays local), starting
  `xfsettingsd` if needed.
- Starts missing `xfce4-power-manager`, `picom -b`, `nm-applet`,
  `blueman-applet`, and `unclutter-xfixes --timeout 3`.
- Runs `session-reload.sh`: `systemctl --user daemon-reload`, `try-restart`
  `task-notify.timer`, and restart `dunst.service` only when `dunstrc` changed.
  dunst 1.9.2 has no reload command and restarting discards visible notices.
  See the [Taskwarrior manual](../task/MANUAL.md).
- Sends running Picom `SIGUSR1`; guarded autostart handles a stopped instance.
  Display setup completes before one `Welcome`, `i3 reloaded`, or aggregated
  partial-failure toast.
- Restarts the [group controller](#session-controller) (and with it
  `autotiling`, `snap-watcher.sh`, `overflow-watcher.py`),
  `kakaotalk-float-watcher.sh`, `randr-hotplug.sh`, `usb-hotplug.sh`,
  `super-polybar-listener.py`, `top-edge-peek.py`, and `quit-key.py`.
- Starts missing `xss-lock --transfer-sleep-lock -- lock.sh` and
  `/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1` (guarded by
  the `polkit-gnome` process).
- Runs `~/.local/bin/disable-trackpoint-middle-click` under
  `/tmp/disable-trackpoint-middle-click.lock` and `~/.local/bin/touchpad apply`.

Watchers use runtime locks against duplicates. `display-setup.sh` arranges
outputs, asks the controller to reconcile workspace outputs, asks
`dunst-start.sh` to restart dunst only when its laptop/primary monitor index
changes, refreshes wallpaper, and launches the per-output bars.

## Dependencies

| Area | Required programs |
| --- | --- |
| Core | `i3`, `i3-msg`, `bash`, `jq`, `flock`. |
| Launchers/apps | `ghostty`, `xfce4-terminal`, `rofi`, `thunar`, `zed`, `flatpak`, `app.zen_browser.zen`, Helium AppImage under `~/Applications`. |
| Desktop | `xfsettingsd`, `xfce4-power-manager`, `xfce4-display-settings`, `xfce4-taskmanager`, `i3lock`, `xss-lock`, `gnome-keyring-daemon`, `picom`, `nm-applet`, `blueman-applet`, `blueman-tray`, `blueman-manager`, `unclutter-xfixes`, `polkit-gnome-authentication-agent-1`. |
| Media/capture | `pactl`, `playerctl`, `brightnessctl`, `flameshot`. |
| Display/bar/snap | `xrandr`, `udevadm` (systemd), `polybar`, `polybar-msg`, `xdotool`, `xinput`, `xmodmap`, `xwininfo`, `xprop`, `feh`. |
| Restore | `i3-resurrect`, `notify-send`, `busctl`, `zathura`, `sioyek`, `xclip`, `sha256sum`. |
| Tests | `Xephyr`, `xterm`; ShellCheck when available. |

Python helpers use `/usr/bin/python3` so Conda/user environments cannot shadow
distro modules. `.chezmoidata/packages.toml` provisions `python3-i3ipc`,
`python3-xlib`, and `python3-lz4` (`lz4.block`) in `linuxmint-i3-x11`, and
`~/.local/bin/autotiling` through `packages.pipx.apps`.

Other helpers managed in this source state: `~/.local/bin/touchpad`,
`~/.local/bin/disable-trackpoint-middle-click`, and `~/.config/polybar/launch.sh`.

## Runtime and State Files

Helpers are documented in their feature sections. Shared libraries:
`_snap-common.sh` (geometry/focus), `_polybar-common.sh` (bar visibility/peek),
`_toast-common.sh` (notices), `_resurrect-common.sh` (operation lock,
dependencies, metadata, group lookup), and the Python group modules listed
under [Session Controller](#session-controller). `i3-resurrect-state.py`
validates/publishes snapshots, filters and normalizes groups, plans restores,
pairs browser state, checks readiness, and reports sessions. Profile B/C use
`i3-resurrect-{save,restore}-all-{b,c}.sh`; their `resurrect*` data stays local.

Runtime files below use `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`:

| Files | Purpose |
| --- | --- |
| `i3-titles.state` | Decorations. |
| `i3-groups-<hash>/` | Controller session (hash of `DISPLAY` and i3 socket): `state.json` (group, views, history, leases, pending launches, workers), `controller.sock`, `controller.lock`, `start.lock`, `controller.log`. |
| `i3-snap-watcher.lock`, `i3-kakaotalk-float-watcher.lock`, `i3-randr-hotplug.lock`, `i3-usb-hotplug.lock`, `i3-quit-key.lock` | Watcher singleton locks. |
| `i3-resurrect-<display-hash>.lock` | Shared save/restore operation. |
| `i3-polybar-toggle.lock`, `i3-polybar-peek-worker.lock` | Visibility/peek serialization. |
| `i3-polybar-peek.owner`, `i3-polybar-peek.trigger`, `i3-polybar-peek.hold` | Peek ownership, deadline, holder PID. |
| `i3-super-polybar-listener.lock`, `i3-top-edge-peek.lock` | Gesture watcher locks. |
| `i3-polybar-nav.idx`, `i3-polybar-nav.restore-hidden` | Keyboard cursor and prior bar visibility. |
| `i3-polybar-nav.marker`, `i3-polybar-nav.marker.lock` | Tray highlight rectangle and painter lock. |
| `i3-window-mode.restore-hidden` | Window-mode prior visibility. |
| `i3-reload-toast` | First-login versus subsequent-reload toast stamp. |
| `tile-snap-<con_id>.lock` | Per-window snap serialization. |

Persistent logs: `${XDG_STATE_HOME:-$HOME/.local/state}/i3/snap.log` and
`${XDG_STATE_HOME:-$HOME/.local/state}/polybar/polybar-<output>.log`.
Trackpoint setup uses `/tmp/disable-trackpoint-middle-click.lock`.
Snapshot layouts/programs/application metadata live in `resurrect{,-b,-c}`;
manifests, `last-restore.json`, and original legacy metadata in
`resurrect-meta{,-b,-c}`. `tests/` contains standalone checks.

## Maintenance Notes

- Keep `default_border pixel 1` in `config` aligned with `NEW="pixel 1"` in
  `toggle-titles.sh`.
- Update `I3_LAPTOP_OUTPUT` for a different laptop connector. Keep the slot
  output policy in `target_output` (`group_controller.py`) aligned with the
  `workspace N output` lines in `config` for every group, and `SLOTS`
  (`workspace_groups.py`) with `MAX_WS` (`overflow-watcher.py`).
- Add groups only as in [Adding a Group](#adding-a-group). Callers must use
  `workspace_groups.py`, never compute offsets themselves.
- After USB topology changes, inspect `usb-hotplug.sh --dump` and override
  `I3_USB_TYPEC_BUSES` if needed.
- `_toast-common.sh`'s `TOAST_WRAP` default is 27, matching the theme's 270px
  content width at JuliaMono 13; update it with `spotlight.rasi` width/font.
- Keep `^[Pp]olybar$` searches aligned with the bar's class. Change snap marks
  in `tile-snap.sh`, `snap-watcher.sh`, `resnap.sh`, and cleanup code together.
- Browser launch changes require updates to `i3-resurrect-save-all.sh` and
  `zen-url-state.py`. Keep `SESSION_PATTERNS` in `ghostty-session-state.py`
  aligned with `hpc`/`hpcz` attach commands.
- Helium upgrades require a valid `helium.desktop` or matching
  `~/Applications/helium*.AppImage`. Profile `workspaces.txt` selects restores;
  unlisted legacy layout files are ignored.
- Keep [Python/pipx dependencies](#dependencies) paired with provisioning and
  use system-Python entrypoints.

## Quick Commands

```sh
# Validate save dependencies / restore dependencies and snapshot metadata
~/.config/i3/i3-resurrect-save-all.sh --check
~/.config/i3/i3-resurrect-restore-all.sh --check

# Refit snapped windows and inspect geometry/debug output
~/.config/i3/resnap.sh
tail -n 100 "${XDG_STATE_HOME:-$HOME/.local/state}/i3/snap.log"

# Fast checks from the applied tree, or from chezmoi source state
~/.config/i3/tests/run-fast.sh
bash dot_config/i3/tests/executable_run-fast.sh

# Group controller state and decisions (overflow, restore, recovery)
~/.config/i3/workspace-groups.py status | jq .
tail -f "$(~/.config/i3/workspace-groups.py path)/controller.log"

# Restart the controller and its placement workers
~/.config/i3/workspace-groups.py start
```

# i3 Configuration Manual

Reference for `~/.config/i3/config`, its helpers, and local i3-resurrect
profiles. See also the [Polybar controls](../polybar/docs.md) and
[Ghostty guide](../ghostty/docs.md).

## Overview

An i3/X11 session with XFCE desktop services and Polybar instead of
`xfce4-panel`. It provides floating snap regions with automatic fill/rebalance,
focus history, overflow handling, three session profiles, display/USB hotplug
notices, and utility-window floating rules.

## Core Session Settings

- Modifier: `Mod4` (Super/Windows); font: `pango:DejaVu Sans 10`.
- Focus follows the mouse; focus wrapping and cursor warping are disabled.
- `workspace_auto_back_and_forth` is enabled.
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
| `Super+Space` | Rofi drun (`XDG_CURRENT_DESKTOP=XFCE:i3`, `spotlight` theme). |
| `Super+Tab` / `Super+Shift+Tab` | Previous window / Rofi window switcher. |
| `Super+T` | Thunar. |
| `Super+P` / `XF86Display` | Minimal XFCE display settings. |
| `Super+Shift+P` | Refresh display layout, wallpaper, and Polybars. |
| `Ctrl+Super+Z` / `Ctrl+Shift+Z` | Zed / Zen Browser Flatpak. |
| `Ctrl+Alt+Escape` on release | `xkill`. |
| `Ctrl+Shift+Escape` | `xfce4-taskmanager`. |

`Ctrl+Alt+T` belongs to XFCE; `Super+D` snaps right. `Ctrl+Super+H/L` are
reserved for numeric workspace navigation; the old Helium/lock bindings are
disabled. Lock with `Super+Escape`.

### Window Management

| Binding | Action |
| --- | --- |
| `Super+Shift+Q` / `Alt+F4` | Close focused window. |
| `Super+H/J/K/L` / `Super+Arrow keys` | Focus left/down/up/right. |
| `Super+Shift+H/L` | Move to previous/next numbered workspace and follow; wrap 1↔10. |
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

i3 has no previous-output command.

### i3 Control

| Binding | Action |
| --- | --- |
| `Super+Shift+C` | Reload i3 config. |
| `Super+Shift+I` | Validate and restart i3; refresh user services, changed dunst config, Picom, displays, wallpaper, and bars; show one result toast. |
| `Super+Shift+E` | Confirm exit through `i3-nagbar`. |
| `Super+Escape` on release | Lock with `lock.sh`. |

### Workspaces

Workspaces are numbered `1–10`; `0` selects `10`.

| Binding | Action |
| --- | --- |
| `Super+number` / `Super+Alt+number` | Switch and briefly reveal Polybar if hidden. |
| `Ctrl+Alt+number` | Switch without a peek. |
| `Super+Shift+number-row` | Move focused window, follow, and peek. Uses keycodes regardless of keyboard layout. |
| `Super+Alt+H/L` | Previous/next existing workspace and peek. |
| `Super+Ctrl+H/L` | Previous/next number, including empty workspaces, and peek. Stops at 1/10 without peeking. |
| `Super+Shift+H/L` | Move to previous/next number, follow, and peek; wraps 1↔10. |

`workspace-action.sh` handles switching/moving; `move-to-workspace.sh` validates
moves. On either Polybar, wheel up/down selects the previous/next number across
all `1–10`, including empty workspaces, and wraps. Scrolling preserves the
[top-edge pointer hold](#top-edge-peek). `mouse_warping none` keeps the pointer
stationary across outputs, including keyboard switches.

Workspaces `1–2` use `primary` (the laptop); `3–10` use `nonprimary` (external).
With no active external output, all ten remain available on the laptop and
accept moved windows. Output keywords avoid hardware-specific connector names.

XFCE's conflicting `Ctrl+Super+L` and `Super+R` custom shortcuts are removed;
its default `Ctrl+Alt+L` lock and `Alt+F2` appfinder remain available.

### Kill Workspace Mode

`Super+X` runs `kill-workspace-mode.sh open`, revealing Polybar and recording
its previous visibility.

| Binding | Action |
| --- | --- |
| `1` ... `0` | Close all windows on workspace `1–10`; exit, leaving the bar as it is. |
| `Shift+K` | Close all windows everywhere, exit, and restore prior bar visibility. |
| `Return` / `Escape` | Abort and restore prior bar visibility. |

`kill-all-windows.sh` implements `Shift+K`. A transient peek counts as hidden;
an already persistent bar stays visible on abort/global close. Each `open`
rewrites the restore marker, so an earlier number-key exit cannot leave stale
visibility state for the next invocation.

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
| `Super+M` | Toggle the `_desktop` workspace. |

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
`i3-titles.state` and `i3-focus-history`. Debug output goes to
`${XDG_STATE_HOME:-$HOME/.local/state}/i3/snap.log`, trimmed above about 200 KB
to the newest 500 lines. See [Runtime and State Files](#runtime-and-state-files).

## Focus History

`focus-tracker.sh` subscribes to focus events and writes current/previous
container IDs as two lines in `$XDG_RUNTIME_DIR/i3-focus-history`.
`focus-prev.sh` (`Super+Tab`) focuses the second ID, toggling between the two
most recent windows. The watcher locks against duplicates and reconnects on
subscription loss.

## Autotiling Integration

`~/.local/bin/autotiling` starts through i3 autostart without a depth limit;
[overflow handling](#overflow-watcher) controls capacity. The shared
`apply_autotiling_split` in `_snap-common.sh` follows the same policy after
snap fallbacks and tiled unsnaps: vertical for taller containers, horizontal
for wider/square ones. Floating/fullscreen windows and stacked/tabbed parents
are skipped.

## Overflow Watcher

`overflow-watcher.py` is a Python `i3ipc` listener. A newly opened or manually
moved window smaller than one quarter of its workspace is handed onward,
searching numbers upward and wrapping `10→1`:

1. First occupied workspace with room.
2. Otherwise first empty workspace.
3. Otherwise next number.

Capacity uses the destination's focus chain; stacked/tabbed insertion parents
always have room. Same-workspace rearrangements, floating/fullscreen windows,
scratchpad (`-1`), and the watcher's own recent moves are excluded.

Moves are issued from the source before following: focusing the destination
first can make an i3 criteria-matched move silently no-op. Each relocation
requests a transient Polybar peek.

| Option | Effect/default |
| --- | --- |
| `-f`, `--fraction` | Minimum workspace area share, `0.25`. |
| `--no-follow` | Keep focus at the source. |
| `-d`, `--debug` | Decisions on stderr. |
| `I3_OVERFLOW_PEEK` | Override the peek helper; required for isolation in nested tests because Polybar IPC is not display-scoped. |

## Tests

`tests/run-fast.sh` runs the quick checks, Bash syntax, optional ShellCheck,
and `i3 -C`, using `/usr/bin/python3` for Python. From chezmoi source state it
maps `executable_` filenames into a temporary applied tree, testing edits
without touching live config; it also runs directly from `~/.config`.

| Test | Covers |
| --- | --- |
| `run-fast.sh` | All fast checks, source-state mapping, syntax, lint, and i3 config parsing. |
| `test-overflow-watcher.py` | Pure functions of `overflow-watcher.py`; runs in milliseconds. |
| `test-overflow-live.py` | Drives a throwaway Xephyr i3 session through every overflow rule on one and two screens. Needs `Xephyr`, `xterm`, `autotiling`; takes minutes. |
| `test-config-consistency.py` | Safe unbounded autotiling restarts, bar-nav arrays/twins, current and safe power commands, shared restore helpers, and system-Python entrypoints. |
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
| `test-tile-snap.sh` | Region geometry for all nine snaps including odd-sized workspaces, Polybar inset arithmetic, pseudo-output clamping, size-hint convergence, the `_presnap_`/`_pretiling_` mark protocol, unsnap, and the per-window lock. |
| `test-snap-watcher.sh` | Auto-fill region choice, splitting the largest occupant to make room, the fallback to tiling when nothing can be split, and rebalancing survivors after a snapped window closes. |
| `test-zen-url-state.py` | Session-store parsing for both Zen and Firefox layouts, profile discovery and dedup, i3 tree walking, window-to-page title matching, the gates that keep a headless save out of the live address-bar capture, and its focus checks. |
| `test-window-mode.sh` | Window mode's show-on-entry and restore-prior-Polybar-state contract. |
| `test-session-reload.sh` | Service refresh, changed-dunstrc handling, Picom `SIGUSR1`, and single success/partial-failure toast coordination. |
| `../../polybar/tests/test-launch.sh` | Multi-monitor launch, tray ordering, lock-fd closure, hung-bar kill escalation, log defaults and filename safety, and rotation. |
| `../../polybar/tests/test-confirm-poweroff.sh` | Explicit confirmation and safe cancellation/timeout behavior for every prompt backend, including the no-backend path. |

The live test never touches the running session:

```sh
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

`move-to-workspace.sh` accepts `1–10`, exits `2` for invalid numbers, and
follows successful moves. `workspace-action.sh` supplies the relative wrapping
for `Super+Shift+H/L`; shifted number-row bindings select exact destinations.
The [output policy](#workspaces) places `3–10` externally when connected.
The overflow watcher may forward a moved window again if it occupies less than
a quarter of its destination.

## Show Desktop

`show-desktop.sh` (`Super+M`) switches to the empty `_desktop` workspace;
pressing it there runs `workspace back_and_forth` to return. Windows are not
minimized.

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

B/C wrappers set `I3_RESURRECT_STATE_DIR` and `I3_RESURRECT_META_DIR`, then exec
the main scripts. All profiles share a nonblocking lock per X display in
`${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`: concurrent operations report busy and
exit rather than queue. `--check` only inspects dependencies/files; other
failures notify with their reason.

### Save Script

`i3-resurrect-save-all.sh` saves every active workspace from `get_workspaces`.
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
`focused-workspace.txt`, `zathura-pages.json`, `zen-pages.json`,
`ghostty-sessions.json`, and `labroute.txt`. The profile metadata directory's
`snapshot.json` selects current and previous generations.

Save takes the operation lock and a restrictive umask, captures one i3 tree
for identities/application metadata, records route state, and runs
`i3-resurrect save` per workspace. Window changes other than titles abort the
save; retry once the desktop settles. It normalizes layouts, ensures Zen
programs exist for placeholders, stabilizes Helium commands, and inserts
captured URLs, PDF pages, and per-window Ghostty launch state.

After validating all layouts, program lists, and present application metadata,
it flushes the generation and atomically publishes the manifest. Failed or
interrupted saves preserve the old selection. The first successful save can
archive a valid legacy flat profile as the previous generation; original files
stay intact and invalid legacy data is never offered for recovery.

Published generations are immutable. Each save keeps only the current and
previous generations, removing older ones and interrupted-save leftovers. A
notification reports the saved workspace count.

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

`i3-resurrect-restore-all.sh` resolves and validates the saved workspace list.
State/metadata paths use the [save defaults](#save-script).

| Setting | Default |
| --- | --- |
| `I3_RESURRECT_LAYOUT_DELAY` | `0.25` seconds. |
| `I3_RESURRECT_WAIT_ATTEMPTS` / `I3_RESURRECT_POLL_INTERVAL` | `48` attempts / `0.25` seconds. |
| `I3_LAPTOP_OUTPUT` | `eDP`. |
| `I3_RESURRECT_EXTERNAL_WORKSPACES` | `3 4 5 6 7 8 9 10`. |
| `I3_RESURRECT_REMOTE_HELPERS` | `~/.zsh/rc.d/50-remote.zsh`. |
| `I3_RESURRECT_LABROUTE_TIMEOUT` | `45` seconds. |

`--check` validates dependencies/helpers, the complete workspace list, referenced
layout/program JSON, filename collisions, focused workspace, route state, and
present application metadata without changing windows, routing, or Polybar.
More than ten nonempty saved workspaces is rejected. Legacy flat data is used
only when no manifest exists; an invalid manifest never silently falls back.

`--previous` selects the prior generation; B/C wrappers accept both options:

```sh
~/.config/i3/i3-resurrect-restore-all.sh --previous --check
~/.config/i3/i3-resurrect-restore-all.sh --previous
```

Restore takes the shared lock, resolves one snapshot, validates it, then:

1. If `labroute.txt` is `on`, runs `labroute on` through the remote helpers.
   Failure/timeout aborts before touching windows or Polybar; restore never
   turns the route off.
2. Hides a visible bar. Maps nonempty saved workspaces in number order to empty
   slots `1–10`, starting at `1`. Any tiled/floating window reserves a live
   slot; scratchpad and workspaces outside `1–10` are left alone.
3. If empty slots are insufficient, fills them first, then opens the rest
   alongside existing windows in occupied slots, lowest first. No window is
   closed; capacity counts workspaces, not windows.
4. Builds temporary renamed layout/program copies, preserving the snapshot.
   Commands are shell-quoted; unsafe working directories become `$HOME`.
   Swallow titles are dropped: apps such as Zathura set theirs after mapping.
   Rechecks each empty destination; a newly occupied slot is skipped and
   reported.
5. Switches to each destination, moves `3–10` to an active external output when
   available, restores layout (`append_layout` on shared slots), waits, and
   launches programs. Checks command results, workspace existence, swallowed
   placeholders, expected window count, and Ghostty's unique instances,
   ignoring windows that were already there. A missing workspace is a failure.
6. Rechecks successes after all restores, then focuses the mapped saved focused
   workspace if it contained saved windows. Restores/raises the bar on exit
   if it was previously visible.
7. Writes `last-restore.json`: snapshot, source/destination mapping, shared
   slots, status/reason per workspace, and session retry guidance. The result
   notification lists mappings, shared slots, and failures.

Terminal launches report `Remote attach requested (unverified)`, not confirmed
remote login/attachment. Unlaunched sessions and failed-workspace sessions
appear under `Reattach by hand`.

Example: live windows on `1,4` and saved workspaces `1,2,3,4,5` map to
`2,3,5,6,7`, preserving both live workspaces. Nine saved nonempty workspaces
map to `2,3,5,6,7,8,9,10,1`, sharing only live workspace `1`. This applies
to all three profiles.

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
cat "$meta/workspaces.txt"                 # which workspaces will restore
cat "$meta/focused-workspace.txt"
jq . "$meta/zathura-pages.json"            # captured PDF pages
jq . "$meta/zen-pages.json"                # captured browser URLs
jq . "$meta/ghostty-sessions.json"         # Ghostty dirs and sessions
cat "$meta/labroute.txt"                   # route at save time
jq -r '.[].command | if type=="array" then join(" ") else . end' \
   "$state/workspace_7_programs.json"      # what workspace 7 relaunches
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
- Restarts `focus-tracker.sh`, `snap-watcher.sh`, `kakaotalk-float-watcher.sh`,
  `randr-hotplug.sh`, `usb-hotplug.sh`, `super-polybar-listener.py`,
  `~/.local/bin/autotiling`, `overflow-watcher.py`, and `top-edge-peek.py`.
- Starts missing `xss-lock --transfer-sleep-lock -- lock.sh` and
  `/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1` (guarded by
  the `polkit-gnome` process).
- Runs `~/.local/bin/disable-trackpoint-middle-click` under
  `/tmp/disable-trackpoint-middle-click.lock` and `~/.local/bin/touchpad apply`.

Watchers use runtime locks against duplicates. `display-setup.sh` arranges
outputs, asks `dunst-start.sh` to restart dunst only when its laptop/primary
monitor index changes, refreshes wallpaper, and launches the per-output bars.

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
`_toast-common.sh` (notices), and `_resurrect-common.sh` (operation lock,
dependencies, metadata). `i3-resurrect-state.py` validates/publishes snapshots,
pairs browser state, checks readiness, and reports sessions. Profile B/C use
`i3-resurrect-{save,restore}-all-{b,c}.sh`; their `resurrect*` data stays local.

Runtime files below use `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`:

| Files | Purpose |
| --- | --- |
| `i3-titles.state`, `i3-focus-history` | Decorations and current/previous focus. |
| `i3-focus-tracker.lock`, `i3-snap-watcher.lock`, `i3-kakaotalk-float-watcher.lock`, `i3-randr-hotplug.lock`, `i3-usb-hotplug.lock` | Watcher singleton locks. |
| `i3-resurrect-<display-hash>.lock` | Shared save/restore operation. |
| `i3-polybar-toggle.lock`, `i3-polybar-peek-worker.lock` | Visibility/peek serialization. |
| `i3-polybar-peek.owner`, `i3-polybar-peek.trigger`, `i3-polybar-peek.hold` | Peek ownership, deadline, holder PID. |
| `i3-super-polybar-listener.lock`, `i3-top-edge-peek.lock` | Gesture watcher locks. |
| `i3-polybar-nav.idx`, `i3-polybar-nav.restore-hidden` | Keyboard cursor and prior bar visibility. |
| `i3-polybar-nav.marker`, `i3-polybar-nav.marker.lock` | Tray highlight rectangle and painter lock. |
| `i3-window-mode.restore-hidden` | Window-mode prior visibility. |
| `i3-reload-toast` | First-login versus subsequent-reload toast stamp. |
| `i3-workspace-cycle.lock`, `tile-snap-<con_id>.lock` | Scroll and per-window snap serialization. |

Persistent logs: `${XDG_STATE_HOME:-$HOME/.local/state}/i3/snap.log` and
`${XDG_STATE_HOME:-$HOME/.local/state}/polybar/polybar-<output>.log`.
Trackpoint setup uses `/tmp/disable-trackpoint-middle-click.lock`.
Snapshot layouts/programs/application metadata live in `resurrect{,-b,-c}`;
manifests, `last-restore.json`, and original legacy metadata in
`resurrect-meta{,-b,-c}`. `tests/` contains standalone checks.

## Maintenance Notes

- Keep `default_border pixel 1` in `config` aligned with `NEW="pixel 1"` in
  `toggle-titles.sh`.
- Update `I3_LAPTOP_OUTPUT` for a different laptop connector. Keep workspace
  output assignments and `I3_RESURRECT_EXTERNAL_WORKSPACES` aligned; if the
  `1–10` range changes, update `MAX_WS` in `overflow-watcher.py`, workspace
  bindings, and `workspace-action.sh` arithmetic/validation.
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

# Replace the running overflow watcher with a foreground debug instance
pkill -f overflow-watcher.py
~/.config/i3/overflow-watcher.py --debug
```

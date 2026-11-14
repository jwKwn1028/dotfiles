# i3 Configuration Manual

Controls and maintenance for i3/X11; see also [Polybar](../polybar/docs.md),
[Ghostty](../ghostty/docs.md), and the
[GTK theme](../../dot_themes/Ghostty-TokyoNight/README.md) (Ghostty-TokyoNight
and Papirus-Dark via `xfsettingsd`). Super is `Mod4`; Ctrl/Caps are swapped.
Focus follows the mouse without wrapping or warping, borders are `pixel 1`,
and activation uses i3's `smart` policy.

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

Copilot (`Super+Shift+F23`, keycode `201`, on release) toggles one floating
Ghostty on the current monitor, sized while hidden and then shown centered.
Hiding keeps its size and commands; closing starts fresh. It skips the Zsh
banner, snapshots, and focus history, and is shared across groups.

### Window Management

| Binding | Action |
| --- | --- |
| `Super+Shift+Q` / `Alt+F4` | Close the focused window. |
| `Ctrl+Super+Shift+Q` / `Ctrl+Alt+F4` | Kill the focused window's client. |
| `Ctrl+Q` | Close apps listed in `QUIT_CLASSES` (`quit-key.py`). |
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

Moves are refused while outputs show different groups or the group is restoring.

### i3 Control

| Binding | Action |
| --- | --- |
| `Super+Shift+C` | Reload i3 config. |
| `Super+Shift+I` | Validate and restart i3, then [refresh the session](#autostart-and-dependencies). |
| `Super+Shift+E` | Confirm exit through `i3-nagbar`. |
| `Super+Escape` (release) | Lock with `lock.sh`. |

### Workspaces

Number keys address slots `1–10` (`0` is `10`) of the selected
[group](#workspace-groups).

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

Slot navigation and moves peek too. Boundary stops and clicks on the current
tab or slot do nothing. XFCE's `Ctrl+Super+L` and `Super+R` shortcuts are removed.

### Kill Workspace Mode

`Super+X` captures the group and bar visibility, then shows
`kill workspace (K: group, A: all)`.

| Binding | Action |
| --- | --- |
| `1` ... `0` | Close every window on that slot; exit, leaving the bar as is. |
| `Shift+K` / `Shift+A` | Close every window in the group / **all** groups; exit and restore the bar. |
| `Return` / `Escape` | Abort and restore the bar. |

Slots match exactly (`1` never hits `10`); group kills spare scratchpad and
unmanaged windows. Switching groups cancels the mode, and a peek counts as
hidden when the bar is restored.

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

Each group owns workspaces `index × 10 + slot`, with stable zero-based indices
from `workspace-groups.json`: A is 1–10, B 11–20, C 21–30. Polybar shows local
slots (B's `3` is `13`; `13: project` keeps that identity). Duplicate numbers
block group actions. Other workspaces, `_desktop`, and the scratchpad are
unmanaged; empty slots are created on demand.

Switching restores each monitor's slot and the focused output, closes active
modes, and verifies the result. Only `Super+Shift+K/J` moves a window between
groups (B:4 → C:4), checking capacity and clearing stale restore and overflow
decisions.

### Focus and Urgency

Window selection is global and never moves windows. History skips controller
transitions and Copilot. Activation in a hidden group marks it urgent (`C!`);
identified background arrivals keep the current view. Other external focus
changes reconcile both outputs.

### Displays

Slots 1–2 go to the primary output and 3–10 to an external one; one monitor
shows all. The controller applies this on switch, reload, hotplug, and display
setup, resetting a remembered slot that breaks the rule, or an empty one, to
primary 1 / external 3. Disconnects keep the last focused slot and external
memory; windows keep their group.

### Session Controller

`workspace-groups.py start` replaces the session's controller and old watchers.
It owns `autotiling`, `snap-watcher.sh`, and `overflow-watcher.py`, serializes
group operations, reconnects after i3 restarts, and stops 10 s after i3 exits.
Failed IPC commits nothing; while groups are unavailable, placement pauses and
Polybar shows `groups unavailable`.

| File | Responsibility |
| --- | --- |
| `workspace_groups.py` | Group identities, session paths and client, snapshot filtering. |
| `group_controller.py` | Views, navigation, moves, focus, kills, overflow, workers. |
| `group_restore.py` | Placement leases, launch identity, placeholders, late arrivals. |
| `workspace-groups.py` | CLI, daemon, Polybar subscription, Rofi window list. |
| `workspace-action.sh` | Fast shell client for bindings and scripts; falls back to the CLI. |

State, socket, locks, and `controller.log` live in
`$XDG_RUNTIME_DIR/i3-groups-<hash>/`.

To add a group, give it an unused index in `workspace-groups.json` (e.g.
`"D": 3`), then add its shortcut and `workspace 31`…`40` output assignments in
`config`. List order sets tab order; renumbering an existing group is refused.

## XFWM-Style Snap System

| Binding | Region |
| --- | --- |
| `Super+A/D` | Left/right half. |
| `Super+W/S` | Upper/lower half. |
| `Super+Q/E/Z/C` | Upper-left/upper-right/lower-left/lower-right quarter. |
| `Super+U` (release) | Unsnap to the original floating geometry or tiling position. |

`tile-snap.sh REGION [CON_ID]` also takes `full` and `unsnap`, and accounts for
output geometry, bars, borders, and size hints. `_snap_*` marks the region;
`_presnap_*`/`_pretiling_*` keep the original geometry and anchors across
repeated snaps. `snap-watcher.sh` fills free space, splits occupants, and
expands survivors; `resnap.sh` refreshes after bar or title changes.
Autotiling splits tall containers vertically and wide ones horizontally,
skipping floating, fullscreen, stacked, and tabbed layouts.

## Overflow Watcher

A new or moved tiled window smaller than a quarter of its workspace moves, once,
within its group, searching upward with 10→1 wrapping: first an occupied slot
predicted to have room, else the first empty slot, else it stays and the full
group is logged. Floating, fullscreen, scratchpad, restored, and rearranged
windows are skipped; background moves keep focus.

Options: `--fraction`/`-f` (`0.25`), `--no-follow`, `--debug`/`-d`.

## Polybar Integration

`launch.sh` starts hidden bars on every output with one tray on the internal or
primary output; `display-setup.sh` owns relaunches. Keep `screenchange-reload`
and `wm-restack` off, and keep the launcher lock out of detached children
(`9>&-`). The `groups` module shows `A [B] C | 1 2 [3] 7 10`, with `!` on urgent
inactive groups; `internal/i3` shows mode labels.

One i3-started volume watcher updates both modules without idle polling.
See [Polybar controls](../polybar/docs.md#pointer-actions) for volume limits.

Workspace keys and Super taps peek a hidden bar for `I3_POLYBAR_PEEK_MS`
(200 ms), extended by repeats. Holding Super alone keeps it until release;
`I3_SUPER_HOLD_MS` sets the threshold. Peeks never resnap, and toggles cancel
them.

### Bar Mode

`Super+B` opens a keyboard cursor over date, audio, battery, Wi-Fi, Bluetooth,
and power: `h/l` or arrows select, `j/k` scroll (1%), `Return`/`Shift+Return`
left/right click, `Escape` exits. Menu actions exit, toggles stay, and exit
restores prior visibility. Power entries need mouse confirmation.
`nm-applet` docks before `blueman-tray` to match the cursor order.

### Top-Edge Peek

The pointer within 2 px of a monitor's top reveals a hidden bar until it moves
40 px away (`I3_POLYBAR_EDGE_ENTER_PX`, `I3_POLYBAR_EDGE_LEAVE_PX`, polled every
`I3_POLYBAR_EDGE_POLL_MS`, 25 ms). Scrolling keeps the hold; a visible
fullscreen window suppresses it until the pointer leaves.

Held peeks check their holder every 50 ms without spawning child processes.

## Monitors, Wallpaper, and USB

`display-setup.sh` puts the first external output at `0x0` with the laptop to
its right, or turns the panel off when the lid is closed. The laptop is
`I3_LAPTOP_OUTPUT` (`eDP`) if connected, else the first `eDP*`/`LVDS*`; with no
panel the layout is left alone. It then reconciles workspaces, dunst,
wallpaper (`~/.wallpaper-laptop.png`, `~/.wallpaper-external.png`), and bars.
`I3_DISPLAY_SETUP_DELAY` is 1 s at login and 0 on later reloads.

`randr-hotplug.sh` debounces connections for `I3_RANDR_HOTPLUG_QUIET` (0.7 s)
and toasts them; lid changes apply silently after 0.15 s.

`usb-hotplug.sh` toasts coalesced USB/Type-C changes after a quiet initial
scan. Inspect with `--dump`; set `I3_USB_TYPEC_BUSES`, `I3_USB_HOTPLUG_QUIET`
(0.7), `I3_USB_TYPEC_WINDOW` (3 s), `I3_USB_TOAST_DETAIL=full|compact`, and
`I3_TOAST_WRAP`.

## Floating Rules

Settings, admin, and input utilities float centered; patterns live in `config`.
KakaoTalk (`kakaotalk.exe`) floats at `420×760`, and its watcher undoes Wine's
return to tiling.

## i3-Resurrect Save and Restore

Profiles store one group (the selected one, or `--group=B`) and restore into
any group.

| Profile | Save (release) | Restore | State / metadata |
| --- | --- | --- | --- |
| Main | `Super+Ctrl+A` | `Super+Ctrl+R` | `resurrect` / `resurrect-meta` |
| B | `Super+Ctrl+B` | `Super+Ctrl+S` | `resurrect-b` / `resurrect-meta-b` |
| C | `Super+Ctrl+C` | `Super+Ctrl+T` | `resurrect-c` / `resurrect-meta-c` |
| All groups | `Super+Ctrl+Y` | `Super+Ctrl+P` | `resurrect-session` / `resurrect-meta-session` |

All-groups save publishes only if every group succeeds; restore returns each to
its group and view. Restores fill empty slots first and never move existing,
scratchpad, or unmanaged windows. `i3-resurrect-session.py save|restore` takes
`--check` (no desktop changes) and `restore --previous`. Profiles share a lock
per display. Snapshots hold local paths, URLs, and session names, so
`resurrect*` stays gitignored.

**Saving** (`i3-resurrect-save-all.sh`) captures the group without moving
windows and normalizes it to slots 1–10. Empty groups or failures keep the old
snapshot; `snapshot.json` is validated, flushed, and published atomically, and
`group-format.json` versions the slot format.

| Application | State and limits |
| --- | --- |
| Zathura | File and page; unreadable state launches plain. |
| Zen/Helium | Address-bar URL (clipboard and focus restored), else Zen/Firefox session files; ambiguous windows launch plain. |
| Helium | Transient paths resolve via `helium.desktop`, then the newest AppImage. |
| Ghostty | Working directory and first `hpc`/`hpcz` session per window; tabs and splits are not rebuilt. |

Set `ZEN_LIVE_URL_CAPTURE=0` to skip live capture; `ZEN_PROFILE_ROOTS` and
`I3_RESURRECT_PROC_ROOT` override lookup roots. Remote attaches are requested,
not verified; failures say `Reattach by hand`.

**Restoring** (`i3-resurrect-restore-all.sh [--check] [--previous]`, also via
the B/C wrappers) validates temporary copies before touching the desktop:

1. Plan the lowest empty slots, then occupied ones.
2. Build launch tokens and placeholders, rejecting shell-string, `gtk-launch`,
   `xdg-open`, and `dbus-send` launches; mismatched layouts restore programs
   only.
3. Restore `labroute on` if recorded; failure aborts first. It is never turned off.
4. Reserve placement, select the group, pause tiling and snap workers, hide
   bars, and route only provably owned windows.
5. Verify windows, restore focus, clear empty placeholders, resume workers,
   restore bars, and write `last-restore.json`.

Switching groups cancels further launches; issued ones keep their destination
for at least two minutes or while the launcher lives. Ambiguous arrivals are
reported, not moved. Example: live A slots `1,4` plus saved `1–5` restore into
`2,3,5,6,7`; into an empty B they use `11–15`.

Defaults: `I3_RESURRECT_LAYOUT_DELAY=0.25`, `I3_RESURRECT_WAIT_ATTEMPTS=48`,
`I3_RESURRECT_POLL_INTERVAL=0.25`, `I3_RESURRECT_LABROUTE_TIMEOUT=45`,
`I3_RESURRECT_REMOTE_HELPERS=~/.zsh/rc.d/50-remote.zsh`; `I3_RESURRECT_STATE_DIR`
and `I3_RESURRECT_META_DIR` override profile paths.

## Autostart and Dependencies

Startup runs XFCE settings and power, keyring, Polkit, Picom, network and
Bluetooth applets, xss-lock, input setup, and watchers. On every reload
`session-reload.sh` refreshes changed user units, changed dunst config, Picom,
displays, wallpaper, and bars, with one result toast. `lock.sh` prefers
i3lock-color over i3lock.

Packages are in `.chezmoidata/packages.toml`: system Python with
`python3-i3ipc`, `python3-xlib`, `python3-lz4`; pipx autotiling; `xrandr`,
Polybar, X11 tools, `feh`, `jq`, and `flock`.

## Runtime and State Files

Under `$XDG_RUNTIME_DIR`: `i3-groups-<hash>/` (groups), `i3-polybar-*` (bars),
`i3-*-mode.restore-hidden` (bar visibility), `i3-titles.state` (borders),
`tile-snap-<id>.lock` (snaps). Logs, rotated above ~200 KB:
`~/.local/state/i3/snap.log`, `~/.local/state/polybar/polybar-<output>.log`,
and the controller's `controller.log`.

## Maintenance

- Keep `default_border` and `toggle-titles.sh` aligned, and change snap mark
  formats in every snap helper at once.
- Keep group indices, output policy, config assignments, and shortcuts
  consistent; use `workspace_groups.py` rather than local offsets.
- Pair Python dependency changes with the package manifest; browser or remote
  launch changes also affect snapshots and `SESSION_PATTERNS`.
- Review a scoped `chezmoi diff` and `apply --dry-run --force` before applying.

```sh
~/.config/i3/workspace-groups.py status | jq .
less "$(~/.config/i3/workspace-groups.py path)/controller.log"
~/.config/i3/workspace-groups.py start
~/.config/i3/resnap.sh
~/.config/i3/i3-resurrect-restore-all.sh --check --group=B
jq . ~/.config/i3/resurrect-meta/last-restore.json
```

## Tests

`bash dot_config/i3/tests/executable_run-fast.sh` (or
`~/.config/i3/tests/run-fast.sh` once applied) runs syntax, ShellCheck, config
parsing, and the unit tests in a temporary tree. Live tests need Xephyr and
xterm (overflow also needs autotiling); stub `I3_GROUP_PEEK` in nested tests,
since Polybar IPC is not display-scoped.

```sh
~/.config/i3/tests/test-workspace-groups-live.py [scratch-only|session-only]
~/.config/i3/tests/test-overflow-live.py
```

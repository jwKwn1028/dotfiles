# i3 Configuration Manual

This manual documents the i3 setup in `~/.config/i3`. It covers the main
`config`, all helper scripts in this directory, and the saved i3-resurrect
state directories present at the time this manual was written.

## Overview

This is a pure i3 session that keeps a small set of XFCE services for desktop
integration. `xfce4-panel` is intentionally not started; Polybar is the status
bar.

The config is built around these major features:

- Super/Mod4-driven i3 window management.
- XFWM-style snap-to-region behavior implemented with custom scripts.
- Automatic snap fill/rebalance for workspaces that already contain snapped
  windows.
- A two-window Super+Tab focus toggle backed by a focus-history watcher.
- Three i3-resurrect save/restore profiles.
- Browser/PDF session enhancements for Zen Browser, Helium, Zathura, and
  Sioyek-based workspaces.
- Polybar show/hide integration that resizes snapped windows after the bar
  changes.
- Global title-bar toggling that also resizes snapped windows.
- Laptop/external monitor placement policy.
- Floating rules for system dialogs, settings tools, input-method tools,
  update tools, and KakaoTalk/Wine windows.
- Show-desktop behavior via a dedicated `_desktop` workspace.

## Core Session Settings

The modifier key is `Mod4`, usually the Super/Windows key.

General behavior:

- Font: `pango:DejaVu Sans 10`.
- Focus does not follow the mouse.
- Focus wrapping is disabled.
- `workspace_auto_back_and_forth` is enabled.
- Default borders are `pixel 1` for both tiled and floating windows.
- Edge borders are hidden with `hide_edge_borders smart`.
- Title bars are off by default and can be toggled at runtime.

Theme colors use a Tokyo Night style palette:

- Focused border/background/text/indicator/child border: `#c0caf5`,
  `#1a1b26`, `#c0caf5`, `#c0caf5`, `#c0caf5`.
- Unfocused and focused-inactive windows use `#16161e` with text `#565f89`.

## Keybinding Reference

### Launchers

| Binding | Action |
| --- | --- |
| `Super+Return` | Launch Ghostty with `LIBGL_ALWAYS_SOFTWARE=1`. |
| `Super+Shift+Return` | Launch `xfce4-terminal`. |
| `Super+Space` | Open Rofi drun with `XDG_CURRENT_DESKTOP=XFCE:i3` and the `spotlight` theme. |
| `Super+Tab` | Focus the previously focused window via `focus-prev.sh`. |
| `Super+Shift+Tab` | Open Rofi window switcher. |
| `Super+T` | Open Thunar. |
| `Super+P` | Open minimal XFCE display settings. |
| `XF86Display` | Open minimal XFCE display settings. |
| `Super+Shift+P` | Run `display-setup.sh`. |
| `Ctrl+Super+Z` | Launch Zed. |
| `Ctrl+Super+L` | Lock the session with `xflock4`. |
| `Ctrl+Alt+P` | Launch Super Productivity Flatpak. |
| `Ctrl+Super+H` | Launch the Helium AppImage. |
| `Ctrl+Shift+Z` | Launch Zen Browser Flatpak. |
| `Ctrl+Alt+Escape` on release | Run `xkill`. |
| `Ctrl+Shift+Escape` | Launch `xfce4-taskmanager`. |

`Ctrl+Alt+T` is intentionally left for XFCE, and `Super+D` is used for snap
right instead of application launch.

### Window Management

| Binding | Action |
| --- | --- |
| `Super+Shift+Q` | Kill focused window. |
| `Alt+F4` | Kill focused window. |
| `Super+H/J/K/L` | Focus left/down/up/right. |
| `Super+Arrow keys` | Focus left/down/up/right. |
| `Super+Shift+H/J/K/L` | Move window left/down/up/right. |
| `Super+Shift+Arrow keys` | Move window left/down/up/right. |
| `Super+Shift+M` | Show a scratchpad window. |
| `Super+Ctrl+M` | Move focused window to scratchpad. |
| `Super+B` | Set horizontal split. |
| `Super+V` | Set vertical split. |
| `Super+Shift+Space` | Toggle floating mode. |
| `Super+X` | Toggle fullscreen. |
| `Ctrl+Super+Right` | Move container to output on the right. |
| `Ctrl+Super+Left` | Move container to output on the left. |

### Resize Mode

Enter resize mode with `Super+R`.

Inside resize mode:

| Binding | Action |
| --- | --- |
| `H` | Shrink width by 10 px or 10 ppt. |
| `J` | Grow height by 10 px or 10 ppt. |
| `K` | Shrink height by 10 px or 10 ppt. |
| `L` | Grow width by 10 px or 10 ppt. |
| `Return` | Return to default mode. |
| `Escape` | Return to default mode. |

### i3 Control

| Binding | Action |
| --- | --- |
| `Super+Shift+C` | Reload i3 config. |
| `Super+Shift+R` | Restart i3. |
| `Super+Shift+E` | Show an `i3-nagbar` confirmation, then exit i3 if confirmed. |

### Workspaces

There are numbered workspaces `1` through `10`.

| Binding | Action |
| --- | --- |
| `Super+1` ... `Super+0` | Switch to workspace `1` ... `10`. |
| `Ctrl+Alt+1` ... `Ctrl+Alt+0` | Also switch to workspace `1` ... `10`. |
| `Super+Shift+number-row` | Move focused window to workspace and follow it. |
| `Super+Alt+H` | Previous workspace. |
| `Super+Alt+L` | Next workspace. |

Shifted number-row moves are implemented with keycodes so keyboard layout does
not change which workspace receives the window. These moves call
`move-to-workspace.sh`.

Workspace output policy:

- Workspaces `1` to `6` are assigned to the primary output.
- Workspaces `7` to `10` are assigned to `HDMI-A-0`, `DP-1`, `DP-2`, or a
  non-primary output.
- `move-to-workspace.sh` refuses moves to workspaces `7` to `10` unless an
  external output is active.

### Kill Workspace Mode

Enter the mode with `Super+N`.

If Polybar is hidden, `show-polybar-or-kill-workspace.sh` shows it first, then
enters the mode.

Inside kill-workspace mode:

| Binding | Action |
| --- | --- |
| `1` ... `0` | Kill all windows on workspace `1` ... `10`. |
| `Shift+K` | Kill all windows everywhere. |
| `Return` | Return to default mode. |
| `Escape` | Return to default mode. |

### Media, Brightness, and Screenshots

| Binding | Action |
| --- | --- |
| `XF86AudioRaiseVolume` | Increase default sink volume by 5 percent. |
| `XF86AudioLowerVolume` | Decrease default sink volume by 5 percent. |
| `XF86AudioMute` | Toggle default sink mute. |
| `XF86AudioPlay` | Toggle media playback. |
| `XF86AudioNext` | Next media track. |
| `XF86AudioPrev` | Previous media track. |
| `XF86MonBrightnessUp` | Increase brightness by 5 percent. |
| `XF86MonBrightnessDown` | Decrease brightness by 5 percent. |
| `Print` | Launch Flameshot GUI. |
| `Shift+Print` | Launch Flameshot GUI. |
| `Alt+Print` | Launch Flameshot GUI. |
| `Super+Shift+S` | Launch Flameshot GUI. |

### Bar, Title Bars, and Desktop

| Binding | Action |
| --- | --- |
| `Super+Shift+B` | Toggle Polybar visibility and resnap snapped windows. |
| `Super+Shift+T` | Toggle title bars and resnap snapped windows. |
| `Super+M` | Toggle the `_desktop` workspace. |

## XFWM-Style Snap System

The snap feature is implemented by `tile-snap.sh`, `_snap-common.sh`,
`snap-watcher.sh`, and `resnap.sh`.

It is not normal i3 tiling. A snapped window becomes floating, is resized to a
workspace region, and receives an i3 mark such as `_snap_left`.

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

`tile-snap.sh` stores state in i3 marks:

- `_snap_<region>` records the current snap region.
- `_presnap_<x>_<y>_<w>_<h>_<floating>` records the original geometry and
  whether the window was floating before the first snap.
- `_pretiling_<parent>_<layout>_<prev>_<next>` records enough tiling-tree
  context to restore a formerly tiled window near its original position.
- `_snap_parent_<target>`, `_snap_prev_<target>`, and `_snap_next_<target>`
  mark restore anchors for unsnapping tiled windows.

Only the first snap captures pre-snap state. Later resnaps keep the original
restore target intact.

### Geometry Rules

Snaps are calculated from the target window's current workspace and output.

The script:

- Resolves the workspace rectangle from `i3-msg -t get_tree`.
- Cross-checks the real active output from `i3-msg -t get_outputs`.
- Keeps placement inside the active output if i3 exposes stale or oversized
  workspace geometry during monitor changes.
- Detects visible Polybar windows with `xdotool` and `xwininfo`.
- Adds top/bottom insets only when i3 has not already reserved that space.
- Handles odd pixel dimensions without leaving a 1 px gap.
- Uses `pixel 1` or `normal` borders according to the current title-bar state.

Some applications enforce size hints. For those, `tile-snap.sh` retries the
placement up to 10 times and shrinks the request by detected overflow so the
actual window stays inside the target rectangle.

### Unsnap Behavior

`Super+U` restores the snapped window.

If the original window was floating, it returns to its original floating
geometry. If it was tiled, the script tries to restore it to the original tree
slot using stored parent/sibling marks. If the old parent disappeared, it falls
back to nearby anchors. If no pre-snap mark exists, unsnap simply disables
floating and removes snap marks.

After restoring a tiled window, the script calls the shared autotiling split
logic so the restored container has the same split direction policy as the
running autotiling daemon.

### Auto Fill and Rebalance

`snap-watcher.sh` subscribes to i3 window events.

On new windows:

- It applies the current title-bar default to the new window.
- It skips windows that are already floating.
- If the workspace already has snapped windows, it finds the largest free
  snap region and snaps the new window there.
- If no free region remains but a larger snapped region can be split, it
  splits an existing snapped window and gives the new window the other half.
- If it cannot make room, it unsnaps all snapped windows on that workspace and
  lets normal i3 tiling resume.

On close events:

- If a snapped window closes, the watcher expands remaining snapped windows
  into the freed quadrants when possible.
- Expansion prefers larger regions first and avoids overlap with other snapped
  windows.

The watcher uses a runtime lock so only one copy runs, waits briefly during
i3 restarts, and reconnects if the i3 subscription stream ends.

### Resnap

`resnap.sh` finds all windows with `_snap_*` marks and reapplies their snap
region. It is used after Polybar visibility changes and after title-bar changes.

The script runs each window resnap concurrently. `tile-snap.sh` still serializes
per target window with a per-container lock, so repeated key events do not race
on marks.

### Shared Snap Runtime Files

`_snap-common.sh` defines shared paths and helpers:

- Runtime directory: `${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`.
- Title-bar state: `$XDG_RUNTIME_DIR/i3-titles.state`.
- Focus history: `$XDG_RUNTIME_DIR/i3-focus-history`.
- Snap log: `${XDG_STATE_HOME:-$HOME/.local/state}/i3/snap.log`.

The snap log is rotated at about 200 KB by keeping the last 500 lines.

## Focus History

`focus-tracker.sh` runs in the background from i3 autostart.

It subscribes to i3 window focus events and writes two lines to
`$XDG_RUNTIME_DIR/i3-focus-history`:

1. Current focused container ID.
2. Previous focused container ID.

`focus-prev.sh`, bound to `Super+Tab`, reads the second line and focuses that
container. Pressing `Super+Tab` repeatedly toggles between the two most recent
windows.

The tracker uses a runtime lock and reconnects if the i3 event subscription
ends.

## Autotiling Integration

The external daemon `$HOME/.local/bin/autotiling --limit 6` is started
from i3 autostart on every reload/restart.

`_snap-common.sh` also implements `apply_autotiling_split`, a local helper used
after snap fallback operations and tiled unsnaps. It mirrors the daemon's
width/height rule:

- Taller containers get vertical splitting.
- Wider or square containers get horizontal splitting.
- Floating and fullscreen windows are skipped.
- Stacked and tabbed parents are skipped.
- Containers at or beyond the depth limit are skipped.
- The default depth limit is `6`.

This keeps windows restored from the snap system aligned with the same split
policy as normal new tiled windows.

## Title-Bar Toggle

`toggle-titles.sh` toggles title bars for all windows across all workspaces.

State is stored in `$XDG_RUNTIME_DIR/i3-titles.state`:

- `off`: new and existing windows use `border pixel 1`.
- `on`: new and existing windows use `border normal`.

i3 cannot change `default_border` at runtime, so `snap-watcher.sh` applies the
current state to every new window.

`toggle-titles-resnap.sh` runs `toggle-titles.sh`, then `resnap.sh` so snapped
windows fit the new decoration geometry.

## Polybar Integration

Polybar is launched from:

```sh
~/.config/polybar/launch.sh
```

The i3 config starts it after `display-setup.sh` on every reload/restart.

`toggle-polybar-resnap.sh`, bound to `Super+Shift+B`, handles bar visibility:

- Uses `polybar-msg cmd hide` or `polybar-msg cmd show`.
- If showing the bar and IPC is unavailable, relaunches Polybar using the
  launch script.
- Polls the X server through `xdotool` and `xwininfo` until the requested
  visibility is reflected.
- Raises visible Polybar windows so they stay above existing windows.
- Calls `resnap.sh` so snapped windows shrink/grow with the usable screen area.
- Uses a runtime lock to avoid concurrent toggles.

`show-polybar-or-kill-workspace.sh` ensures Polybar is visible before entering
kill-workspace mode.

## Monitor and Wallpaper Setup

`display-setup.sh` controls monitor layout.

Defaults:

- Laptop output: `eDP`.
- Override with `I3_LAPTOP_OUTPUT`.
- Initial delay: `I3_DISPLAY_SETUP_DELAY`, default `1` second.

Behavior:

- Waits for the laptop output to appear, up to about 5 seconds.
- Uses the first connected non-laptop output as the external monitor.
- With an external monitor:
  - External output is placed at `0x0`.
  - Laptop output is primary and placed to the right of the external.
- Without an external monitor:
  - Laptop output is primary at `0x0`.
- Runs `wallpaper.sh` afterward.

`wallpaper.sh` uses `feh` if available:

```sh
feh --no-fehbg --bg-fill "$HOME/.wallpaper-laptop.png" "$HOME/.wallpaper-external.png"
```

## Workspace Movement Guard

`move-to-workspace.sh` is used by `Super+Shift+number-row`.

Rules:

- Workspaces `1` to `6` always accept moved windows.
- Workspaces `7` to `10` accept moved windows only when a non-laptop output is
  connected and active.
- Invalid workspace numbers exit with status `2`.
- Successful moves also switch focus to the destination workspace.

The laptop output defaults to `eDP` and can be overridden with
`I3_LAPTOP_OUTPUT`.

## Show Desktop

`show-desktop.sh` implements show-desktop by switching to a dedicated
workspace named `_desktop`.

Behavior:

- If the current workspace is not `_desktop`, `Super+M` switches to `_desktop`.
- If the current workspace is `_desktop`, `Super+M` uses i3
  `workspace back_and_forth` to return to the previous workspace.

This does not minimize windows. It simply uses an empty workspace as the
desktop view.

## Floating Rules

The config makes utility and dialog-style windows floating and centered.

Explicit classes:

- `Xfce4-power-manager-settings`
- `Nm-connection-editor`
- `Blueman-manager`
- `Blueman-adapters`
- `Pavucontrol`

XFCE settings/tools by class or instance:

- `xfce4-display-settings`
- `xfce4-settings-manager`
- `xfce4-settings-editor`
- `xfce4-appearance-settings`
- `xfce4-mouse-settings`
- `xfce4-keyboard-settings`
- `xfce4-notifyd-config`
- `xfce4-session-settings`
- `thunar-settings`
- XFCE terminal settings by title.

System/admin tools by class or instance:

- `xfce4-taskmanager`
- `system-config-printer`
- `org.gnome.DiskUtility`
- `gnome-disks`
- `gufw`
- `driver-manager`
- `mintsources`
- `mintreport`
- `mintbackup`
- `timeshift`
- `timeshift-gtk`
- `timeshift-launcher`
- `users-admin`
- `time-admin`

Input and locale tools by class or instance:

- `fcitx5-configtool`
- `fcitx-config-gtk3`
- `fcitx5-config-qt`
- `mintlocale`
- `mintlocale-im`
- `im-config`
- `ibus-setup-hangul`

Other desktop utilities by class or instance:

- `light-locker-settings`
- `onboard-settings`
- `mugshot`
- `menulibre`
- `rofi-theme-selector`

Update manager windows:

- Any class or instance matching `mintupdate`.
- Any title matching `update manager`, case-insensitive.
- Korean update-manager title variants are also matched.

KakaoTalk/Wine windows:

- Class `kakaotalk.exe`.
- Instance `kakaotalk.exe`.
- Titles matching `kakaotalk`, case-insensitive.
- Korean KakaoTalk title variants.
- These windows are floated, resized to `420x760`, and centered.

## KakaoTalk Float Watcher

`kakaotalk-float-watcher.sh` keeps KakaoTalk windows floating after Wine remaps
or maximizes them during login.

Behavior:

- Runs under a runtime lock.
- Scans current windows at startup.
- Subscribes to i3 window events and reacts to KakaoTalk-related changes.
- Ignores minimized/hidden KakaoTalk windows.
- For visible KakaoTalk windows, disables fullscreen, enables floating, resizes
  to `420x760`, and centers the window.
- Reconnects if the i3 event stream ends.

## i3-Resurrect Save and Restore

There are three save/restore profiles:

| Profile | Save binding | Restore binding | State directory | Metadata directory |
| --- | --- | --- | --- | --- |
| Main | `Ctrl+Super+A` on release | `Ctrl+Super+R` | `resurrect` | `resurrect-meta` |
| B | `Ctrl+Super+B` on release | `Ctrl+Super+S` | `resurrect-b` | `resurrect-meta-b` |
| C | `Ctrl+Super+C` on release | `Ctrl+Super+T` | `resurrect-c` | `resurrect-meta-c` |

The B and C scripts are thin wrappers that set `I3_RESURRECT_STATE_DIR` and
`I3_RESURRECT_META_DIR`, then exec the main save/restore scripts.

### Save Script

`i3-resurrect-save-all.sh` saves every active workspace listed by
`i3-msg -t get_workspaces`.

Default environment and paths:

- `I3_RESURRECT_STATE_DIR`: `~/.config/i3/resurrect`.
- `I3_RESURRECT_META_DIR`: `~/.config/i3/resurrect-meta`.
- `I3_RESURRECT_SWALLOW`: `class,instance,title`.
- Workspace list: `workspaces.txt`.
- Focused workspace: `focused-workspace.txt`.
- Zathura state: `zathura-pages.json`.
- Zen/Helium URL state: `zen-pages.json`.
- Zen URL helper: `zen-url-state.py`.
- Helium desktop file: `~/.local/share/applications/helium.desktop`.

`--check` verifies that `i3-msg`, `jq`, and `i3-resurrect` are available.

Save behavior:

- Creates state and metadata directories.
- Captures Zathura page state through D-Bus when possible.
- Captures Zen and Helium URL state through `zen-url-state.py`.
- Writes sorted workspace names to `workspaces.txt`.
- Writes the focused workspace to `focused-workspace.txt`.
- Runs `i3-resurrect save` for each workspace.
- Normalizes saved layout JSON after each save.
- Ensures Zen Browser programs exist for Zen layout placeholders.
- Rewrites Helium AppImage commands to stable launch commands.
- Adds captured Zen/Helium URLs back into browser launch commands.
- Adds captured Zathura page numbers back into Zathura launch commands.
- Sends a desktop notification with the saved workspace count.

Layout normalization removes titles from swallows for Ghostty, Zen, and Helium
so restored windows are less likely to miss placeholders because of changed
window titles.

### Zathura Page Capture

The save script:

- Finds Zathura windows in the i3 tree.
- Uses `xprop` to get each window PID.
- Uses `busctl --user` against `org.pwmt.zathura.PID-<pid>`.
- Reads `filename` and zero-based `pagenumber`.
- Stores a one-based page number in metadata.
- Rewrites future Zathura restore commands with `--page=<page>`.

### Zen and Helium URL Capture

`zen-url-state.py` captures current browser pages for Zen and Helium windows.

It uses two strategies:

- Live URL capture, enabled by default:
  - Uses `xdotool` to activate a browser window.
  - Sends `Ctrl+L`, then `Ctrl+C`.
  - Reads the clipboard with `xclip`.
  - Restores the old clipboard and active window afterward.
  - Can be disabled with `ZEN_LIVE_URL_CAPTURE=0`.
- Session-file fallback:
  - Reads Zen/Firefox-style session files under
    `~/.var/app/app.zen_browser.zen/.zen` and `~/.zen`.
  - Can be overridden with `ZEN_PROFILE_ROOTS`.
  - Handles Mozilla `jsonlz4` session files through Python `lz4.block`.

The helper matches i3 browser windows to session pages by normalized title and
browser class. It ignores blank URLs and writes JSON entries containing
workspace, window ID, title, URL, profile, session file, window index, and
browser type.

### Helium Command Stabilization

Helium is a versioned AppImage. i3-resurrect may capture a temporary
`/tmp/.mount_helium...` command from the running process, which will not exist
after reboot.

The save script resolves a stable command by:

- Reading the `Exec=` line from `~/.local/share/applications/helium.desktop`.
- Removing desktop field codes like `%U`.
- Falling back to the newest `~/Applications/helium*.AppImage`.
- Replacing Helium-like saved commands with the stable command.

### Restore Script

`i3-resurrect-restore-all.sh` restores the saved workspace list from metadata.

Default environment and paths:

- `I3_RESURRECT_STATE_DIR`: `~/.config/i3/resurrect`.
- `I3_RESURRECT_META_DIR`: `~/.config/i3/resurrect-meta`.
- `I3_RESURRECT_LAYOUT_DELAY`: `0.25`.
- `I3_RESURRECT_KILL_WAIT_ATTEMPTS`: `40`.
- `I3_RESURRECT_KILL_POLL_INTERVAL`: `0.25`.
- `I3_RESURRECT_WAIT_ATTEMPTS`: `48`.
- `I3_RESURRECT_POLL_INTERVAL`: `0.25`.
- `I3_LAPTOP_OUTPUT`: `eDP`.
- `I3_RESURRECT_EXTERNAL_WORKSPACES`: `7 8 9 10`.

`--check` verifies that `i3-msg`, `jq`, `i3-resurrect`, and a saved workspace
list are available.

Restore behavior:

- Aborts if no workspace list exists.
- Hides Polybar during restore if it is visible.
- Kills all existing windows and waits for them to close.
- Detects an active external output.
- For each saved workspace:
  - Switches to the workspace.
  - Moves workspaces `7` to `10` to the active external output if one exists.
  - Restores layout first.
  - Waits briefly.
  - Restores programs.
  - Waits until i3-resurrect placeholders are swallowed.
- Restores focus to the saved focused workspace.
- Restores Polybar visibility on exit if it was visible before restore.
- Sends a success or error notification.

## Saved Session Profiles

The repository currently contains saved layouts and programs for three profiles.
These files are data used by the restore scripts, not static i3 config.

### Main Profile

Directories:

- State: `resurrect`.
- Metadata: `resurrect-meta`.

Metadata:

- Saved workspaces: `2`, `3`, `4`, `5`, `7`, `8`, `9`, `10`.
- Focused workspace: `8`.
- Captured Zathura page entries: `5`.
- Captured Zen/Helium page entries: `2`.

Saved programs:

| Workspace | Programs |
| --- | --- |
| `1` | Zathura, quantum chemistry PDF, page 1. |
| `2` | Zathura, relativistic quantum chemistry PDF, page 4. |
| `3` | Zathura, density matrix PDF, page 20. |
| `4` | Zathura, quantum mechanics PDF, page 1. |
| `5` | Zathura, decoherence PDF, page 11. |
| `6` | Helium AppImage, YouTube video URL. |
| `7` | Ghostty and Zen Browser opened to Learn C++. |
| `8` | Ghostty and Sioyek opened to `notes.pdf`. |
| `9` | Zathura quantum chemistry PDF, page 79, and Ghostty. |
| `10` | Zen Browser opened to a ChatGPT computational workspace URL. |

The main metadata workspace list does not currently include workspaces `1` and
`6`, but the state directory contains saved program/layout files for them.

### Profile B

Directories:

- State: `resurrect-b`.
- Metadata: `resurrect-meta-b`.

Metadata:

- Saved workspaces: `2`, `4`, `5`, `7`, `8`, `9`.
- Focused workspace: `7`.
- Captured Zathura page entries: `6`.
- Captured Zen/Helium page entries: `0`.

Saved programs:

| Workspace | Programs |
| --- | --- |
| `1` | Empty saved program list. |
| `2` | Zathura, relativistic quantum chemistry PDF, page 1. |
| `3` | Two Zathura windows for solid-state physics notes. |
| `4` | Zathura, quantum mechanics PDF, page 1. |
| `5` | Zathura, decoherence PDF, page 1. |
| `6` | Two Zathura windows for solid-state physics note PDFs. |
| `7` | Zathura, `DoWeReallyUnderstandQuantumMechanics.pdf`, page 1. |
| `8` | Zathura, density matrix PDF, page 1. |
| `9` | Zathura, quantum chemistry PDF, page 1. |

The metadata workspace list does not currently include workspaces `1`, `3`,
or `6`, but the state directory contains saved files for them.

### Profile C

Directories:

- State: `resurrect-c`.
- Metadata: `resurrect-meta-c`.

Metadata:

- Saved workspaces: `2`, `4`, `5`, `6`, `7`, `8`, `9`, `10`.
- Focused workspace: `7`.
- Captured Zathura page entries: `5`.
- Captured Zen/Helium page entries: `3`.

Saved programs:

| Workspace | Programs |
| --- | --- |
| `2` | Zathura, relativistic quantum chemistry PDF, page 4. |
| `4` | Zathura, quantum mechanics PDF, page 1. |
| `5` | Zathura, decoherence PDF, page 11. |
| `6` | Helium AppImage, YouTube video URL. |
| `7` | Ghostty and Zen Browser opened to Learn C++. |
| `8` | Zathura, density matrix PDF, page 20. |
| `9` | Zathura, quantum chemistry PDF, page 82. |
| `10` | Helium AppImage opened to YouTube. |

## Autostart

The i3 config starts these services and scripts.

One-shot startup:

- `gnome-keyring-daemon --start --components=secrets`.
- `xrdb -merge ~/.Xresources`.
- `xsetroot -cursor_name left_ptr`.
- `xfsettingsd` if not already running.
- `xfce4-power-manager` if not already running.
- `picom -b` if not already running.
- `nm-applet` if not already running.
- `blueman-applet` if not already running.
- `unclutter-xfixes --timeout 3` if not already running.
- `dropbox start -i`; the Dropbox launcher no-ops if the daemon is already running.
- `xss-lock -- xflock4`.

Always on reload/restart:

- Stop and restart `focus-tracker.sh`.
- Stop and restart `snap-watcher.sh`.
- Stop and restart `kakaotalk-float-watcher.sh`.
- Stop and restart `$HOME/.local/bin/autotiling --limit 6`.
- Run `$HOME/.local/bin/disable-trackpoint-middle-click` under a
  `/tmp/disable-trackpoint-middle-click.lock` flock.
- Run `display-setup.sh`, then `~/.config/polybar/launch.sh`.

The three long-running watchers also use their own runtime locks, so duplicate
instances are avoided even during i3 reloads.

## Dependencies

Core:

- `i3`
- `i3-msg`
- `bash`
- `jq`
- `flock`

Launchers and apps:

- `ghostty`
- `xfce4-terminal`
- `rofi`
- `thunar`
- `zed`
- `flatpak`
- Zen Browser Flatpak: `app.zen_browser.zen`
- Super Productivity Flatpak: `com.super_productivity.SuperProductivity`
- Helium AppImage under `~/Applications`

Desktop integration:

- `xfsettingsd`
- `xfce4-power-manager`
- `xfce4-display-settings`
- `xfce4-taskmanager`
- `xflock4`
- `xss-lock`
- `gnome-keyring-daemon`
- `picom`
- `nm-applet`
- `blueman-applet`
- `unclutter-xfixes`

Media and screenshots:

- `pactl`
- `playerctl`
- `brightnessctl`
- `flameshot`

Monitor/bar/snap helpers:

- `xrandr`
- `polybar`
- `polybar-msg`
- `xdotool`
- `xwininfo`
- `xprop`
- `feh`

Session restore:

- `i3-resurrect`
- `notify-send`
- `busctl`
- `zathura`
- `sioyek`
- Python 3
- Python module `lz4.block` for decoding browser session files
- `xclip` for live browser URL capture

Local helper programs expected outside this directory:

- `~/.local/bin/autotiling`
- `~/.local/bin/disable-trackpoint-middle-click`
- `~/.config/polybar/launch.sh`

## Runtime and State Files

Inside this directory:

- `config`: main i3 configuration.
- `_snap-common.sh`: shared snap/focus helpers.
- `tile-snap.sh`: manual snap and unsnap implementation.
- `snap-watcher.sh`: automatic snap fill/rebalance watcher.
- `resnap.sh`: reapplies current snap regions.
- `toggle-polybar-resnap.sh`: toggles Polybar and resnaps.
- `show-polybar-or-kill-workspace.sh`: shows Polybar before kill mode.
- `toggle-titles.sh`: toggles title bars globally.
- `toggle-titles-resnap.sh`: toggles title bars and resnaps.
- `focus-tracker.sh`: records current and previous focus.
- `focus-prev.sh`: focuses the previous window.
- `display-setup.sh`: applies monitor layout and wallpaper.
- `wallpaper.sh`: applies laptop/external wallpapers through `feh`.
- `move-to-workspace.sh`: guarded move-to-workspace command.
- `show-desktop.sh`: toggles `_desktop` workspace.
- `kakaotalk-float-watcher.sh`: repairs KakaoTalk floating state.
- `i3-resurrect-save-all.sh`: main save profile script.
- `i3-resurrect-restore-all.sh`: main restore profile script.
- `i3-resurrect-save-all-b.sh` and `i3-resurrect-restore-all-b.sh`: profile B.
- `i3-resurrect-save-all-c.sh` and `i3-resurrect-restore-all-c.sh`: profile C.
- `zen-url-state.py`: Zen/Helium URL capture helper.
- `resurrect`, `resurrect-b`, `resurrect-c`: saved i3-resurrect layouts and
  program lists.
- `resurrect-meta`, `resurrect-meta-b`, `resurrect-meta-c`: saved workspace,
  focus, browser URL, and Zathura page metadata.

Runtime files outside this directory:

- `$XDG_RUNTIME_DIR/i3-titles.state`
- `$XDG_RUNTIME_DIR/i3-focus-history`
- `$XDG_RUNTIME_DIR/i3-focus-tracker.lock`
- `$XDG_RUNTIME_DIR/i3-snap-watcher.lock`
- `$XDG_RUNTIME_DIR/i3-kakaotalk-float-watcher.lock`
- `$XDG_RUNTIME_DIR/i3-polybar-toggle.lock`
- `$XDG_RUNTIME_DIR/tile-snap-<con_id>.lock`
- `${XDG_STATE_HOME:-$HOME/.local/state}/i3/snap.log`
- `/tmp/disable-trackpoint-middle-click.lock`

## Maintenance Notes

- Keep `default_border pixel 1` in `config` synchronized with `NEW="pixel 1"`
  in `toggle-titles.sh`.
- If changing the laptop output name, update `I3_LAPTOP_OUTPUT` or the default
  in scripts that use it.
- If changing which workspaces belong on external monitors, update both the
  i3 workspace output directives and `I3_RESURRECT_EXTERNAL_WORKSPACES` usage.
- If Polybar changes its class name, update searches for `^[Pp]olybar$`.
- If changing snap mark names, update `tile-snap.sh`, `snap-watcher.sh`,
  `resnap.sh`, and cleanup logic together.
- If changing browser launch commands, update the Zen/Helium detection logic in
  `i3-resurrect-save-all.sh` and `zen-url-state.py`.
- If Helium is upgraded, the restore scripts should keep working as long as
  `~/.local/share/applications/helium.desktop` or a matching
  `~/Applications/helium*.AppImage` exists.
- The saved profile metadata controls which workspaces restore. A state
  directory may contain saved files for workspaces that are not listed in the
  corresponding `workspaces.txt`; those files will not be restored by the
  profile until the metadata list includes them.

## Quick Commands

Check the main save script dependencies:

```sh
~/.config/i3/i3-resurrect-save-all.sh --check
```

Check the main restore script dependencies and metadata:

```sh
~/.config/i3/i3-resurrect-restore-all.sh --check
```

Manually resnap all snapped windows:

```sh
~/.config/i3/resnap.sh
```

Inspect the snap/debug log:

```sh
tail -n 100 "${XDG_STATE_HOME:-$HOME/.local/state}/i3/snap.log"
```

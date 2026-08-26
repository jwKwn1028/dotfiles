# X11 to Wayland Transition Notes

> This document is the plan for adding a Sway-style Wayland session beside i3
> on the Mint/Ubuntu profile, the repo's only Linux desktop profile.

This repository currently contains a working X11/i3 desktop profile. Future
agents should treat it as a known-good fallback and add a parallel Wayland
profile instead of editing the i3/X11 files in place.

Preferred migration target: Sway or another wlroots compositor. Sway is the
lowest-risk first step because the current setup is already i3-shaped and many
`i3-msg` JSON workflows can be ported to `swaymsg`.

Note that this repo carries provisioning as well as dotfiles, so the migration
is packages *and* configuration — see [Provisioning](#provisioning) first. A
Wayland profile that is only config files will appear to work on the machine
that authored it and fail completely on a fresh one.

## Current Machine Snapshot

Last audited on **2026-08-20**. This is a dated observation, not a promise about
the next machine or the state after a distro upgrade.

- The machine is Linux Mint 22.3 on kernel `6.17.0-1032-oem`, using the AMD
  `amdgpu` driver. The active desktop is still i3 on X11:
  `XDG_SESSION_TYPE=x11`, `XDG_CURRENT_DESKTOP=i3`, `DISPLAY=:0`.
- LightDM is the display manager. It currently has only i3 and XFCE X11 session
  entries; `/usr/share/wayland-sessions` does not exist, so no packaged Wayland
  session is available.
- The source state has no `sway/`, `waybar/`, or `kanshi/` tree, and
  `.chezmoidata/packages.toml` still provisions only `packages.apt.i3_x11`.
  The migration has therefore **not started** in this repo.
- `sway`, `waybar`, `swayidle`, `swaylock`, `slurp`, `kanshi`, `fuzzel`, and
  `xdg-desktop-portal-wlr` are not installed. `grim` and `wl-clipboard` are
  installed only as recommended dependencies of existing software
  (`flameshot` and `pass` respectively), and `xwayland` is already installed.
  That partial tool presence is not a usable Sway stack and must not be treated
  as evidence that provisioning is complete.
- The kernel currently exposes the internal panel as `eDP-1` and the connected
  external monitor as `DP-1`. XRandR names can differ, and Sway output names
  must still be captured from `swaymsg -t get_outputs` in the real session.
- The current machine's chezmoi data predates the explicit `desktopProfile`
  answer. The templates correctly infer `linuxmint-i3-x11` for Mint/Ubuntu
  when the key is absent; a fresh `chezmoi init` records the prompt explicitly.

The original architectural decision still holds: add Sway beside i3 and keep
the working X11 session as the fallback.

## Ground Rules

- Keep `dot_config/i3/` usable as the X11 fallback until the user explicitly
  asks to remove it.
- Create new Wayland files beside the existing X11 files, for example:
  - `dot_config/sway/config`
  - `dot_config/waybar/config`
  - `dot_config/waybar/style.css`
  - `dot_config/kanshi/config`
  - `dot_config/swaylock/config`
  - `dot_config/swayidle/config` if a standalone config is used
- Do not blindly replace command names. Wayland deliberately blocks many X11
  automation patterns, especially global window inspection, synthetic input,
  and clipboard scraping.
- Prefer compositor-native configuration for outputs, input devices, locking,
  idle handling, screenshots, and wallpaper.
- When a helper script is still needed, make it session-aware rather than
  breaking X11. Check `WAYLAND_DISPLAY`, `XDG_SESSION_TYPE`, `SWAYSOCK`, and
  `DISPLAY`.

## Provisioning

This repo installs software as well as writing configuration, so a Wayland
config file is inert until the packages behind it exist. Provisioning comes
first, before any `sway/config` is written.

Package lists live in `.chezmoidata/packages.toml` and are consumed by the
`run_once_*` scripts. `packages.apt.i3_x11` currently provisions only the X11
session stack — i3, Polybar, Picom, Rofi, feh, xdotool, wmctrl, xclip, xsel,
LightDM, light-locker, and related desktop applications — and is gated on
`class == "desktop"` plus
`desktopProfile == "linuxmint-i3-x11"`, prompted in `.chezmoi.toml.tmpl`.

Add the Wayland packages to the same `i3_x11` list. Having both stacks
installed at once is what makes the X11 fallback real:

```toml
# .chezmoidata/packages.toml, appended to [packages.apt] i3_x11
"sway", "swaybg", "swayidle", "swaylock",
"waybar", "wl-clipboard", "grim", "slurp", "kanshi", "fuzzel",
"xwayland", "xdg-desktop-portal-wlr", "xdg-desktop-portal-gtk",
```

All of the above resolve on Mint 22.3 / Ubuntu 24.04 (verified via
`apt-cache policy`; sway is 1.9, waybar 0.9.24). Three tools that a Wayland
migration would reach for are **not** in these repos — do not add them to the
apt list:

- `rofi-wayland` — unavailable. Use `fuzzel` (1.9.2) or `wofi` (1.4.1).
- `swappy` — unavailable. Drop the screenshot annotation step, or install it
  outside apt if it turns out to be wanted.
- `swww` — unavailable. Use `swaybg` (1.2.0) for wallpaper.

Re-check availability rather than trusting this list after a distro upgrade;
these three are the ones most likely to change.

The explicit `xwayland` entry matters here. Ubuntu's Sway 1.9 package does not
depend on it, while this desktop still needs XWayland for Wine/KakaoTalk and
possibly other legacy applications. It happens to be installed on the current
machine, but a fresh install must not rely on that accident. Keep the GTK
portal beside the wlroots portal: wlr supplies wlroots screen capture while GTK
continues to provide portal interfaces that wlr does not implement.

The installed Flameshot package already recommends `grim` and
`xdg-desktop-portal-wlr`; that is why `grim` is present today. Its packaged
documentation still calls generic Wayland support experimental, so test
Flameshot in Sway after the portal is configured before deciding whether to
replace it. Keep `grim` explicit even though it was pulled in indirectly here.

Only split these into a separate Mint `wayland` list if the user decides to
make Sway independently selectable or to retire the combined fallback.

Further notes:

- `.chezmoiignore` already routes the i3 tree by desktop profile. Any future
  Sway tree needs an explicit Mint-profile rule before it is added.
- `light-locker` is X11-only and pairs with lightdm. Sway uses
  `swayidle`/`swaylock` instead. Leave light-locker installed for the fallback.
- A Sway session needs a greeter entry. The `sway` package ships a
  wayland-session file, and lightdm can offer it alongside i3, but confirm the
  greeter actually lists both before relying on it.
- `run_once_after_50-install-fonts.sh.tmpl` describes its fonts in terms of
  polybar/rofi. The same Nerd Font serves Waybar, so only its comments need
  updating.

## Files to Leave As X11 Fallback

These files are X11-specific and should stay available for the existing i3
session:

- `dot_config/i3/config`
- `dot_config/picom/picom.conf`
- `dot_config/polybar/config.ini`
- `dot_config/polybar/executable_launch.sh`
- `dot_config/polybar/scripts/executable_confirm-poweroff.sh`
- `executable_dot_x-unstick.sh` — an X11 stuck-modifier fix. It has no meaning
  under Wayland; do not port it, just leave it for the fallback session.

`dot_config/i3/MANUAL.md` is a special case. It stays correct for the i3
session and should not be edited in place, but it is a large user-facing
keybinding manual — a Sway session makes it wrong. Treat a parallel
`dot_config/sway/MANUAL.md` as a migration deliverable. No `MANUAL.pdf` is
currently present in the source state; do not plan around or claim a generated
PDF unless one is deliberately added later.

The following are mostly session-agnostic and normally should not need Wayland
changes:

- `dot_config/ghostty/config`
- `dot_zprofile`
- `dot_zshenv`
- `dot_profile`
- `dot_zshrc`
- editor configs under `dot_config/helix`, `dot_config/zed`,
  `dot_config/micro`, `dot_vimrc`, and `dot_nanorc`

## Main Replacements

| X11/i3 component | Current file or command | Wayland replacement |
| --- | --- | --- |
| Window manager | `dot_config/i3/config` | `dot_config/sway/config` |
| Bar | Polybar | Waybar |
| Compositor | Picom | built into Sway/Wayland compositor |
| Output setup | `xrandr`, `display-setup.sh` | `kanshi` or `swaymsg output` |
| Wallpaper | `feh`, `wallpaper.sh` | `swaybg` (`swww` is not in apt) |
| Lock/idle | `xss-lock`, `xflock4`, `i3lock` | `swayidle`, `swaylock` |
| Screenshots | `flameshot gui` | first test Flameshot + portal; fall back to `grim` + `slurp` |
| Launcher | `rofi` | `fuzzel` or `wofi` (`rofi-wayland` is not in apt) |
| Clipboard | `xclip`, `xsel` | `wl-copy`, `wl-paste` |
| Input devices | `xinput`, `xfconf-query` | Sway `input` blocks or libinput/udev |
| Screen capture portal | GTK/XApp portals only | add `xdg-desktop-portal-wlr`, keep GTK fallback |
| X resources | `xrdb` | remove or replace per app |
| Cursor root | `xsetroot` | Sway `seat`/cursor config |
| Hide cursor | `unclutter-xfixes` | `swayidle` or compositor features |
| Kill clicked window | `xkill` | use compositor kill binding or `swaymsg kill` |

## High-Risk Files That Need Rewrite

### `dot_config/i3/executable_display-setup.sh`

This is pure `xrandr`. Replace with `kanshi` profiles or Sway `output`
directives. Do not try to run it under Wayland.

Current behavior to preserve:

- laptop output defaults to `eDP`
- external output, when present, is placed left of the laptop
- laptop remains primary-equivalent
- wallpaper is reapplied after output changes
- one Polybar instance is relaunched per active output
- an i3 reload/restart produces the short welcome/reload toast; decide whether
  that feedback is worth keeping rather than losing it accidentally

### `dot_config/i3/executable_wallpaper.sh`

The `feh` caller that `display-setup.sh` invokes to reapply the wallpaper. It
sets `$HOME/.wallpaper-laptop.png` and `$HOME/.wallpaper-external.png` with
`feh --no-fehbg --bg-fill`, exiting silently when feh is absent.

Under Sway this becomes `swaybg` (one instance per output) or a `swaybg`
invocation per `output ... bg` directive. Note that `feh` maps both wallpapers
in one call across the X screen; `swaybg` is per-output, so the laptop/external
split has to be expressed as two outputs rather than one command.

### `dot_local/bin/executable_touchpad` and `executable_dot_toggle-touchpad.sh`

The canonical touchpad utility and its compatibility entry point are both
X11-only:

- `dot_local/bin/executable_touchpad` — `xinput` plus XFCE pointer settings,
  with a desired-state file and an `apply` action called from i3 autostart and
  `~/.x-unstick.sh`.
- `executable_dot_toggle-touchpad.sh` — compatibility wrapper for the old
  `~/.toggle-touchpad.sh` path; maps `toggle|on|off` to the canonical utility.

Both hardcode `export DISPLAY="${DISPLAY:-:0}"` and fall back to
`$HOME/.Xauthority`, so under a Wayland session they either abort at their
`command -v xinput` guard or, worse, silently drive a stale X server. Neither
is safe to leave on a Sway autostart path.

Both encode the same hardware quirk, worth preserving: the ELAN pad exposes two
X pointer nodes (a `Touchpad` node and a shadow `Mouse` node) that must be
switched together, while external mice and the TrackPoint are left alone. Under
libinput/Sway that dual-node workaround should be unnecessary — verify with
`swaymsg -t get_inputs` before porting the logic rather than assuming it.

The 2026-08-20 hardware audit still shows both
`ELAN0688:00 04F3:320B Touchpad` and its shadow `... Mouse`, plus the internal
`TPPS/2 Elan TrackPoint` and an external `Lenovo TrackPoint Keyboard II`.
There are also two more X11-owned input sources to account for now:

- `dot_config/xfce4/xfconf/private_xfce-perchannel-xml/pointers.xml` disables
  the ELAN touchpad and carries pointer acceleration/tapping choices.
- `run_after_90-install-x11-input-configs.sh.tmpl` installs an Xorg libinput
  acceleration rule for the external TrackPoint keyboard and writes
  `/etc/default/keyboard` with `ctrl:swapcaps`.

Do not port the Xorg rule itself. Re-express its acceleration setting in Sway,
and verify whether the system keyboard option is inherited; if it is not, add
the equivalent `xkb_options ctrl:swapcaps` to Sway.

In Sway, prefer `input` blocks:

```ini
input type:touchpad {
    events disabled
}
```

If runtime toggling is needed, use `swaymsg input <identifier> events enabled`
or `disabled`, but first inspect identifiers with:

```sh
swaymsg -t get_inputs
```

### `dot_local/bin/executable_disable-trackpoint-middle-click`

This rewrites X11 button maps with `xinput`, disabling button 2 on the internal
TrackPoint, the ELAN shadow-mouse node, and the external Lenovo TrackPoint
keyboard every two seconds. On Wayland, prefer libinput/Sway settings or a
udev/hwdb rule. A direct one-for-one script may not exist, so verify the three
physical behaviors independently.

### `dot_config/polybar/*` and its i3-side callers

Polybar is X11-oriented. Replace with Waybar rather than porting Polybar helper
scripts.

Current behavior to preserve:

- hidden by default
- one bar per active output, with the tray pinned to the internal panel
- persistent toggle with `Super+Shift+B`, including resnapping windows around
  the changed reserved area
- brief peeks after workspace switches, cross-workspace focus, and overflow
  moves
- quick standalone-Super and held-Super peeks, plus a top-edge pointer peek
- keyboard bar mode (`Super+B`) with module selection, actions, and synthetic
  clicks on the Wi-Fi/Bluetooth tray icons
- kill-workspace mode (`Super+X`), including the all-workspaces action that
  hides the bar afterward
- modules for workspaces, date, CPU, memory, audio, battery, network, tray, and
  power menu
- power menu confirmation before shutdown (`polybar/scripts/executable_confirm-poweroff.sh`)
- recovery from the fullscreen/orphan-dock state that can leave Polybar mapped
  when its own visibility state says hidden

The migration surface is now much larger than `polybar/` itself:

- `_polybar-common.sh`, `toggle-polybar-resnap.sh`, and `polybar-peek.sh` own
  visibility, transient ownership, locking, window raising, and X11 dock
  repair through `xdotool`, `xwininfo`, and Python Xlib.
- `bar-nav.sh` and `bar-nav-marker.py` implement keyboard access by sending
  synthetic X11 clicks and painting an override-redirect X11 marker over tray
  icons. That cannot be translated directly; use native Sway bindings for the
  underlying actions or design keyboard-accessible Waybar modules.
- `super-polybar-listener.py` reads XI2 raw events from `xinput test-xi2` and
  resolves keycodes with `xmodmap`. `top-edge-peek.py` globally polls the X
  pointer with Python Xlib/XRandR. Both are intentionally blocked by Wayland's
  input model. Decide whether an explicit bar toggle is sufficient before
  building compositor- or layer-shell-specific replacements.
- `workspace-action.sh`, `focus-prev.sh`, `overflow-watcher.py`,
  `kill-workspace-mode.sh`, `window-mode.sh`, and
  `kill-all-windows.sh` are compositor workflows with a
  Polybar feedback hook. Port the workflow and replace or remove the hook.
  `window-mode.sh` only shows the bar and restores its prior visibility, so on
  Waybar it reduces to nothing if the bar is always visible.
- `polybar/scripts/executable_confirm-poweroff.sh` uses Zenity, Rofi, or
  `xmessage` and treats a 30-second timeout as confirmation to power off. Test
  a Wayland-capable confirmation UI deliberately; do not silently turn the
  timed safety prompt into an immediate shutdown binding.

Waybar reserves its own space through layer-shell, so most of the
measure-the-bar-then-resnap logic should disappear rather than be translated.
Do not port the `xdotool`/`xwininfo` geometry probing; check Waybar's reserved
area or drop the compensation entirely and re-measure what is actually needed.
Waybar parity is a product decision here: persistent visibility is simple, but
the current transient peeks and keyboard cursor are substantial custom
features, not ordinary bar configuration.

### `dot_config/i3/executable_kakaotalk-float-watcher.sh`

The i3 config now has declarative, case-insensitive `class` and `instance`
rules for exactly `kakaotalk.exe`. The watcher remains as a fallback for Wine
remaps that defeat the initial rule; it subscribes to i3 window events, skips
hidden/fullscreen windows, checks hidden state with `xprop`, and repairs only a
visible KakaoTalk window that became tiled.

Under Sway, translate the existing rule against the XWayland `class`/`instance`
criteria first. Keep the fullscreen exception. Only rebuild a `swaymsg`
subscription watcher if Wine still defeats the rule; do not carry the X11
watcher over speculatively.

### `dot_config/i3/executable_i3-resurrect-save-all.sh`
### `dot_config/i3/executable_i3-resurrect-restore-all.sh`
### `dot_config/i3/executable_zen-url-state.py`

These are the most fragile migration area.

There are also `-b` and `-c` variants of both save and restore
(`executable_i3-resurrect-save-all-b.sh`, `...-c.sh`, and the restore pair).
They are ~276-byte wrappers that set `I3_RESURRECT_STATE_DIR` /
`I3_RESURRECT_META_DIR` and delegate to the base script, giving three
independent session profiles with state under `resurrect{,-b,-c}/` and
`resurrect-meta{,-b,-c}/`. Port the base scripts and the wrappers follow for
free — but do not miss them when grepping. The live `resurrect*/` and
`resurrect-meta*/` trees are ignored, local-only X11-shaped session state, not
configuration and not source material for the Sway profile.

The base scripts rely on:

- `i3-resurrect`
- `i3-msg`
- X11 window IDs
- `xprop` for window PID lookup
- `xdotool` for activating browser windows and sending keys
- `xclip` for live browser URL capture
- Polybar visibility inspection through X windows
- Zen session files plus live Zen/Helium URL matching
- Helium AppImage command normalization
- `xprop` plus Zathura's user D-Bus API for PDF page capture

The save path now preserves more than the old guide recorded: Zen and Helium
URLs, stable Helium launch commands, Zathura page numbers, focused workspace,
and the list of workspaces to restore. The restore path hides Polybar, closes
existing windows, rebuilds each saved workspace, moves workspaces 7–10 to the
active external output, and restores focus and prior bar visibility. A partial
port must say explicitly which of those behaviors it drops.

Under Sway, some layout IPC can move to `swaymsg`, but the browser URL capture
path should be redesigned. Wayland blocks synthetic global input and arbitrary
clipboard/window scraping by design.

Practical migration strategy:

- First port only layout/workspace restore if needed.
- Disable or degrade live browser URL capture under Wayland.
- Prefer browser session files, browser CLI URL arguments, or explicit user
  workflow over `xdotool`-style automation.
- Do not assume `i3-resurrect` works unchanged with Sway.

## Lower-Risk Files to Port

These scripts are mostly compositor IPC plus JSON parsing and can likely be
ported from `i3-msg` to `swaymsg`, with careful testing. The ratio is
encouraging — `tile-snap.sh`, the largest of them, is 37 `i3-msg` calls against
only 2 X11 ones (`xdotool`, `xwininfo`, both in the Polybar-probing path noted
below):

- `dot_config/i3/executable__snap-common.sh`
- `dot_config/i3/executable_tile-snap.sh`
- `dot_config/i3/executable_snap-watcher.sh`
- `dot_config/i3/executable_focus-tracker.sh`
- `dot_config/i3/executable_focus-prev.sh`
- `dot_config/i3/executable_resnap.sh`
- `dot_config/i3/executable_show-desktop.sh`
- `dot_config/i3/executable_move-to-workspace.sh`
- `dot_config/i3/executable_workspace-action.sh`
- `dot_config/i3/executable_overflow-watcher.py`
- `dot_config/i3/executable_toggle-titles.sh`
- `dot_config/i3/executable_toggle-titles-resnap.sh`

`move-to-workspace.sh` no longer uses `xrandr`: it validates workspace numbers
1–10 and sends one move-and-follow `i3-msg` command. `workspace-action.sh`
wraps numbered and relative navigation, delegates moves to it, and requests a
bar peek. Output policy now lives in the i3 `primary`/`nonprimary` workspace
directives and the restore script, so the older high-risk description of this
file as an output detector was stale.

`overflow-watcher.py` is also compositor-IPC rather than X11 geometry code. It
uses `python3-i3ipc` events and the i3 tree to move windows that land below a
quarter-workspace size floor. Sway's IPC compatibility makes it a reasonable
port candidate, but verify connection through `SWAYSOCK`, event fields, tree
geometry, and command results instead of assuming the Python client is drop-in.

Watch for these differences:

- Sway uses `app_id` for native Wayland clients and `window_properties.class`
  for XWayland clients.
- Some i3 commands and marks are compatible, but test every command with
  `swaymsg`.
- Geometry and output names may differ from X11.
- The current snap scripts inspect Polybar windows with `xdotool`/`xwininfo`;
  remove that logic or replace it with Waybar-aware reserved space handling.

## XFCE and X11 Session Glue

The current session is pure i3, but it deliberately borrows XFCE services and
settings. A Sway profile must make explicit choices for them instead of simply
omitting every line containing `xfce`:

- `xfsettingsd` supplies XSettings theming and cursor behavior. The managed
  `xsettings.xml` names the GTK theme, icon theme, JuliaMono fonts, and Bibata
  cursor. Configure native Wayland GTK/cursor settings separately while keeping
  enough XSettings support for XWayland applications if they need it.
- `xfce4-power-manager` owns the current lid, power-button, battery brightness,
  and lock-on-suspend policy from `xfce4-power-manager.xml`. Decide whether to
  keep it after testing Wayland support or divide the policy among logind,
  Sway bindings, `swayidle`, and `brightnessctl`. Do not accidentally create
  two lid/suspend handlers.
- The profile manages XFCE pointer, notification, power, and XSettings XML.
  Keep that tree gated to the X11 fallback unless an individual setting is
  deliberately shared.
- `dunst` is in the provisioned package list and the Mint package is linked
  with Wayland support, while `xfce4-notifyd` is also installed on this
  machine. Pick and test one notification daemon in Sway so D-Bus activation
  does not produce a race between them.

The session also starts gnome-keyring, a polkit agent, NetworkManager and
Bluetooth applets, Dropbox, and `autotiling`. They are not inherently X11-only,
but their startup environment, tray behavior, and (for `autotiling`) Sway IPC
compatibility must be tested. Waybar's tray cannot be assumed to reproduce the
current XEmbed tray ordering.

## Main `i3/config` Porting Notes

Start by copying concepts, not the file verbatim.

Keep:

- Mod key and most navigation bindings
- workspace numbering and workspace movement policy
- floating rules, translated for `app_id` where needed
- media, volume, brightness, and application launch bindings
- custom snap bindings if the helper scripts are ported

Replace:

- `env XDG_CURRENT_DESKTOP=XFCE:i3 rofi ...`
- `xfce4-display-settings --minimal`
- `xflock4`
- `/usr/bin/xkill`
- `i3-nagbar`
- `flameshot gui` only if its tested portal path is inadequate
- Polybar launch/toggle bindings
- `xrdb -merge ~/.Xresources`
- `xsetroot -cursor_name left_ptr`
- `xfsettingsd` if it only exists for X11 theming/cursor behavior
- `picom -b`
- `unclutter-xfixes`
- `xss-lock -- xflock4`
- `super-polybar-listener.py` and `top-edge-peek.py`

Likely Wayland equivalents:

```ini
set $mod Mod4
bindsym $mod+Return exec ghostty
bindsym $mod+space exec fuzzel
bindsym Control+$mod+l exec swaylock
bindsym Print exec grim -g "$(slurp)" - | wl-copy
exec dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
exec swayidle -w timeout 600 'swaylock' before-sleep 'swaylock'
exec waybar
exec swaybg -i "$HOME/.wallpaper-laptop.png" -m fill
```

The environment import is important for user services and portals; confirm the
actual user-service environment after login rather than assuming the display
manager populated it. The screenshot line is the plain fallback and copies to
the clipboard because `swappy` is not packaged here. Try the existing
Flameshot annotation workflow through the wlroots portal first, then accept the
plain grab only if the annotation flow is unnecessary or unreliable.

Do not commit these exact examples without adapting them to installed tools and
the user's preferred workflow.

## Clipboard Notes

`dot_local/bin/executable_clipcopy` already has Wayland support, but its current
priority favors X11 when `DISPLAY` is set. In XWayland sessions both `DISPLAY`
and `WAYLAND_DISPLAY` may exist. Prefer `wl-copy` whenever
`WAYLAND_DISPLAY` is non-empty.

This is not only a Wayland concern — the two files already contradict each
other. `dot_tmux.conf` documents the priority as "wl-copy (Wayland) -> xclip
(X11) -> pbcopy (macOS) -> OSC52 fallback", while `clipcopy` both describes
itself as "xclip -> xsel -> Wayland" and behaves that way. Reordering `clipcopy`
to check `WAYLAND_DISPLAY` first makes the code match the intent already written
down in tmux, and is safe under X11 because `WAYLAND_DISPLAY` is unset there.
Fix the stale comment on `clipcopy` line 3 at the same time; it claims the host
is "Mint XFCE / X11".

`dot_tmux.conf` should update Wayland environment variables:

```tmux
set -g update-environment "DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE SWAYSOCK KRB5CCNAME SSH_ASKPASS SSH_AUTH_SOCK SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY TERM_PROGRAM"
```

Keep X11 variables too so tmux remains usable in the fallback session.

## Suggested Implementation Order

1. Add the Wayland packages to `packages.apt.i3_x11` in
   `.chezmoidata/packages.toml`. Inspect `chezmoi diff`, `chezmoi status`, and
   `chezmoi apply --dry-run` before intentionally applying so the install script
   re-runs. Nothing below this line works until the software exists, and a
   fresh machine gets no Wayland stack at all today.
2. Add the `.chezmoiignore` routing for the new Sway/Waybar/Kanshi trees before
   adding them. A server or `desktopProfile=none` must not receive the session.
3. Add a minimal `dot_config/sway/config` with terminal, launcher, workspaces,
   movement, volume, brightness, lock, screenshot, autostart, and the systemd/
   D-Bus environment import needed by portals.
4. Configure and verify the wlr + GTK portal combination, including Flatpak
   screenshot/screen-share behavior and the existing Flameshot workflow.
5. Add output management with `kanshi` or Sway `output` directives.
6. Add input configuration for the ELAN touchpad and both TrackPoints, replacing
   the X11 touchpad utility, its compatibility wrapper, and the XFCE/Xorg pointer
   policy rather than only swapping `xinput` for `swaymsg`.
7. Add Waybar config and style. Decide explicitly which peek, keyboard-bar, and
   kill-mode behaviors survive; do not port Polybar in place.
8. Adjust the clipboard helper and tmux environment.
9. Port simple compositor-IPC helper scripts to session-aware wrappers or Sway
   copies, testing `overflow-watcher.py` and `autotiling` separately.
10. Decide whether session restore is worth rebuilding under Wayland and which
    Zen, Helium, and Zathura metadata is still required.
11. Only after Wayland is stable, ask the user before deleting or replacing X11
   files. This is also the point to split the package lists (a `wayland` list
   plus a `session` prompt in `.chezmoi.toml.tmpl`) and to rewrite
   the documentation as a parallel `dot_config/sway/MANUAL.md`.

## Validation Checklist

Before calling the migration done, verify in a real Wayland session:

- a from-scratch `chezmoi init --apply` installs the Wayland stack, not just the
  config files (the packages step is the one most easily forgotten, because an
  already-migrated machine passes every check below without it)
- the greeter offers both the Sway and i3 sessions
- `echo $XDG_SESSION_TYPE` prints `wayland`
- `systemctl --user show-environment` contains `DISPLAY`, `WAYLAND_DISPLAY`,
  `SWAYSOCK`, and the intended desktop/session values
- terminal launches
- launcher opens
- lock and idle behavior work
- lid, suspend, and power-button policy work once, with no competing handler
- the wlr and GTK portals select the expected backends
- screenshots, Flameshot annotation (if retained), and Flatpak screen sharing
  work
- clipboard works inside and outside tmux
- audio, brightness, battery, network, and tray display correctly
- exactly one notification daemon is active, and notifications appear on the
  intended output
- polkit prompts and keyring-backed secrets still work
- internal and external monitors are arranged correctly
- touchpad and TrackPoint behavior matches the X11 setup
- XWayland apps still open when needed, especially Wine/KakaoTalk, and the
  translated KakaoTalk rule does not fight fullscreen
- the chosen workspace overflow, snapping, bar visibility, and kill-mode
  behaviors match the decisions recorded during the port
- Korean/input-method behavior still works
- fallback i3/X11 session still starts

## Commands Useful During Migration

```sh
swaymsg -t get_version
swaymsg -t get_tree
swaymsg -t get_outputs
swaymsg -t get_inputs
swaymsg -t get_workspaces
echo "$XDG_SESSION_TYPE $WAYLAND_DISPLAY $SWAYSOCK $DISPLAY"
systemctl --user show-environment
systemctl --user status xdg-desktop-portal.service xdg-desktop-portal-wlr.service
```

Use `rg` to find X11 dependencies before changing behavior:

```sh
rg -n "xrandr|xinput|xmodmap|xdotool|xprop|xwininfo|Xlib|xclip|xsel|picom|polybar|feh|xss-lock|xflock4|xkill|xrdb|xsetroot|unclutter|xfconf|xfsettingsd|xfce4-power-manager|i3-msg|i3ipc" -S --glob '!X11_TO_WAYLAND_TRANSITION.md' .
```

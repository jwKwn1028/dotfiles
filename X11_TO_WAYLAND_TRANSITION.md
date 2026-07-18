# X11 to Wayland Transition Notes

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
`run_once_*` scripts. `packages.apt.desktop` is currently pure X11 — i3,
polybar, picom, rofi, feh, flameshot, xdotool, wmctrl, xclip, xsel, lightdm,
light-locker — and is gated on `class == "desktop"`, prompted in
`.chezmoi.toml.tmpl`.

During the transition, add the Wayland packages to the **same** `desktop` list
rather than creating a new one. Having both stacks installed at once is what
makes the X11 fallback real:

```toml
# .chezmoidata/packages.toml, appended to [packages.apt] desktop
"sway", "swaybg", "swayidle", "swaylock",
"waybar", "wl-clipboard", "grim", "slurp", "kanshi", "fuzzel",
"xdg-desktop-portal-wlr",
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

Only split these into a separate `wayland` list — and add a `session` prompt
next to `class` in `.chezmoi.toml.tmpl` — at step 9 below, once X11 is actually
being retired. Splitting earlier costs the fallback for no gain.

Further notes:

- `.chezmoiignore` does no class gating, so new `dot_config/sway/` files get
  written on every machine exactly as `dot_config/i3/` already is. That matches
  the current design; no change needed.
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

`dot_config/i3/MANUAL.md` and its generated `MANUAL.pdf` are a special case.
They stay correct for the i3 session and should not be edited in place, but
they are a 30KB user-facing keybinding manual — a Sway session makes them
wrong. Treat them as a migration deliverable rather than a fallback file, and
plan either a Wayland section or a parallel `dot_config/sway/MANUAL.md`,
regenerating the PDF to match.

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
| Screenshots | `flameshot gui` | `grim` + `slurp` (`swappy` is not in apt) |
| Launcher | `rofi` | `fuzzel` or `wofi` (`rofi-wayland` is not in apt) |
| Clipboard | `xclip`, `xsel` | `wl-copy`, `wl-paste` |
| Input devices | `xinput`, `xfconf-query` | Sway `input` blocks or libinput/udev |
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

### `dot_config/i3/executable_wallpaper.sh`

The `feh` caller that `display-setup.sh` invokes to reapply the wallpaper. It
sets `$HOME/.wallpaper-laptop.png` and `$HOME/.wallpaper-external.png` with
`feh --no-fehbg --bg-fill`, exiting silently when feh is absent.

Under Sway this becomes `swaybg` (one instance per output) or a `swaybg`
invocation per `output ... bg` directive. Note that `feh` maps both wallpapers
in one call across the X screen; `swaybg` is per-output, so the laptop/external
split has to be expressed as two outputs rather than one command.

### `dot_config/i3/executable_move-to-workspace.sh`

Uses `xrandr` to detect whether the external output is active, then routes the
workspace accordingly (`I3_LAPTOP_OUTPUT`, default `eDP`). Same `xrandr`
problem as `display-setup.sh`. Replace the detection with
`swaymsg -t get_outputs` and match on the Sway output name, which may not equal
the X11 name.

### `dot_local/bin/executable_touchpad` and `executable_dot_toggle-touchpad.sh`

There are now **two** touchpad scripts, and both are X11-only:

- `dot_local/bin/executable_touchpad` — `xinput` plus XFCE pointer settings,
  with a desired-state file and an `apply` action called from i3 autostart and
  `~/.x-unstick.sh`.
- `executable_dot_toggle-touchpad.sh` — newer, `xinput`-only, `toggle|on|off`.

Both hardcode `export DISPLAY="${DISPLAY:-:0}"` and fall back to
`$HOME/.Xauthority`, so under a Wayland session they either abort at their
`command -v xinput` guard or, worse, silently drive a stale X server. Neither
is safe to leave on a Sway autostart path.

Both encode the same hardware quirk, worth preserving: the ELAN pad exposes two
X pointer nodes (a `Touchpad` node and a shadow `Mouse` node) that must be
switched together, while external mice and the TrackPoint are left alone. Under
libinput/Sway that dual-node workaround should be unnecessary — verify with
`swaymsg -t get_inputs` before porting the logic rather than assuming it.

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

This rewrites X11 button maps with `xinput`. On Wayland, prefer libinput/Sway
settings or a udev/hwdb rule. A direct one-for-one script may not exist.

### `dot_config/polybar/*` and its i3-side callers

Polybar is X11-oriented. Replace with Waybar rather than porting Polybar helper
scripts.

Current behavior to preserve:

- hidden by default
- toggle with `Super+Shift+B`
- modules for workspaces, date, CPU, memory, audio, battery, network, tray, and
  power menu
- power menu confirmation before shutdown (`polybar/scripts/executable_confirm-poweroff.sh`)

Two scripts under `dot_config/i3/` are tightly coupled to Polybar and are the
real work here, not `polybar/` itself:

- `dot_config/i3/executable_toggle-polybar-resnap.sh` — the heaviest of the
  pair. It drives Polybar visibility and then resnaps windows around the
  reclaimed space, inspecting bar windows with `xdotool`/`xwininfo`.
- `dot_config/i3/executable_show-polybar-or-kill-workspace.sh` — overloads the
  bar-visibility check with workspace teardown.

Waybar reserves its own space through layer-shell, so most of the
measure-the-bar-then-resnap logic should disappear rather than be translated.
Do not port the `xdotool`/`xwininfo` geometry probing; check Waybar's reserved
area or drop the compensation entirely and re-measure what is actually needed.

### `dot_config/i3/executable_kakaotalk-float-watcher.sh`

Keeps KakaoTalk floating after Wine remaps/maximizes it during login, via
`xdotool` polling on top of `_snap-common.sh`.

Under Sway this is very likely a declarative `for_window` rule against the
XWayland `window_properties.class` (KakaoTalk runs under Wine, so it stays an
XWayland client) rather than a watcher process. Try the rule first; only keep a
watcher if Wine defeats it.

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
free — but do not miss them when grepping, and note that the committed
`resurrect*/` JSON is X11-shaped saved state, not configuration.

The base scripts rely on:

- `i3-resurrect`
- `i3-msg`
- X11 window IDs
- `xprop` for window PID lookup
- `xdotool` for activating browser windows and sending keys
- `xclip` for live browser URL capture
- Polybar visibility inspection through X windows

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
- `dot_config/i3/executable_toggle-titles.sh`
- `dot_config/i3/executable_toggle-titles-resnap.sh`

Watch for these differences:

- Sway uses `app_id` for native Wayland clients and `window_properties.class`
  for XWayland clients.
- Some i3 commands and marks are compatible, but test every command with
  `swaymsg`.
- Geometry and output names may differ from X11.
- The current snap scripts inspect Polybar windows with `xdotool`/`xwininfo`;
  remove that logic or replace it with Waybar-aware reserved space handling.

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
- `flameshot gui`
- Polybar launch/toggle bindings
- `xrdb -merge ~/.Xresources`
- `xsetroot -cursor_name left_ptr`
- `xfsettingsd` if it only exists for X11 theming/cursor behavior
- `picom -b`
- `unclutter-xfixes`
- `xss-lock -- xflock4`

Likely Wayland equivalents:

```ini
set $mod Mod4
bindsym $mod+Return exec ghostty
bindsym $mod+space exec fuzzel
bindsym Control+$mod+l exec swaylock
bindsym Print exec grim -g "$(slurp)" - | wl-copy
exec swayidle -w timeout 600 'swaylock' before-sleep 'swaylock'
exec waybar
exec swaybg -i "$HOME/.wallpaper-laptop.png" -m fill
```

The screenshot line copies to the clipboard because `swappy` is not packaged
here; `flameshot gui` currently offers annotation, so confirm whether that is
actually used before accepting a plain grab as the replacement.

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

1. Add the Wayland packages to `packages.apt.desktop` in
   `.chezmoidata/packages.toml` and `chezmoi apply` so the install script
   re-runs. Nothing below this line works until the software exists, and a
   fresh machine gets no Wayland stack at all today.
2. Add minimal `dot_config/sway/config` with terminal, launcher, workspaces,
   movement, volume, brightness, lock, screenshot, and autostart.
3. Add Waybar config and style. Do not port Polybar in place.
4. Add output management with `kanshi` or Sway `output` directives.
5. Add input configuration for touchpad and TrackPoint behavior, replacing both
   X11 touchpad scripts rather than only the one under `dot_local/bin/`.
6. Adjust clipboard helper and tmux environment.
7. Port simple `i3-msg` helper scripts to session-aware wrappers or Sway copies.
8. Decide whether session restore is worth rebuilding under Wayland.
9. Only after Wayland is stable, ask the user before deleting or replacing X11
   files. This is also the point to split the package lists (a `wayland` list
   plus a `session` prompt in `.chezmoi.toml.tmpl`) and to rewrite
   `dot_config/i3/MANUAL.md` / `MANUAL.pdf`.

## Validation Checklist

Before calling the migration done, verify in a real Wayland session:

- a from-scratch `chezmoi init --apply` installs the Wayland stack, not just the
  config files (the packages step is the one most easily forgotten, because an
  already-migrated machine passes every check below without it)
- the greeter offers both the Sway and i3 sessions
- `echo $XDG_SESSION_TYPE` prints `wayland`
- terminal launches
- launcher opens
- lock and idle behavior work
- screenshots work
- clipboard works inside and outside tmux
- audio, brightness, battery, network, and tray display correctly
- internal and external monitors are arranged correctly
- touchpad and TrackPoint behavior matches the X11 setup
- XWayland apps still open when needed
- Korean/input-method behavior still works
- fallback i3/X11 session still starts

## Commands Useful During Migration

```sh
swaymsg -t get_tree
swaymsg -t get_outputs
swaymsg -t get_inputs
swaymsg -t get_workspaces
echo "$XDG_SESSION_TYPE $WAYLAND_DISPLAY $SWAYSOCK $DISPLAY"
```

Use `rg` to find X11 dependencies before changing behavior:

```sh
rg -n "xrandr|xinput|xdotool|xprop|xwininfo|xclip|xsel|picom|polybar|feh|xss-lock|xflock4|xkill|xrdb|xsetroot|unclutter|i3-msg" -S .
```

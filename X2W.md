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

Last audited on **2026-09-26**; first audited 2026-08-20. This is a dated
observation, not a promise about the next machine or the state after a distro
upgrade.

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
  `xdg-desktop-portal-wlr` are not installed. `grim`, `wl-clipboard`, and
  `xdg-desktop-portal-gtk` are installed only as dependencies of existing
  software (`flameshot`, `pass`, and the portal stack respectively), and
  `xwayland` is already installed. That partial tool presence is not a usable
  Sway stack and must not be treated as evidence that provisioning is complete.
- Under X11 on `amdgpu` the outputs are named `eDP` (internal panel) and
  `DisplayPort-0` (external), with `HDMI-A-0` and `DisplayPort-1` through
  `DisplayPort-6` present but disconnected. `display-setup.sh` defaults
  `I3_LAPTOP_OUTPUT` to `eDP` accordingly. An earlier revision of this file
  recorded `eDP-1` and `DP-1`; that was wrong, so do not trust a draft that
  copied those. Sway renames outputs regardless — capture the real names from
  `swaymsg -t get_outputs` in the session.
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

Re-verified on 2026-09-26: every package in the block above still resolves
(sway 1.9, swaybg 1.2.0, swayidle 1.8.0, swaylock 1.7.2, waybar 0.9.24,
wl-clipboard 2.2.1, grim 1.4.0, slurp 1.5.0, kanshi 1.5.1, fuzzel 1.9.2,
xwayland 23.2.6, and both portals), and all three tools above are still
unavailable. Re-check rather than trusting this list after a distro upgrade;
those three are the ones most likely to change.

Three more are packaged and worth knowing about, though none is required:

- `wlr-randr` (0.3.0) and `wdisplays` (1.1.1) — one-shot and graphical output
  inspection. Useful while writing kanshi profiles, because there is no
  `xrandr` to fall back on when a layout misbehaves.
- `mako-notifier` (1.8.0) — the wlroots-native notification daemon, and the
  obvious candidate if dunst does not behave under Sway. See
  [XFCE and X11 Session Glue](#xfce-and-x11-session-glue) for why exactly one
  daemon must win, and `dunst-start.sh` under
  [Session Lifecycle Helpers](#session-lifecycle-helpers) for the X11
  assumption baked into how dunst is started today.

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

## The `desktopProfile` Gating Trap

Read this before deciding how a Sway session gets selected, because the choice
is not free. Eight files branch on the **exact string** `linuxmint-i3-x11`:

| File | Test | What it gates |
| --- | --- | --- |
| `.chezmoiignore` | `ne` | the whole desktop config tree |
| `run_once_before_10-install-apt-packages.sh.tmpl` | `eq` (twice) | the i3 PPA and the `i3_x11` apt list |
| `run_once_after_30-install-cli-tools.sh.tmpl` | `eq` | desktop CLI tooling |
| `run_after_90-install-x11-input-configs.sh.tmpl` | `eq` | the Xorg rule and `/etc/default/keyboard` |
| `run_once_after_95-build-i3lock-color.sh.tmpl` | `eq` | the i3lock-color build |
| `run_once_after_96-build-zathura.sh.tmpl` | `eq` | the zathura build |
| `.chezmoi.toml.tmpl` | — | the prompt that defines the value |
| `.githooks/tests/test-pre-commit.sh` | — | fixture data |

Keeping one profile that installs both stacks, as
[Provisioning](#provisioning) recommends, sidesteps every row above. That is
most of why it is the recommendation.

If a `linuxmint-sway-wayland` value is introduced instead, all eight change
meaning at once, and they fail in two different directions. `.chezmoiignore`
is the dangerous one: its `ne` test means a new profile name **silently
excludes**

    .config/rofi/  .config/dunst/  .config/fcitx5/  .config/xfce4/

Rofi, dunst, and fcitx5 are not X11-only, and fcitx5 is the Korean input
method. A Sway machine missing `.config/fcitx5/` reads as an input-method bug,
not a routing bug. The `eq` rows fail more quietly still — the machine simply
never gets `/etc/default/keyboard`, so `ctrl:swapcaps` and
`korean:ralt_hangul` go missing with no error anywhere.

So splitting the profile is not "add a value to the prompt". It is: decide,
per file, whether the gate means *i3 specifically* or *a Linux desktop of any
session*, and convert the second group to a shared test first. Do that as its
own change, verified with `chezmoi status` against both values, rather than
inside the commit that adds the Sway config.

## Files to Leave As X11 Fallback

These files are X11-specific and should stay available for the existing i3
session:

- `dot_config/i3/config`
- `dot_config/picom/picom.conf`
- `dot_config/polybar/config.ini`
- `dot_config/polybar/executable_launch.sh`
- `dot_config/polybar/scripts/executable_confirm-poweroff.sh`

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

### The shared toast layer

`dot_config/i3/_toast-common.sh` was added after the first audit and is now the
most widely shared X11 dependency in the i3 tree: `display-setup.sh`,
`usb-hotplug.sh`, and `tests/test-usb-hotplug.sh` all source it.

`show_toast` renders a transient status message by running
`rofi -e "<text>" -theme reload-toast -m primary` in the background and killing
it after `I3_TOAST_SECONDS`. `wrap_toast` hard-wraps at 27 columns first,
because Rofi 1.7.5 mis-sizes a box it wraps itself past two lines.

Three separate things break under Wayland, and each needs its own decision:

- **Rofi.** `rofi-wayland` is not packaged here, and `fuzzel`, the launcher
  replacement suggested in [Main Replacements](#main-replacements), has no
  `-e` message mode. The toast is therefore *not* covered by the launcher
  decision, however much it looks like it should be.
- **`-m primary`.** An X11 monitor concept. Wayland notification daemons take
  an output name instead, which is the same question `dunst-start.sh` faces.
- **The 27-column wrap.** A workaround for a Rofi bug. Whatever replaces Rofi
  almost certainly wraps correctly, so port the call sites, not `wrap_toast`.

The low-effort path is `notify-send` through whichever notification daemon wins
under Sway, which turns each toast into an ordinary notification and deletes
both the wrap workaround and the manual kill timer. That is a visible behavior
change — these toasts are centered overlays today, not corner notifications —
so confirm it is wanted rather than assuming equivalence.

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

Two changes since the first audit reshape this port:

- The toast is no longer an inline Rofi call; `display-setup.sh` now sources
  `_toast-common.sh`. See [The shared toast layer](#the-shared-toast-layer).
- `dot_config/i3/executable_randr-hotplug.sh` now re-runs `display-setup.sh` on
  monitor hotplug, keyed on the connected-output set from `xrandr --query`
  rather than the raw i3 `output` event, with a 0.7s coalescing window and an
  `flock` that the `exec_always` pkill must be able to release. Under Sway most
  of this disappears — kanshi reacts to output hotplug natively. Check what
  kanshi already covers before porting the poll loop; if a watcher is still
  wanted after that, `swaymsg -t subscribe '["output"]'` replaces the `xrandr`
  polling, and `tests/test-randr-hotplug.sh` goes with the old mechanism.

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
  with a desired-state file and an `apply` action called from i3 autostart.
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
  `/etc/default/keyboard` with
  `XKBOPTIONS="ctrl:swapcaps,korean:ralt_hangul"`.

Do not port the Xorg rule itself; re-express its acceleration setting in Sway.

The keyboard options are not a detail to defer, and there are two of them now —
`korean:ralt_hangul` is newer than the first audit, which recorded only
`ctrl:swapcaps`. `/etc/default/keyboard` belongs to console-setup: X11 picks it
up, and Sway does not read it at all. Both options have to be restated:

```ini
input type:keyboard {
    xkb_options ctrl:swapcaps,korean:ralt_hangul
}
```

`korean:ralt_hangul` makes right Alt a Hangul key, beside the Ctrl+Space
trigger fcitx5 already lists. Losing it silently is easy, because Ctrl+Space
keeps working and the failure then looks like an fcitx5 problem rather than a
missing xkb option. That is why the
[Validation Checklist](#validation-checklist) names both triggers.

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
### `dot_config/i3/executable_ghostty-session-state.py`

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
- Ghostty's X11 `WINDOWID` and `--x11-instance-name` to pair terminal windows
  with their shells and placeholders

The save path now preserves more than the old guide recorded: Zen and Helium
URLs, stable Helium launch commands, Zathura page numbers, Ghostty working
directories and first remote sessions, the lab route mode, focused workspace,
and the list of workspaces to restore. The restore path hides Polybar, closes
the windows on saved workspaces that had windows, re-enables a saved lab route,
rebuilds those workspaces, moves workspaces 3–10 to the active external output,
and restores focus and prior bar visibility. A partial port must say explicitly which of those
behaviors it drops.

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

## Session Lifecycle Helpers

These were added or reshaped after the first audit and had no entry here. None
approaches the Polybar or resurrect surface in size, but each encodes a
decision that a mechanical command swap gets wrong.

### `dot_config/i3/executable_usb-hotplug.sh`

The cheapest port in the tree, and worth not rewriting by mistake. It toasts
USB attach and detach by parsing `udevadm monitor --udev --property` across the
`usb` and `typec` subsystems, correlating a Type-C partner event with USB
enumeration inside a 3s window, and caching device fields so a detach toast can
still name hardware that is already gone.

None of that is X11. `udevadm monitor --udev` is unprivileged and
session-agnostic, and the script never touches a display server. Its only X11
dependency is the toast it emits through `_toast-common.sh`. Resolve the toast
layer and this script and its test follow with no other change; the i3
`exec_always` line that starts it becomes the Sway equivalent.

### `dot_config/i3/executable_lock.sh` and `run_once_after_95-build-i3lock-color.sh.tmpl`

`lock.sh` probes `i3lock --version` for the `.c.` marker identifying
i3lock-color and, when present, locks with the full theme — ring, inside,
verify, wrong, and modifier colors, a 60px radius, and JuliaMono at three
sizes. Stock i3lock is the fallback. `run_once_after_95` exists only to build
i3lock-color from source, because Ubuntu does not package it.

`swaylock` *is* packaged (1.7.2) and takes the same class of options, so the
Wayland side needs no build step — drop that dependency rather than porting it.
Two details do not survive a flag rename: swaylock spells the ring geometry
`--indicator-radius` and `--indicator-thickness`, not `--radius` and
`--ring-width`; and the foreground behavior that `-n` selects for i3lock
matters differently here, because `swayidle`'s `before-sleep` contract needs
swaylock to stay in the foreground. Verify the lock screen actually renders as
intended instead of assuming the translation worked.

`tests/test-lock.sh` covers the version probe and the fallback. A Sway
counterpart needs its own.

### `dot_config/i3/executable_dunst-start.sh`

Starts dunst 1.9 pinned to the internal panel, resolving that panel by reading
`xrandr --listmonitors` and extracting the **numeric index** of the output
matching `I3_LAPTOP_OUTPUT` (default `eDP`), then falling back to the first
`eDP`/`LVDS` name, the primary-flagged monitor, and the first listed.

dunst's `monitor` setting is an index under X11 but an **output name** under
Wayland, so this is not a command swap: the entire index-resolution function
becomes unnecessary and collapses to the Sway output name. Take that name from
`swaymsg -t get_outputs`, per the snapshot note about renaming.

This is also where the notification-daemon choice becomes concrete. If mako
wins instead of dunst, this script is deleted rather than ported, and its
output and follow behavior has to be re-expressed in mako's config.

### `dot_config/i3/executable_session-reload.sh` and `executable_i3-restart.sh`

`session-reload.sh` runs from `exec_always`, so it fires on every reload. It
reloads systemd user units, restarts dunst only when `dunstrc` is newer than
the running service, refreshes Picom and the displays, and collects failures
into the reload toast. Under Sway the Picom step disappears, the display step
becomes kanshi, and the toast follows the toast decision; the systemd and dunst
steps carry over unchanged.

`i3-restart.sh` validates a candidate config with `i3 -C -c <config>` before
replacing the running instance, reporting through `notify-send` and falling
back to `i3-nagbar`. Sway validates with `sway --validate -c <config>`. For the
error path, confirm whether `swaynag` is present — there is no separate
`swaynag` package in these repos, so it either ships inside `sway` or is
unavailable, and that was not verified from an installed system. Keep the
validate-before-restart guard either way; it is the reason a bad edit does not
cost a session.

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

Reordering `clipcopy` to check `WAYLAND_DISPLAY` first is safe under X11,
where `WAYLAND_DISPLAY` is unset. Fix the stale comment on `clipcopy` line 3 at
the same time; it still claims the host is "Mint XFCE / X11".

An earlier revision of this file justified that reorder by saying
`dot_tmux.conf` documents a "wl-copy -> xclip -> pbcopy -> OSC52" priority that
`clipcopy` contradicts. That was wrong: no such comment exists in
`dot_tmux.conf`, whose clipboard notes cover `set-clipboard on` and the OSC 52
path. The reorder is still right, it just is not resolving a contradiction.

That revision also recommended replacing `update-environment` with one literal
string. **Do not.** `dot_tmux.conf` deliberately does:

```tmux
set -gu update-environment
set -g update-environment[99] TERM_PROGRAM
```

`-gu` restores tmux's built-in default list and the indexed assignment appends
to it, so the config never has to track what upstream ships. On tmux 3.7c that
default is `DISPLAY KRB5CCNAME MSYSTEM SSH_ASKPASS SSH_AUTH_SOCK SSH_AGENT_PID
SSH_CONNECTION WAYLAND_DISPLAY WINDOWID XAUTHORITY` — `WAYLAND_DISPLAY` is
already carried. The literal string would drop `MSYSTEM`, freeze the list
against future tmux versions, and add nothing that is not there already.

Only two variables are genuinely missing, and they append the same way:

```tmux
set -g update-environment[100] SWAYSOCK
set -g update-environment[101] XDG_SESSION_TYPE
```

Both are harmless in the X11 fallback, where they are unset.

## Suggested Implementation Order

1. Add the Wayland packages to `packages.apt.i3_x11` in
   `.chezmoidata/packages.toml`. Inspect `chezmoi diff`, `chezmoi status`, and
   `chezmoi apply --dry-run` before intentionally applying so the install script
   re-runs. Nothing below this line works until the software exists, and a
   fresh machine gets no Wayland stack at all today.
2. Add the `.chezmoiignore` routing for the new Sway/Waybar/Kanshi trees before
   adding them. A server or `desktopProfile=none` must not receive the session.
   If that routing tempts you to introduce a second profile value, stop and read
   [The `desktopProfile` Gating Trap](#the-desktopprofile-gating-trap) — that
   conversion is its own change, landed before this one.
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

## Tests

AGENTS.md requires running the relevant standalone checks, and the desktop tree
carries 21 of them under `dot_config/i3/tests/` plus 2 under
`dot_config/polybar/tests/`. 22 of those 23 run from
`dot_config/i3/tests/run-fast.sh` and are tabulated in
`dot_config/i3/MANUAL.md`; `test-overflow-live.py` needs a live session and is
deliberately left out. The first audit did not mention any of them; they are a
migration deliverable, not an afterthought.

They fall into three groups that need different treatment:

- **Tests of X11 mechanics** — `test-polybar-peek.sh`, `test-bar-nav.sh`,
  `test-super-polybar-listener.py`, `test-top-edge-peek.py`,
  `test-randr-hotplug.sh`, `test-i3-resurrect-polybar.sh`. These die with the
  features they cover. Do not port them; retire each one alongside the decision
  about whether its feature survives.
- **Tests of logic that merely runs under X11** — `test-tile-snap.sh`,
  `test-snap-watcher.sh`, `test-usb-hotplug.sh`, `test-lock.sh`,
  `test-dunst-start.sh`, `test-session-reload.sh`, `test-zen-url-state.py`.
  These assert on geometry arithmetic, parsing, and protocol through fixtures
  and stubbed commands, so they are the ones worth adapting —
  `test-usb-hotplug.sh` nearly for free, for the same reason its script is.
- **Contract tests.** `test-provisioning-contract.py` pairs desktop runtime
  consumers with their provisioning declarations, so it is exactly the tripwire
  that catches a config-only migration: adding Wayland packages or a Sway
  config without the other half should make it fail. Extend it to cover the
  Sway profile rather than loosening it. `test-config-consistency.py` is mixed
  — its bar-navigation and power-menu checks are Polybar-specific and retire
  with Polybar, while its autotiling-restart, `pgrep`-matchability, and
  system-interpreter checks apply to any session and should be kept.

Keep `run-fast.sh` green on the X11 machine throughout the migration. A Sway
entry point belongs beside it, not inside it, until that session is real.

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
- Korean/input-method behavior still works through **both** triggers: the
  fcitx5 Ctrl+Space binding and the right-Alt Hangul key from
  `korean:ralt_hangul`
- status toasts still appear — display change, USB attach and detach —
  through whatever replaced Rofi's `-e` mode
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
rg -n "xrandr|xinput|xmodmap|xdotool|xprop|xwininfo|Xlib|xclip|xsel|picom|polybar|feh|xss-lock|xflock4|xkill|xrdb|xsetroot|unclutter|xfconf|xfsettingsd|xfce4-power-manager|i3-msg|i3ipc" -S --glob '!X2W.md' .
```

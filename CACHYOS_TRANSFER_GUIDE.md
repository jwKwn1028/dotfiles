# Transferring This Chezmoi Setup to CachyOS

Last reviewed: 2026-07-26

This guide covers a fresh CachyOS desktop running **Niri with Noctalia** while
keeping the existing Linux Mint **i3/X11** setup intact. The two desktops are
separate profiles; CachyOS is not treated as an in-place port of the i3 files.

The short version is:

1. Initialize chezmoi without applying anything.
2. Select `desktop` and `cachyos-niri-noctalia`.
3. Apply the CachyOS package-provisioning script **first**.
4. Apply a small, shared command-line configuration set **next**.
5. Capture and curate the working Niri and Noctalia configuration only after
   the packaged CachyOS session has been tested.
6. Finish with a full dry run before allowing a full apply.

Do not use `chezmoi init --apply` for the first CachyOS checkout.

## What the profile split protects

The repository has three desktop-profile values:

| Value | Purpose |
| --- | --- |
| `linuxmint-i3-x11` | Mint/Ubuntu apt packages and the existing i3, Polybar, Picom, Rofi, and X11 helpers |
| `cachyos-niri-noctalia` | CachyOS pacman packages and future Niri/Noctalia source state |
| `none` | Shared terminal configuration only; suitable for a server or an unsupported desktop |

On CachyOS, `.chezmoiignore` prevents the Mint i3/X11 targets from being
applied. On Mint, it prevents Niri and Noctalia targets from being applied.
Noctalia runtime state and cache remain local on every profile:

```text
~/.local/state/noctalia/
~/.cache/noctalia/
```

The existing i3 configuration and helper-script bodies are deliberately
unchanged. This refactor only routes files and packages to the correct
platform.

## Phase 0: finish on Linux Mint

Before booting the new system, make sure the chezmoi source is committed and
available from its remote:

```sh
cd "$(chezmoi source-path)"
git status --short
chezmoi diff
chezmoi apply --dry-run --verbose
git push
```

Review any uncommitted files before committing. Do not assume that a live edit
under `$HOME` is already in chezmoi; use `chezmoi re-add TARGET_PATH` for a change
that should be transported.

The current Mint installation may predate the `desktopProfile` setting. Refresh
its local chezmoi config before the next ordinary Mint apply:

```sh
chezmoi init
```

Choose:

```text
Machine class: desktop
Desktop profile: linuxmint-i3-x11
```

Then verify the selection:

```sh
chezmoi data | jq '{os: .chezmoi.os, distro: .chezmoi.osRelease.id, class, desktopProfile}'
chezmoi ignored
```

## Phase 1: bootstrap CachyOS without applying dotfiles

First update CachyOS and install only the tools needed to retrieve this
repository:

```sh
sudo pacman -Syu --needed chezmoi git
```

Clone and initialize the repository, but omit `--apply`:

```sh
chezmoi init REPOSITORY_URL
```

Choose:

```text
Machine class: desktop
Desktop profile: cachyos-niri-noctalia
```

If the repository is already cloned as the chezmoi source, run `chezmoi init`
without a URL.

Confirm that chezmoi detected the intended system and profile:

```sh
chezmoi data | jq '{os: .chezmoi.os, distro: .chezmoi.osRelease.id, class, desktopProfile}'
chezmoi ignored
chezmoi status
```

Expected values include:

```text
os: linux
distro: cachyos
class: desktop
desktopProfile: cachyos-niri-noctalia
```

The ignored list should include `.config/i3`, `.config/polybar`,
`.config/picom`, `.config/rofi`, and the X11-only helpers. If it does not, stop
before applying and correct `~/.config/chezmoi/chezmoi.toml`.

## Phase 2: what to apply first

Apply package provisioning first. It installs the shared command-line tools
and the CachyOS-supported Niri/Noctalia stack before any configuration depends
on them.

Preview the one script:

```sh
chezmoi apply --dry-run --verbose \
  --source-path run_once_before_11-install-pacman-packages.sh.tmpl
```

If the preview names only the pacman provisioning script, apply it:

```sh
chezmoi apply \
  --source-path run_once_before_11-install-pacman-packages.sh.tmpl
```

The script uses:

```sh
sudo pacman -Syu --needed
```

for the base package set, then installs the Niri/Noctalia desktop set. It is
intentionally interactive: pacman may need a real decision when CachyOS changes
a package group or introduces a conflict. Do not convert this into a partial
upgrade such as `pacman -Sy`.

The desktop list starts with CachyOS's `cachyos-niri-noctalia` package so the
fresh machine retains the distribution's supported session integration. Do
not add the older `cachyos-niri-settings` package beside it: both provide and
conflict with `cachyos-desktop-settings`. The list also installs the shared
Wayland utilities declared in `.chezmoidata/packages.toml`.

After the script completes, reboot if pacman upgraded the kernel, graphics
stack, systemd, or the display manager. Log into Niri and confirm the stock
CachyOS/Noctalia session starts before adding personal configuration.

## Phase 3: what to apply next

Apply a deliberately small shared shell/tool layer next. Preview it with
scripts excluded:

```sh
chezmoi apply --dry-run --verbose --exclude=scripts \
  ~/.zshenv \
  ~/.zprofile \
  ~/.zshrc \
  ~/.zsh \
  ~/.tmux.conf \
  ~/.config/bat \
  ~/.config/btop \
  ~/.config/fastfetch \
  ~/.config/helix \
  ~/.config/starship.toml \
  ~/.config/yazi
```

Inspect the diff for platform-specific paths before applying the same target
set:

```sh
chezmoi diff
chezmoi apply --exclude=scripts \
  ~/.zshenv \
  ~/.zprofile \
  ~/.zshrc \
  ~/.zsh \
  ~/.tmux.conf \
  ~/.config/bat \
  ~/.config/btop \
  ~/.config/fastfetch \
  ~/.config/helix \
  ~/.config/starship.toml \
  ~/.config/yazi
```

Open a new terminal and test Zsh, tmux, Helix, Yazi, Starship, clipboard
operations, and path initialization. If a shared config proves Linux
Mint-specific, gate the smallest affected fragment; do not fork the whole file
by hostname.

## Phase 4: optional provisioning scripts

The remaining scripts should not be applied as a group on the first pass.
Review and run them individually when their purpose is wanted:

| Order | Script | CachyOS decision |
| --- | --- | --- |
| 20 | `run_once_after_20-install-flatpaks.sh.tmpl` | Run after checking the declared GUI applications are wanted on this installation. |
| 30 | `run_once_after_30-install-cli-tools.sh.tmpl` | Review first. Pacman already supplies several CLI tools, while this script also bootstraps Rust/Cargo and Miniconda. |
| 40 | `run_once_after_40-set-default-shell.sh` | Run only if replacing CachyOS's default login shell with Zsh is intentional. |
| 50 | `run_once_after_50-install-fonts.sh.tmpl` | Optional; JetBrains Mono Nerd Font is also declared in the CachyOS package set. |
| 60 | `run_onchange_after_60-configure-zen-userjs.sh.tmpl` | Run only after Zen has launched once and created its local profile. |

Use the same narrow pattern for any script you approve:

```sh
source_script=run_once_after_20-install-flatpaks.sh.tmpl
chezmoi apply --dry-run --verbose --source-path "$source_script"
chezmoi apply --source-path "$source_script"
```

Do not run the CLI-tools script merely to obtain `eza`, `yazi`, `starship`, or
`zoxide`; those are already provided by pacman. A later cleanup can split the
cross-distribution bootstrap script into smaller capabilities.

Before a later full `chezmoi apply`, every script in the table must be either
approved and run, or explicitly gated out of the CachyOS profile in source.
Leaving one merely "undecided" is not enough: a full apply would run it.

## Phase 5: capture Niri after the stock session works

CachyOS should remain the source of the initial Niri/Noctalia integration. Test
the packaged session first, then curate only the personal settings that must be
reproduced.

Record the package and session facts:

```sh
pacman -Q | rg 'cachyos-niri|niri|noctalia|quickshell'
pacman -Qqen > /tmp/cachyos-explicit-repo-packages.txt
pacman -Qqem > /tmp/cachyos-foreign-packages.txt
niri --version
niri validate
```

Review `~/.config/niri/config.kdl` for machine-local values before adding it:

- output connector names, modes, scale, and physical placement;
- input-device identifiers;
- wallpaper and host-specific paths;
- autostart commands duplicated by CachyOS or Noctalia;
- secrets, tokens, usernames, and private endpoints.

Keep output and device facts local until there is a real cross-machine rule for
them. Once the portable part is clean:

```sh
chezmoi add ~/.config/niri/config.kdl
chezmoi diff
niri validate
```

This creates the future `dot_config/niri/` source state. It will be ignored by
the Mint profile automatically. Prefer small includes or templates if only a
few Niri values differ between machines.

## Phase 6: capture Noctalia according to its installed generation

Do not copy the entire Noctalia directory blindly. CachyOS can move between
Noctalia generations, and their configuration formats differ.

Identify what is installed:

```sh
pacman -Q | rg 'noctalia|quickshell'
command -v noctalia
command -v qs
```

### Noctalia v5

Noctalia v5 uses hand-managed TOML in `~/.config/noctalia/` and GUI-managed
overrides in `~/.local/state/noctalia/settings.toml`. Export a portable merged
configuration and validate it:

```sh
noctalia config export > /tmp/noctalia-config.toml
noctalia config validate /tmp/noctalia-config.toml
install -Dm644 /tmp/noctalia-config.toml ~/.config/noctalia/config.toml
chezmoi add ~/.config/noctalia/config.toml
```

Do **not** add `~/.local/state/noctalia/`; the profile routing explicitly
ignores it. Review exported location, calendar, plugin, wallpaper, output, and
device values before committing.

### Noctalia v4

Noctalia v4 uses its own JSON configuration and normally starts under Niri
through:

```text
spawn-at-startup "qs" "-c" "noctalia-shell"
```

Configure it in the GUI, inspect the files under `~/.config/noctalia/`, and add
only the stable user-owned JSON files. Exclude caches, generated templates,
plugin checkouts, credentials, device identifiers, and host-specific paths.
Test the installed shell manually with:

```sh
qs -c noctalia-shell
```

After adding either generation:

```sh
chezmoi diff
chezmoi status
```

The resulting `dot_config/noctalia/` source state is applied only by the
CachyOS profile.

## Phase 7: reconcile packages from the real CachyOS machine

The initial pacman list is a reproducible baseline, not a claim that every Mint
application belongs on the Niri machine. Compare the explicit package lists
captured in Phase 5 with `.chezmoidata/packages.toml`.

Before adding a package:

```sh
pacman -Si package-name
```

Put official CachyOS/Arch repository packages in:

```toml
[packages.pacman]
common = []
niri_noctalia = []
```

Keep AUR/foreign packages separate from the official pacman list. Do not
silently introduce an AUR helper or automate unreviewed PKGBUILDs. If an AUR
package becomes required for reproduction, add an explicit, independently
reviewable provisioning path later.

## Phase 8: final dry run, then full apply

Only after the shared shell layer, Niri, Noctalia, package manifest, and every
remaining provisioning-script decision have been tested independently:

```sh
chezmoi data | jq '{os: .chezmoi.os, distro: .chezmoi.osRelease.id, class, desktopProfile}'
chezmoi ignored
chezmoi status
chezmoi diff
chezmoi apply --dry-run --verbose
```

The dry run must not propose any of these CachyOS targets:

```text
~/.config/i3/
~/.config/polybar/
~/.config/picom/
~/.config/rofi/
~/.x-unstick.sh
~/.toggle-touchpad.sh
```

It also must not propose Noctalia state, cache, secrets, or host-specific
display identifiers. Apply the full profile only after the preview is clean:

```sh
chezmoi apply
```

## Ongoing workflow

Use the same repository on both systems, but let each profile render only its
own desktop:

```sh
chezmoi diff
chezmoi status
chezmoi apply --dry-run
chezmoi apply
```

When changing a profile-specific file, validate on that profile before
committing. A good cross-system change has all three properties:

1. the Mint render still contains the existing i3/X11 setup;
2. the CachyOS render contains Niri/Noctalia and no i3/X11 target;
3. package provisioning and the configuration that consumes it change
   together.

If the two installations share a physical home partition, do not apply both
profiles into the same `$HOME` without an additional design pass. Profile
routing prevents the wrong files from being written, but it cannot preserve
two different live versions of a shared file at one target path.

## Recovery rules

- Stop at the first unexpected target in `chezmoi status` or a dry run.
- Use `chezmoi diff` to identify what chezmoi would overwrite.
- Pull an intentional live edit back with `chezmoi re-add TARGET_PATH`.
- Fix the source state or profile selection; do not edit ignored i3 files into
  Niri equivalents.
- Keep the stock CachyOS Niri/Noctalia package configuration available until
  the curated source state has survived a reboot and a second apply.

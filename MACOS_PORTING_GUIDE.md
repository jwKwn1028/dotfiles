# Porting This Chezmoi Setup to macOS

Last audited against the repository and upstream documentation: 2026-08-20

This document is the implementation contract for a coding agent asked to move
this dotfile setup from Linux Mint/Ubuntu to macOS. It describes the desired
result, the current hazards, the source-state layout, native replacements, and
the checks that must pass before a Mac is allowed to apply the repository.

The repository now contains a useful Darwin Zsh compatibility layer, but it is
still **not safe for a fresh macOS apply**. Do not run `chezmoi init --apply` on
a Mac until the remaining provisioning and target-isolation gates in Phase 1
are implemented and the synthetic Darwin audit is clean.

## Desired outcome

Create a parallel Darwin profile that reproduces the user's workflow as
closely as macOS permits while retaining Linux Mint/i3 as the known-good
fallback.

“Exact” has four levels in this guide:

1. **Shared verbatim:** portable configuration has one source and renders the
   same content on Linux and macOS.
2. **Parameterized:** the behavior is shared, but paths, executable names, or
   key modifiers are selected from `.chezmoi.os` and `.chezmoi.arch`.
3. **Native equivalent:** an X11/i3 behavior is redesigned around a macOS-native
   tool because the Linux primitive does not exist.
4. **Intentionally local:** credentials, browser profiles, SSH endpoints,
   project-trust records, and macOS privacy grants are not transported by Git.

The port is complete only when a fresh Mac can install the declared software,
render the Darwin target without Linux artifacts, and provide the accepted
workflow equivalents below—without changing the Linux render.

## Non-negotiable agent rules

1. Read `AGENTS.md`, this file, and the current package/scripts before editing.
2. Add Darwin files in parallel. Do not convert `dot_config/i3/`, Polybar,
   Picom, or Rofi in place.
3. Use the built-in `.chezmoi.os` value (`darwin` or `linux`) for OS selection.
   Use `.chezmoi.arch` only where artifacts differ by CPU architecture.
4. Never select behavior by username, hostname, `/opt/homebrew`, or
   `/usr/local` alone. Ask `brew --prefix` after Homebrew is available.
5. Put shared content in `.chezmoitemplates/`; render small platform-specific
   wrappers into the correct target locations.
6. Add package declarations and their consuming configuration in the same
   change. A config-only port is not reproducible on a fresh Mac.
7. Do not commit browser data, `~/.ssh`, SSH host aliases, agent project trust,
   Keychain exports, tokens, device IDs, or anything from macOS TCC databases.
8. Do not attempt to automate Privacy & Security approval. Accessibility,
   Automation, Screen Recording, and Full Disk Access require a deliberate
   user decision.
9. Never run `chezmoi apply` as the first test. Render, inspect, dry-run, and
   apply a narrow file group before the full profile.
10. Preserve existing user changes and the Linux target throughout the work.

## Current implementation snapshot

This snapshot was verified on 2026-08-20 by rendering the current source with
`.chezmoi.os=darwin`, `.chezmoi.arch=arm64`, `class=desktop`, and
`desktopProfile=none`. It is a source audit, not evidence from a real Mac.

Already implemented:

- `.chezmoi.toml.tmpl` keeps `class` separate from OS and defaults an
  unsupported desktop to `desktopProfile=none`.
- `.chezmoiignore` suppresses the i3, XFCE, Polybar, Picom, Rofi, Fcitx5, X11
  input helpers, Thunar integration, and GTK theme when the profile is not
  `linuxmint-i3-x11`.
- The apt installer and X11 input installer render empty on Darwin.
- The Zen, Firefox, Thunderbird, and Helium profile scripts have explicit
  non-Linux early exits.
- `dot_zsh/macos/` supplies narrow `date`, `wc`, `systemctl`, clipboard, rsync,
  and fzf compatibility. `dot_zshenv` already sources its prelude, and
  `macos/doctor.zsh` validates it on a real Mac.
- The shared `clipcopy` and tmux clipboard paths already support `pbcopy`.

Blocking hazards still present:

- `run_once_after_20-install-flatpaks.sh.tmpl` renders its Linux body on Darwin.
- `run_once_after_30-install-cli-tools.sh.tmpl` renders on Darwin and downloads
  `Miniconda3-latest-Linux-x86_64.sh`.
- `run_once_after_40-set-default-shell.sh` is not a template and assumes
  `getent`, Linux `/etc/shells` handling, and `sudo tee`.
- `run_once_after_50-install-fonts.sh.tmpl` renders on Darwin and installs under
  `~/.local/share/fonts` using fontconfig.
- The synthetic Darwin target still includes the Linux Helium desktop/AppImage
  payload, `.config/pipewire/`, `.config/systemd/`, `.config/zathura/`, Linux
  browser chrome payloads, and the Linux VS Code target under `.config/Code/`.
- `.chezmoidata/packages.toml` has no Darwin package section or Homebrew
  provisioning, and `README.md` still documents Linux only.
- The current macOS shell installer calls Homebrew directly and can append to
  `~/.zshenv`, although that file is now managed and already contains the hook.
  Its dependencies and setup must be folded into the Darwin profile rather than
  treated as a complete machine bootstrap.
- `dot_gitconfig.tmpl` unconditionally selects the Linux `libsecret` helper,
  and shared shell paths still name Linux/application-specific locations.
- `dot_bashrc` and `executable_dot_cleanup-agents.sh` require modern Bash; do
  not assume Apple's system Bash is sufficient.
- GNU and BSD variants of `sed`, `stat`, `date`, `find`, `readlink`, and `xargs`
  differ. Every shared script using non-POSIX flags needs a Darwin test or an
  explicit dependency.

The next macOS safety change must make every remaining Linux-only script render
to no script on Darwin. The official chezmoi pattern is:

```gotemplate
{{ if eq .chezmoi.os "linux" -}}
#!/usr/bin/env bash
# Existing Linux-only script body.
{{ end -}}
```

Rename the non-template default-shell script to
`run_once_after_40-set-default-shell.sh.tmpl` before adding that guard. Do not
rely only on “command not found” checks: the Miniconda URL is valid enough to
download the wrong artifact before failing.

## Recommended source-state architecture

Use OS selection and shared templates, not duplicated hand-maintained files.
A mature layout should resemble:

```text
.chezmoidata/packages.toml
.chezmoitemplates/
  vscode-settings.jsonc
  shared-zshrc.tmpl
dot_config/
  aerospace/aerospace.toml
  sketchybar/executable_sketchybarrc
  private_Code/User/private_settings.json.tmpl
Library/
  Application Support/
    Code/User/private_settings.json.tmpl
run_onchange_before_15-install-homebrew-packages.sh.tmpl
```

Chezmoi interprets `.chezmoiignore` as a template and matches target paths, not
source-state names. Gate whole target trees with negative tests because files
are managed by default. Keep the current `$desktopProfile` prelude and extend
it with a `macos-aerospace` value when the Darwin desktop actually lands:

```gotemplate
{{ if ne $desktopProfile "linuxmint-i3-x11" }}
/.config/i3/
/.config/polybar/
/.config/picom/
/.config/rofi/
{{ end }}

{{ if ne .chezmoi.os "linux" }}
/.config/pipewire/
/.config/systemd/
/Applications/helium.desktop
/Applications/helium.png
/Applications/update-helium.sh
/.local/share/applications/helium.desktop
{{ end }}

{{ if ne $desktopProfile "macos-aerospace" }}
/.config/aerospace/
/.config/sketchybar/
{{ end }}

{{ if ne .chezmoi.os "darwin" }}
/Library/Application Support/Code/User/
{{ end }}
```

For content needed at different target paths, keep one shared template:

```gotemplate
{{/* .chezmoitemplates/vscode-settings.jsonc */}}
{
  // Shared settings go here. Add OS-only keys with .chezmoi.os conditions.
}
```

Both platform wrappers should contain only:

```gotemplate
{{- template "vscode-settings.jsonc" . -}}
```

The Linux wrapper targets `~/.config/Code/User/settings.json`; the Darwin
wrapper targets `~/Library/Application Support/Code/User/settings.json`.

## Phase 0 — capture the Mac facts

Run these read-only checks on the target Mac and record the results in the
working notes, not in committed machine-specific data:

```sh
sw_vers
uname -m
uname -s
printf 'shell=%s\n' "$SHELL"
xcode-select -p 2>/dev/null || true
command -v brew >/dev/null && brew --prefix
command -v bash >/dev/null && bash --version | head -n 1
chezmoi data | jq '{os: .chezmoi.os, arch: .chezmoi.arch, home: .chezmoi.homeDir}'
```

Expected chezmoi OS is `darwin`; common architecture values are `arm64` and
`amd64`. Install Apple's Command Line Tools interactively with
`xcode-select --install` if they are missing. Do not script acceptance of an
Apple license or password prompt.

As of this audit, Homebrew's supported macOS baseline is Sonoma 14 or newer on
officially supported hardware. Treat that as a moving prerequisite: re-check
Homebrew's installation page for the target OS instead of copying this version
number indefinitely.

Keep `class` (`desktop` or `server`) as a separate workload choice; do not add
`darwin` as a third machine class. OS branches come from `.chezmoi.os`, while
`class` continues to decide whether GUI applications belong on that machine.
When the native desktop layer is ready, add `macos-aerospace` as a
`desktopProfile` choice; leave the Darwin default as `none` until its packages,
ignore rules, config, and verification land together.

## Phase 1 — make provisioning safe

### 1. Gate all Linux provisioning

The apt and X11 input scripts already render empty on Darwin. Apply the same
outer OS guard to Flatpak, the current CLI/Miniconda installer, fonts, and the
renamed default-shell template. Prefer an empty render to a runtime
`command -v` escape: chezmoi does not execute a script whose template result is
empty. Verify on Linux that rendered bodies remain byte-for-byte equivalent
except for intentional fixes.

The browser/profile scripts currently render small skip-only scripts on
Darwin. They are safe by inspection, but eventually make Linux-only ones empty
as well so `chezmoi status` and `chezmoi diff` describe only real Darwin work.

### 2. Bootstrap Homebrew explicitly

Homebrew requires Apple's Command Line Tools. Its supported default prefixes
remain `/opt/homebrew` on Apple Silicon and `/usr/local` on Intel, but later
code must use `brew --prefix` once Homebrew is available rather than inferring
the active installation from one hard-coded path.

Homebrew installation is a user-approved bootstrap step. Do not silently pipe
a remote installer into a shell from `chezmoi apply`. Homebrew's installer is
interactive and shows its changes before proceeding; record it as a manual
prerequisite. Once Homebrew exists, add its environment in
`dot_zprofile.tmpl`, for example:

```sh
for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [ -x "$brew_bin" ]; then
    eval "$("$brew_bin" shellenv)"
    break
  fi
done
unset brew_bin
```

### 3. Extend the package manifest

Keep the existing Linux keys and add a Darwin section. Start small and verify
every formula/cask on the target Mac with `brew info` or `brew search`; do not
guess a cask name from a Linux application ID.

```toml
[packages.darwin]
taps = [
    "nikitabobko/tap",
    "FelixKratz/formulae",
]
brews = [
    "bash", "bat", "btop", "cmake", "coreutils", "fd", "fzf", "git", "git-lfs",
    "helix", "jq", "micro", "node", "pipx", "pkg-config",
    "ranger", "ripgrep", "rsync", "sevenzip", "shellcheck", "sketchybar",
    "task", "tmux", "tree", "wget", "zoxide",
]
casks = [
    "ghostty", "visual-studio-code", "zed",
    "nikitabobko/tap/aerospace",
]
```

Both desktop tools come from third-party taps. Inspect them before first use.
If the installed Homebrew version requires tap trust, prefer its narrow
formula/cask trust declarations over trusting an entire tap, and keep that
decision visible in the generated Brewfile.

Render the list into a temporary `Brewfile` from a
`run_onchange_*homebrew-packages.sh.tmpl` script and invoke
`brew bundle --file="$brewfile"`. Homebrew documents `--file` with an actual
path; a temporary file is also reusable for `brew bundle check`. `run_onchange_`
makes package-state changes follow manifest changes without reinstalling on
every apply. Make the script fail with a clear manual-bootstrap message if
`brew` is absent.

The Darwin package list must include at least `coreutils`, `rsync`, and `fzf`
because the existing `dot_zsh/macos/` compatibility layer tests for them.
Install modern `bash` if `.bashrc`, the Claude status line, or
`cleanup-agents.sh` will be managed on Darwin. Once the manifest owns these
packages, change `macos/install.zsh` so it no longer appends to the
chezmoi-managed `.zshenv`; retain `macos/doctor.zsh` as the runtime check.

Keep the Rust/cargo list shared only after each crate is confirmed on Darwin.
Homebrew Bundle can also represent Cargo packages, but choose one owner: do not
install the same crates through both the current script and a Brewfile.
The Miniconda artifact must be selected from both OS and architecture:

| `.chezmoi.os` | `.chezmoi.arch` | Installer family |
| --- | --- | --- |
| `linux` | `amd64` | `Miniconda3-latest-Linux-x86_64.sh` |
| `darwin` | `arm64` | `Miniconda3-latest-MacOSX-arm64.sh` |
| `darwin` | `amd64` | `Miniconda3-latest-MacOSX-x86_64.sh` |

Fail closed for any unlisted combination rather than downloading a plausible
but wrong artifact.

## Phase 2 — classify every current target

### Share or lightly template

These are normally portable, but must still be rendered and tested on macOS:

| Source | Darwin treatment |
| --- | --- |
| `dot_gitconfig.tmpl` | Share; keep the prompt/noreply identity and credential helper conditional. Linux `libsecret` is not available on macOS. |
| `dot_profile` | Convert to a template or make every optional startup file conditional. The current unconditional `.local/bin/env` and Cargo sources can fail on a fresh Mac. |
| `dot_zshrc`, `dot_zprofile`, `dot_zshenv` | The modular Zsh loader and Darwin prelude now exist. Convert path-bearing files to templates; discover Homebrew/Go rather than retaining `/usr/local/go`, and treat FullProf, VESTA, and Quantum ESPRESSO paths as explicit optional software. Keep the existing guarded `macos/compat.zsh` source in `dot_zshenv`. |
| `dot_zsh/macos/` | Keep the narrow shims and `doctor.zsh`. Move `coreutils`, `rsync`, and `fzf` ownership into the Darwin package manifest; stop the installer from modifying managed `.zshenv`. Test both Apple Silicon and Intel path resolution. |
| `dot_bashrc` | Share only when a Homebrew Bash version is declared, or keep a reduced POSIX-compatible Darwin branch. Do not assume Apple's system Bash supports the current feature set. |
| `dot_tmux.conf` | Share; retain `pbcopy` support and audit environment variables that only exist under X11. |
| `dot_config/starship.toml` | Share. |
| `dot_config/helix/` | Share; verify every configured language server is installed. |
| `dot_config/ghostty/` | Share the XDG directory, which Ghostty supports on macOS, but template the contents. The current file includes GTK-only keys and i3-specific tab-bar behavior. Ghostty 1.2.3+ prefers `config.ghostty`; the existing `config` name remains a legacy fallback. Rename only after the Linux Ghostty version is verified. |
| `dot_config/zed/` | Share; Zed documents `~/.config/zed/settings.json` and `keymap.json` on both platforms. Keep SSH connections local. |
| `dot_config/bat/`, `btop/`, `fastfetch/`, `micro/`, `ranger/`, `rtk/`, `yazi/` | Share after installing each command and checking tool-specific platform options. |
| `dot_condarc.tmpl`, `private_dot_npmrc.tmpl` | Share the rendered policy, but select platform/architecture-specific runtime installations separately. |
| `dot_nanorc`, `dot_vimrc`, `dot_visidatarc`, `dot_taskrc` | Share after syntax and command-availability checks; do not infer that a similarly named Homebrew formula provides the same program. |
| `private_dot_claude/`, `private_dot_codex/` | Share only the narrow settings currently owned here and validate status-line interpreters. MCP servers, plugins, skills, hooks, auth caches, and project trust are installer/tool-owned machine state and must remain outside this repo on Darwin too. |
| `dot_local/bin/executable_weather` | Share after confirming `curl` and `jq`. |
| `dot_local/bin/executable_clipcopy` | Share; its `pbcopy` branch is the native macOS path. |

### Relocate with shared content

| Linux source/target | Darwin target | Method |
| --- | --- | --- |
| `dot_config/private_Code/User/settings.json` | `Library/Application Support/Code/User/settings.json` | Shared template with Linux/Darwin wrappers. Remove Linux interpreter paths and platform-only settings from the shared body. |
| `dot_config/private_Code/User/keybindings.json` | `Library/Application Support/Code/User/keybindings.json` | Shared template; translate only shortcuts whose modifier semantics differ. |
| Linux font directory `~/.local/share/fonts` | `~/Library/Fonts` or Homebrew font casks | Prefer verified font casks; otherwise use a Darwin-only installer. |

### Linux-only: ignore on Darwin

Do not copy these to a Mac merely because the paths are harmless:

- `dot_config/i3/` and every i3-resurrect helper.
- `dot_config/polybar/`, `dot_config/picom/`, and `dot_config/rofi/`.
- `dot_config/xfce4/`, `dot_config/fcitx5/`, the GTK theme, and Thunar
  integration already tied to `linuxmint-i3-x11`.
- `dot_config/pipewire/` and `dot_config/systemd/`.
- `dot_config/zathura/` unless a supported macOS installation is deliberately
  selected and tested.
- `executable_dot_toggle-touchpad.sh` and
  `dot_local/bin/executable_disable-trackpoint-middle-click`.
- `executable_dot_x-unstick.sh`.
- `Applications/` Helium AppImage files and the duplicate Linux desktop entry.
- `Applications/executable_update-helium.sh`.
- Linux browser chrome payloads until a native macOS browser installation and
  profile-location strategy are deliberately selected.
- Linux-only display, wallpaper, X clipboard, power-dialog, and daemon scripts.

### Rewrite before sharing

| Source | Required Darwin work |
| --- | --- |
| `executable_dot_cleanup-agents.sh` | Install modern Bash explicitly or port associative-array logic to zsh/Python. Audit BSD `stat`/`find` behavior. |
| `executable_dot_sync-zen-to-helium-bookmarks.sh` | Add `~/Library/Application Support/...` profile discovery, handle spaces safely, and retain read-only SQLite access. Never commit the resulting bookmarks. |
| `dot_zsh/macos/executable_install.zsh` | Stop appending a hook that `dot_zshenv` already manages. Let declarative provisioning install its three formulae and keep this script only for idempotent setup that cannot be expressed in source state. |
| shell startup files | Replace Linux paths and GNU-only commands with OS branches; do not globally prepend both Homebrew prefixes. Preserve the existing narrow compatibility shims instead of shadowing every BSD utility. |
| app launch helpers | Use `open -a <App>` or verified CLI entry points rather than `.desktop` files and AppImages. |

## Phase 3 — replace the X11/i3 desktop natively

Do not mechanically translate command names. macOS owns composition, display
spaces, notifications, and privacy-sensitive automation.

| Linux behavior | Recommended Darwin design | Notes |
| --- | --- | --- |
| i3 tiling and workspaces | AeroSpace in `~/.config/aerospace/aerospace.toml` | The XDG path is supported; do not also manage `~/.aerospace.toml`. Start from the current official i3-like sample, set the current `config-version`, and rebuild bindings intentionally because macOS reserves many Command shortcuts. |
| i3 window rules | AeroSpace `on-window-detected` callbacks | Match stable application bundle IDs, not transient titles. Use the current `if = 'test %{app-bundle-id} = ...'` form; the older `if.app-id` form is soft-deprecated. |
| i3-resurrect | AeroSpace persistent workspaces plus explicit app-launch commands | `persistent-workspaces` requires AeroSpace config version 2 at this review. There is no reliable generic restore of arbitrary native windows, tabs, and application state; define an accepted subset. |
| Polybar | SketchyBar in `~/.config/sketchybar/` | Scripts must be executable and use absolute or `$CONFIG_DIR`-based paths. |
| Rofi launcher | Spotlight initially; optionally Raycast/Alfred after explicit selection | Do not add a paid or account-backed launcher by assumption. |
| Picom | None | macOS supplies the compositor. Remove this layer. |
| Dunst/`notify-send` | Notification Center via `osascript`, or a verified optional notifier | Automation prompts may appear. |
| `xclip`/`xsel` | `pbcopy`/`pbpaste` | Already supported by `clipcopy`. |
| `xrandr` | System Settings first; optionally a verified display tool | Capture the desired monitor behavior, not connector names from Linux. |
| `xdotool`, `wmctrl`, `xprop`, `xwininfo` | AeroSpace CLI, app-specific APIs, or narrowly scoped AppleScript | Global inspection/input requires redesign and may require Accessibility permission. |
| `xinput`, `brightnessctl` | System Settings/Control Center or a deliberately chosen tool | Do not simulate global input or modify protected settings databases. |
| LightDM/Light Locker | macOS loginwindow and Lock Screen | Not managed by these dotfiles. |
| Thunar | Finder | Port only custom actions that have a clear native equivalent. |
| Flameshot | Native screenshot tools first | Screen Recording permission is user-controlled. |

Decide the multi-display Spaces setting before implementing the bar. Current
SketchyBar setup documentation requires **Displays have separate Spaces** to be
enabled, while AeroSpace documents different multi-monitor tradeoffs and may
recommend disabling it for some workflows. If SketchyBar is part of the
accepted profile, keep the setting enabled first and validate AeroSpace's
monitor/workspace routing under that constraint. Do not automate the setting or
assume the two tools' preferred defaults are identical.

At this review, AeroSpace's upstream documentation also states that its app is
not notarized and that the Homebrew cask handles the quarantine attribute.
Treat AeroSpace as an explicit user-approved trust decision; never generalize
that behavior into a helper that strips quarantine from arbitrary downloads.

Recommended order for the desktop layer:

1. Install AeroSpace only and reproduce focus, move, layout, workspace, and
   monitor-routing essentials.
2. Use `config-version = 2`, validate with `aerospace reload-config`, and use it
   for at least one normal work session before adding callbacks.
3. Add SketchyBar with a minimal workspace indicator only after deciding the
   **Displays have separate Spaces** behavior.
4. Port status modules one at a time, using queryable native data sources.
5. Add launchers, notification helpers, and display automation only after the
   base workflow is stable.

## Phase 4 — shell and command portability

For every shared script:

1. Check its interpreter and the version actually selected on macOS.
2. Run syntax checks with that interpreter.
3. Search for `/proc`, `/sys`, `/run/user`, `/usr/share`, apt, Flatpak,
   systemd, X11 variables, and GNU-only flags.
4. Prefer POSIX syntax where practical; otherwise declare and install the exact
   dependency (`bash`, `gnu-sed`, `coreutils`, and so on).
5. Resolve installed paths at runtime with `command -v`, `brew --prefix`, or
   chezmoi template data.

Common differences that require tests include:

- BSD `sed -i` syntax versus GNU `sed -i`.
- BSD `stat` format flags versus GNU `stat -c`.
- `date` arithmetic and formatting options.
- the absence of GNU `readlink -f` and `flock` in a default macOS install.
- case-insensitive filesystems and paths containing spaces under `~/Library`.
- GUI applications receiving a different `PATH` from interactive shells.
- X11 variables (`DISPLAY`, `XAUTHORITY`, `WINDOWID`) having no Darwin meaning.

Do not “solve” portability by installing every GNU replacement and shadowing
system tools globally. Use explicit executable names (`gsed`, `gstat`) or a
script-local Homebrew path when GNU behavior is genuinely required.

The current `dot_zsh/macos/bin/` directory follows this rule for the few
incompatibilities already demonstrated by the shared rc modules. Extend those
shims only from a failing Darwin test; their existence is not proof that the
rest of the shell or provisioning scripts are portable.

## Phase 5 — privacy and macOS permissions

The public repository intentionally omits browser profiles, bookmarks, SSH
endpoints, agent trust lists, and personal project paths. Keep that boundary on
macOS:

- Reinstall browsers and use their supported account sync or a private export;
  never add `~/Library/Application Support/<browser>` to chezmoi.
- Keep SSH configuration and keys local. If a reusable, non-sensitive SSH
  fragment is later added, isolate it from hostnames, usernames, and key paths.
- Store tokens in Keychain, a password manager, environment injection, or the
  local chezmoi config—not in templates committed to Git.
- Let the user grant Accessibility, Automation, Screen Recording, and Full
  Disk Access in System Settings. Never edit or copy a TCC database.
- Document each requested permission, which executable receives it, and the
  feature that fails without it. Grant the smallest useful set.

## Phase 6 — verification sequence

### Linux regression gate

Run on the existing Linux machine before testing Darwin:

```sh
chezmoi data | jq '.chezmoi | {os, arch, homeDir}'
chezmoi execute-template < each-changed-file.tmpl
chezmoi diff
chezmoi status
chezmoi apply --dry-run --force
shellcheck changed-linux-shell-scripts
bash -n changed-bash-scripts
zsh -n dot_zshrc
```

The Darwin additions must not alter rendered Linux files unless the change is
an intentional portability fix reviewed on Linux.

### Darwin render gate

Before access to a Mac, run a synthetic render audit from Linux. Override only
the platform facts and non-secret profile choices; retain the real source
directory so `include` and `lstat` calls still work:

```sh
darwin_data='{"chezmoi":{"os":"darwin","arch":"arm64","homeDir":"/Users/audit"},"class":"desktop","desktopProfile":"none"}'
chezmoi --override-data "$darwin_data" managed

for source_file in run_*; do
    printf '%s: ' "$source_file"
    chezmoi --override-data "$darwin_data" execute-template --file "$source_file" |
        sed -n '1p'
done
```

Run this for both `arm64` and `amd64`. It catches template/ignore leaks but
cannot validate BSD utilities, Homebrew, GUI paths, permissions, or actual app
behavior.

On the Mac, before any apply:

```sh
chezmoi data | jq '.chezmoi | {os, arch, homeDir}'
chezmoi ignored
chezmoi managed
chezmoi status
chezmoi diff
chezmoi apply --dry-run --verbose
```

The output must contain no apt, Flatpak, Linux Miniconda, i3, Polybar, Picom,
Rofi, AppImage, `/home/...`, X11, or Linux service actions.

Then apply in narrow groups:

1. Git and shell-independent CLI configs.
2. Zsh startup files in a second terminal session.
3. Editors and terminal configuration.
4. Homebrew package provisioning.
5. AeroSpace.
6. SketchyBar and helper scripts.
7. Remaining optional GUI integrations.

After each group, inspect `chezmoi diff` again and retain a working terminal
that is not using the newly edited shell configuration.

### Static and CI checks

- `shellcheck` for POSIX/Bash scripts and `bash -n` with the declared Bash.
- `zsh -n` for Zsh files.
- `~/.zsh/macos/doctor.zsh` on each supported Mac architecture after Homebrew
  provisioning.
- `plutil -lint` for any generated plist.
- JSON/JSONC/TOML validators for rendered configs.
- `brew bundle check` against the rendered Brewfile.
- A macOS CI job may validate rendering and syntax, but it cannot prove GUI
  behavior or grant privacy permissions.
- Run Gitleaks against the final Git history before publication.

## Acceptance criteria

A coding agent may call the macOS port complete only when all boxes are true:

- [ ] Current Linux `chezmoi apply --dry-run --force` still succeeds.
- [ ] Darwin dry-run renders no Linux package, AppImage, X11, or `/home` paths.
- [ ] Every Darwin-managed application is installed by the package manifest or
      explicitly documented as a manual prerequisite.
- [ ] Shared configurations have one canonical source template.
- [ ] Git, Zsh, tmux, Starship, Helix, Ghostty, Zed, VS Code, bat, btop, and
      Yazi start with their intended configuration.
- [ ] AeroSpace covers the agreed focus/move/layout/workspace workflow.
- [ ] SketchyBar, if included, starts at login and survives reload.
- [ ] Clipboard, launcher, notifications, screenshots, and display behavior
      have tested native equivalents or explicit documented omissions.
- [ ] Scripts pass the declared interpreter and BSD/GNU compatibility tests.
- [ ] `~/.zsh/macos/doctor.zsh` passes after declarative package provisioning.
- [ ] Required macOS privacy permissions are documented and manually granted.
- [ ] Browser profiles, SSH details, project trust, secrets, device IDs, and
      TCC data are absent from Git and from the rendered public profile.
- [ ] Gitleaks reports no findings in the final history.
- [ ] README bootstrap instructions clearly distinguish Linux from macOS.

## Agent handoff format

If the work stops before completion, leave a concise status block in the pull
request or task response:

```text
Completed phases:
Current macOS version/architecture:
Linux regression result:
Darwin dry-run result:
Packages/configs added together:
Manual permissions still required:
Known behavioral gaps:
Next exact file/command to inspect:
```

Do not mark the port complete because files render. The desktop equivalence and
fresh-machine package/config pairing are part of the deliverable.

## Official references

- [chezmoi template variables](https://www.chezmoi.io/reference/templates/variables/)
- [chezmoi machine-to-machine differences and shared templates](https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/)
- [chezmoi scripts and OS-gated package examples](https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/)
- [chezmoi declarative package installation](https://www.chezmoi.io/user-guide/advanced/install-packages-declaratively/)
- [Homebrew installation and supported prefixes](https://docs.brew.sh/Installation)
- [Homebrew Bundle and Brewfile](https://docs.brew.sh/Brew-Bundle-and-Brewfile)
- [Apple Command Line Tools installation](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools)
- [AeroSpace guide](https://nikitabobko.github.io/AeroSpace/guide)
- [SketchyBar setup](https://felixkratz.github.io/SketchyBar/setup)
- [Ghostty configuration locations](https://ghostty.org/docs/config)
- [VS Code settings locations](https://code.visualstudio.com/docs/configure/settings)
- [Zed configuration locations](https://zed.dev/faq)
- [Apple Accessibility permission guidance](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac)
- [Apple screen and system-audio recording permissions](https://support.apple.com/guide/mac-help/mchld6aa7d23/mac)

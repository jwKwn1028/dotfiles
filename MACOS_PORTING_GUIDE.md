# Porting This Chezmoi Setup to macOS

Last audited against the repository and upstream documentation: 2026-09-27

Implementation contract: workflow parity, target isolation, provisioning, and verification for a parallel macOS profile.

**Fresh macOS apply is unsafe.** Do not run `chezmoi init --apply` until Phase 1 provisioning/isolation gates and the synthetic Darwin audit pass.

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

1. Read AGENTS.md, this contract, and current packages/scripts first.
2. Add Darwin counterparts; retain i3/Polybar/Picom/Rofi as the Linux fallback.
3. Branch on `.chezmoi.os`, and `.chezmoi.arch` for architecture-specific artifacts.
4. Never branch on usernames/hostnames or infer Homebrew from a prefix; use `brew --prefix`.
5. Share `.chezmoitemplates/` content through platform wrappers.
6. Land packages and consuming configs together.
7. Keep browser data, SSH keys/aliases, trust, Keychain exports, tokens, device IDs, and TCC data local.
8. Users grant Accessibility, Automation, Screen Recording, and Full Disk Access manually.
9. Render, inspect, dry-run, then apply narrow groups before a full apply.
10. Preserve user changes and the Linux target.

## Current implementation snapshot

Source audit: 2026-09-27, chezmoi 2.72.2, darwin/arm64, desktop/none; no real
Mac validation. arm64/amd64 renders were identical. Darwin-specific code existed
only in `dot_zsh/macos/`; other gates excluded Linux.

Implemented: separate class/profile selection; X11 tree exclusions; empty apt,
input, TLP, logind, screenshot, and source-build renders; browser skip guards;
narrow Zsh date/wc/systemctl/clipboard/rsync/fzf shims and doctor; pbcopy support;
Linux gates for restic/Tailscale; local SSH values and OS-gated ProxyCommand.
`docs.md` documents audit-only use.

Remaining blockers:

- Flatpak, CLI/Miniconda, fonts, and default-shell provisioning still render
  Linux assumptions. The shell script needs `.tmpl`; runtime command guards
  cannot prevent downloading a valid but wrong Linux artifact.
- No Darwin package section/Homebrew provisioning. Keep apt source-build
  dependencies Linux-only; move macos/install.zsh dependencies into the manifest
  and stop it appending to managed `.zshenv`.
- Codex modify_ needs `/usr/bin/python3` + tomlkit (otherwise pass-through);
  Claude modify_ needs Python on PATH through CLT/Homebrew.
- fd's Debian symlink renders empty on Mac: managed but silently uncreated.
  Declare native fd; Yazi also needs a package declaration so its cross-platform
  `ya pkg install` can run. Keep that plugin script cross-platform.
- Exclude remaining Linux payloads and empty directories listed in Phase 2.
- Git selects libsecret/cache, not osxkeychain. Shared paths and GNU/BSD flags
  need tests. Bash config/cleanup require modern Bash.

Make Linux-only templates render empty, retaining Linux output:

```gotemplate
{{ if eq .chezmoi.os "linux" -}}
#!/usr/bin/env bash
# Existing Linux-only script body.
{{ end -}}
```

Rename the shell installer to
`.chezmoiscripts/run_once_after_40-set-default-shell.sh.tmpl` before gating it.

## Recommended source-state architecture

Use OS selection and shared templates, not duplicated hand-maintained files.
A mature layout should resemble:

```text
.chezmoidata/packages.toml
.chezmoiscripts/
  run_onchange_before_15-install-homebrew-packages.sh.tmpl
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
```

`.chezmoiignore` matches whole target paths, without a leading slash. Gate entire trees; retain its profile prelude and add `macos-aerospace` only with a working desktop.

Extend the existing X11 profile block. Add Linux-only exclusions beside the restic/Tailscale guards:

```gotemplate
{{ if ne .chezmoi.os "linux" }}
.config/pipewire/
.config/systemd/
.config/zathura/
.config/i3-resurrect/
.config/flameshot/
.config/fontconfig/
.local/bin/cpu-load
.local/bin/fd
.local/bin/tests/
.local/share/applications/helium.desktop
.local/share/helium-newtab/
.sync-zen-to-helium-bookmarks.sh
Applications/
{{ end }}

{{ if ne $desktopProfile "macos-aerospace" }}
.config/aerospace/
.config/sketchybar/
{{ end }}

{{ if ne .chezmoi.os "darwin" }}
Library/Application Support/Code/User/
{{ end }}
```

Ignore whole directories to remove empty targets. Keep macOS `~/Applications`
unmanaged; the current payload is a Linux AppImage launcher.

Exclude Linux test suites wholesale; re-admit each alongside its port.

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

Audit baseline: Homebrew requires Sequoia 15+ on supported hardware. Recheck
upstream requirements for the target Mac.

Keep class as desktop/server workload, not OS. Darwin defaults to profile none
until macos-aerospace packages, ignores, config, and verification land together.

## Phase 1 — make provisioning safe

### 1. Gate all Linux provisioning

Gate Flatpak, CLI/Miniconda, fonts, and the renamed default-shell template.
Prefer empty renders, which chezmoi never executes; verify Linux renders remain
unchanged. Leave cross-platform Yazi plugin installation command-guarded.
Eventually make browser skip-only renders empty too.

### 2. Bootstrap Homebrew explicitly

Homebrew requires CLT and explicit user-approved bootstrap; never pipe its
installer silently from apply. Discover it initially at the supported prefixes,
then use `brew --prefix`. Seed the login environment in `dot_zprofile.tmpl`:

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
    "bash", "bat", "btop", "cmake", "coreutils", "eza", "fd", "fzf", "git",
    "git-lfs", "helix", "jq", "micro", "node", "pipx", "pkg-config",
    "ranger", "ripgrep", "rsync", "sevenzip", "shellcheck", "sketchybar",
    "starship", "task", "tmux", "tree", "wget", "yazi", "zoxide",
]
casks = [
    "ghostty", "visual-studio-code", "zed",
    "nikitabobko/tap/aerospace",
]
```

Review third-party taps; use narrow formula/cask trust declarations when
required, keeping trust visible in the Brewfile. A run_onchange_ template should
render a temporary Brewfile, run `brew bundle --file="$brewfile"`, and fail with
a manual-bootstrap message if brew is absent. Reuse it for `brew bundle check`.

Declare coreutils, rsync, fzf, starship, eza, zoxide, yazi, and fd: shared shell
modules and plugin setup depend on them. Declare modern Bash for .bashrc,
Claude's status line, and cleanup. Stop macos/install.zsh modifying `.zshenv`;
retain doctor.zsh. Test both architectures. Verify Rust crates on Darwin and
choose one installer owner (cargo or Brewfile).

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
| `dot_profile` | Share; the optional `.local/bin/env` and Cargo sources are guarded, and the juliaup block only edits `PATH`. |
| `dot_zshrc`, `dot_zprofile`, `dot_zshenv` | The modular Zsh loader and Darwin prelude now exist. Convert path-bearing files to templates; discover Homebrew/Go rather than retaining `/usr/local/go`, and treat FullProf, VESTA, and Quantum ESPRESSO paths as explicit optional software. Keep the existing guarded `macos/compat.zsh` source in `dot_zshenv`. |
| `dot_zsh/macos/` | Keep the narrow shims and `doctor.zsh`. Move `coreutils`, `rsync`, and `fzf` ownership into the Darwin package manifest; stop the installer from modifying managed `.zshenv`. Test both Apple Silicon and Intel path resolution. |
| `dot_bashrc` | Share only when a Homebrew Bash version is declared, or keep a reduced POSIX-compatible Darwin branch. Do not assume Apple's system Bash supports the current feature set. |
| `dot_tmux.conf` | Share; retain `pbcopy` support and audit environment variables that only exist under X11. |
| `dot_config/starship.toml` | Share. |
| `dot_config/helix/` | Share; verify every configured language server is installed. |
| `dot_config/ghostty/` | Share the XDG directory, which Ghostty supports on macOS, but template the contents. The current file includes GTK-only keys and i3-specific tab-bar behavior. Ghostty 1.2.3+ prefers `config.ghostty`; the existing `config` name remains a legacy fallback. Rename only after the Linux Ghostty version is verified. |
| `dot_config/zed/` | Share settings/keymap paths; keep SSH local. Choose fonts/sizes per OS in `.chezmoitemplates/zed-settings.jsonc` (currently 8.9pt with Ubuntu Mono fallback). |
| `dot_config/bat/`, `btop/`, `fastfetch/`, `micro/`, `ranger/`, `rtk/`, `yazi/` | Share after installing each command and checking tool-specific platform options. |
| `dot_condarc.tmpl`, `private_dot_npmrc.tmpl` | Share the rendered policy, but select platform/architecture-specific runtime installations separately. |
| `dot_nanorc`, `dot_vimrc`, `dot_visidatarc`, `dot_taskrc` | Share after syntax and command-availability checks; do not infer that a similarly named Homebrew formula provides the same program. |
| `private_dot_claude/`, `private_dot_codex/` | Share only managed settings; verify Python/status-line interpreters because `modify_` scripts execute on Darwin. Keep MCP, plugins, skills, hooks, auth, and project trust installer-owned and local. |
| `dot_local/bin/executable_weather` | Share after confirming `curl` and `jq`. |
| `dot_local/bin/executable_clipcopy` | Share; its `pbcopy` branch is the native macOS path. |
| `.chezmoiexternal.toml` | Share. The five archives are pure Zsh/Vim plugins pinned to checksummed commits, so they are portable; they only need network access at apply time and a matching checksum, and a mismatch fails the Darwin apply exactly as it fails the Linux one. |

### Relocate with shared content

| Linux source/target | Darwin target | Method |
| --- | --- | --- |
| `dot_config/private_Code/User/settings.json` | `Library/Application Support/Code/User/settings.json` | Shared template with Linux/Darwin wrappers. Remove Linux interpreter paths and platform-only settings from the shared body. |
| `dot_config/private_Code/User/keybindings.json` | `Library/Application Support/Code/User/keybindings.json` | Shared template; translate only shortcuts whose modifier semantics differ. |
| Linux font directory `~/.local/share/fonts` | `~/Library/Fonts` or Homebrew font casks | Prefer verified font casks; otherwise use a Darwin-only installer. |

### Linux-only: ignore on Darwin

Do not copy these to a Mac merely because the paths are harmless:

- `dot_config/i3/`, `dot_config/i3-resurrect/`, and every i3-resurrect helper.
  The resurrect config is a separate target tree, so the desktop-profile block
  does not catch it.
- `dot_config/polybar/`, `dot_config/picom/`, and `dot_config/rofi/`.
- `dot_config/xfce4/`, `dot_config/private_fcitx5/`, the GTK theme, and Thunar
  integration already tied to `linuxmint-i3-x11`.
- `dot_config/pipewire/` and `dot_config/systemd/`.
- `dot_config/zathura/` unless a supported macOS installation is deliberately
  selected and tested.
- `dot_local/bin/executable_touchpad` and its
  `executable_dot_toggle-touchpad.sh` compatibility wrapper.
- `dot_config/flameshot/` and `dot_config/fontconfig/`.
- `dot_local/bin/executable_cpu-load`, which parses `/proc/stat`;
  `dot_local/bin/symlink_fd.tmpl`, which exists only for Debian's `fdfind`
  name; and the `dot_local/bin/tests/` suites.
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

Decide **Displays have separate Spaces** before the bar. SketchyBar requires it;
test AeroSpace routing with it enabled. Do not automate the setting or assume
both tools prefer the same default.

AeroSpace was unnotarized at audit; its cask handles quarantine. Require explicit
user trust, and never strip quarantine from arbitrary downloads.

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

Use explicit gsed/gstat or script-local paths where GNU behavior is required;
never shadow all system utilities.

Extend `dot_zsh/macos/bin/` shims only from failing Darwin tests; they do not
prove the rest of the profile portable.

## Phase 5 — privacy and macOS permissions

The public repository intentionally omits browser profiles, bookmarks, SSH
endpoints, agent trust lists, and personal project paths. Keep that boundary on
macOS:

- Reinstall browsers and use their supported account sync or a private export;
  never add `~/Library/Application Support/<browser>` to chezmoi.
- Keep SSH keys, `known_hosts`, and control sockets local. The one managed
  fragment, `private_dot_ssh/private_config.tmpl`, already takes its aliases,
  hostnames, and username from `~/.config/chezmoi/chezmoi.toml` and keeps the
  Linux `ProxyCommand` behind an OS test. Preserve that split; a Darwin render
  must not introduce a literal host or user.
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

for source_file in .chezmoiscripts/run_*; do
    printf '%s: ' "$source_file"
    chezmoi --override-data "$darwin_data" execute-template --file "$source_file" |
        sed -n '1p'
done
```

Audit both arm64 and amd64. Identical renders do not validate architecture choices, BSD utilities, packages, GUI paths, permissions, or runtime behavior.

Overrides change template data, not the host. `lookPath` still uses host PATH; `.chezmoi.sourceDir` stays real (including the Git-hook template path). `lstat`/`include` follow supplied paths: a synthetic home can produce misleading `missing` profile hashes. Check apparent leaks against templates; verify reruns on a Mac.

Point the audit at an empty directory as well, so the Darwin render is compared
against nothing instead of against the live Linux home:

```sh
audit_dest="$(mktemp -d)"
chezmoi --override-data "$darwin_data" --destination "$audit_dest" status
```

An empty destination exposes fresh targets as `A` without writes. Limits: empty scripts still show `R`, so inspect `execute-template`; empty symlinks remain `managed` but disappear from status/apply (notably fd).

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

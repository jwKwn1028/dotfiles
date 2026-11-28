# Usage

Daily use and recovery; [application guides](README.md#documentation).
Keep endpoints, identities, private paths, and backup data local.

## Day-to-day

```sh
chezmoi edit <file> # edit source state
chezmoi diff        # preview changes
chezmoi apply       # apply; reruns changed run_once_* scripts
chezmoi re-add      # import local edits
chezmoi update      # git pull + apply
```

Document conversion and Typst layouts:
[Pandoc and Typst presets](dot_local/share/pandoc/docs.md).

Terminal PDF viewer: [fancy-cat manual](dot_config/fancy-cat/MANUAL.md).

## fancy-cat, hxp, and remote-tools

Each lives in its own repository. This repo pins a pushed commit for fresh
machines and owns the config around it; an existing checkout is never fetched
or switched.

| Project | Checkout | Pin (`.chezmoidata/packages.toml`) | Installed by |
|---|---|---|---|
| fancy-cat | `~/.local/src/fancy-cat`, branch `zathura` | `packages.source.fancy_cat.fork_commit` | `after_98`: builds `~/.local/bin/fancy-cat` |
| hxp | `~/Applications/hxp` | `packages.git.hxp.commit` | `after_99`: clones if missing, runs `install.sh --no-config` |
| remote-tools | `~/Applications/remote-tools` | `packages.git.remote_tools.commit` | `after_99`: clones if missing; zsh sources `shell/jobmon.zsh` |

To change one, commit and push in its repository, then set its pin to that
commit and commit here. hxp and remote-tools edits apply at once; fancy-cat
rebuilds from the local `zathura` tip on the next `chezmoi apply`.
`./run-tests.sh` fails while a pin is unpushed or lacks what these configs use.
Fresh clones need `githubUser`.

## Agent cleanup

Preview with `~/.cleanup-agents.sh`; quit Claude Code and Codex before adding
`--apply`. Chats and memory need confirmation; beyond them, only known caches
and session state are removed.

## bashrc

`dot_bashrc` works on remote clusters without desktop provisioning.
Test: `bash dot_local/bin/tests/executable_test-bashrc.sh`.

## Recover a Linux i3 desktop

For x86_64, `class=desktop`, `desktopProfile=linuxmint-i3-x11`.
Steps 1–5 restore managed files; 6–10 restore local state. Check
[hardware assumptions](HARDWARE.md) on other machines.

### 1. Install the base system

Install Mint 22.3 or Ubuntu 24.04 (Ubuntu also needs `flatpak`), then:

```sh
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl python3 python3-tomlkit
```

### 2. Bootstrap chezmoi

Use the upstream binary, not an apt package:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
chezmoi init 'https://github.com/OWNER/REPOSITORY.git'
```

`init` prompts for identity, profile, endpoints, screenshot path, and optional
birthday (`MM-DD`); answers stay in `~/.config/chezmoi/chezmoi.toml`.

### 3. Review

```sh
chezmoi status
chezmoi diff | less
chezmoi apply --dry-run --force --verbose | less
```

`--force` only suppresses prompts here; without `--dry-run` it overwrites drift.

### 4. Apply

Run `chezmoi apply -v` interactively. Scripts in `.chezmoiscripts/` execute
without creating that target directory. Order:

| Script suffix | Installs/configures |
| --- | --- |
| `before_10` | Manifest apt packages/PPAs; externals follow. |
| `after_05` | Git privacy hooks. |
| `after_20` | Flatpaks. |
| `after_30` | pipx, Rust/cargo, Starship, zoxide, Miniconda. |
| `after_35` | Pinned Yazi plugins; retries when ya is available. |
| `after_40` | Zsh login shell (password prompt). |
| `after_50` | Fonts. |
| `after_60/62/65/70` | Browser/mail profiles. |
| `after_90/91/92` | X11 input, TLP, screenshot path. |
| `after_93/94` | Lid policy, GTK/XFConf, Thunar folder settings. |
| `after_95/96/97/98` | Pinned i3lock-color, Zathura, btop (g++-14), fancy-cat; sudo for dependencies. |
| `after_99` | Pinned Ghostty AppImage (replaces apt/PPA); missing hxp/remote-tools checkouts from githubUser, with `hxp/install.sh --no-config`. Existing checkouts stay untouched. |

`run_once_` tracks successful rendered content; `run_onchange_` also tracks its
path, so moving it can rerun it. Cargo/font/project failures do not stop other
items; fix errors and apply again. Installed items are skipped.

### 5. Start i3

Log out, pick **i3** in LightDM, and log back in.

### 6. Install deliberate gaps as needed

- **Helium:** `~/Applications/update-helium.sh` downloads its AppImage and
  updates `helium.desktop`.
- **Taskwarrior:** install upstream `task` 3.x; apt's 2.6.2 cannot read the
  sqlite data `dot_taskrc` targets. Enable reminders with
  `systemctl --user daemon-reload && systemctl --user enable --now task-notify.timer`.
  See `~/.config/task/MANUAL.md`.
- **Session recovery.** `Super+Ctrl+P` restores i3 and reattaches Ghostty.
  `C-b C-r` restores tmux; `C-b C-s` saves. Panes resume Claude Code, Codex,
  and `hxp` (after Ghostty attaches). Helix reopens its files, cursors and simple
  splits ([limits](dot_config/helix/docs.md#session-recovery)).
  Enable 15-minute saves with `systemctl --user daemon-reload && systemctl --user enable --now tmux-resurrect-save.timer i3-resurrect-save.timer`.
  See the [i3 manual](dot_config/i3/MANUAL.md#i3-resurrect-save-and-restore).
- **Tmux window names.** Editors show their active file (24 cells), also under
  Yazi; Helix, Micro, nano and Vim follow buffer switches within a second.
- **hxp:** Ctrl+L jumps between the editor (Helix, Micro) and fancy-cat.
- **npm:** install NodeSource's `nodejs`, which bundles npm; apt's `npm`
  conflicts with it, so the manifest installs `nodejs` alone. `~/.npmrc` puts
  global packages in `~/.local/npm-global`.
- **Optional scientific software:** nothing installs it; `.zshenv` adds its
  usual paths to PATH, harmless when missing.

Claude Code/Codex plugins, skills, MCP servers, and hooks stay installer-owned
and unmanaged.

### 7. Configure new profiles

Launch/quit Zen, Firefox, Thunderbird, and Helium; rerun `chezmoi apply -v`.
`profiles.ini` changes retrigger the first three; first appearance of Helium's
`Preferences` retriggers Helium. Close Helium before applying its settings.

### 8. Restore private state

- **SSH:** restore `~/.ssh/id_ed25519`, which the rendered SSH config expects,
  or generate one with `ssh-keygen -t ed25519` and register it. Then switch the
  source repo to SSH:

  ```sh
  git -C "$(chezmoi source-path)" remote set-url origin \
      'git@github.com:OWNER/REPOSITORY.git'
  ```

- **GPG/pass:** import the secret key and restore the password store with its
  `.gpg-id`; run `pass init <key-id>` only for a new store or missing `.gpg-id`.
- **Browsers/mail:** restore bookmarks, extensions, accounts, and mail by sync
  or private export; never manage whole profiles with chezmoi.
- **Restic:** restore the externally backed-up `~/.config/restic/password`,
  mode 0600.
- **Personal data:** mount the backup and restore into a temporary directory
  first. Repositories sit under the old short hostname:

  ```sh
  chmod 600 ~/.config/restic/password
  find /mnt/backup/restic -mindepth 2 -maxdepth 2 -type d -name home -print
  old_repo=/mnt/backup/restic/OLD_HOST/home
  restic -r "$old_repo" --password-file ~/.config/restic/password snapshots
  restic -r "$old_repo" --password-file ~/.config/restic/password \
    restore latest --target /tmp/restic-restore
  ```

  Inspect the restore before copying anything home.

### 9. Re-establish backups

See `~/.config/restic/README.md`. Mount the backup filesystem at `/mnt/backup`
through a `nofail` UUID fstab entry, verify it, and create the writable parent:

```sh
mountpoint /mnt/backup
sudo install -d -m 0750 -o "$USER" -g "$(id -gn)" /mnt/backup/restic
```

The wrapper uses `/mnt/backup/restic/$(hostname -s)/{home,system}`: the old
hostname and password continue those repositories; a new hostname adds a
sibling.

```sh
restic-backup init
sudo ~/.local/bin/restic-backup init-system
restic-backup home
sudo ~/.local/bin/restic-backup system
systemctl --user daemon-reload
systemctl --user enable --now restic-backup.timer restic-maintenance.timer
```

`restic-backup init` verifies an existing repository or initializes a missing
one, generating the password only if absent.

### 10. Verify

```sh
chezmoi status
~/.config/i3/tests/run-fast.sh
~/.config/polybar/tests/test-launch.sh
~/.local/bin/tests/test-weather.sh # plus the directory's other tests
```

Some drift from tool-owned files is expected. `~/.config/i3/MANUAL.md` covers
manual checks and keybindings.

## macOS: audit only

Until [Phase 1 gates and Darwin checks](MACOS_PORTING_GUIDE.md) pass, macOS
allows only source init, read-only rendering, and port development. Never run
`init --apply`, bare `apply`, or provisioning there. Install chezmoi/jq separately:

```sh
chezmoi init 'https://github.com/OWNER/REPOSITORY.git'
chezmoi data | jq '.chezmoi | {os, arch, homeDir}' # expect os = darwin
chezmoi ignored
chezmoi managed
chezmoi diff
chezmoi apply --dry-run --verbose
```

# Usage

Operating manual for this chezmoi source: daily commands, recovering a Linux i3
desktop, and the macOS boundary. [`README.md`](README.md) describes the repo
and [indexes the application guides](README.md#documentation). Examples are
generic; real SSH endpoints, account and machine names, private project paths,
and backup contents stay in local configuration or state.

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

## bashrc

`dot_bashrc` targets remote clusters with only basic tools and can be copied to
`~/.bashrc` without desktop provisioning. Test it with
`bash dot_local/bin/tests/executable_test-bashrc.sh`.

## Recover a Linux i3 desktop

For `class = desktop` and `desktopProfile = linuxmint-i3-x11` on x86_64. Steps
1–5 restore managed state; 6–10 restore what is deliberately kept out of Git.

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

`init` prompts for Git identity, machine class and desktop profile, SSH and
Tailscale endpoints, the screenshot directory, and an optional `MM-DD` birthday
banner. The answers live only in `~/.config/chezmoi/chezmoi.toml`.

### 3. Review

```sh
chezmoi status
chezmoi diff | less
chezmoi apply --dry-run --force --verbose | less
```

`--force` only suppresses prompts here; without `--dry-run` it overwrites drift.

### 4. Apply

Run `chezmoi apply -v` in an interactive terminal. In order:

1. `run_once_before_10`: apt sets from `.chezmoidata/packages.toml`, then the
   files and clones in `.chezmoiexternal.toml`.
2. `run_once_after_05`: point the source repo's Git hooks at `.githooks`.
3. `run_once_after_20`: Flathub apps.
4. `run_once_after_30`: profile-specific pipx apps, rustup, cargo crates
   (including Taskwarrior TUI), Starship, zoxide, and Miniconda.
5. `run_onchange_after_35`: Yazi plugins locked in
   `dot_config/yazi/package.toml`; re-runs once `ya` is on PATH.
6. `run_once_after_40`: add zsh to `/etc/shells` and `chsh` (password prompt).
7. `run_once_after_50`: fonts into `~/.local/share/fonts`.
8. `run_onchange_after_60/62/65/70`: browser and Thunderbird profiles.
9. `run_after_90/91`: X11 keyboard/TrackPoint and TLP configuration.
10. `run_onchange_after_92`: the Flameshot screenshot directory.
11. `run_after_93`: the logind lid-switch drop-in.
12. `run_once_after_95/96`: build pinned i3lock-color into `/usr/local` and
    zathura into `~/.local`, installing build dependencies with sudo.

The cargo and font installers continue past individual failures, then report
provisioning as failed. Fix the cause and rerun `chezmoi apply -v`; installed
tools and fonts are skipped.

### 5. Start i3

Log out, pick **i3** in LightDM, and log back in.

### 6. Install deliberate gaps as needed

- **Helium:** `~/Applications/update-helium.sh` downloads its AppImage and
  updates `helium.desktop`.
- **Taskwarrior:** install upstream `task` 3.x; apt's 2.6.2 cannot read the
  sqlite data `dot_taskrc` targets. Enable reminders with
  `systemctl --user daemon-reload && systemctl --user enable --now task-notify.timer`.
  See `~/.config/task/MANUAL.md`.
- **npm:** install NodeSource's `nodejs`, which bundles npm; apt's `npm`
  conflicts with it, so the manifest installs `nodejs` alone. `~/.npmrc` puts
  global packages in `~/.local/npm-global`.
- **Optional scientific software:** nothing installs it; `.zshenv` adds it to
  PATH only when present.

Claude Code/Codex plugins, skills, MCP servers, and hooks stay installer-owned
and unmanaged.

### 7. Configure new profiles

Launch and quit Zen, Firefox, Thunderbird, and Helium once, then rerun
`chezmoi apply -v`. The first three retrigger on their `profiles.ini` hash,
installing sanitized `user.js` and Zen/Thunderbird `chrome/` customizations.
Helium has no `profiles.ini`: its script retriggers when `Preferences` goes from
missing to present, without hashing the mutable profile. If Helium is running,
that step reports a failure; close Helium and apply again.

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

Scratch recovery is unsupported: never run `chezmoi init --apply`, a bare
`chezmoi apply`, or provisioning scripts on macOS.
[MACOS_PORTING_GUIDE.md](MACOS_PORTING_GUIDE.md) is the canonical inventory,
contract, and verification sequence. Until its Phase 1 gates and Darwin checks
pass, only source init, read-only rendering, and port development are allowed.
Install chezmoi and `jq` separately; the safe boundary is:

```sh
chezmoi init 'https://github.com/OWNER/REPOSITORY.git'
chezmoi data | jq '.chezmoi | {os, arch, homeDir}' # expect os = darwin
chezmoi ignored
chezmoi managed
chezmoi diff
chezmoi apply --dry-run --verbose
```

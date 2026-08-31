# dotfiles

Personal [chezmoi](https://chezmoi.io) configuration and provisioning for a
reproducible **Linux Mint 22.3 / Ubuntu 24.04** i3/X11 machine.

## Day-to-day

```sh
chezmoi edit <file> # edit source state
chezmoi diff        # preview changes
chezmoi apply       # apply; reruns changed run_once_* scripts
chezmoi re-add      # import local edits
chezmoi update      # git pull + apply
```

## Recover a Linux i3 desktop

Use `class = desktop` and `desktopProfile = linuxmint-i3-x11` on x86_64.
Steps 1–5 restore managed state; 6–10 restore everything deliberately kept out
of Git.

### 1. Install the base system

Install Mint 22.3 or Ubuntu 24.04, then:

```sh
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl
```

On Ubuntu also run `sudo apt install -y flatpak`.

### 2. Bootstrap chezmoi

Install the upstream binary (not an apt package here), then initialize:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
chezmoi init 'https://github.com/OWNER/REPOSITORY.git'
```

The bootstrap prompts for Git identity and the optional `MM-DD` birthday banner
value; those answers live only in `~/.config/chezmoi/chezmoi.toml`.

### 3. Review

```sh
chezmoi status
chezmoi diff | less
chezmoi apply --dry-run --verbose | less
```

### 4. Apply

Run `chezmoi apply -v` in an interactive terminal. In order:

1. `run_once_before_10-install-apt-packages`: install apt sets from
   `.chezmoidata/packages.toml`, write and clone files from
   `.chezmoiexternal.toml`.
2. `run_once_after_20`: install Flathub apps.
3. `run_once_after_30`: install profile-specific pipx apps, rustup, cargo
   crates, Starship, zoxide, and Miniconda.
4. `run_once_after_40`: add zsh to `/etc/shells` and run `chsh` (password
   prompt).
5. `run_once_after_50`: install fonts in `~/.local/share/fonts`.
6. `run_onchange_after_60/62/65/70`: configure browser/Thunderbird profiles.
7. `run_after_90/91`: install X11 keyboard/TrackPoint/TLP configuration.

### 5. Start i3

Log out, select **i3** in LightDM, and log back in.

### 6. Install deliberate gaps as needed

- **Helium:** run `~/Applications/update-helium.sh` to download its AppImage
  and update `helium.desktop`.
- **Taskwarrior:** install upstream `task` 3.x; apt's 2.6.2 flat-file binary
  cannot read the sqlite data targeted by `dot_taskrc`. Then switch on
  reminders: `systemctl --user daemon-reload && systemctl --user enable --now
  task-notify.timer`. See `~/.config/task/MANUAL.md`.
- **i3-resurrect:** `pipx install i3-resurrect`; helpers expect
  `~/.local/bin/i3-resurrect`.
- **Optional scientific software:** `.zshenv` adds it to PATH when present;
  nothing installs it, and absent paths are inert.

Claude Code/Codex plugins, skills, MCP servers, and hooks remain installer-owned
and intentionally unmanaged.

### 7. Configure new profiles

Launch and quit Zen, Firefox, Thunderbird, and Helium once, then run:

```sh
chezmoi apply -v
```

Zen, Firefox, and Thunderbird retrigger on their `profiles.ini` hash, installing
sanitized `user.js` and Zen/Thunderbird `chrome/` customizations. Helium has no
`profiles.ini`, so its script hashes the presence of `Preferences` without
hashing the mutable profile itself. Creating the profile changes that marker
from `missing` to `present` and automatically retriggers the merge. If Helium is
running, the apply reports the deferred step as a failure; close Helium and run
`chezmoi apply -v` again.

### 8. Restore private state

- **SSH:** restore `~/.ssh/id_ed25519`, expected by the step 2 rendered config,
  or run `ssh-keygen -t ed25519` to register. Then switch source repo to SSH:

  ```sh
  git -C "$(chezmoi source-path)" remote set-url origin \
      'git@github.com:OWNER/REPOSITORY.git'
  ```

- **GPG/pass:** import the secret key and restore the password store with its
  `.gpg-id`; use `pass init <key-id>` only for a new store or missing `.gpg-id`.
- **Browsers/mail:** restore bookmarks, extensions, accounts, and mail via sync
  or private export; never manage whole profiles with chezmoi.
- **Restic:** restore the externally backed-up `~/.config/restic/password`,
  mode 0600.
- **Personal data:** mount the backup and restore to a temporary directory
  first. Repositories sit below the old short hostname:

  ```sh
  chmod 600 ~/.config/restic/password
  find /mnt/backup/restic -mindepth 2 -maxdepth 2 -type d -name home -print
  old_repo=/mnt/backup/restic/OLD_HOST/home
  restic -r "$old_repo" --password-file ~/.config/restic/password snapshots
  restic -r "$old_repo" --password-file ~/.config/restic/password \
    restore latest --target /tmp/restic-restore
  ```

  Inspect the restore before copying documents, projects, or other data home.

### 9. Re-establish backups

See `~/.config/restic/README.md`. Mount the backup filesystem at `/mnt/backup`
through a `nofail` UUID fstab entry, verify it, and create its writable parent:

```sh
mountpoint /mnt/backup
sudo install -d -m 0750 -o "$USER" -g "$(id -gn)" /mnt/backup/restic
```

The wrapper uses `/mnt/backup/restic/$(hostname -s)/{home,system}`. The old
hostname plus password continues those repositories; a new one adds a sibling:

```sh
restic-backup init
sudo ~/.local/bin/restic-backup init-system
restic-backup home
sudo ~/.local/bin/restic-backup system
systemctl --user daemon-reload
systemctl --user enable --now restic-backup.timer restic-maintenance.timer
```

`restic-backup init` verifies an existing repository or initializes a missing
one, generating the password only when absent.

### 10. Verify

```sh
chezmoi status
~/.config/i3/tests/run-fast.sh
~/.config/polybar/tests/test-launch.sh
~/.local/bin/tests/test-weather.sh # plus the directory's other tests
```

Some status drift is expected from tool-owned files. See
`~/.config/i3/MANUAL.md` for manual checks and keybindings.

## macOS: audit only

Scratch recovery is unsupported. Do **not** run `chezmoi init --apply`, a bare
`chezmoi apply`, or provisioning scripts on macOS.

[MACOS_PORTING_GUIDE.md](MACOS_PORTING_GUIDE.md) is the canonical inventory,
contract, and verification sequence. Until its Phase 1 gates and Darwin checks
pass, macOS allows only source init, read-only rendering, and port development.
Install chezmoi and `jq` separately; the safe boundary is:

```sh
chezmoi init 'https://github.com/OWNER/REPOSITORY.git'
chezmoi data | jq '.chezmoi | {os, arch, homeDir}' # expect os = darwin
chezmoi ignored
chezmoi managed
chezmoi diff
chezmoi apply --dry-run --verbose
```

## License

Original work: [MIT](LICENSE). Third-party components retain their own licenses.

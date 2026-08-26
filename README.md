# dotfiles

Personal and opinionated machine configuration managed with [chezmoi](https://chezmoi.io),
targeting **Linux Mint 22.3 / Ubuntu 24.04** with i3/X11.

This repo carries both the **configuration** (dotfiles) and the
**provisioning** (scripts that install the software those configs are for), so
a bare machine can be brought up reproducibly.

## Day-to-day

```sh
chezmoi edit <file>     # edit a managed file in the source
chezmoi diff            # preview pending changes
chezmoi apply           # apply changes (re-runs changed run_once_* scripts)
chezmoi re-add          # pull local edits back into the source
chezmoi update          # git pull + apply
```

## Recovering a Linux i3 desktop from scratch

Rebuilds a Linux Mint 22.3 / Ubuntu 24.04 x86_64 machine to the state this
repository describes, using `class = desktop` and
`desktopProfile = linuxmint-i3-x11`. Steps 1–6 bootstrap and apply the managed
state; 7–11 cover software and state the repository deliberately cannot carry.

### What is and is not recovered

Recovered from this repository: apt/flatpak/cargo software, fonts, zsh + the
whole shell environment, i3/Polybar/Picom/Rofi/dunst desktop, terminal and
editor configuration, X11 input and TLP tuning, the publishable subset of
browser and Thunderbird preferences, and the restic backup wrappers.

**Not** recovered, by design — see `AGENTS.md`, "Never commit
machine-identifying values": SSH keys and host endpoints, the GPG key and
`pass` store, browser profiles and bookmarks, mail, the restic repository
password, agent tool state (MCP servers, plugins, project trust), and all
personal data. Those come from step 9 and your backups.

### 1. Base system

Install Linux Mint 22.3 (or Ubuntu 24.04), log in, and bring it current:

```sh
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl
```

On Ubuntu also `sudo apt install -y flatpak` — the flatpak step is skipped
when the command is absent, and unlike Mint, Ubuntu does not ship it.

### 2. Install chezmoi

Not an apt package here; install the upstream binary into `~/.local/bin`:

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
```

The `export` matters only for this bootstrap shell — `~/.local/bin` is on PATH
permanently once the managed `.zshenv` lands in step 5.

### 3. Initialize the source directory

```sh
chezmoi init 'https://github.com/OWNER/REPOSITORY.git'
```

Replace `OWNER/REPOSITORY` with the HTTPS clone path shown for this repository.
Use HTTPS, not SSH: there is no key on the machine yet. Step 9 switches the
remote over once keys are restored.

`chezmoi init` renders `.chezmoi.toml.tmpl` and prompts for the per-machine
values this repository refuses to store:

| Prompt                        | Notes                                                                                                     |
| ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| Full name / Email             | Git author identity                                                                                       |
| Machine class                 | `desktop` installs Flatpaks, fonts, and the selected desktop package set; `server` skips those installers |
| Desktop profile               | Defaults to `linuxmint-i3-x11` on Mint/Ubuntu and `none` elsewhere; choose `none` on a server             |
| Remote SSH username           | Blank uses SSH's default login name; it does not control whether host stanzas exist                       |
| GPU/HPC host alias + hostname | Both halves are needed, or that stanza is omitted                                                         |
| Screenshot directory          | Blank renders `~/Pictures/Screenshots` (the bootstrap prompt currently abbreviates this as `~/Pictures`)  |

The answers go to `~/.config/chezmoi/chezmoi.toml`, outside this repository.
They are asked once (`promptStringOnce`); to correct a typo later, edit that
file directly rather than re-running `init`.

### 4. Review before applying

Most entries should be creations (`A`). Modifications (`M`) are normal for
files the installer or `/etc/skel` already created, such as `.bashrc` and
`.profile`; unexpected deletions deserve closer inspection.

```sh
chezmoi status
chezmoi diff | less
chezmoi apply --dry-run --verbose | less
```

### 5. Apply

```sh
chezmoi apply -v
```

Run this in a terminal you can answer prompts in. In order:

1. `run_once_before_10-install-apt-packages` — adds the helix PPA and installs
   the apt sets from `.chezmoidata/packages.toml`. **sudo prompts**, and
   installing `lightdm` opens a debconf dialog asking which display manager to
   make default; choose `lightdm`. The laptop power set (`tlp`) installs only
   when a battery is present.
2. Managed files are written, and `.chezmoiexternal.toml` clones the zsh
   plugins and vim themes (network required).
3. `run_once_after_20` — Flathub apps (desktop class only).
4. `run_once_after_30` — rustup, the cargo crates, starship, zoxide, and
   Miniconda into `~/miniconda3`. The slowest step; a failed crate warns and
   continues rather than aborting.
5. `run_once_after_40` — adds zsh to `/etc/shells` and `chsh`es to it
   (**password prompt**).
6. `run_once_after_50` — Fonts into `~/.local/share/fonts`.
7. `run_onchange_after_60/62/65/70` — browser and Thunderbird preferences.
   These print "has not created a profile yet" and skip; step 8 completes them.
8. `run_after_90` / `run_after_91` — X11 keyboard/TrackPoint config and the TLP
   charge-threshold drop-in (**sudo prompts**).
9. `run_onchange_after_92` — creates the screenshot directory.

### 6. Log out and start the i3 session

Log out, and at the LightDM greeter pick the **i3** session before logging back
in. The login shell is now zsh, and the fonts and desktop configuration take
effect on this new session.

### 7. Software the manifest does not install

Deliberate gaps requiring manual installation when wanted:

- **Helium** — an AppImage, not a package. Run
  `~/Applications/update-helium.sh`; it downloads the current release and
  points `helium.desktop` at it.
- **Taskwarrior** — apt ships 2.6.2 (flat-file), while `dot_taskrc` targets 3.x
  (sqlite), so the apt binary cannot read this data. Install `task` from
  upstream; `taskwarrior-tui` does come from apt.
- **i3-resurrect** — the save/restore scripts look for it at
  `~/.local/bin/i3-resurrect`: `pipx install i3-resurrect`.
- **Optional scientific software** — `.zshenv` puts on PATH if present. Nothing installs them, and
  their absence only makes those PATH entries inert.

Agent tooling (Claude Code and Codex plugins, skills, MCP servers, hooks) is
out of scope on purpose; each installer re-registers its own state.

### 8. Second pass — browser profiles

The profile scripts need a profile to write into, and Helium only exists after
step 7. Launch Zen, Firefox, Thunderbird, and Helium once each, then quit them.
First rerun chezmoi:

```sh
chezmoi apply -v
```

The Zen, Firefox, and Thunderbird scripts hash their `profiles.ini` into their
rendered bodies, so the new profiles retrigger them automatically. This
installs their sanitized `user.js` files and the Zen/Thunderbird `chrome/`
customizations.

Helium does not have a `profiles.ini`, and its current `run_onchange_` script
does not yet include the existence of `Preferences` in its rendered state. The
first skipped run is therefore remembered. Render and run that one script
explicitly after Helium is closed:

```sh
chezmoi execute-template --file \
  "$(chezmoi source-path)/run_onchange_after_70-configure-helium-profile.sh.tmpl" |
  bash
```

This merges the publishable Helium preference subset, installs its new-tab
background, and links its browserpass native messaging host.

### 9. Restore the local-only state

None of this is in Git. Restore it from your backups or password manager:

- **SSH keys** — `~/.ssh/config` is rendered from the step 3 answers and
  expects `~/.ssh/id_ed25519`. Restore that key, or generate a new one with
  `ssh-keygen -t ed25519` and register the public half with GitHub and each
  remote host. Then point the source repo at SSH:
  ```sh
  git -C "$(chezmoi source-path)" remote set-url origin \
      'git@github.com:OWNER/REPOSITORY.git'
  ```
  Replace `OWNER/REPOSITORY` with this repository's SSH clone path.
- **GPG key and `pass` store** — import the secret key, then clone or restore the
  existing password store, including its `.gpg-id`. Run `pass init <key-id>`
  only when creating a new store or replacing a missing `.gpg-id`.
- **Browser and mail state** — bookmarks, extensions, accounts, and Thunderbird
  mail. Use each application's sync or a private export; never add a profile
  directory to chezmoi.
- **Restic repository password** — restore it to
  `~/.config/restic/password`, set mode 0600, and keep the external copy. It is
  generated locally and ignored by chezmoi; without it, the old repositories
  cannot be read.
- **Personal data** — mount the backup filesystem and restore the home snapshot
  to a temporary directory first. Repositories are stored below a directory
  named for the old short hostname, which may differ from the fresh install:
  ```sh
  chmod 600 ~/.config/restic/password
  find /mnt/backup/restic -mindepth 2 -maxdepth 2 -type d -name home -print
  old_repo=/mnt/backup/restic/OLD_HOST/home
  restic -r "$old_repo" --password-file ~/.config/restic/password snapshots
  restic -r "$old_repo" --password-file ~/.config/restic/password \
    restore latest --target /tmp/restic-restore
  ```
  Inspect the temporary restore before copying `Documents`, projects, or other
  data into the new home directory.

### 10. Re-establish backups

Full procedure in `~/.config/restic/README.md`. Mount the backup filesystem at
`/mnt/backup` using a `nofail` fstab entry by UUID, verify the mount, and create
the writable parent directory:

```sh
mountpoint /mnt/backup
sudo install -d -m 0750 -o "$USER" -g "$(id -gn)" /mnt/backup/restic
```

The wrapper selects `/mnt/backup/restic/$(hostname -s)/{home,system}`. To
continue the old repositories, restore their password and retain the original
hostname. With a different hostname, these commands create a new sibling
backup history and leave the old repositories available for explicit restores.
Then run:

```sh
restic-backup init
sudo ~/.local/bin/restic-backup init-system
restic-backup home
sudo ~/.local/bin/restic-backup system
systemctl --user daemon-reload
systemctl --user enable --now restic-backup.timer restic-maintenance.timer
```

`restic-backup init` verifies an existing repository or initializes a missing
one; it generates `~/.config/restic/password` only when that file is absent.
Whenever a new password is generated, save it to a password manager
immediately.

### 11. Verify

```sh
chezmoi status                       # drift after a clean rebuild
~/.config/i3/tests/run-fast.sh       # i3 helper suite
~/.config/polybar/tests/test-launch.sh
~/.local/bin/tests/test-weather.sh   # and the rest of that directory
```

Some `chezmoi status` output is expected rather than a defect list — several
targets are rewritten live by the tools that own them. `~/.config/i3/MANUAL.md`
documents the manual i3 checks and the keybindings.

## macOS status and safe audit

**There is no supported scratch-recovery procedure for macOS yet.** Do not run
`chezmoi init --apply`, a bare `chezmoi apply`, or the current provisioning
scripts on a Mac.

The current Darwin render still has material blockers:

- `20-install-flatpaks`, `30-install-cli-tools`, `40-set-default-shell`, and
  `50-install-fonts` still contain Linux behavior; the CLI installer downloads
  the Linux x86_64 Miniconda artifact.
- The managed target still includes, among other Linux artifacts,
  `.config/Code/`, `.config/flameshot/`, `.config/i3-resurrect/`,
  `.config/pipewire/`, `.config/systemd/`, `.config/zathura/`, Linux browser
  chrome assets, Helium AppImage/desktop payloads, and the bookmark-sync helper.
- There is no declarative Darwin package set or native desktop profile.
  Portable-looking configurations are not necessarily ready either: Git still
  selects the Linux `libsecret` credential helper, Ghostty contains GTK/i3
  settings, and shared shell/editor files retain Linux-specific paths and
  commands.

[`MACOS_PORTING_GUIDE.md`](MACOS_PORTING_GUIDE.md) is the canonical inventory,
implementation contract, and verification sequence. Until its Phase 1 safety
gates and Darwin acceptance checks pass, use the repository on a Mac only for
source initialization, read-only target rendering, and port development.

After installing chezmoi and `jq` separately, this is the safe audit boundary:

```sh
chezmoi init 'https://github.com/OWNER/REPOSITORY.git'
chezmoi data | jq '.chezmoi | {os, arch, homeDir}' # expect os = darwin
chezmoi ignored
chezmoi managed
chezmoi diff
chezmoi apply --dry-run --verbose
```

Replace `OWNER/REPOSITORY` with the HTTPS clone path shown for this repository.
At the prompts, leave `desktopProfile = none`; this suppresses the implemented
i3/X11 profile but does not make the remaining Darwin target safe to apply.
Do not infer that an unlisted target is portable merely because its path looks
harmless.

## License

Original configuration and scripts in this repository are available under the
[MIT License](LICENSE). Third-party software, themes, and externally fetched
components remain subject to their respective licenses.

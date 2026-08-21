# Local restic backup

This setup stores encrypted backups on a locally attached HDD or SSD. It backs
up only this Linux Mint installation:

- `restic-backup home` captures the home directory (including dotfiles,
  Documents, Downloads, browser profiles, and project sources).
- `sudo ~/.local/bin/restic-backup system` captures curated system state in a
  separate root-owned repository.
- Both commands use `--one-file-system`, so they do not cross into EFI,
  Windows/NTFS, Fedora/Btrfs, removable, or other mounted filesystems.

The repositories are separate because restic writes files as the process user.
This keeps the system job from leaving root-owned files in the home repository.

The privileged source list lives in `~/.config/restic/config.sh` and includes:

- `/etc`, `/root`, `/usr/local`, `/srv`, and `/var/www`;
- local mail and cron state;
- the small dpkg/apt/aptitude files needed to reconstruct package selection;
- AccountsService, NetworkManager, Bluetooth, Bolt, fingerprint, and Tailscale
  identity/pairing state.

Missing paths are skipped. Every existing source must be on Linux Mint's root
filesystem, and `--one-file-system` prevents crossing a nested mount. `/opt`,
`/boot`, caches, logs, and all of `/var/lib` are deliberately omitted: on this
machine they are mostly reinstallable application payloads, transient data, or
live databases that need application-aware dumps. Add an exact path to
`RESTIC_SYSTEM_PATHS` in the chezmoi config if it contains irreplaceable data.

## One-time setup

Mount the backup filesystem at `/mnt/backup`. To use another fixed mount point,
set `resticMount = "/your/path"` in the `[data]` section of
`~/.config/chezmoi/chezmoi.toml` before applying. Prefer a stable `/etc/fstab`
entry by filesystem UUID with `nofail`; do not rely on a changing `/dev/sdX`
name. The wrapper verifies that the path is a real mount point and refuses to
write there otherwise, preventing a disconnected drive from filling the Linux
system disk.

For the default path, confirm the drive is mounted before creating a directory
that the user can write:

```sh
mountpoint /mnt/backup
sudo install -d -m 0750 -o "$USER" -g "$(id -gn)" /mnt/backup/restic
```

Then apply the dotfiles and initialize both repositories:

```sh
chezmoi apply
restic-backup init
sudo ~/.local/bin/restic-backup init-system
restic-backup home
sudo ~/.local/bin/restic-backup system
```

`init` creates a random password at `~/.config/restic/password` with mode 0600.
That file is unmanaged and ignored by chezmoi. Save a separate copy in a
password manager: neither repository can be recovered without it.

Enable the daily home backup and monthly maintenance after the first successful
manual backup:

```sh
systemctl --user daemon-reload
systemctl --user enable --now restic-backup.timer restic-maintenance.timer
systemctl --user list-timers 'restic-*'
```

If the drive is absent, the job fails safely. After attaching it, run
`restic-backup home` manually rather than waiting for the next scheduled run.
The system repository is intentionally manual; run
`sudo ~/.local/bin/restic-backup system` after meaningful system configuration
or package changes.

## Retention and checks

Each repository keeps every snapshot from the last 2 days, then 7 daily, 5
weekly, 12 monthly, and 3 yearly snapshots. The home maintenance timer prunes
unused data and verifies a random 5% of data monthly. Because the curated system
repository is comparatively small, its manual maintenance verifies all data:

```sh
restic-backup maintenance
sudo ~/.local/bin/restic-backup maintenance-system
```

Inspect snapshots and logs with:

```sh
restic-backup snapshots
sudo ~/.local/bin/restic-backup snapshots-system
journalctl --user -u restic-backup.service
journalctl --user -u restic-maintenance.service
```

## Restore examples

Always restore to a temporary directory first and inspect the result:

```sh
restic -r /mnt/backup/restic/$(hostname -s)/home \
  --password-file ~/.config/restic/password snapshots
restic -r /mnt/backup/restic/$(hostname -s)/home \
  --password-file ~/.config/restic/password restore latest \
  --target /tmp/restic-restore
```

For system state, use the sibling `system` repository and run restic with
`sudo`. Restore into a temporary directory first; do not overwrite a running
system's `/etc` or `/var/lib` directly.

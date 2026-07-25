# dotfiles

Personal machine configuration managed with [chezmoi](https://chezmoi.io),
with parallel desktop profiles for:

- **Linux Mint 22.3 / Ubuntu 24.04** with i3/X11
- **CachyOS** with Niri and Noctalia

This repo carries both the **configuration** (dotfiles) and the
**provisioning** (scripts that install the software those configs are for), so
a bare machine can be brought up reproducibly. A fresh CachyOS machine is
intentionally brought up in stages so package and desktop boundaries can be
verified before live configuration is overwritten.

Do not use a one-command apply on a fresh CachyOS installation. Follow
[`CACHYOS_TRANSFER_GUIDE.md`](CACHYOS_TRANSFER_GUIDE.md) to initialize without
applying, provision packages first, and then add the shared and desktop layers
in stages.

Desktop selection is stored as `desktopProfile` in the machine-local chezmoi
configuration:

```text
linuxmint-i3-x11
cachyos-niri-noctalia
none
```

## Day-to-day

```sh
chezmoi edit <file>     # edit a managed file in the source
chezmoi diff            # preview pending changes
chezmoi apply           # apply changes (re-runs changed run_once_* scripts)
chezmoi re-add          # pull local edits back into the source
chezmoi update          # git pull + apply
```

## License

Original configuration and scripts in this repository are available under the
[MIT License](LICENSE). Third-party software, themes, and externally fetched
components remain subject to their respective licenses.

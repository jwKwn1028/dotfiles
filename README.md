# dotfiles

Personal machine configuration managed with [chezmoi](https://chezmoi.io),
targeting **Linux Mint 22.3 / Ubuntu 24.04** with an i3 desktop.

This repo carries both the **configuration** (dotfiles) and the
**provisioning** (scripts that install the software those configs are for), so
a bare machine can be brought up with a single command.

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

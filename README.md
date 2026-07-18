# dotfiles

Personal machine configuration managed with [chezmoi](https://chezmoi.io),
targeting **Linux Mint 22.3 / Ubuntu 24.04** with an i3 desktop.

This repo carries both the **configuration** (dotfiles) and the
**provisioning** (scripts that install the software those configs are for), so
a bare machine can be brought up with a single command.

The desktop is X11/i3 today. Before changing that, read
[`X11_TO_WAYLAND_TRANSITION.md`](X11_TO_WAYLAND_TRANSITION.md) — it inventories
every X11-coupled file here, what replaces it, and the order to do it in. The
short version: add a parallel Wayland profile, keep i3 as the fallback, and do
not edit the X11 files in place.

macOS is not supported by the current provisioning scripts. In particular,
do **not** run `chezmoi init --apply` on a Mac yet: the CLI-tool installer still
selects a Linux Miniconda build and several desktop scripts assume apt/X11.
Agents implementing a parallel Darwin profile must follow
[`MACOS_PORTING_GUIDE.md`](MACOS_PORTING_GUIDE.md) and preserve Linux as the
known-good target throughout the port.

## Bootstrap a new Linux machine

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply jwKwn1028
```

Replace `jwKwn1028` with the full repo URL if the shorthand doesn't resolve.
This installs chezmoi, clones the repo, prompts for a few values (see below),
runs the install scripts, and writes all the dotfiles.

On first run you'll be asked for:

| Prompt  | Meaning                                                            |
| ------- | ----------------------------------------------------------------- |
| `name`  | git author name                                                   |
| `email` | git author email                                                  |
| `class` | `desktop` (full i3/GUI stack) or `server` (CLI/dev tools only)    |
| `context7ApiKey` | Context7 MCP key; leave blank to skip                    |

Answers are stored in `~/.config/chezmoi/chezmoi.toml` (local only, never
committed). Re-run `chezmoi init` to change them.

## What gets installed

Provisioning is data-driven: edit [`.chezmoidata/packages.toml`](.chezmoidata/packages.toml)
and the relevant `run_once_*` script re-runs on the next `chezmoi apply`.

| Script | Installs |
| ------ | -------- |
| `run_once_before_10-install-apt-packages` | apt packages (+ PPAs). `common` everywhere; `desktop` set only when `class == desktop`. |
| `run_once_after_20-install-flatpaks`      | Flathub apps (desktop only). |
| `run_once_after_30-install-cli-tools`     | rustup + cargo crates (eza, yazi, LSPs, rtk, …), starship, zoxide, Miniconda. |
| `run_once_after_40-set-default-shell`     | Sets zsh as the login shell. |
| `run_once_after_50-install-fonts`         | Nerd Font (icons) + New Computer Modern (desktop only). |

`sudo` will prompt for a password during the apt/font steps.

## Secrets

Secrets are **not** committed. `context7ApiKey` is prompted once at
`chezmoi init` and stored in the local chezmoi config; templates read it from
there or from a `CONTEXT7_API_KEY` environment variable, whichever is set.

Browser profiles and bookmarks, SSH connection definitions, and per-project
agent trust settings are intentionally not managed because they contain
personal or machine-specific state.

For additional secrets, prefer chezmoi's built-in
[age encryption](https://chezmoi.io/user-guide/encryption/age/) or a
password-manager template function rather than plaintext in this repo.

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

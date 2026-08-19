# dotfiles

Personal machine configuration managed with [chezmoi](https://chezmoi.io),
targeting **Linux Mint 22.3 / Ubuntu 24.04** with i3/X11.

This repo carries both the **configuration** (dotfiles) and the
**provisioning** (scripts that install the software those configs are for), so
a bare machine can be brought up reproducibly.

Desktop selection is stored as `desktopProfile` in the machine-local chezmoi
configuration:

```text
linuxmint-i3-x11
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

## Agent tooling

Claude Code and Codex **plugins, skills, and MCP servers are not managed here**
— their own installers own those registrations, which carry machine-local paths
and trust state. This repo tracks only the static configuration around them
(`~/.claude/settings.json`, `~/.codex/rules`, model selection). See
[`AGENTS.md`](AGENTS.md).

## License

Original configuration and scripts in this repository are available under the
[MIT License](LICENSE). Third-party software, themes, and externally fetched
components remain subject to their respective licenses.

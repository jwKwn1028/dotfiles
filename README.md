# dotfiles

Personal [chezmoi](https://chezmoi.io) configuration and provisioning for a
reproducible **Linux Mint 22.3 / Ubuntu 24.04** i3/X11 machine.

```sh
chezmoi diff   # preview changes
chezmoi apply  # apply; reruns changed run_once_* scripts
chezmoi update # git pull + apply
```

macOS is audit-only: never run `chezmoi apply` or a provisioning script there.

## Documentation

- [docs.md](docs.md) — daily commands, full desktop recovery, macOS boundary
- [MACOS_PORTING_GUIDE.md](MACOS_PORTING_GUIDE.md) — macOS port contract
- [X11_TO_WAYLAND_TRANSITION.md](X11_TO_WAYLAND_TRANSITION.md) — Sway plan
- [AGENTS.md](AGENTS.md) — working rules for agents and contributors

Application guides, installed into their matching config directories:

- [i3](dot_config/i3/MANUAL.md) and [Polybar](dot_config/polybar/docs.md)
- [Ghostty](dot_config/ghostty/docs.md) and [Zsh](dot_zsh/docs.md)
- [Helix](dot_config/helix/docs.md), [Micro](dot_config/micro/docs.md),
  [Zed](dot_config/zed/docs.md), and [VS Code](dot_config/private_Code/User/docs.md)
- [Yazi](dot_config/yazi/yazi_docs.md), [Taskwarrior](dot_config/task/MANUAL.md),
  and [Restic](dot_config/private_restic/README.md)

## License

Original work: [MIT](LICENSE). Third-party components retain their own licenses.

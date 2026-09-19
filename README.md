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

## License

Original work: [MIT](LICENSE). Third-party components retain their own licenses.

# AGENTS.md

Guidance for agents working in this repository. Canonical for every agent tool;
`CLAUDE.md` imports this file rather than restating it. Put guidance here.

## What this repo is

The [chezmoi](https://chezmoi.io) **source directory** for this machine — not a
normal project. It carries both configuration (dotfiles) and provisioning
(`run_once_*` scripts that install the software those configs are for).
Target: Linux Mint 22.3 / Ubuntu 24.04, i3 desktop. See `README.md`.

## Editing rules

Filenames here are chezmoi **source-state names**, not target names:
`dot_zshrc` → `~/.zshrc`, `private_dot_claude/` → `~/.claude/`,
`executable_*` → mode 0755, `*.tmpl` → rendered as a Go template. Renaming a
file renames its target. Read
[chezmoi's source-state attributes](https://chezmoi.io/reference/source-state-attributes/)
before creating files with a new prefix.

- **Every root-level file lands in `$HOME` unless ignored.** `.chezmoiignore`
  matches TARGET paths and already excludes the repo docs. A new root file
  (`NOTES.md`, a script) will be written to `~/` — add it there if that isn't
  what you want. Check with `chezmoi status`: `A` means "will be created".
- Edit files **here**, not in `$HOME` — `chezmoi apply` overwrites the target.
  To pull in a change made live in `$HOME`, use `chezmoi re-add`.
- Prefer `chezmoi diff` before `chezmoi apply`. Applying rewrites live config.
- Secrets are never committed. `context7ApiKey` is prompted at `chezmoi init`
  and lives in `~/.config/chezmoi/chezmoi.toml`, outside this repo. Do not
  inline secrets into templates.
- `.gitignore` keeps agent scaffolding (`.claude`, `.codex`, `.AGENTS.md`) out
  of history on purpose. `AGENTS.md` and `CLAUDE.md` are the deliberate
  exceptions so a fresh clone gets these rules — keep both free of secrets.

## Provisioning

Software lists live in `.chezmoidata/packages.toml`, consumed by the
`run_once_*` scripts and gated on `class` (`desktop` | `server`) from
`.chezmoi.toml.tmpl`. Add software by editing that manifest, not by editing the
install scripts — they re-run on the next `apply` when the data changes.

Package names are apt names for Mint 22.3 / Ubuntu 24.04. Verify with
`apt-cache policy <pkg>` before adding; several plausible Wayland tools
(`rofi-wayland`, `swappy`, `swww`) are **not** in these repos.

## The X11 → Wayland transition

The desktop is X11/i3, and much of it is deeply X11-coupled (`xrandr`,
`xdotool`, `xinput`, Polybar, `i3-resurrect`). If a task touches that surface,
read [`X11_TO_WAYLAND_TRANSITION.md`](X11_TO_WAYLAND_TRANSITION.md) first — it
inventories every affected file, what replaces it, and the order to work in.

Standing rules from that document:

- Add a **parallel** Wayland profile (`dot_config/sway/`, `dot_config/waybar/`).
  Do not edit the i3/X11 files in place; they are the known-good fallback until
  the user explicitly retires them.
- A migration is packages *and* config. Config-only changes appear to work on
  this machine and fail on a fresh one.
- Do not mechanically swap command names. Wayland blocks global window
  inspection, synthetic input, and clipboard scraping by design, so some
  scripts need redesigning rather than porting.

## The Linux → macOS port

If a task adds, changes, or evaluates macOS support, read
[`MACOS_PORTING_GUIDE.md`](MACOS_PORTING_GUIDE.md) first. It is the migration
contract and file-by-file inventory for a parallel Darwin profile.

- Keep the Linux Mint/i3 source state working; gate Linux-only files and add
  Darwin counterparts instead of replacing the fallback.
- Use `.chezmoi.os == "darwin"` and shared `.chezmoitemplates` rather than
  hostnames or hard-coded Homebrew/home paths.
- Package installation and application configuration must land together.
- Browser profiles, SSH endpoints, agent project-trust lists, credentials, and
  macOS privacy-permission databases remain local and must not enter Git.
- Never run the current repository with `chezmoi init --apply` on macOS before
  the guide's provisioning safety gates and dry-run checks are complete.

## Verifying

There is no test suite. `chezmoi apply` against live config is the risky step,
so verify with `chezmoi diff` / `chezmoi status` / `chezmoi apply --dry-run`,
and lint shell scripts with `shellcheck` when changing them.
`chezmoi execute-template < file.tmpl` renders a template without applying it.

# AGENTS.md

Guidance for agents working in this repository. Canonical for every agent tool;
`CLAUDE.md` imports this file rather than restating it.

## What this repo is

The [chezmoi](https://chezmoi.io) **source directory** for this machine — not a
normal project. It carries both configuration (dotfiles) and provisioning
(`run_once_*` scripts that install the software those configs are for).
Targets Linux Mint 22.3 / Ubuntu 24.04 with i3/X11. See `README.md`.

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
- Drift in `chezmoi status` is normal, not a defect list: several targets are
  rewritten live by the tools that own them. Reconcile only what the task asks
  for, and never let a broad `apply` sweep up unrelated drift.
- **Never commit machine-identifying values** — this repo is public. Secrets,
  usernames, hostnames, IPs, SSH host aliases, institution or lab names, and
  literal `/home/...` paths. An alias identifies a machine as surely as its
  address does, and a path can name an employer.
  - Per-machine values go through `promptStringOnce` in `.chezmoi.toml.tmpl`
    and live in `~/.config/chezmoi/chezmoi.toml`, outside this repo: currently
    `sshRemoteUser`, `ssh{Gpu,Hpc}Host{,Name}`, `tailscaleExitNode`,
    `flameshotSavePath`.
  - Use `{{ .chezmoi.homeDir }}`, never a literal home path (see `750fd0a`).
  - `chezmoi add` copies a live file verbatim — read the result before
    committing. That is how a flameshot savePath naming a lab directory got in.
  - Never add `~/.ssh` wholesale; `.gitignore` allowlists only
    `private_dot_ssh/private_config.tmpl`.
- `.gitignore` excludes agent scaffolding (`.claude`, `.codex`) on purpose;
  `AGENTS.md` and `CLAUDE.md` are the deliberate exceptions so a fresh clone
  gets these rules. Keep both free of secrets.

## Agent tooling this repo does not manage

Claude Code and Codex plugins, skills, MCP servers, agent definitions, and
installer-wired hooks are **out of scope**. Don't add them, don't restore one
you see in `$HOME` but not here, and don't investigate drift in them — each
installer keeps its own registration current, so a copy in Git goes stale and
downgrades the live one. The only exceptions are
`private_dot_claude/modify_private_settings.json` (stable settings only) and
`private_dot_codex/modify_private_config.toml` (`model` and
`model_reasoning_effort` only). Both modify scripts must preserve installer-owned
keys already present in the live files.

## Provisioning

Software lists live in `.chezmoidata/packages.toml`, consumed by the
`run_once_*` scripts and gated on `class` (`desktop` | `server`) from
`.chezmoi.toml.tmpl` plus `desktopProfile` (`linuxmint-i3-x11` | `none`). Add
software by editing that manifest, not the install scripts — they re-run on the
next `apply` when the data changes.

`packages.apt` names are for Mint 22.3 / Ubuntu 24.04; verify with
`apt-cache policy <pkg>`.

## The Mint X11 → Sway transition

The Mint desktop is deeply X11-coupled (`xrandr`, `xdotool`, `xinput`, Polybar,
`i3-resurrect`). Before proposing Sway as a second session, read
[`X11_TO_WAYLAND_TRANSITION.md`](X11_TO_WAYLAND_TRANSITION.md). Standing rules:

- Add a **parallel** profile (`dot_config/sway/`, `dot_config/waybar/`); the
  i3/X11 files are the known-good fallback until explicitly retired.
- A migration is packages *and* config — config-only changes work here and fail
  on a fresh machine.
- Don't mechanically swap command names. Wayland blocks window inspection,
  synthetic input, and clipboard scraping, so some scripts need redesigning.

## The Linux → macOS port

Read [`MACOS_PORTING_GUIDE.md`](MACOS_PORTING_GUIDE.md) before adding or
evaluating macOS support — it is the migration contract and file inventory.

- Gate Linux-only files and add Darwin counterparts; keep the Mint/i3 source
  state working.
- Branch on `.chezmoi.os` and share via `.chezmoitemplates`, not hostnames or
  hard-coded Homebrew paths.
- Packages and config must land together.
- Browser profiles, SSH endpoints, agent trust lists, credentials, and macOS
  privacy databases stay local.
- Never `chezmoi init --apply` on macOS before the guide's safety gates pass.

## Verifying

There is no repo-wide test runner. Run the relevant standalone checks under
`dot_config/i3/tests/`, `dot_config/polybar/tests/`, and `dot_local/bin/tests/`;
`dot_config/i3/MANUAL.md` documents the i3 checks. `chezmoi apply` against live
config is the risky step, so verify with `chezmoi diff` / `chezmoi status` /
`chezmoi apply --dry-run`. Check Bash/POSIX scripts with `shellcheck` and
`bash -n`, Zsh with `zsh -n`.
`chezmoi execute-template < file.tmpl` renders a template without applying it.

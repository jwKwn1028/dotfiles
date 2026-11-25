# fancy-cat Manual

Terminal PDF viewer with Zathura-style controls. Config:
`~/.config/fancy-cat/config.json`; recolor matches `zathurarc`.

## Opening

`fancy-cat FILE [PAGE]` opens at PAGE or the remembered position. Yazi/`fo` use
`fancy-cat-open`: inline in Ghostty, kitty, or local Ghostty/tmux; elsewhere a
new Ghostty window. Restored panes use `--wait-for-client`. Yazi `O` offers Zathura.

Local tmux needs `allow-passthrough on`; graphics appear in visible panes.
`Ctrl+b Ctrl+b` passes Ctrl-b to the viewer. The viewer titles its terminal
with the file name until it quits; tmux names the window after it, also when
Yazi opened it, without `.pdf`, cut to 24 cells.

## Keys

| Key | Action |
| --- | --- |
| `h j k l` | Scroll; pages run on continuously |
| `J` / `K`, `gg` / `G` | Next / previous page, first page / end; also Page Down / Up, Home / End |
| Count prefix | `5J` moves 5 pages, `12G` goes to page 12 |
| `Ctrl+d` / `Ctrl+u`, `Ctrl+t` / `Ctrl+y` | Half a view down / up, left / right |
| `Ctrl+f` / `Ctrl+b`, Space / Shift+Space, `t` / `y` | A full view down / up, left / right |
| `H` / `L`, `P` | Page top / bottom, snap to the page |
| `+` / `-`, `Alt++` / `Alt+-` | Zoom in / out, in larger steps |
| `s` / `a`, `d` / `D`, `r` | Fit width / page, two-page spreads / first column, rotate |
| `/` `?`, `n` / `N` | Search forward / backward, next / previous match |
| Tab, `f` / `F` / `c` | Contents, follow / show / copy a numbered link |
| `Ctrl+o` / `Ctrl+i`, `m`x / `'`x | Jump back / forward, set / go to mark x |
| `R` / `Y` | Reload / copy the file path |
| `T` | Shell in the PDF's folder: right tmux split, else a Ghostty tab |
| `Ctrl+l`, Ctrl+click | Jump to the source at the pointer (else the view centre) in hxp's editor |
| `Ctrl+r` / `Ctrl+n` | Toggle recolor / single-row status bar |
| `:12`, `:100%`, `:exec CMD` | Page, zoom, run `CMD` with `$FILE` and `$PAGE` |
| `:y+200`, `:x-100` | Scroll down / pan left by pixels |
| `q`, `:q`, `Ctrl+c` / Escape | Quit / clear a count, key, or highlights |

Search ignores case; incremental search pauses briefly before starting. Escape
returns to its origin. Contents: j/k navigate, l/h expand/collapse, Enter jumps;
Tab/Escape/q close. Only HTTP/HTTPS/mailto links launch via xdg-open.

Click links, drag blank space to pan, drag text to copy, double-click words.
Wheel scrolls (`wheel_step`; Ghostty emits 5 events/notch), Shift pans, Ctrl zooms.

## Reloading and memory

`FileMonitor.enabled` reloads settled writes and retains the old PDF during
rebuild gaps. Strip cache: 256 MiB; Ghostty image cache: up to 320 MB.

## Configuration

`KeyMap` accepts key objects, Zathura strings (`gg`, `<C-d>`), or lists; `[]`
unbinds. `Maps` binds commands (used for `T`).

| `General` option | Here |
| --- | --- |
| `white`, `black`, `recolor_keephue`, `recolor_reverse_video` | Recolor as in zathurarc |
| `first_page_column` | `2`: page 1 alone on the right of spreads |
| `remember_page` | Reopen at the last page (1000 most recent files) |
| `scroll_step`, `wheel_step`, `page_gap` | 40 px per `j`/`k`, 12 px per wheel event, 3 px between pages |
| `zoom_step`, `zoom_mult` | 10% steps, 32% with Alt |
| `trim_margins`, `smooth_scroll` | Off |

Use Zathura for SyncTeX.

## Build

`run_once_after_98` prefers the local `~/.local/src/fancy-cat` zathura branch,
then githubUser's pinned fork, then upstream 0.6.0. Fork versions are
`0.6.0+zathura.<commit>`; local commits rebuild on apply. Upstream ignores fork
settings and opens tmux PDFs separately. Build: Zig 0.15.2 + system MuPDF;
missing libraries install through pkexec (sudo without GUI).

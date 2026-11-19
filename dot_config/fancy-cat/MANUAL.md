# fancy-cat Manual

fancy-cat is the terminal PDF viewer, built from a public fork with
Zathura-like controls. Its config is `~/.config/fancy-cat/config.json`; colors,
zoom steps, and `Ctrl+r` recolor match `~/.config/zathura/zathurarc`.

## Opening

`fancy-cat FILE [PAGE]` opens at PAGE or where you left off. Yazi and `fo` use
`fancy-cat-open`: in place in Ghostty, kitty, or local tmux under Ghostty,
otherwise in a separate Ghostty window. In Yazi, `O` still offers Zathura.

In local tmux, images pass through (`allow-passthrough on`, visible panes only)
and move in whole cells. `Ctrl+b Ctrl+b` sends `Ctrl+b` to fancy-cat.

`T`, here and in Zathura, opens a Ghostty tab in the document's folder: in
fancy-cat's own window, or from tmux and Zathura in the last focused one.

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
| `T` | Ghostty shell tab in the document's folder |
| `Ctrl+r` / `Ctrl+n` | Toggle recolor / single-row status bar |
| `:12`, `:100%`, `:exec CMD` | Page, zoom, run `CMD` with `$FILE` and `$PAGE` |
| `:y+200`, `:x-100` | Scroll down / pan left by pixels |
| `q`, `:q`, `Ctrl+c` / Escape | Quit / clear a count, key, or highlights |

Search ignores case; with `incremental_search` it starts after a short pause,
and Escape returns to where it began. In the contents, `j`/`k` move, `l`/`h`
open and close, Enter jumps, and Tab, Escape, or `q` close. Only HTTP, HTTPS,
and mailto links open, with `xdg-open`; `F` and `c` show or copy others.

Click a link to follow it, drag blank space to pan, drag text to copy a range,
and double-click to copy a word. The wheel scrolls `wheel_step` pixels per
event (Ghostty sends 5 a notch); Shift+wheel pans and Ctrl+wheel zooms.

## Reloading and memory

With `FileMonitor.enabled`, saves reload once writes settle; the old version
stays while a rebuild briefly deletes the PDF. Pages stack continuously in a
256 MiB strip cache (Ghostty keeps up to 320 MB of images).

## Configuration

`KeyMap` takes key objects (`{"key": "j", "modifiers": ["shift"]}`), Zathura
strings (`"gg"`, `"<C-d>"`), or lists of them; `[]` unbinds. `Maps` binds keys
to commands like Zathura's `map` (`T` here).

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

`run_once_after_98` builds the `zathura` branch of `~/.local/src/fancy-cat` if
present, else the fork on GitHub under chezmoi's `githubUser` at the commit
pinned in `packages.toml`, both as `0.6.0+zathura.<commit>`; new local commits
rebuild on `chezmoi apply`. With neither, it builds upstream 0.6.0, which
ignores the fork-only settings above and opens tmux PDFs in a separate window.
It links system MuPDF with Zig 0.15.2 and installs missing libraries with
`pkexec`, or `sudo` without a GUI.

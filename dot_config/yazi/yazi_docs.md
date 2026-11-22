# Yazi Manual

Yazi 26.9.1 in Ghostty/i3/X11. Edit `dot_config/yazi/` in chezmoi; `ya pkg`
manages downloaded plugins. `~` or F1 lists bindings.

## Files

`yazi.toml`: options/openers; `keymap.toml`: keys; `init.lua`: plugins;
`theme.toml`: theme; `package.toml`: pinned plugins/flavor. Only `folder-rules`
is a local plugin; other plugin/flavor directories are downloaded.

## Starting Yazi

| Command | Opens Yazi in |
| --- | --- |
| `y [dir]` | `dir` or here. `q` leaves your shell in Yazi's last folder, `Q` doesn't, `E` hands over to Zed (see [Shell](#shell-and-other-programs)) |
| `yp` / `yd` | `~/Documents/Workspace/Project` / `~/Downloads` |
| `yl` / `yc` / `yr` (Zsh) | The paper library (`g l`) / the chezmoi source / the git root |
| `yazi [dir]` | `dir`, without ever changing the shell's folder |

A file argument opens its folder with that file hovered.

### From Helix

`Ctrl-y` opens at the buffer. Enter/`l` selects a file; `q` changes Helix's
folder to Yazi's, `Q` to the buffer's. No selection reopens the buffer;
`E` opens the folder in Zed. See [Helix](../helix/docs.md).

## The screen

Parent/current/preview columns use 1:1:2 widths. Mouse clicks select/open;
wheel scrolls. Modes: `NOR`, `SEL` (select), `UNS` (unset).

## Moving around

| Key | Action |
| --- | --- |
| `j` / `k` | Next / previous file |
| `l` / `h` | Enter the folder (or open the file) / go to the parent |
| `H` / `L` | Back / forward in history |
| `gg` / `G` | Top / bottom |
| `Ctrl-d` / `Ctrl-u` | Half page down / up |
| `Ctrl-f` / `Ctrl-b` | Full page down / up |
| `g h` / `g c` / `g d` | `~` / `~/.config` / `~/Downloads` |
| `g w` / `g p` | `~/Documents/Workspace` / `~/Documents/Workspace/Project` |
| `g l` | `~/Documents/Workspace/Known/Paper/Library/Library` |
| `g .` / `g r` | The chezmoi source / the git root |
| `g s` / `g t` | [Git changes](#git) / [trash](#trash) |
| `g Space` | Type a path, with `Tab` completion |
| `g f` | The hovered symlink's target |
| `Z` | A frequent folder, via zoxide (shared with the shell) |
| `z` | Any file below here, dotfiles included, via fzf (`FZF_DEFAULT_COMMAND`) |

## Finding things

| Key | Action |
| --- | --- |
| `/` / `?` | Jump to the next / previous matching name; `n` / `N` repeat |
| `f` | Filter the folder; `Esc` clears |
| `s` | Search names recursively (fd); an empty query lists everything |
| `S` | Search contents recursively (ripgrep) |
| `Ctrl-s` | Cancel a search |

Smart-case: lowercase ignores case. In results, Enter opens, `l` enters,
`h` or Escape leaves.

## Opening files

Enter/`o` opens selected or hovered files; `O` / Shift-Enter lists openers.

| Type | `Enter` | Also in `O` |
| --- | --- | --- |
| Folder | Helix (`l` goes inside) | Open (Thunar), Zed, Reveal |
| Text, code, JSON, JavaScript | Helix (`$EDITOR`) | Zed, Reveal |
| `.txt` | micro | Zed |
| PDF | fancy-cat | Zathura |
| Image | `xdg-open` | feh, Reveal |
| Audio, video | `xdg-open` (VLC) | Show media info, Reveal |
| Archive | [Extract here](#archives) | Reveal |
| Empty file | Helix | Reveal |
| Anything else | `xdg-open` | Reveal |

Reveal opens Thunar; Show EXIF uses exiftool. Terminal apps block, GUI apps
detach. Helix/micro/Zed/feh receive all selected files; xdg-open/fancy-cat the
first. `q` returns from fancy-cat. See [Micro](../micro/docs.md).

### Structure and simulation files

Editors = Helix, micro, Zed, `$EDITOR`; Reveal is always available.

| Files | `Enter` | Also in `O` |
| --- | --- | --- |
| `.cif`, `.vasp`, `.cell`, `POSCAR*`, `CONTCAR*` | VESTA | OVITO, editors |
| `.vesta`, `.mcif` | VESTA | editors |
| `.cube`, `.cub` | VESTA | Avogadro 2, OVITO |
| `.xsf`, `CHG`, `CHGCAR*`, `LOCPOT*`, `ELFCAR*`, `PARCHG*` | VESTA | OVITO |
| `.xyz` | OVITO | Avogadro 2, VESTA, editors |
| `.extxyz` | OVITO | Avogadro 2, editors |
| `XDATCAR*`, `vaspout.h5`, `.lammpstrj`, `.dump`, `.ovito` | OVITO | — |
| VASP files, `.xyz`, `.extxyz`, `.lammpstrj`, `.dump` ending in `.gz` or `.zst` | OVITO | Extract here |
| VASP files ending in `.bz2` or `.xz` | Extract here | — |
| `.pdb` | Avogadro 2 | OVITO, VESTA, editors |
| `.mol`, `.sdf`, `.cml`, `.cjson`, `.fchk`, `.molden`, `.mold`, `.molf`, `.gamout` | Avogadro 2 | editors |
| `.in`, `.pwi` (Quantum ESPRESSO input) | Helix | OVITO, micro, Zed, `$EDITOR` |

VASP names are case-sensitive; extensions are not. `POSCAR_gen.py` and similar
scripts remain scripts. VESTA cannot read compressed files; OVITO reads gz/zst.
Use VESTA for periodic cubes, Avogadro for orbitals. VESTA/OVITO use PATH, then
`~/Applications` (newest ovito-*). VESTA receives all selected files; others the first.

## Selecting

Space toggles and advances; `v`/`V` select/unset a range; Ctrl-a selects all,
Ctrl-r inverts, Escape clears or exits visual mode.

## File operations

| Key | Action |
| --- | --- |
| `y` / `x` | Yank to copy / to move; `y` also puts the files on the [clipboard](#clipboard) |
| `p` / `P` | Paste into the hovered folder (else here) / paste, overwriting |
| `Y` or `X` | Cancel the yank |
| `-` / `_` / `Ctrl--` | Absolute symlink / relative symlink / hardlink to the yanked files |
| `a` | Create a file; a trailing `/` makes a folder, and missing parents are created |
| `A` | Bulk create in micro, one path per line |
| `r` | Rename, cursor before the extension; with several selected, bulk rename in micro |
| `d` / `D` | Trash / delete permanently (both ask) |
| `C` | [Zip](#archives) the selection |

`p` preserves existing files by adding suffixes. Bulk creation/rename uses
micro; reorder the `local://*.txt` opener to change it.

## Archives

Enter extracts beside the archive, reusing its single top-level folder or
creating a named folder; collisions get suffixes. Compressed tarballs extract
in one step. deb/ISO preview but do not extract.

`C` offers `7z a .zip <selection>`: insert a name; change zip to 7z/tar if needed.
Paths stay relative.

## Trash

`d` uses desktop trash; `g t` opens it. `O` restores selections or empties trash;
Enter opens without restoring.

## Clipboard

| Key | Copies |
| --- | --- |
| `c c` / `c C` | Full path / `file://` URL |
| `c d` / `c D` | Parent folder path / URL |
| `c f` / `c n` | File name / without the extension |
| `c r` | Path relative to the git root (else the current folder) |
| `c y` | The file's contents |
| `c i` | The image itself, e.g. to paste a screenshot into chat |
| `y` | The files as a `text/uri-list`, which `Ctrl-v` pastes into apps |

Multiple paths from `c c` / `c r` are newline-separated.

## Previews

Text/code, JSON, images/SVG, video frames, PDF pages, fonts, archives, and folder
listings preview automatically. Other types use `file`. Cache: `/tmp/yazi-$UID`
(up to 1000×1200 images); clear with `ya cache clear`.

| Key | Action |
| --- | --- |
| `J` / `K` | Scroll: text lines, PDF pages, video position |
| `T` | Maximize / restore the preview |
| `Ctrl-p` | Hide / show the preview |
| `Tab` | Spot panel (type, size, dimensions): `j` / `k` rows, `h` / `l` files, `c c` copies a cell, `Tab` or `Esc` closes |

## Sorting and columns

Default: natural sort, folders first, hidden files off (`.` toggles).
Downloads uses newest-first with folders mixed in; leaving restores defaults.

`,` then `n/a/m/b/s/e/r`: natural/name/modified/created/size/extension/random.
Uppercase reverses; m/b/s also changes the column. `m` then `s/m/b/p/o/n`:
size/modified/created/permissions/owner/no column. Choices last for the tab.

## Tabs

`t t` new, `t r` rename, 1–9 select, `[`/`]` previous/next, `{`/`}` reorder,
Ctrl-c closes (quits on the last). Yank in one tab, paste in another.

## Git

Marks show file status. `g r` finds the root; `g s` lists changes below the
current folder (requires a commit; `h`/Escape leaves). `c r` copies root-relative
paths, useful for Markdown or Claude Code references.

## Shell and other programs

| Key | Action |
| --- | --- |
| `!` | Shell here, its prompt marked `󰇥 yazi`; `exit` returns |
| `;` / `:` | Run a command in the background / foreground (`git add -p`, `htop`) |
| `E` | Open the folder in Zed and quit |
| `Ctrl-t` | New Ghostty window here |
| `W` | taskwarrior-tui; `q` returns |
| `Ctrl-z` | Suspend; `fg` resumes |
| `q` | Quit |

`E` exits with code 10. Under `y`, the shell changes to Yazi's folder and closes
only an interactive local Ghostty tab/split outside tmux/SSH; elsewhere it stays.

Commands run here. Placeholders: `%h` hovered, `%s` selected, `%s1`/`%s2` indexed
selection, `%d` parent folders, `%y` yanked, `%%` literal %. Examples:
`; chmod +x %h`, `: git log -p -- %h`. term-cwd makes new Ghostty surfaces use
Yazi's current folder.

## Tasks

`w` opens copies/moves/deletes/extractions/commands: j/k select, Enter output,
x cancel, w/Escape close. Quitting with running tasks asks first.

## Prompts, menus and dialogs

Enter accepts; Escape cancels. Prompts: Ctrl-a/e start/end, Ctrl-u/k delete
before/after, Ctrl-w delete word, Up/Down (Ctrl-p/n) history, Ctrl-[ vi mode.
Menus use j/k; confirmations use y/Enter or n/Escape. Help: Enter runs a binding.

## Maintenance

Review/apply `~/.config/yazi`, then restart Yazi. Provisioning installs the
pinned plugins when `ya` becomes available. Upgrade Yazi before its development
plugins; keep `yazi` and `ya` at the same version.

```sh
ya pkg list
ya pkg upgrade
ya pkg add yazi-rs/plugins:<name>
chezmoi add ~/.config/yazi/package.toml
```

Local binaries use the verified `yazi-x86_64-unknown-linux-gnu.zip` release,
installed with `pkexec install -m 0755`; fresh machines use manifest cargo entries.
`YAZI_LOG=debug yazi` logs to `~/.local/state/yazi/yazi.log`.

## Known limitations

- tmux images need local tmux under Ghostty.
- Show media info needs the uninstalled `mediainfo`.
- Clipboard keys need X11/xclip or GNU realpath; Sway needs replacements.
- The Git-changes view may log harmless `Cannot spawn git` errors.
- Ghostty drag/drop is unavailable; use `y` then Ctrl-v where supported.
- The theme waits for a terminal startup reply; no reply leaves the default theme.

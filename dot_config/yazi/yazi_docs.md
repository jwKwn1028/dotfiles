# Yazi Manual

The Yazi setup in `~/.config/yazi`, for Yazi 26.9.1 in Ghostty on i3/X11.
Edit `dot_config/yazi/` in the chezmoi source, not `~/.config/yazi`; plugins
installed by `ya pkg` are separate. In Yazi, `~` or `F1` lists every binding.
See also the [Helix guide](../helix/docs.md) (its `Ctrl-y` picker) and the
[Micro guide](../micro/docs.md).

## Files

| File | Purpose |
| --- | --- |
| `yazi.toml` | Layout, sorting, previews, openers and open rules, git fetchers |
| `keymap.toml` | Custom keys, in front of Yazi's defaults |
| `init.lua` | Starts the `git`, `term-cwd` and `folder-rules` plugins |
| `theme.toml` | The `tokyo-night` flavor |
| `package.toml` | `ya pkg` lockfile: six plugins and the flavor, pinned by revision |
| `plugins/folder-rules.yazi/` | Local plugin: newest-first sorting in `~/Downloads` |
| Other `plugins/*.yazi`, `flavors/*.yazi` | Installed by `ya pkg`, not tracked |

Elsewhere in the repo:

| File | Purpose |
| --- | --- |
| `dot_zsh/rc.d/35-navigation.zsh`, `dot_bashrc` | The `y` wrapper and launch shortcuts |
| `dot_local/bin/executable_hx-yazi`, `dot_config/helix/config.toml` | Helix's `Ctrl-y` picker |
| `dot_config/starship.toml` | The `󰇥 yazi` prompt badge |
| `dot_local/bin/symlink_fd.tmpl` | `fd` → `fdfind`, for `s` search on Ubuntu |
| `.chezmoiscripts/run_onchange_after_35-install-yazi-plugins.sh.tmpl` | `ya pkg install` when `package.toml` changes; retries on the next apply |
| `.chezmoidata/packages.toml` | `yazi-fm`, `yazi-cli` and `resvg` cargo entries |

## Starting Yazi

| Command | Opens Yazi in |
| --- | --- |
| `y [dir]` | `dir` or here. `q` leaves your shell in Yazi's last folder, `Q` doesn't, `E` hands over to Zed (see [Shell](#shell-and-other-programs)) |
| `yp` / `yd` | `~/Documents/Workspace/Project` / `~/Downloads` |
| `yl` / `yc` / `yr` (Zsh) | The paper library (`g l`) / the chezmoi source / the git root |
| `yazi [dir]` | `dir`, without ever changing the shell's folder |

Passing a file opens its folder with the file hovered.

**From Helix,** `Ctrl-y` opens Yazi at the current buffer. `Enter` or `l` opens
the file in Helix; `q` closes Yazi and `:cd`s Helix to Yazi's folder, `Q` to
the buffer's folder; picking nothing reopens the buffer; `E` opens the folder
in Zed and returns.

## The screen

Three columns, 1:1:2: parent folder, current folder, preview. The header shows
the path and any tabs; the list shows icon, name, size and git mark; the status
bar shows the mode (`NOR`, `SEL` visual select, `UNS` visual unset), size,
permissions and position. Tokyo Night matches Helix, Ghostty and Starship. The
mouse works: click to hover or open, scroll to move.

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

Smart-case: all lowercase ignores case, any uppercase matches exactly. In
results, `Enter` opens, `l` enters, `h` or `Esc` leaves.

## Opening files

`Enter` or `o` opens the selection (or the hovered file) with the first
opener; `O` or `Shift-Enter` lists them all.

| Type | `Enter` | Also in `O` |
| --- | --- | --- |
| Folder | Helix (`l` goes inside) | Open (Thunar), Zed, Reveal |
| Text, code, JSON, JavaScript | Helix (`$EDITOR`) | Zed, Reveal |
| `.txt` | micro | Zed |
| PDF | Zathura | — |
| Image | `xdg-open` | feh, Reveal |
| Audio, video | `xdg-open` (VLC) | Show media info, Reveal |
| Archive | [Extract here](#archives) | Reveal |
| Empty file | Helix | Reveal |
| Anything else | `xdg-open` | Reveal |

Reveal opens the folder in Thunar and comes with Show EXIF (`exiftool`). Helix
and micro take over the terminal; GUI apps run detached. With several files
selected, Helix, micro, Zed and feh get them all (feh as a slideshow);
`xdg-open` gets the first.

### Structure and simulation files

"Editors" means Helix, micro, Zed, `$EDITOR`. Every row also offers Reveal.

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

- VASP names are case-sensitive and extensions aren't, so `poscar_tools.py`
  stays a script. Scripts named after VASP files (`POSCAR_gen.py`, `.sh`,
  `.jl`) open like any other script.
- VESTA can't read compressed files; OVITO reads `.gz` and `.zst` directly.
- A periodic `.cube` (from `pp.x`, say) suits VESTA; for a molecular orbital,
  pick Avogadro 2.
- VESTA and OVITO come from `PATH`, or else `~/Applications` (the newest
  `ovito-*`). VESTA gets every selected file; OVITO and Avogadro 2 the first.

## Selecting

Most operations act on the selection, or on the hovered file. `Space` toggles
and moves down, `v` / `V` select / deselect a range as you move, `Ctrl-a`
selects all, `Ctrl-r` inverts, and `Esc` leaves visual mode or clears.

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

`p` never overwrites: a clash becomes `note_1.txt`. Bulk create and rename use
micro, the first blocking opener for `.txt`; reorder the `local://*.txt` rule
in `yazi.toml` to use Helix.

## Archives

`Enter` on a zip, 7z, rar, tar or compressed tarball extracts it next to the
archive: into `photos/` for `photos.zip`, straight out if it holds a single
top-level folder, `.tar.gz` and friends in one step, never overwriting
(`photos_1/`). Archives, `.deb` packages and disk images preview as listings;
`.deb` and ISO files aren't extracted.

`C` prompts with `7z a .zip <selection>`, the cursor before `.zip`: type a name
and press `Enter`. Paths inside stay relative. Change `.zip` to `.7z` or `.tar`
for those formats.

## Trash

`d` uses the desktop trash, shared with Thunar; `g t` opens it. There, `O`
offers Restore selected files and Empty trash bin; `Enter` opens without
restoring.

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

With several files selected, `c c` and `c r` copy one path per line.

## Previews

Text and code are highlighted, JSON pretty-printed, images and SVG (`resvg`)
drawn through Ghostty's graphics protocol, video shown as a frame (ffmpeg), PDF
as the page, fonts as a sample, archives and folders as listings, and anything
else as `file` output.

| Key | Action |
| --- | --- |
| `J` / `K` | Scroll: text lines, PDF pages, video position |
| `T` | Maximize / restore the preview |
| `Ctrl-p` | Hide / show the preview |
| `Tab` | Spot panel (type, size, dimensions): `j` / `k` rows, `h` / `l` files, `c c` copies a cell, `Tab` or `Esc` closes |

Images are cached at up to 1000×1200 px in `/tmp/yazi-$UID` and appear at once.
`ya cache clear` fixes a stale preview.

## Sorting and columns

Natural sort (`ch2` before `ch10`), folders first, a size column, and dotfiles
hidden (`.` toggles). `~/Downloads` sorts newest first with folders mixed in,
and reverts when the tab leaves. Its subfolders use the normal sort, and a sort
you pick there lasts until you leave.

**Sort** with `,` then `n` natural, `a` alphabetical, `m` modified, `b`
created, `s` size, `e` extension, or `r` random. Uppercase reverses (`, M` is
newest first, `, S` largest first); `m`, `b` and `s` also show that column.
**Right-hand column** with `m` then `s` size, `m` modified, `b` created, `p`
permissions, `o` owner, or `n` none. Both last for the tab.

## Tabs

`t t` opens a tab here, `t r` renames it, `1`–`9` switch, `[` / `]` go to the
previous / next, `{` / `}` move it, and `Ctrl-c` closes it (quitting on the
last). To copy between folders, yank in one tab and paste in another.

## Git

In a repo, files show `?` when untracked or an icon when modified, staged,
added, deleted or ignored; folders show the most important status inside.

- `g r` jumps to the root.
- `g s` lists changed and untracked files below the current folder, so run it
  from the root. It needs one commit; `h` or `Esc` leaves.
- `c r` copies root-relative paths, for `@path` in Claude Code or Markdown
  links.

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

`E` quits with exit code 10 once Zed starts. Under `y`, the shell then cds to
Yazi's folder and closes the Ghostty tab or split, but only interactively in
Ghostty, outside tmux and SSH; elsewhere it stays open there. This matches the
shell's `z` and `c`.

Commands start in the current folder and take placeholders: `%h` hovered, `%s`
selected (or hovered), `%s1`, `%s2`… the first, second… selected, `%d` their
folders, `%y` yanked, `%%` a literal `%`. For example, `;` `chmod +x %h` or
`:` `git log -p -- %h`.

The term-cwd plugin reports Yazi's folder to Ghostty, so Ghostty's new tab,
split and window open there.

## Tasks

Copies, moves, deletes, extractions and `;` commands run as Yazi tasks (not
Taskwarrior), with progress in the status bar. `w` opens the list: `j` / `k`
move, `Enter` shows output, `x` cancels, `w` or `Esc` closes. Quitting with
tasks running asks first.

## Prompts, menus and dialogs

- **Prompts:** type at once; `Enter` submits, `Esc` cancels. `Ctrl-a` /
  `Ctrl-e` go to the start / end, `Ctrl-u` / `Ctrl-k` delete to the start /
  end, `Ctrl-w` deletes a word, `Up` / `Down` (or `Ctrl-p` / `Ctrl-n`) recall
  history, and `Ctrl-[` switches to vi normal mode (word motions, `u` undo).
- **Menus:** `j` / `k`, `Enter`, `Esc`.
- **Confirmations:** `y` or `Enter`; `n` or `Esc`.
- **Help** (`~` or `F1`): `Enter` runs the highlighted binding.

## Recipes

| Goal | Keys |
| --- | --- |
| Open a project file | `y`, `g p`, `z` and part of the name, `Enter` |
| File a download | `g d`, `Enter` to extract, `x`, `g w`, `p` |
| Paste files into a GUI app | Select, `y`, `Ctrl-v` in the app |
| Reference a file in Claude Code | `c r`, then `@` and paste |
| Review a repo's changes | `g r`, `g s` |
| Batch rename | `v` to select, `r`, edit in micro, save, quit, confirm |
| Scaffold files | `A`, then `src/`, `src/main.rs` one per line |
| Undo a deletion | `g t`, select, `O`, Restore selected files |
| Hand a project to Zed | `y`, `g p`, pick it, `E` |
| Compare two folders | `t t`, go to the other folder, `[` / `]` |

## Maintenance

**Config:** edit `dot_config/yazi/*`, then
`chezmoi diff ~/.config/yazi && chezmoi apply ~/.config/yazi`, and restart Yazi.

**Plugins and the flavor** are pinned in `package.toml`. `ya pkg` rewrites the
live lockfile, so copy it back afterwards:

```sh
ya pkg list                            # installed
ya pkg upgrade                         # update everything
ya pkg add yazi-rs/plugins:<name>      # add one
chezmoi add ~/.config/yazi/package.toml
```

A new machine runs `ya pkg install` on `chezmoi apply`. The official plugins
track Yazi's development branch, so upgrade Yazi first.

**Yazi itself:** `yazi` and `ya` here are the prebuilt release in
`/usr/local/bin`. Download `yazi-x86_64-unknown-linux-gnu.zip` from GitHub
releases, check its sha256, and install both with `pkexec install -m 0755`.
Fresh machines get them from cargo via `packages.toml`. Keep both the same
version.

**Debugging:** `YAZI_LOG=debug yazi` writes `~/.local/state/yazi/yazi.log`;
`ya cache clear` resets previews.

| Tool | Used for |
| --- | --- |
| `fd` (→ `fdfind`) | `s`, `z` |
| `rg` | `S` |
| `fzf`, `zoxide` | `z`, `Z` |
| `7z` | Extracting, `C`, archive previews |
| `ffmpeg`, `pdftoppm`, `magick`, `resvg`, `jq` | Video, PDF, HEIC/AVIF/JXL and font, SVG, JSON previews |
| `file` | File type detection |
| `git` | Git marks, `g r`, `g s`, `c r` |
| `xclip`, `python3` | `y` file list, `c i` |
| `clipcopy` | `c y`, `c r` |
| `exiftool` | Show EXIF |
| `hx`, `micro`, `zathura`, `zed`, `feh`, `ghostty` | Openers and quick actions |
| `VESTA`, `ovito`, `avogadro2` | Structure and simulation openers |
| `taskwarrior-tui` | `W` |

## Known limitations

- **No image previews in tmux:** `dot_tmux.conf` doesn't enable
  `allow-passthrough`.
- **Show media info fails:** `mediainfo` isn't installed.
- **Clipboard keys are X11-only:** `y`'s file list, `c i` and `c r` need xclip
  or GNU `realpath`; a Sway session needs Wayland versions.
- **Git changes shows no git marks:** the git plugin logs a harmless "Cannot
  spawn `git`" there, an interaction between two upstream plugins.
- **No drag and drop:** Ghostty doesn't support the protocol yet; `y` and
  `Ctrl-v` cover apps that accept pasted files.
- **The theme waits for the terminal:** it appears once the terminal answers
  Yazi's startup query, at once in Ghostty; terminals that never answer get
  the default theme.

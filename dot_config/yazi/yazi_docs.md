# Yazi Manual

How the Yazi setup in `~/.config/yazi` works and how to use it day to day.
Written for Yazi 26.9.1 in Ghostty on i3/X11. The tracked configuration is
managed by chezmoi: edit the files under `dot_config/yazi/` in the source repo,
not in `~/.config/yazi`. Plugins installed by `ya pkg` are separate.

Press `~` (or `F1`) inside Yazi at any time for the live list of bindings.
The [Helix guide](../helix/docs.md) covers its `Ctrl-y` Yazi picker, and the
[Micro guide](../micro/docs.md) covers that editor's keys when Yazi opens it.

## Contents

- [Files](#files)
- [Starting Yazi](#starting-yazi)
- [The screen](#the-screen)
- [Moving around](#moving-around)
- [Finding things](#finding-things)
- [Opening files](#opening-files)
- [Selecting](#selecting)
- [File operations](#file-operations)
- [Archives](#archives)
- [Trash](#trash)
- [Clipboard](#clipboard)
- [Previews](#previews)
- [Sorting and columns](#sorting-and-columns)
- [Tabs](#tabs)
- [Git](#git)
- [Shell and other programs](#shell-and-other-programs)
- [Tasks](#tasks)
- [Prompts, menus and dialogs](#prompts-menus-and-dialogs)
- [Day-to-day recipes](#day-to-day-recipes)
- [Maintenance](#maintenance)
- [Known limitations](#known-limitations)

## Files

| File | Purpose |
| --- | --- |
| `yazi.toml` | Pane ratio, sorting, size column, preview limits, openers and open rules, git fetchers. |
| `keymap.toml` | Custom keys, added in front of Yazi's defaults. Anything not listed there is a Yazi default. |
| `init.lua` | Starts the `git`, `term-cwd` and `folder-rules` plugins. |
| `theme.toml` | Selects the `tokyo-night` flavor for dark terminals. |
| `package.toml` | Lockfile for `ya pkg`: the six plugins and the flavor, pinned by revision. |
| `plugins/folder-rules.yazi/` | Local plugin: newest-first sorting in `~/Downloads`. |
| `plugins/*.yazi`, `flavors/*.yazi` (others) | Installed by `ya pkg`, not tracked in the repo. |

Related files elsewhere in the repo:

| File | Purpose |
| --- | --- |
| `dot_zsh/rc.d/35-navigation.zsh`, `dot_bashrc` | The `y` wrapper and `yp` alias. |
| `dot_local/bin/executable_hx-yazi`, `dot_config/helix/config.toml` | Helix's `Ctrl-y` file picker. |
| `dot_config/starship.toml` | The `󰇥 yazi` prompt badge in shells opened from Yazi. |
| `dot_local/bin/symlink_fd.tmpl` | `~/.local/bin/fd` → `fdfind`, so `s` search works on Ubuntu. |
| `run_onchange_after_35-install-yazi-plugins.sh.tmpl` | Runs `ya pkg install` when `package.toml` changes. |
| `.chezmoidata/packages.toml` | `yazi-fm`, `yazi-cli` and `resvg` cargo entries. |

## Starting Yazi

| Command | What it does |
| --- | --- |
| `y [dir]` | Start Yazi. Quitting with `q` leaves your shell in Yazi's last directory; `Q` quits without changing it; `E` opens Zed and closes the terminal, like `z` (see [Shell and other programs](#shell-and-other-programs)). |
| `yp` | `y` in `~/Documents/Workspace/Project`. |
| `yazi [dir]` | Plain Yazi; the shell never changes directory. |
| `Ctrl-y` in Helix | Yazi as a file picker (below). |

Passing a directory opens Yazi inside it; passing a file opens its folder with
that file hovered.

### From Helix

`Ctrl-y` in normal mode opens Yazi at the current buffer's file:

- `Enter` or `l` on a file opens it in Helix and closes Yazi.
- `q` closes Yazi, and Helix `:cd`s to the folder you were in.
- `Q` closes Yazi, and Helix `:cd`s to the current buffer's folder.
- If you pick nothing, the current buffer is simply reopened.
- `E` opens the folder in Zed and returns to Helix.

## The screen

Three columns in a 1:1:2 ratio: the parent folder, the current folder, and a
wide preview of the hovered item.

- **Header:** the current path, and tabs when you have more than one.
- **File list:** icon, name, size on the right, and a git mark in git repos.
- **Status bar:** the mode (`NOR`, `SEL` for visual select, `UNS` for visual
  unset), the hovered file's size and permissions, and your position in the
  list.

The Tokyo Night flavor colors the UI and the syntax highlighting in previews.
It matches the Helix, Ghostty and Starship themes.

`T` maximizes the preview and `T` again restores it. `Ctrl-p` hides or shows
the preview. The mouse works too: click to hover or open, scroll to move.

## Moving around

| Key | Action |
| --- | --- |
| `j` / `k` | Next / previous file |
| `l` | Enter the hovered folder, or open the hovered file |
| `h` | Go to the parent folder |
| `H` / `L` | Back / forward in history |
| `gg` / `G` | Top / bottom of the list |
| `Ctrl-d` / `Ctrl-u` | Half page down / up |
| `Ctrl-f` / `Ctrl-b` | Full page down / up |

### Jumps

| Key | Goes to |
| --- | --- |
| `g h` | `~` |
| `g c` | `~/.config` |
| `g d` | `~/Downloads` (sorted newest first) |
| `g w` | `~/Documents/Workspace` |
| `g p` | `~/Documents/Workspace/Project` |
| `g r` | Root of the current git repo |
| `g s` | "Git changes" view (see [Git](#git)) |
| `g t` | Trash (see [Trash](#trash)) |
| `g Space` | Type a path, with `Tab` completion |
| `g f` | The target of the hovered symlink |
| `Z` | A frequently used folder, via zoxide (shares your shell's zoxide history) |
| `z` | Any file below the current folder, dotfiles included, via fzf (uses your shell's `FZF_DEFAULT_COMMAND`) |

## Finding things

| Key | Action |
| --- | --- |
| `/` then text | Jump to the next name containing it; `n` / `N` for next / previous match |
| `?` then text | Same, searching backwards |
| `f` then text | Filter the current folder to matching names; `Esc` clears it |
| `s` then text | Search file names recursively (fd); results appear as a flat list |
| `S` then text | Search file contents recursively (ripgrep) |
| `Ctrl-s` | Cancel a running search |

Matching is smart-case: all lowercase ignores case, any uppercase makes it
case-sensitive. In search results, `Enter` opens, `l` enters, and `h` or `Esc`
leaves the results. `s` with an empty query lists every file below the
current folder.

## Opening files

`Enter` or `o` opens the selected files, or the hovered one, with the first
opener for their type. `O` (or `Shift-Enter`) opens a menu with every opener
for that type.

| File type | `Enter` / `o` | Also in the `O` menu |
| --- | --- | --- |
| Folder | Helix on the folder (use `l` to go inside) | Open (Thunar), Zed, Reveal |
| Text and code | Helix (`$EDITOR`) | Zed, Reveal |
| `.txt` | micro | Zed |
| JSON, JavaScript | Helix | Zed, Reveal |
| PDF | Zathura | none |
| Image | System viewer (`xdg-open`) | feh, Reveal |
| Audio, video | System player (`xdg-open`, VLC) | Show media info, Reveal |
| Archive | Extract here (see [Archives](#archives)) | Reveal |
| Empty file | Helix | Reveal |
| Anything else | `xdg-open` | Reveal |

"Reveal" opens the containing folder in Thunar and always comes with "Show
EXIF", which runs `exiftool`. Helix and micro take over the terminal until you
quit them. GUI openers
(Zathura, Zed, feh, `xdg-open`) run detached, so you can keep using Yazi.

With several files selected, Helix, micro, Zed and feh receive all of them
(several buffers in Helix, a slideshow in feh). `xdg-open` opens only the
first.

## Selecting

Most operations act on the selection, or on the hovered file when nothing is
selected.

| Key | Action |
| --- | --- |
| `Space` | Toggle the hovered file and move down |
| `v` | Visual mode: moving selects a range |
| `V` | Visual unset mode: moving deselects a range |
| `Ctrl-a` | Select everything |
| `Ctrl-r` | Invert the selection |
| `Esc` | Leave visual mode, or clear the selection |

## File operations

| Key | Action |
| --- | --- |
| `y` | Yank (copy) the files. Also puts them on the clipboard as files; see [Clipboard](#clipboard) |
| `x` | Yank to cut (move) |
| `p` | Paste into the hovered folder, or into the current folder when hovering a file |
| `P` | Paste, overwriting files with the same name |
| `Y` or `X` | Cancel the yank |
| `-` / `_` | Symlink the yanked files here, as absolute / relative links |
| `Ctrl--` | Hardlink the yanked files here |
| `a` | Create a file; end the name with `/` to create a folder. `a/b/c.txt` creates the missing folders too |
| `A` | Bulk create: opens micro, one path per line, a trailing `/` makes a folder |
| `r` | Rename, with the cursor before the extension |
| `r` with several selected | Bulk rename: opens micro with one name per line. Edit, save, quit, confirm |
| `d` | Move to the trash (asks first) |
| `D` | Delete permanently (asks first) |
| `C` | Zip the selection (see [Archives](#archives)) |

`p` never overwrites: a clash gets a numbered name such as `note_1.txt`.

Bulk rename and bulk create use micro because they pick the first
terminal-blocking opener for `.txt` files. Reorder the `local://*.txt` rule in
`yazi.toml` to use Helix instead.

## Archives

- **Extract:** `Enter` on a zip, 7z, rar, tar or compressed tarball
  (`.tar.gz`, `.tar.xz`, `.tar.zst`, `.tar.bz2`) extracts it next to the
  archive:
  - into a folder named after the archive (`photos.zip` → `photos/`);
  - straight out if the archive holds a single top-level folder;
  - `.tar.gz` and friends in one step, with no leftover `.tar`;
  - never overwriting: extracting twice gives `photos_1/`.
- **Compress:** `C` opens a prompt with `7z a .zip <selection>`. The cursor
  sits before `.zip`: type a name and press `Enter`. Paths inside the archive
  are relative (plain names, and folders keep their tree). Change `.zip` to
  `.7z` or `.tar` to get that format.

Archives, `.deb` packages and disk images also preview as a file listing, so
you can look inside without extracting. `.deb` and ISO files aren't extracted
by `Enter`.

## Trash

`d` moves files to the desktop trash (the same one Thunar uses). `g t` opens
the trash as a folder:

- `O` on trashed items offers **Restore selected files** (back to their
  original location) and **Empty trash bin**. Select several with `Space` to
  restore them together.
- `Enter` opens the first choice, "Open", without restoring.

## Clipboard

| Key | Copies |
| --- | --- |
| `c c` | Full path |
| `c C` | `file://` URL |
| `c d` / `c D` | Parent folder path / URL |
| `c f` | File name |
| `c n` | File name without the extension |
| `c r` | Path relative to the git root (relative to the current folder outside a repo) |
| `c y` | The file's contents |
| `c i` | The image itself, as an image |
| `y` | Yanks, and also copies the files as a file list |

With several files selected, `c c` and `c r` copy one path per line.

`y` puts the files on the clipboard as a file list (`text/uri-list`), which
`Ctrl-v` pastes into apps that accept pasted files. `c i` puts image data on
the clipboard, for pasting a screenshot into a chat. `c y` and the built-in
`c` keys work anywhere; `y`'s file list, `c i` and `c r` need X11/Linux.

## Previews

The right pane previews the hovered item:

| Type | Preview |
| --- | --- |
| Code, text | Syntax highlighted |
| JSON | Pretty-printed |
| Images, SVG | Real images through Ghostty's graphics protocol (SVG via `resvg`) |
| Video | A frame, via ffmpeg |
| PDF | The rendered page |
| Fonts | A sample |
| Archives | File listing |
| Folders | Their contents, with the current sort |
| Other | The output of `file` |

| Key | Action |
| --- | --- |
| `J` / `K` | Scroll the preview down / up: lines of text, PDF pages, video position |
| `T` | Maximize / restore the preview |
| `Ctrl-p` | Hide / show the preview |
| `Tab` | "Spot" panel: details (type, size, dimensions and so on) |

In the Spot panel, `j` / `k` move between rows, `h` / `l` switch to the
previous / next file, `c c` copies the highlighted cell, and `Tab` or `Esc`
closes it.

Images are cached at up to 1000×1200 px in `/tmp/yazi-$UID`, and they appear
without any delay. Run `ya cache clear` if a preview looks stale.

## Sorting and columns

- **Default:** natural sort (`ch2` before `ch10`) with folders first, and a
  size column.
- **`~/Downloads`:** newest first, with folders mixed in. It switches on when
  a tab enters Downloads and back to that tab's previous sort when it leaves.
  Subfolders of Downloads use your normal sort. A sort you choose by hand
  inside Downloads lasts until you leave, even while new downloads land.

| Key | Sort by |
| --- | --- |
| `, n` / `, N` | Natural / reversed |
| `, a` / `, A` | Alphabetical / reversed |
| `, m` / `, M` | Modified time, oldest / newest first (also shows the time column) |
| `, b` / `, B` | Created time / reversed (also shows it) |
| `, s` / `, S` | Size, smallest / largest first (also shows sizes) |
| `, e` / `, E` | Extension / reversed |
| `, r` | Random |

| Key | Right-hand column |
| --- | --- |
| `m s` | Size (default) |
| `m m` | Modified time |
| `m b` | Created time |
| `m p` | Permissions |
| `m o` | Owner |
| `m n` | Nothing |

`.` shows or hides dotfiles (hidden by default). Sort and column changes
apply to the current tab until you change them again.

## Tabs

| Key | Action |
| --- | --- |
| `t t` | New tab in the current folder |
| `t r` | Rename the current tab |
| `1` to `9` | Switch to tab N |
| `[` / `]` | Previous / next tab |
| `{` / `}` | Move the current tab left / right |
| `Ctrl-c` | Close the tab (quits Yazi if it is the last one) |

Copying between two folders: open the other folder in a second tab, yank in
one tab, switch tabs, and paste.

## Git

Inside a git repo, each file shows its status:

- `?` for untracked files;
- icons for modified, staged, added, deleted and ignored files;
- folders show the most important status of what they contain.

| Key | Action |
| --- | --- |
| `g r` | Jump to the repo root |
| `g s` | "Git changes": a flat list of changed and untracked files |
| `c r` | Copy paths relative to the repo root, for `@path` in Claude Code or Markdown links |

"Git changes" only lists changes under the current folder, so run it from the
root (`g r` first) to see everything. The repo needs at least one commit. Open
files from the list as usual; `h` or `Esc` leaves it.

## Shell and other programs

| Key | Action |
| --- | --- |
| `!` | Open your shell in the current folder; `exit` returns to Yazi |
| `;` | Run a command in the background |
| `:` | Run a command in the foreground, for interactive programs such as `git add -p` or `htop` |
| `E` | Open the current folder in Zed, quit Yazi, and close the terminal (like `z` in the shell) |
| `Ctrl-t` | New Ghostty window in the current folder |
| `W` | Open taskwarrior-tui full-screen; quitting it (`q`) returns to Yazi |
| `Ctrl-z` | Suspend Yazi; `fg` brings it back |
| `q` | Quit |

In a shell opened with `!`, the Starship prompt starts with `󰇥 yazi`. That's
the reminder to `exit` back instead of starting another Yazi.

`E` follows the same rule as the shell's `z` and `c`. Once Zed has started,
Yazi quits with exit code 10. `y` then cds to Yazi's folder and closes the
Ghostty tab or split, but only in an interactive shell in Ghostty, outside
tmux and SSH. Anywhere else the shell stays open in that folder. Started as
plain `yazi`, `E` just opens Zed and quits.

Commands run by `;` and `:` start in the current folder and can use these
placeholders:

| Placeholder | Expands to |
| --- | --- |
| `%h` | The hovered file |
| `%s` | The selected files (or the hovered one) |
| `%s1`, `%s2` … | The first, second … selected file |
| `%d` | The folders containing the selected files |
| `%y` | The yanked files |
| `%%` | A literal `%` |

Examples: `;` then `chmod +x %h`, or `:` then `git log -p -- %h`.

Yazi reports its folder to Ghostty as you move (the term-cwd plugin). So
Ghostty's own new tab, split and window keys open in Yazi's current folder.

## Tasks

Copies, moves, deletes, extractions and background commands run as tasks. The
status bar shows their progress. These are Yazi's own jobs, unrelated to
Taskwarrior; `W` opens taskwarrior-tui.

| Key | Action |
| --- | --- |
| `w` | Open the task list |
| `j` / `k` | Move between tasks |
| `Enter` | Show a task's output |
| `x` | Cancel a task |
| `w` or `Esc` | Close the list |

Quitting while tasks are running asks for confirmation.

## Prompts, menus and dialogs

**Prompts** (rename, create, search, shell, `g Space`):

- You start typing straight away; `Enter` submits; `Esc` cancels.
- Line editing: `Ctrl-a` / `Ctrl-e` jump to the start / end, `Ctrl-u` /
  `Ctrl-k` delete to the start / end, `Ctrl-w` deletes a word.
- `Up` / `Down` (or `Ctrl-p` / `Ctrl-n`) recall earlier entries.
- `Ctrl-[` switches to vi-style normal mode, for word motions and `u` undo.

**Menus** (the `O` menu, help): `j` / `k` to move, `Enter` to choose, `Esc` to
cancel.

**Confirmations:** `y` or `Enter` to confirm, `n` or `Esc` to cancel.

**Help** (`~` or `F1`): lists every binding for the current context. `Enter`
runs the highlighted one.

## Day-to-day recipes

| Goal | Keys |
| --- | --- |
| Open a project file in Helix | `y`, `g p`, `z` and type part of the name, `Enter`. Quit Helix to come back. `q` leaves your shell in that folder. |
| Deal with a download | `g d` (newest first), `Enter` on an archive to extract it, `x` on the result, `g w`, `p` to move it into the workspace. |
| Paste files into a GUI app | Select with `Space`, `y`, then `Ctrl-v` in an app that accepts pasted files. |
| Paste a screenshot into chat | Hover the image, `c i`, `Ctrl-v`. |
| Reference code in Claude Code | Hover the file, `c r`, type `@` and paste. |
| Review what changed in a repo | `g r`, `g s`, `Enter` on a file to open it in Helix. |
| Rename a batch of files | `v` and move to select, `r`, edit the names in micro, save, quit, confirm. |
| Scaffold files and folders | `A`, write `src/`, `src/main.rs`, `README.md` one per line, save, quit, confirm. |
| Zip files for email | Select, `C`, type the name, `Enter`. |
| Find a file you only half remember | `s` and part of the name, or `S` and a phrase from its contents. |
| Undo a deletion | `g t`, select the file, `O`, "Restore selected files". |
| Run a few commands here | `!`, work, `exit`. |
| Check your Taskwarrior list | `W`, look or edit, `q` to return to Yazi. |
| Hand a project over to Zed | `y`, `g p`, pick the project, `E`: Zed opens there and the terminal closes. |
| Browse a folder in Thunar | `O` then "Open" on the folder. |
| Compare two folders side by side | `t t`, go to the second folder, switch with `[` / `]`. |

## Maintenance

**Change the config.** Edit `dot_config/yazi/*` in the chezmoi source, then:

```sh
chezmoi diff ~/.config/yazi
chezmoi apply ~/.config/yazi
```

Restart Yazi to pick up the changes.

**Plugins and the flavor.** They're pinned in `package.toml`:

```sh
ya pkg list                            # what is installed
ya pkg upgrade                         # update everything
ya pkg add yazi-rs/plugins:<name>      # add one
chezmoi add ~/.config/yazi/package.toml
```

`ya pkg` rewrites the live `package.toml`, so pull it back into the repo with
`chezmoi add` afterwards. On a new machine, `chezmoi apply` runs
`ya pkg install` from the lockfile. The official plugins track Yazi's
development branch, so upgrade Yazi before upgrading plugins.

**Upgrade Yazi.** On this machine `yazi` and `ya` are the official prebuilt
release in `/usr/local/bin`. Download the new
`yazi-x86_64-unknown-linux-gnu.zip` from the GitHub releases page, check its
sha256, and install both binaries with `pkexec install -m 0755`. Fresh
machines get Yazi from cargo through `packages.toml` instead. `yazi` and `ya`
must always be the same version.

**Debugging.** Two tools help:

- `YAZI_LOG=debug yazi` writes `~/.local/state/yazi/yazi.log`.
- `ya cache clear` resets previews.

**External tools used:**

| Tool | Used for |
| --- | --- |
| `fd` (`~/.local/bin/fd` → `fdfind`) | `s` search, `z` |
| `rg` | `S` search |
| `fzf`, `zoxide` | `z`, `Z` |
| `7z` | Extracting, `C`, archive previews |
| `ffmpeg` | Video previews |
| `pdftoppm` | PDF previews |
| `magick` | HEIC/AVIF/JXL and font previews |
| `resvg` | SVG previews |
| `jq` | JSON previews |
| `file` | File type detection |
| `git` | Git marks, `g r`, `g s`, `c r` |
| `xclip`, `python3` | `y` file list, `c i` |
| `clipcopy` | `c y`, `c r` |
| `exiftool` | "Show EXIF" |
| `hx`, `micro`, `zathura`, `zed`, `feh`, `ghostty` | Openers and quick actions |
| `taskwarrior-tui` | `W` |

## Known limitations

- **No image previews inside tmux.** `dot_tmux.conf` doesn't enable
  `allow-passthrough`, so images only show when Yazi runs directly in Ghostty.
- **"Show media info" fails for audio and video.** `mediainfo` isn't
  installed.
- **The clipboard keys are X11-only.** `y`'s file list, `c i` and `c r` need
  xclip or GNU `realpath`. A Sway session will need Wayland versions.
- **The "Git changes" view shows no git marks.** The git plugin logs a
  harmless "Cannot spawn `git`" error there. It's an interaction between the
  two upstream plugins.
- **No drag and drop.** Yazi can drag files to other apps, but only in
  terminals that support the drag-and-drop protocol, which Ghostty doesn't
  yet. `y` and `Ctrl-v` work in apps that accept pasted file lists.
- **The theme appears once the terminal answers Yazi's startup query.** That's
  instant in Ghostty. Terminals that never answer get the default theme.

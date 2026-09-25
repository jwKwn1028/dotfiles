# Zsh shortcuts and commands

The interactive shell loads `rc.d/_lib.zsh`, then the numbered `rc.d` modules.
This guide covers the user-facing keys and functions defined there. The
machine-specific remote settings come from the local chezmoi data file; no
remote endpoint, account name, or SSH alias belongs in this guide.

## Editing the command line

`zsh-helix-mode` provides the modal command line when its plugin is installed.
The following bindings are added on top of it:

| Keys | Mode | Action |
| --- | --- | --- |
| `j k` or `Escape` | Insert | Return to normal mode. |
| `Alt+H` / `Alt+L` | Insert | Move left / right, clearing the selection. |
| `Alt+J` / `Alt+K` | Insert | Move down / up, or to the next / previous history item. |
| `Alt+Q` / `Alt+E` | Insert | Move to the start / end of the command line. |
| `v` | Normal | Enter select mode. |
| `V` | Normal or select | Paste after the cursor, or replace selections with the clipboard. |
| `Ctrl+X Ctrl+E` | Insert, normal, or plain Zsh | Edit the command line in the configured editor. |
| `Ctrl+T` | Insert or normal | Pick a file with fzf and insert its path. |
| `Alt+C` | Insert or normal | Pick a directory with fzf and change to it. |
| `Ctrl+R` | Insert or normal | Search command history with fzf. |
| `Tab` | With the Helix/fzf integration | Complete through fzf. |
| `Ctrl+F` | Shell prompt | Accept the autosuggestion. |
| `Alt+F` | Shell prompt | Move forward one word. |

The fzf keys depend on its installed widgets. The command line keymap is
separate from the editor keymaps in `~/.config/helix/docs.md`,
`~/.config/zed/docs.md`, and `~/.config/Code/User/docs.md`.

## Daily commands

| Command | Action |
| --- | --- |
| `hz` | Edit the Zsh source through chezmoi, review the diff, and ask whether to apply the scoped change. |
| `sz` | Show loaded Zsh changes, check syntax, then restart the shell. |
| `c` / `z` | Open the current directory in VS Code / Zed. In an interactive Ghostty tab outside tmux and SSH, close that shell after launch. |
| `n`, `r`, `y` | Run nnn, ranger, or Yazi; on exit, follow the directory selected there. |
| `hf` | Pick a file with fzf and open it in Helix. |
| `zn` / `zs SEARCH` | Pick a note / search note contents, then open the choice in Helix. |
| `ex ARCHIVE` | Extract a supported archive into the current directory. |
| `so` / `zo` | Pick a PDF or pass one as an argument; prefer Sioyek / Zathura. |
| `bo` | Pick or open an EPUB in ebook-viewer. |
| `io` | Pick or open images in xviewer, falling back to feh. |
| `thunar` | Open Thunar in the current directory when no path is given. |
| `crpf` / `crpd` | Pick a file / directory and copy its path to the clipboard. |
| `COMMAND Y` | Global alias that pipes a command's output to `clipcopy`. |
| `sysmon [SECONDS]` | Show live CPU, GPU, RAM, temperature, and fan readings. |
| `zpup` | Fast-forward Git-based Zsh plugins; run `sz` to load updates. |
| `wtail FILE...` | Watch the last ten lines of each file, refreshing every ten seconds. |
| `poweroff` | Ask for confirmation with a ten-second timeout before shutting down. |
| `btop` | In Ghostty, temporarily shrink the font while btop runs, then reset it. |

Short aliases include `h` for Helix in the current directory, `mo` for Micro,
`twt` for taskwarrior-tui, `tcal` for task-calendar, and `:q` for exiting the
shell. `:qa` sends an Alt+F4 keypress to the active window on X11. `ls` uses
eza, `rg` uses smart-case search, and `v` opens Vim in the current directory.

`cd --`, `cd ---`, and longer runs of `-` go back two, three, or more entries
in Zsh's directory stack. With `zoxide` installed, ordinary `cd` also records
navigation. `yp`, `np`, and `rp` start their file managers in the configured
workspace directory; `~/.config/yazi/yazi_docs.md` covers
the Yazi wrapper in detail.

The `t<W><D><d|s>` Taskwarrior shortcuts, their time and priority suffixes,
and reminder offsets are documented in `~/.config/task/MANUAL.md`.

## Remote helpers

These function names are public parts of the shell setup. They use endpoints
supplied by local chezmoi data; substitute no real address or alias into this
file.

| Command | Action |
| --- | --- |
| `labroute status|on|off|toggle` | Inspect or change the optional remote route. |
| `ssh-close` / `ssh-close -a` | List shared connections / close all configured shared connections. |
| `ssh-close HOST_ALIAS` | Close one shared SSH connection using an alias supplied locally. |
| `cdcluster`, `sftp-gpu`, `sftp-hpc` | Open SFTP to the configured default or named remote role. |
| `grem`, `grem-gpu`, `grem-hpc` | Download one or more remote paths into the current directory. |
| `prem`, `prem-gpu`, `prem-hpc` | Upload local paths, optionally specifying a remote destination. |
| `hpc-list`, `hpc [SESSION]` | List remote sessions or attach to a named tmux session. |
| `hpc-detach SESSION`, `hpc-kill SESSION` | Detach clients or terminate a named tmux session. |
| `hpcz-list`, `hpcz [SESSION]` | List sessions or attach to a named zmx session. |
| `hpcz-detach SESSION`, `hpcz-kill SESSION` | Detach clients or terminate a named zmx session. |

Use `-f` only when the relevant kill helper reports that a session has attached
clients and you intend to override that guard.

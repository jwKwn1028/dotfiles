# Zsh shortcuts and commands

The interactive shell loads `rc.d/_lib.zsh`, then the numbered `rc.d` modules.
Remote endpoints, account names, and SSH aliases come from local chezmoi data;
never write real ones into this guide.

## Editing the command line

`zsh-helix-mode`, when installed, makes the command line modal: block cursor in
normal mode, underline in select, bar in insert or a Helix prompt. The shape is
restored on every redraw, including after fzf or the editor; Ghostty's shell
integration uses `no-cursor` to leave it alone. Bindings added on top:

| Keys | Mode | Action |
| --- | --- | --- |
| `j k` / `Escape` | Insert | Return to normal mode. |
| `Alt+H` / `Alt+L` | Insert | Move left / right, clearing the selection. |
| `Alt+J` / `Alt+K` | Insert | Move down / up, or to the next / previous history item. |
| `Alt+Q` / `Alt+E` | Insert | Move to the start / end of the command line. |
| `v` | Normal | Enter select mode. |
| `V` | Normal, select | Paste after the cursor, or replace selections with the clipboard. |
| `Ctrl+X Ctrl+E` | Insert, normal, plain Zsh | Edit the command line in the configured editor. |
| `Ctrl+T` / `Alt+C` | Insert, normal | Pick a file with fzf and insert its path / pick a directory and `cd` to it. |
| `Ctrl+R` | Insert, normal | Search history with fzf. |
| `Tab` | Helix/fzf integration | Complete through fzf. |
| `Ctrl+F` / `Alt+F` | Prompt | Accept the autosuggestion / move forward one word. |

The fzf keys need fzf's installed widgets. Editor keymaps are separate: see
`~/.config/helix/docs.md`, `~/.config/zed/docs.md`, and
`~/.config/Code/User/docs.md`.

## Daily commands

| Command | Action |
| --- | --- |
| `hz` | Edit the Zsh source through chezmoi, review the diff, and offer a scoped apply. |
| `sz` | Show loaded Zsh changes, check syntax, and restart the shell. |
| `c` / `z` | Open the current directory in VS Code / Zed.* |
| `thunar [PATH...]` | Open the paths, or the current directory, in Thunar.* |
| `n` / `r` / `y` | Run nnn / ranger / Yazi; on exit, `cd` to the directory chosen there. |
| `np` / `rp` / `yp` | The same, starting in the configured workspace directory. |
| `yd` | Yazi, starting in `~/Downloads`. |
| `yl` | Yazi, starting in `~/Documents/Workspace/Known/Paper/Library/Library`. |
| `yc` | Yazi in the chezmoi source directory. |
| `yr` | Yazi at the current Git root. |
| `hf` | Pick a file with fzf and open it in Helix. |
| `zn` / `zs SEARCH` | Pick a note / search note contents, then open the choice in Helix. |
| `so` / `zo` | Open a picked or given PDF, preferring Sioyek / Zathura. |
| `bo` | Open a picked or given EPUB in ebook-viewer. |
| `io` | Open picked or given images in xviewer, falling back to feh. |
| `ex ARCHIVE` | Extract a supported archive into the current directory. |
| `crpf` / `crpd` | Pick a file / directory and copy its path to the clipboard. |
| `COMMAND Y` | Global alias that pipes the output to `clipcopy`. |
| `sysmon [SECONDS]` | Live CPU, GPU, RAM, temperature, and fan readings. |
| `wtail FILE...` | Watch each file's last ten lines, refreshing every ten seconds. |
| `zpup` | Fast-forward Git-based Zsh plugins; `sz` loads the updates. |
| `poweroff` | Shut down after a confirmation with a ten-second timeout. |

\* In an interactive Ghostty tab or split outside tmux and SSH, `c`, `z`, and
`thunar` without arguments close the shell after a successful launch.

Short aliases: `h` (Helix here), `v` (Vim here), `mo` (Micro), `twt`
(taskwarrior-tui), `tcal` (task-calendar), `:q` (exit the shell), and `:qa`
(send Alt+F4 to the active X11 window). `ls` runs eza; `rg` searches smart-case.

`cd --`, `cd ---`, and longer runs of `-` step back two, three, or more entries
in the directory stack. With zoxide installed, plain `cd` also records visits.

`poweroff`, in Bash and Zsh, runs `~/.local/bin/poweroff-confirm`: `y` or `yes`
confirms; blank input, timeout, Ctrl-C, or no terminal cancels; arguments are
rejected. Its mocked terminal checks run from the repo with
`python3 dot_local/bin/tests/executable_test-poweroff-confirm.py`.

See also `~/.config/yazi/yazi_docs.md` for the Yazi wrapper and
`~/.config/task/MANUAL.md` for the `t<W><D><d|s>` Taskwarrior shortcuts, their
time and priority suffixes, and reminder offsets.

## Remote helpers

Unsuffixed helpers use the default remote; `-gpu` / `-hpc` select a named role.

| Command | Action |
| --- | --- |
| `labroute [status\|on\|off\|toggle]` | Inspect (default) or change the optional remote route. |
| `ssh-close [-a \| HOST_ALIAS]` | List shared SSH connections; `-a` closes all configured ones, an alias closes one. |
| `cdcluster`, `sftp-gpu`, `sftp-hpc` | Open SFTP to the remote. |
| `grem`, `grem-gpu`, `grem-hpc` | Download remote paths into the current directory. |
| `prem`, `prem-gpu`, `prem-hpc` | Upload local paths, optionally to a given remote destination. |
| `hpc-list`, `hpc [SESSION]` | List remote tmux sessions, or attach to one. |
| `hpc-detach SESSION`, `hpc-kill [-f] SESSION` | Detach a tmux session's clients, or terminate it. |
| `hpcz-list`, `hpcz`, `hpcz-detach`, `hpcz-kill` | The same, for zmx sessions. |

The kill helpers refuse a session with attached clients unless given `-f`.

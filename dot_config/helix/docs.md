# Helix keybindings

Custom `config.toml` keys; defaults still apply. Spaces separate key sequences;
uppercase means Shift. Python DAP is in `languages.toml`.

## Session recovery

tmux restores each split's file, cursor and launch options, and other buffers.
Splits return if all side by side or all stacked, else as buffers. Later buffers
return if their name is unique near open files, in their git repositories or
under Helix's directory. Unsaved edits are lost; `hxp` panes recover separately.

## Writing language servers

Markdown: marksman + zk; LaTeX/BibTeX: texlab; Typst: tinymist.
Plain text wraps without an LSP.

## Normal mode

| Keys | Action |
| --- | --- |
| `Enter` | Open a line below the selection; stay in normal mode. |
| `V`, `Space p` | Paste the clipboard before the selection. |
| `Space P` | Paste the clipboard after the selection. |
| `Ctrl+L` | Jump to the cursor's spot in the open PDF (LaTeX, Markdown); Typst raises its viewer. |
| `Ctrl+Y` | Pick a file in Yazi; quitting can change Helix's directory ([Yazi guide](../yazi/yazi_docs.md#from-helix)). |

### Python debugger

`Alt+D`, then a key below. uv runs debugpy; launch prompts for a template.

| Next key | Action |
| --- | --- |
| `t` | Toggle a breakpoint. |
| `d` | Launch a debug session. |
| `c` | Continue. |
| `n` / `i` / `o` | Step over / into / out. |
| `v` | Show variables. |
| `r` | Restart. |
| `k` | Terminate. |

## Insert mode

| Keys | Action |
| --- | --- |
| `Alt+H` / `Alt+L` | Move left / right. |
| `Alt+J` / `Alt+K` | Move down / up. |
| `Alt+Q` / `Alt+E` | Move to the line's start / end. |
| `j k` | Return to normal mode. |

## Select mode

| Keys | Action |
| --- | --- |
| `V` | Replace the selection with the clipboard. |
| `Tab` / `Shift+Tab` | Indent / outdent. |
| `Space p` / `Space P` | Paste the clipboard before / after the selection. |

[Zed](../zed/docs.md) and VS Code (`~/.config/Code/User/docs.md`) mirror these
where they can.

## Bash and Zsh

`shfmt` formats Bash on save but never Zsh, whose syntax it breaks; Zsh keeps
Bash's highlighting.

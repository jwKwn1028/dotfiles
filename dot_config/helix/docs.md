# Helix keybindings

Custom `config.toml` keys; defaults still apply. Spaces mean sequences;
uppercase requires Shift. Python DAP is in `languages.toml`.

## Writing language servers

Markdown: marksman + zk; LaTeX/BibTeX: texlab; Typst: tinymist.
Plain text wraps without an LSP.

## Normal mode

| Keys | Action |
| --- | --- |
| `Enter` | Open a line below the selection and return to normal mode. |
| `V` | Paste the system clipboard before the selection. |
| `Space p` | Paste the system clipboard before the selection. |
| `Space P` | Paste the system clipboard after the selection. |
| `Ctrl+L` | Forward search from the cursor to an open PDF viewer. LaTeX and Markdown use the matching PDF; Typst raises its viewer. |
| `Ctrl+Y` | Open Yazi at the current buffer as a file picker. Opening a file returns to Helix; quitting can update Helix's working directory. |

The `Ctrl+Y` integration is also described in the
[Yazi guide](../yazi/yazi_docs.md#from-helix).

### Python debugger

Alt+D, then a key below. uv runs debugpy; launch prompts for a template/parameters.

| Next key | Action |
| --- | --- |
| `t` | Toggle a breakpoint. |
| `d` | Launch a debug session. |
| `c` | Continue. |
| `n` | Step over. |
| `i` | Step into. |
| `o` | Step out. |
| `v` | Show variables. |
| `r` | Restart. |
| `k` | Terminate. |

## Insert mode

| Keys | Action |
| --- | --- |
| `Alt+H` / `Alt+L` | Move left / right. |
| `Alt+J` / `Alt+K` | Move down / up. |
| `Alt+Q` / `Alt+E` | Move to the beginning / end of the line. |
| `j k` | Return to normal mode. Type the two letters in sequence. |

## Select mode

| Keys | Action |
| --- | --- |
| `V` | Replace the selection with the system clipboard. |
| `Tab` / `Shift+Tab` | Indent / outdent the selection. |
| `Space p` | Paste the system clipboard before the selection. |
| `Space P` | Paste the system clipboard after the selection. |

These insert and paste choices are mirrored in the
[Zed guide](../zed/docs.md) and `~/.config/Code/User/docs.md` where those
editors support them.

## Bash and Zsh

`shfmt` formats Bash on save but never Zsh, whose syntax it breaks; Zsh keeps
Bash's highlighting.

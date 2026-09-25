# Helix keybindings

This guide covers the custom bindings in `config.toml`. Helix's default modal
keymap still applies. `languages.toml` supplies the Python debugger used by the
debug keys below. A space between keys means press them in sequence; uppercase
letters require Shift.

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

Press `Alt+D`, then one of these keys. The adapter is `debugpy`, launched
through `uv` as configured in `languages.toml`. Launching prompts for a debug
template and its parameters.

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

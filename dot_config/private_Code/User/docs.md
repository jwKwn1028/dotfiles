# VS Code keybindings

These are all the shortcuts added or removed by `keybindings.json`. VS Code's
other default shortcuts and the Helix extension's own bindings still apply. The
modal shortcuts require `jasew.vscode-helix-emulation`. Open **Keyboard
Shortcuts** in VS Code to inspect the complete active keymap.

A space between keys means press them in sequence. `Shift Shift` means tap Shift
twice. The `Ctrl+T` and `Ctrl+G` sequences are prefix chords.

## Workbench and panels

| Keys | Action |
| --- | --- |
| `Ctrl+Alt+A` | Toggle the activity bar. |
| `Shift+Alt+S` | Toggle the status bar. |
| `Shift Shift` | Open Quick Open to find a file. |
| `Ctrl+Alt+Z` | Toggle the command center. |
| `Ctrl+T Ctrl+L` | Toggle the primary sidebar, configured on the right. |
| `Ctrl+T Ctrl+H` | Toggle the auxiliary sidebar. |
| `Ctrl+T Ctrl+P` | Toggle the integrated terminal. |
| `Ctrl+T Ctrl+S` | Toggle the status bar. |
| `Ctrl+T Ctrl+\` | Toggle the split editor in the current editor group. |
| `Ctrl+P Ctrl+M` | Maximize or restore the panel. |
| `Ctrl+'` | Toggle the integrated terminal when a terminal is active. |
| `Ctrl+G Ctrl+N` | Focus the next editor group. |
| `Ctrl+G Ctrl+A` | Focus the editor group to the left. |
| `Ctrl+G Ctrl+D` | Focus the editor group to the right. |
| `Ctrl+Q` | Close the current VS Code window. |

`Ctrl+Alt+B` no longer toggles the auxiliary sidebar. `Ctrl+K Ctrl+Left` and
`Ctrl+K Ctrl+Right` no longer focus the left and right editor groups. The
terminal's default `Ctrl+Backtick` toggle and the default `Ctrl+Q` quit action are
removed; use `Ctrl+'` or `Ctrl+T Ctrl+P` for the terminal and `Ctrl+Q` to close
the current window.

## Editing and notebooks

| Keys | Where | Action |
| --- | --- | --- |
| `Ctrl+T Ctrl+B` | Writable Markdown, R Markdown, or Quarto editor | Toggle bold formatting via Markdown All in One. |
| `Alt+B` | Jupyter notebook | Add a cell below. |
| `Shift+H` / `Shift+L` | Helix normal or visual mode in an editor | Focus the previous / next editor tab. |
| `Ctrl+H Ctrl+M` | Focused editor in Helix normal or visual mode | Disable Helix mode. |
| `Ctrl+H Ctrl+M` | Focused editor with Helix disabled | Re-enable Helix mode. |

For Markdown, R Markdown, and Quarto editors, the extension's default `Ctrl+B`
bold shortcut is removed in favor of `Ctrl+T Ctrl+B`.

### Helix insert mode

| Keys | Action |
| --- | --- |
| `Alt+H` / `Alt+L` | Move left / right. |
| `Alt+J` / `Alt+K` | Move down / up. |
| `Alt+Q` / `Alt+E` | Move to the beginning / end of the line. |
| `j k` | Leave insert mode. Type them in sequence; the chord briefly waits after `j`. |

### Helix normal and selection modes

| Keys | Mode | Action |
| --- | --- | --- |
| `Enter` | Normal | Insert a line below, then return to normal mode. |
| `Shift+V` | Normal, visual, or select | Paste from the clipboard. |
| `Tab` | Visual or select | Indent selected lines. |
| `Shift+Tab` | Visual or select | Outdent selected lines. |

For the corresponding terminal editor keys, see the
[Helix guide](../../helix/docs.md). Keep account names, remote hosts, and local
project paths out of this managed document.

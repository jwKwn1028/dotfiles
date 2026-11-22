# VS Code keybindings

Custom `keybindings.json` keys; defaults still apply. Modal keys need
`jasew.vscode-helix-emulation`. **Keyboard Shortcuts** shows the full keymap.
Spaces mean sequences; Shift Shift is a double tap; Ctrl+T/G are prefixes.

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
| `Ctrl+T Ctrl+M` | Toggle the menu bar between Alt-only and always shown. |
| `Ctrl+T Ctrl+\` | Toggle the split editor in the current editor group. |
| `Ctrl+P Ctrl+M` | Maximize or restore the panel. |
| `Ctrl+'` | Toggle the integrated terminal when a terminal is active. |
| `Ctrl+G Ctrl+N` | Focus the next editor group. |
| `Ctrl+G Ctrl+A` | Focus the editor group to the left. |
| `Ctrl+G Ctrl+D` | Focus the editor group to the right. |
| `Ctrl+Q` | Close the current VS Code window. |

Unbound defaults: Ctrl+Alt+B, Ctrl+K Ctrl+Left/Right, Ctrl+Backtick.
Ctrl+Q closes this window rather than quitting the application.

Status/menu bars start hidden; left Alt reveals the menu once. Alt-letter
mnemonics yield to editing keys. Native title bars/menus follow the GTK theme.
Ctrl+T Ctrl+S/M changes live settings: `chezmoi re-add` to retain them, or toggle
back before apply.

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

# Micro keybindings

These are all the bindings in `bindings.json`; Micro's default bindings also
apply. A space between keys means a sequence. `Alt+1` through `Alt+9` below
mean the corresponding numbered key, not a literal `1–9` character.

## Movement and navigation

| Keys | Action |
| --- | --- |
| `Alt+H` / `Alt+L` | Move the cursor left / right. |
| `Alt+J` / `Alt+K` | Move down / up one line. |
| `Alt+1` … `Alt+9`, then `Alt+J` | Move down that many lines. |
| `Alt+1` … `Alt+9`, then `Alt+K` | Move up that many lines. |
| `Alt+Q` / `Alt+E` | Move to the start / end of the line. |
| `Alt+W` / `Alt+B` | Move to the next / previous word. |
| `Alt+G` / `Alt+Shift+G` | Move to the start / end of the file. |
| `Alt+M` | Jump to the matching brace. |
| `Alt+,` / `Alt+.` | Switch to the previous / next tab. |

## Editing and tools

| Keys | Action |
| --- | --- |
| `Alt+Z` / `Alt+R` | Undo / redo. |
| `Alt+/` or `Ctrl+_` | Toggle a comment through the comment plugin. |
| `Ctrl+Enter` | Insert a newline when the terminal sends the configured modified-Return sequence. |
| `Ctrl+O` | Open the fzf plugin. |
| `Ctrl+G` | Open the command bar with `goto ` already entered. |
| `Alt+D` / `Alt+U` | Open the command bar with `jump +` / `jump -` entered. |
| `Alt+T` | Toggle the file manager tree. |
| `Alt+;` | Toggle Micro's key menu. |

The `Ctrl+Enter` entry in `bindings.json` is the terminal escape sequence
`ESC[27;5;13~`. It only works when the terminal emits that sequence; Ghostty's
[config](../ghostty/docs.md) leaves `Ctrl+Enter` available to terminal programs.

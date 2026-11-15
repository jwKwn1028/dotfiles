# Micro keybindings

| Keys | Action |
| --- | --- |
| `Alt+H` / `J` / `K` / `L` | Left / down / up / right |
| `Alt+1`…`9`, then `Alt+J` / `K` | Down / up that many lines |
| `Alt+Q` / `E`, `Alt+W` / `B` | Line start / end, next / previous word |
| `Alt+G` / `Alt+Shift+G`, `Alt+M` | File start / end, matching brace |
| `Alt+,` / `.` | Previous / next tab |
| `Alt+Z` / `R` | Undo / redo |
| `Alt+/` or `Ctrl+_` | Toggle comment |
| `Ctrl+Enter` or `Shift+Enter` | Newline |
| `Ctrl+G`, `Alt+D` / `U` | `goto`, `jump +` / `jump -` prompt |
| `Ctrl+O`, `Alt+T`, `Alt+;` | fzf, file tree, key menu |

Modified Enter keys are bound by escape sequence; unbound, Micro reads one as
`Alt+[` (file start) plus literal text.

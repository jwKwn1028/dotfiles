# Thunar keybindings

Yazi-style keys. Actions are set in `modify_accels.scm`, cursor keys in the
Ghostty-TokyoNight `gtk.css`. Text fields are unaffected.

| Keys | Action | Replaces |
| --- | --- | --- |
| `h` `j` `k` `l` | Left / down / up / right | |
| `J` / `K` | Extend selection | |
| `Ctrl+j` / `Ctrl+k` | Move without selecting; `Ctrl+Space` toggles | |
| `g` / `G` | First / last item | |
| `H` / `L` | Back / forward | `Alt+Left` / `Alt+Right` |
| `-` | Parent folder | `Alt+Up` |
| `y` `x` `p` | Copy / cut / paste | `Ctrl+Insert` / – / `Shift+Insert` |
| `d` / `D` | Trash / delete | |
| `r` | Rename | `F2` |
| `a` | New folder | `Ctrl+Shift+N` |
| `.` | Hidden files | `Ctrl+H` |
| `s` | Search | `Ctrl+F` |
| `t` | New tab | `Ctrl+T` |
| `q` | Close window | `Ctrl+Q` (kept by `quit-key.py`) |

Enter opens. `h`/`l` move only in icon and compact views. No key sequences or
visual mode, and bound letters don't start type-to-find.

Reload: `systemctl --user restart thunar.service`

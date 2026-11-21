# Ghostty keybindings

Selecting text copies it to both the primary selection and the clipboard.

These are all the keybindings set or removed by `config`. Ghostty's default
bindings also apply; `ghostty +list-keybinds` prints the complete active list.
The i3 shortcuts below are global in the i3 session, including while Ghostty
is focused.

Rofi and `Super+Enter` launch the AppImage Ghostty; while an old apt Ghostty
still runs, new windows open separately.

Cursor shape follows Zsh's Helix mode: block for normal, underline for select,
and bar for insert or text-entry prompts. `shell-integration-features` disables
Ghostty's cursor changes with `no-cursor`, leaving cursor control to the shell.
After changing this setting, reload Ghostty's config and open a new terminal
tab so its shell starts with the updated integration features.

## Configured in Ghostty

| Keys | Action |
| --- | --- |
| `Ctrl+Enter` | Unbound in Ghostty, so the terminal program can receive it. |
| `Ctrl+0` | Reset the font size. |
| `Ctrl+Shift+Plus` | Increase the font size by 5 points. |
| `Ctrl+Shift+Minus` | Decrease the font size by 5 points. |
| `Ctrl+Shift+H` / `Ctrl+Shift+L` | Focus the split to the left / right. |
| `Ctrl+Shift+J` / `Ctrl+Shift+K` | Focus the split below / above. |
| `Ctrl+Tab` | Focus the next split. This replaces Ghostty's default next-tab shortcut. |
| `Alt+Shift+H` / `Alt+Shift+L` | Switch to the previous / next tab. |
| `Ctrl+Shift+O` / `Ctrl+Shift+E` | Split right / below. |
| `Ctrl+Shift+T` | New tab. |
| `Ctrl+Shift+M` | Toggle tmux mode in the focused split. |
| `Ctrl+Alt+Shift+M` / `Ctrl+Alt+Shift+N` | Force tmux mode on / off. |
| `Ctrl+Alt+K` / `Ctrl+Alt+J` | Scroll up / down five lines. |

`Ctrl+Shift+J` replaces Ghostty's default write-screen-file action. Ghostty
still provides other default shortcuts for copying, pasting, and searching,
and `Alt+1` through `Alt+8` jump to tabs 1 through 8 (`Alt+9` jumps to the last
tab).

## tmux mode

Per split, these keys drive tmux; new splits start with it off.

| Keys in tmux mode | Sends | tmux action |
| --- | --- | --- |
| `Ctrl+Shift+O` / `Ctrl+Shift+E` | `C-b %` / `C-b "` | Split right / below. |
| `Ctrl+Shift+T` | `C-b c` | Insert a window after the current one in the active pane's directory. |
| `Ctrl+Shift+H` / `J` / `K` / `L` | `C-b C-h` / `C-j` / `C-k` / `C-l` | Focus pane. |
| `Alt+Shift+H` / `Alt+Shift+L` | `C-b p` / `C-b n` | Previous / next window. |
| `Ctrl+Alt+Shift+H` / `L` | `M-H` / `M-L` | Previous / next window (outermost tmux). |
| `Alt+1` … `Alt+9`, `Alt+0` | the same keys | Window 1–9, 10 (outermost tmux). |
| `Alt+Tab` | the same key | Last window (outermost tmux). |

On X11, Zsh enables it for `hpc` and tmux attaches. Local tmux enables it on
focus, including after restore. `Alt+Shift+T` reapplies it after reloading
Ghostty. Toggle it manually with `Ctrl+Shift+M`.

## i3 shortcuts affecting Ghostty

| Keys | Action |
| --- | --- |
| `Super+Enter` | Launch Ghostty. |
| `Copilot` | Show/hide the [floating terminal](../i3/MANUAL.md#copilot-terminal). |
| `Alt+Shift+T` | Toggle Ghostty's tab bar between automatic display and hidden. The i3 binding runs `toggle-tabbar.sh`, which reloads Ghostty's config. |

`Alt+Shift+T` is a desktop shortcut, so it applies to Ghostty windows even
though it is absent from Ghostty's `keybind` list. See the
[i3 manual](../i3/MANUAL.md) for other window and workspace shortcuts, and the
[Micro guide](../micro/docs.md) for its terminal `Ctrl+Enter` binding.

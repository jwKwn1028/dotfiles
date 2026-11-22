# Ghostty keybindings

Selecting text copies it to both the primary selection and the clipboard.

Custom keys below supplement defaults; `ghostty +list-keybinds` lists all.
i3 shortcuts are desktop-wide.

Rofi and `Super+Enter` launch the AppImage Ghostty; while an old apt Ghostty
still runs, new windows open separately.

Zsh controls cursor shape: normal block, select underline, insert/prompt bar.
`no-cursor` prevents Ghostty overrides; reload and open a new tab after changing it.

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

`Ctrl+Shift+J` replaces write-screen-file. Default copy/paste/search remain;
Alt+1–8 selects tabs, Alt+9 the last.

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

X11 enables tmux mode on hpc/attach/focus, including restore. Alt+Shift+T
reapplies it after reload; Ctrl+Shift+M toggles manually.

## i3 shortcuts affecting Ghostty

| Keys | Action |
| --- | --- |
| `Super+Enter` | Launch Ghostty. |
| `Copilot` | Show/hide the [floating terminal](../i3/MANUAL.md#copilot-terminal). |
| `Alt+Shift+T` | Toggle Ghostty's tab bar between automatic display and hidden. The i3 binding runs `toggle-tabbar.sh`, which reloads Ghostty's config. |

See [i3](../i3/MANUAL.md) for desktop keys and [Micro](../micro/docs.md) for Ctrl+Enter.

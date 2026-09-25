# Ghostty keybindings

These are all the keybindings set or removed by `config`. Ghostty's default
bindings also apply; `ghostty +list-keybinds` prints the complete active list.
The i3 shortcuts below are global in the i3 session, including while Ghostty
is focused.

## Configured in Ghostty

| Keys | Action |
| --- | --- |
| `Ctrl+Enter` | Unbound in Ghostty, so the terminal program can receive it. |
| `Ctrl+0` | Reset the font size. |
| `Ctrl+Shift+Plus` | Set the font size to 15. |
| `Ctrl+Shift+H` / `Ctrl+Shift+L` | Focus the split to the left / right. |
| `Ctrl+Shift+J` / `Ctrl+Shift+K` | Focus the split below / above. |
| `Ctrl+Tab` | Focus the next split. This replaces Ghostty's default next-tab shortcut. |
| `Alt+Shift+H` / `Alt+Shift+L` | Switch to the previous / next tab. |
| `Ctrl+Alt+K` / `Ctrl+Alt+J` | Scroll up / down five lines. |

`Ctrl+Shift+J` replaces Ghostty's default write-screen-file action. Ghostty
still provides other default shortcuts for creating tabs and splits, copying,
pasting, and searching. For example, `Ctrl+Shift+T` creates a tab,
`Ctrl+Shift+O` creates a split to the right, `Ctrl+Shift+E` creates one below,
and `Alt+1` through `Alt+8` jump to tabs 1 through 8 (`Alt+9` jumps to the last
tab).

## i3 shortcuts affecting Ghostty

| Keys | Action |
| --- | --- |
| `Super+Enter` | Launch Ghostty. |
| `Alt+Shift+T` | Toggle Ghostty's tab bar between automatic display and hidden. The i3 binding runs `toggle-tabbar.sh`, which reloads Ghostty's config. |

`Alt+Shift+T` is a desktop shortcut, so it applies to Ghostty windows even
though it is absent from Ghostty's `keybind` list. See the
[i3 manual](../i3/MANUAL.md) for other window and workspace shortcuts, and the
[Micro guide](../micro/docs.md) for its terminal `Ctrl+Enter` binding.

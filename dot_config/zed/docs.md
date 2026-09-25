# Zed keybindings

These are all the bindings added or removed by `keymap.json`. Zed also uses its
VS Code base keymap and Helix mode, enabled in `settings.json`. Open **Zed: Open
Default Keymap** from the command palette for those built-in bindings.

In the tables, a space between keys means press them in sequence. `Shift Shift`
means tap Shift twice. `Ctrl+T` is a prefix: keep using the second key shown in
the same row.

## Workspace and panels

| Keys | Action |
| --- | --- |
| `Shift Shift` | Toggle the file finder. |
| `Ctrl+T Ctrl+H` | Toggle the left dock. |
| `Ctrl+T Ctrl+L` | Toggle the right dock, where the project panel is configured to live. |
| `Ctrl+T Ctrl+P` | Toggle the terminal panel. |
| `Ctrl+T Ctrl+Shift+S` | Open the settings profile selector. |
| `Ctrl+T Ctrl+S` | Open the profile selector, then send Down and Enter. The available custom profile is `No status bar`. |
| `Ctrl+H Ctrl+M` | Toggle Helix mode. |
| `Ctrl+Q` | Close the Zed window when Vim control is active and no menu is open. |

`Ctrl+Backtick` is explicitly unbound from the terminal panel toggle. Use
`Ctrl+T Ctrl+P` instead.

## Insert mode

These bindings apply only while editing in insert mode.

| Keys | Action |
| --- | --- |
| `j k` | Leave insert mode, as with Escape. Type them in sequence. |
| `Alt+H` / `Alt+L` | Move left / right. |
| `Alt+J` / `Alt+K` | Move down / up. |
| `Alt+Q` / `Alt+E` | Move to the beginning / end of the line. |

## Helix normal and select modes

These bindings are inactive while a menu is open.

| Keys | Mode | Action |
| --- | --- | --- |
| `Enter` | Normal | Open a line below, then return to normal mode. |
| `Shift+V` | Normal | Paste from the system clipboard before the selection. |
| `Space p` | Normal or select | Paste from the system clipboard before the selection. |
| `Space Shift+P` | Normal or select | Paste from the system clipboard after the selection. |
| `Shift+V` | Select | Paste into the selection. |
| `Tab` | Select | Indent the selection. |
| `Shift+Tab` | Select | Outdent the selection. |

For the corresponding terminal editor keys, see the
[Helix guide](../helix/docs.md). This guide contains no machine-specific
settings; those belong in local chezmoi data, outside the public source.

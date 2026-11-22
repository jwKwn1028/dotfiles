# Ghostty-TokyoNight

GTK 3 session theme for `desktop` / `linuxmint-i3-x11`: TokyoNight Storm
colors, JuliaMono 10pt regular, square widgets, and Papirus-Dark icons.

XSettings sets the session theme; apply also updates running XFConf and removes
the old Thunar icon shim. Without D-Bus, changes wait until login. GTK_THEME is
not needed. GTK 2/4, Qt, browsers, and VS Code's editor retain separate themes;
Flatpaks need an in-sandbox copy.

## Check the appearance

Fully quit and reopen apps after editing the stylesheet.

| Command | Check |
| --- | --- |
| `pavucontrol` | Tabs, sliders, and mute buttons. |
| `blueman-manager` | Device icons, rows, and menus. |
| `xfce4-settings-manager` | Settings icons and dialogs. |
| `xfce4-power-manager-settings` | Tab labels clear the separator line. |
| `xfce4-taskmanager` | Column headings, selection, and focus. |
| `mintupdate` | Install Updates fits the toolbar; its disabled arrow stays visible. |
| `thunar` | Tabs, sidebar icons, motion keys, and normal typing in the location field. |

Also check GTK 3 file dialogs, keyboard focus, and warning/error states.
Mint Update uses compact toolbar padding; any remaining overflow actions are
under its down arrow. Disabled actions remain unclickable.

## Customize

Edit the managed `gtk-3.0/gtk.css`. Its `*` font rules override the session
font; secondary labels use `#a9b1d6` on `#292d3e`. The recolored Adwaita base
and widget artwork are generated files.

Thunar's 8px gutter and motion bindings stay scoped to `.standard-view`.
See `~/.config/Thunar/docs.md` for keys. To reload Thunar:

```sh
systemctl --user restart thunar.service
```

## Regenerate after a GTK upgrade

```sh
~/.themes/Ghostty-TokyoNight/tools/regenerate.sh
```

Rebuilds Adwaita and PNG assets using provisioned system Python/GI/GdkPixbuf.
Review and `chezmoi re-add` regenerated files before applying.

## Temporarily return to Adwaita

```sh
xfconf-query -c xsettings -p /Net/ThemeName -s Adwaita
xfconf-query -c xsettings -p /Net/IconThemeName -s ubuntu-mono-light
```

Reopen apps to refresh. The next apply restores the managed defaults; for a
permanent change, edit both the source XSettings XML and the apply script.

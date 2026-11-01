# Ghostty-TokyoNight

GTK 3 session theme for `desktop` / `linuxmint-i3-x11`: TokyoNight Storm
colors, JuliaMono 10pt regular, square widgets, and Papirus-Dark icons.

`xfsettingsd` reads the managed XSettings XML. On apply,
`run_after_94-configure-gtk-theme.sh.tmpl` also updates the running XFConf
session and removes the old Thunar icon shim. Without a session bus, the
settings take effect at login. Thunar and VS Code keep their launch wrappers;
native menus follow XSettings without exporting `GTK_THEME`.

GTK 2, GTK 4/libadwaita, Qt, and browser interfaces keep separate styling.
Flatpak apps need the theme inside their sandbox. VS Code's editor keeps its
own theme, and integrated terminals clear inherited `GTK_THEME` overrides.

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

This rebuilds the Adwaita base and assets. `export-pixbufs.py` converts inline
GdkPixdata resources to PNG using system Python, `python3-gi`, and
`gir1.2-gdkpixbuf-2.0`, all provisioned for this profile. Review and import
regenerated targets with `chezmoi re-add` before the next apply.

## Temporarily return to Adwaita

```sh
xfconf-query -c xsettings -p /Net/ThemeName -s Adwaita
xfconf-query -c xsettings -p /Net/IconThemeName -s ubuntu-mono-light
```

Reopen apps to refresh. The next apply restores the managed defaults; for a
permanent change, edit both the source XSettings XML and the apply script.

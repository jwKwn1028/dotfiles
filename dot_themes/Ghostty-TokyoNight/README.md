# Ghostty-TokyoNight

A GTK3 theme that makes **Thunar** read like a Ghostty window, derived from
`~/.config/ghostty/config`.

It is **scoped to Thunar** — it activates only for processes launched through
`~/.local/bin/thunar`. The global GTK theme is still Adwaita and the global icon
theme is still `ubuntu-mono-light`.

## What it matches

| Ghostty setting | How Thunar picks it up |
| --- | --- |
| `theme = TokyoNight Storm` | full Adwaita-dark recolor onto the Storm palette |
| `background = #292d3e` | every surface — sidebar, view, toolbar, statusbar |
| `foreground`, `selection-background` | `#c0caf5` text, `#364a82` selection |
| `cursor-color = #86be43` | focus rings, caret, checkboxes, progress, tab underline |
| `font-family = JuliaMono` | whole UI, with the same CJK/Nerd-Font fallbacks |
| `font-style-bold = false` | no bold anywhere |
| `window-decoration = none`, square frame | zero border-radius, no shadows, no gradients |
| `window-padding-x/y = 8` | 8px gutter around the file view |
| `scrollbar = never` | thin flat slider, no trough or steppers |

## Files

```
~/.themes/Ghostty-TokyoNight/
  gtk-3.0/gtk.css                 hand-written Ghostty layer (edit this)
  gtk-3.0/_adwaita-recolored.css  generated; GTK's Adwaita-dark, recolored
  gtk-3.0/assets/                 generated; Adwaita's check/slider artwork
  xdg-data/icons/ubuntu-mono-light/  icon-theme redirect shim (see below)
  tools/recolor.py                the palette mapper
  tools/regenerate.sh             rebuild the generated files after a GTK upgrade

~/.local/bin/thunar                       wrapper that turns the theme on
~/.local/share/applications/thunar.desktop  menu/panel launches -> wrapper
~/.config/systemd/user/thunar.service.d/gtk-theme.conf  D-Bus activation -> wrapper
```

All three launch paths route through the one wrapper, so the theme applies
whether Thunar is opened from the menu, from a shell, or by another app asking
D-Bus to "show this folder".

## Two things worth knowing

**Icons can't be set from CSS.** Thunar queries `GtkIconTheme` directly, and
under Xfce that name comes from XSETTINGS, which no per-app setting overrides.
So `xdg-data/icons/ubuntu-mono-light/` is an empty theme declaring
`Inherits=Papirus-Dark`, and the wrapper puts it first on `XDG_DATA_DIRS`:
Thunar resolves the name to the shim, every other app gets the real one.

**Menus ghost slightly.** ~15% of the window beneath shows through open menus.
Not this theme — stock Thunar under Adwaita does the same here. Likely picom's
`use-damage = true` with `backend = "glx"`, known to leave stale content under
newly mapped popups; set `use-damage = false` in `~/.config/picom/picom.conf` if
it bothers you. (This theme already paints menu toplevels opaque.)

## Tweaking

**Font size** — Ghostty's 18pt is oversized for a file manager, so the UI sits at
12pt. Change `font-size` in the `*` block near the top of `gtk-3.0/gtk.css`.

**Anything else** — edit `gtk-3.0/gtk.css` and restart Thunar:

```sh
systemctl --user restart thunar.service
```

**After a GTK upgrade** — if widgets start looking like stock Adwaita again,
the new GTK shipped rules this theme has not seen:

```sh
~/.themes/Ghostty-TokyoNight/tools/regenerate.sh
```

## Removing it

```sh
rm ~/.local/bin/thunar
rm ~/.local/share/applications/thunar.desktop
rm -r ~/.config/systemd/user/thunar.service.d
rm -r ~/.themes/Ghostty-TokyoNight
systemctl --user daemon-reload
systemctl --user restart thunar.service
```

Nothing under `/usr` was modified, so that returns Thunar to stock.

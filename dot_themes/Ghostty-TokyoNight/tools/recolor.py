#!/usr/bin/env python3
"""Recolor GTK3's compiled Adwaita-dark CSS into the Ghostty TokyoNight Storm palette.

The palette is taken straight from ~/.config/ghostty/config plus the TokyoNight
Storm theme file. Three passes decide each replacement:

1. Neutral ramp: an Adwaita-dark lightness maps to the TokyoNight neutral of the
   same lightness, interpolated between anchors sampled from the real theme.
2. Hue families: an Adwaita-dark hue, given as (hue_center_degrees, tolerance,
   target_rgb), maps to the TokyoNight color that replaces it, keeping Adwaita's
   lightness relationship while adopting TokyoNight's hue.
3. Hard overrides: Ghostty is one flat surface, so every Adwaita chrome layer
   (window background, view base, insensitive background, entry background, text
   view background) collapses to the single `background` color. Borders stay
   darker so edges remain legible.

The named-color block at the end of the file feeds apps that read those names
directly -- Thunar does, for its treeview and statusbar.
"""

import colorsys
import re
import sys

# ---------------------------------------------------------------- palette ----
BG        = (0x29, 0x2d, 0x3e)  # ghostty `background` override
BG_DIM    = (0x1d, 0x20, 0x2f)  # palette 0 / cursor-text
FG        = (0xc0, 0xca, 0xf5)  # foreground / palette 15
FG_DIM    = (0xa9, 0xb1, 0xd6)  # palette 7
MUTED     = (0x4e, 0x55, 0x75)  # palette 8
SEL_BG    = (0x36, 0x4a, 0x82)  # selection-background
BLUE      = (0x7a, 0xa2, 0xf7)  # palette 4
GREEN     = (0x9e, 0xce, 0x6a)  # palette 2
RED       = (0xf7, 0x76, 0x8e)  # palette 1
YELLOW    = (0xe0, 0xaf, 0x68)  # palette 3

def hexs(rgb):
    return "#%02x%02x%02x" % rgb

def to_hls(rgb):
    r, g, b = (c / 255.0 for c in rgb)
    return colorsys.rgb_to_hls(r, g, b)

def from_hls(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h, max(0.0, min(1.0, l)), max(0.0, min(1.0, s)))
    return (round(r * 255), round(g * 255), round(b * 255))

NEUTRAL_RAMP = [
    (0.00, (0x0d, 0x0f, 0x16)),
    (0.10, (0x16, 0x18, 0x24)),
    (0.15, BG_DIM),
    (0.20, BG),
    (0.28, (0x3a, 0x3f, 0x58)),
    (0.38, MUTED),
    (0.55, (0x7a, 0x82, 0xa8)),
    (0.75, FG_DIM),
    (0.85, FG),
    (1.00, FG),
]

def ramp(l):
    pts = NEUTRAL_RAMP
    if l <= pts[0][0]:
        return pts[0][1]
    for (l0, c0), (l1, c1) in zip(pts, pts[1:]):
        if l <= l1:
            t = (l - l0) / (l1 - l0) if l1 > l0 else 0.0
            return tuple(round(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    return pts[-1][1]

FAMILIES = [
    (213, 40, BLUE),    # accent / selection blue
    (90,  45, GREEN),   # success green
    (30,  20, YELLOW),  # warning orange
    (0,   20, RED),     # error red
    (355, 20, RED),
]

def recolor(rgb):
    h, l, s = to_hls(rgb)
    if s < 0.10:                       # neutral gray -> TokyoNight neutral
        return ramp(l)
    deg = h * 360.0
    for center, tol, target in FAMILIES:
        d = abs((deg - center + 180) % 360 - 180)
        if d <= tol:
            th, tl, ts = to_hls(target)
            return from_hls(th, l * 0.75 + tl * 0.25, ts * 0.85 + s * 0.15)
    return ramp(l)                     # anything else -> neutral

HARD = {
    "#353535": hexs(BG),       # theme_bg_color
    "#2d2d2d": hexs(BG),       # theme_base_color
    "#303030": hexs(BG),       # theme_unfocused_base_color
    "#323232": hexs(BG),       # insensitive_bg_color
    "#313131": hexs(BG),
    "#2f2f2f": hexs(BG),
    "#2e2e2e": hexs(BG),
    "#2b2b2b": hexs(BG),
    "#2a2a2a": hexs(BG),
    "#282828": hexs(BG),
    "#262626": hexs(BG),
    "#252525": hexs(BG),
    "#232323": hexs(BG),
    "#222222": hexs(BG),
    "#1e1e1e": hexs(BG),       # text_view_bg
    "#1b1b1b": "#1a1d2a",      # borders
    "#202020": "#1d202f",      # unfocused_borders
    "#15539e": hexs(SEL_BG),   # theme_selected_bg_color
    "#eeeeec": hexs(FG),       # theme_fg_color
    "#ffffff": hexs(FG),       # theme_text_color
    "#f7f7f7": hexs(FG),
    "#919190": hexs(MUTED),    # insensitive_fg_color
    "#8a8a89": hexs(MUTED),
    "#8e8e8d": hexs(MUTED),
    "#5b5b5b": hexs(MUTED),    # unfocused_insensitive_color
}

HEX_RE = re.compile(r"#([0-9a-fA-F]{6})\b")

def sub(m):
    key = "#" + m.group(1).lower()
    if key in HARD:
        return HARD[key]
    rgb = tuple(int(key[i:i + 2], 16) for i in (1, 3, 5))
    return hexs(recolor(rgb))

src = open(sys.argv[1]).read()
out = HEX_RE.sub(sub, src)
out += """
/* --- Ghostty palette, exposed as GTK named colors -------------------- */
@define-color theme_fg_color %(fg)s;
@define-color theme_text_color %(fg)s;
@define-color theme_bg_color %(bg)s;
@define-color theme_base_color %(bg)s;
@define-color theme_selected_bg_color %(sel)s;
@define-color theme_selected_fg_color %(fg)s;
@define-color insensitive_bg_color %(bg)s;
@define-color insensitive_fg_color %(muted)s;
@define-color insensitive_base_color %(bg)s;
@define-color theme_unfocused_fg_color %(fgdim)s;
@define-color theme_unfocused_text_color %(fgdim)s;
@define-color theme_unfocused_bg_color %(bg)s;
@define-color theme_unfocused_base_color %(bg)s;
@define-color theme_unfocused_selected_bg_color %(sel)s;
@define-color theme_unfocused_selected_fg_color %(fg)s;
@define-color unfocused_insensitive_color %(muted)s;
@define-color borders #1a1d2a;
@define-color unfocused_borders %(bgdim)s;
@define-color warning_color %(yellow)s;
@define-color error_color %(red)s;
@define-color success_color %(green)s;
@define-color content_view_bg %(bg)s;
@define-color text_view_bg %(bg)s;
""" % dict(fg=hexs(FG), bg=hexs(BG), sel=hexs(SEL_BG), muted=hexs(MUTED),
           fgdim=hexs(FG_DIM), bgdim=hexs(BG_DIM), yellow=hexs(YELLOW),
           red=hexs(RED), green=hexs(GREEN))

open(sys.argv[2], "w").write(out)
print("wrote %s (%d bytes)" % (sys.argv[2], len(out)))

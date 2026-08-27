#!/usr/bin/python3
"""Paint bar mode's selection block over a Polybar tray icon.

Every other stop in bar-nav.sh gets its block from a hidden twin module. The tray
cannot: it is one module holding XEmbed windows Polybar does not own, so a
background would paint behind every icon at once. Draw it here instead -- an
override-redirect ARGB window over the icon, filled with ${colors.selection}
premultiplied for a 32-bit ARGB visual (0xff per channel scaled by the 0x4d
alpha), and with no input region, so bar-nav's Return still reaches the icon.

bar-nav.sh writes "x y width height" into the marker file to place the block and
truncates it to hide. This exits when bar mode does, so a crash upstream cannot
strand a block on the bar.
"""

from __future__ import annotations

import os
import sys
import time

from Xlib import X, display
from Xlib.ext import shape

POLL_SECONDS = 0.04
FILL = 0x4D4D4D4D


def argb_visual(screen):
    """The screen's 32-bit TrueColor visual, without which alpha is ignored."""
    for depth in screen.allowed_depths:
        if depth.depth != 32:
            continue
        for visual in depth.visuals:
            if visual.visual_class == X.TrueColor:
                return visual.visual_id
    return None


def make_block(dsp):
    screen = dsp.screen()
    visual = argb_visual(screen)
    if visual is None:
        return None
    root = screen.root
    win = root.create_window(
        0, 0, 1, 1, 0, 32, X.InputOutput, visual,
        background_pixel=FILL,
        border_pixel=0,
        colormap=root.create_colormap(visual, X.AllocNone),
        override_redirect=True,
        event_mask=0,
    )
    win.shape_rectangles(shape.SO.Set, shape.SK.Input, X.Unsorted, 0, 0, [])
    return win


def read_rect(path):
    try:
        with open(path) as handle:
            fields = handle.read().split()
    except OSError:
        return None
    if len(fields) != 4:
        return None
    try:
        return tuple(int(field) for field in fields)
    except ValueError:
        return None


def main(argv):
    if len(argv) != 3:
        print("usage: bar-nav-marker.py <state-file> <marker-file>",
              file=sys.stderr)
        return 2
    state_path, marker_path = argv[1], argv[2]

    dsp = display.Display()
    block = make_block(dsp)
    if block is None:
        print("bar-nav-marker: no 32-bit visual, cannot draw the block",
              file=sys.stderr)
        return 1

    shown = None
    while os.path.exists(state_path):
        rect = read_rect(marker_path)
        if rect != shown:
            shown = rect
            if rect is None:
                block.unmap()
            else:
                x, y, width, height = rect
                block.configure(x=x, y=y, width=width, height=height,
                                stack_mode=X.Above)
                block.map()
            dsp.sync()
        time.sleep(POLL_SECONDS)

    dsp.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

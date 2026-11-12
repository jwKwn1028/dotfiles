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

from contextlib import closing
import ctypes
import os
import select
import struct
import sys

from Xlib import X, display
from Xlib.ext import shape

FILL = 0x4D4D4D4D
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_DELETE = 0x00000200
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800
IN_Q_OVERFLOW = 0x00004000
IN_IGNORED = 0x00008000
EVENT_HEADER = struct.Struct("=iIII")


class FileWatch:
    def __init__(self, state_path, marker_path):
        libc = ctypes.CDLL(None, use_errno=True)
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int
        self.fd = libc.inotify_init1(os.O_CLOEXEC | os.O_NONBLOCK)
        if self.fd < 0:
            code = ctypes.get_errno()
            raise OSError(code, os.strerror(code))
        self.files = {}
        directories = {}
        removed = IN_DELETE | IN_MOVED_FROM
        updated = removed | IN_CLOSE_WRITE | IN_MOVED_TO
        try:
            for path, events in ((state_path, removed), (marker_path, updated)):
                directory, name = os.path.split(os.path.abspath(path))
                if directory not in directories:
                    wd = libc.inotify_add_watch(
                        self.fd, os.fsencode(directory), updated | IN_DELETE_SELF | IN_MOVE_SELF
                    )
                    if wd < 0:
                        code = ctypes.get_errno()
                        raise OSError(code, os.strerror(code), directory)
                    directories[directory] = wd
                self.files[directories[directory], os.fsencode(name)] = events
        except BaseException:
            self.close()
            raise

    def close(self):
        if self.fd >= 0:
            os.close(self.fd)
            self.fd = -1

    def changed(self):
        try:
            data = os.read(self.fd, 65536)
        except BlockingIOError:
            return False
        offset, changed = 0, False
        while offset < len(data):
            wd, mask, _, size = EVENT_HEADER.unpack_from(data, offset)
            offset += EVENT_HEADER.size
            name = data[offset:offset + size].split(b"\0", 1)[0]
            offset += size
            if mask & (IN_DELETE_SELF | IN_MOVE_SELF | IN_IGNORED):
                raise OSError("Bar navigation directory is no longer watched")
            if mask & IN_Q_OVERFLOW or mask & self.files.get((wd, name), 0):
                changed = True
        return changed

    def wait(self, dsp):
        while True:
            while dsp.pending_events():
                dsp.next_event()
            ready, _, _ = select.select([self.fd, dsp], [], [])
            if self.fd in ready and self.changed():
                return


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

    with closing(FileWatch(state_path, marker_path)) as watcher:
        dsp = display.Display()
        try:
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
                watcher.wait(dsp)
        finally:
            dsp.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

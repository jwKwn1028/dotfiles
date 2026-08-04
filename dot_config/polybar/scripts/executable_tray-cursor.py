#!/usr/bin/env python3
"""Give Polybar's tray icons the click cursor Polybar's own modules get.

A tray icon is a foreign client window reparented into the bar, so the pointer
never enters Polybar's window while it is over one: X11 resolves the cursor from
the window under the pointer, and Polybar's `cursor-click = pointer` only ever
touches its own. Set the cursor on the embedded windows instead.

ctypes rather than python-xlib, which the other X11 helpers here use: the cursor
has to be the one from the active Xcursor theme -- the same load Polybar does --
so it matches the modules beside it, and only libXcursor can do that. A core
font cursor would be an unthemed bitmap hand.

Long-running because the cursor is a resource of this X connection. Closing it
frees the cursor and the icons revert to the arrow. Staying up also means the
icons get repainted when an applet docks late or restarts mid-session.
"""

from __future__ import annotations

import ctypes
import ctypes.util

SUBSTRUCTURE_NOTIFY_MASK = 1 << 19
XEVENT_SIZE = 256  # XEvent is a union; oversized is fine, this is scratch space

Window = ctypes.c_ulong

x11 = ctypes.CDLL(ctypes.util.find_library("X11"))
xcursor = ctypes.CDLL(ctypes.util.find_library("Xcursor"))


class XClassHint(ctypes.Structure):
    # char* rather than c_char_p: ctypes turns c_char_p into bytes on access and
    # the pointer XFree needs is gone with it.
    _fields_ = [("res_name", ctypes.c_void_p), ("res_class", ctypes.c_void_p)]


x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x11.XDefaultRootWindow.restype = Window
x11.XQueryTree.argtypes = [
    ctypes.c_void_p, Window,
    ctypes.POINTER(Window), ctypes.POINTER(Window),
    ctypes.POINTER(ctypes.POINTER(Window)), ctypes.POINTER(ctypes.c_uint),
]
x11.XGetClassHint.argtypes = [ctypes.c_void_p, Window, ctypes.POINTER(XClassHint)]
x11.XSelectInput.argtypes = [ctypes.c_void_p, Window, ctypes.c_long]
x11.XDefineCursor.argtypes = [ctypes.c_void_p, Window, ctypes.c_ulong]
x11.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
x11.XFree.argtypes = [ctypes.c_void_p]
x11.XFlush.argtypes = [ctypes.c_void_p]
xcursor.XcursorLibraryLoadCursor.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
xcursor.XcursorLibraryLoadCursor.restype = ctypes.c_ulong

# A window can vanish between the walk that found it and the request that uses
# it. Xlib's default handler exits the process on the resulting BadWindow.
ERROR_HANDLER = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)
_ignore_errors = ERROR_HANDLER(lambda display, error: 0)
x11.XSetErrorHandler(_ignore_errors)


def children(display, window):
    root, parent = Window(), Window()
    kids = ctypes.POINTER(Window)()
    count = ctypes.c_uint()
    if not x11.XQueryTree(display, window, ctypes.byref(root), ctypes.byref(parent),
                          ctypes.byref(kids), ctypes.byref(count)):
        return []
    found = [kids[i] for i in range(count.value)]
    x11.XFree(kids)
    return found


def window_class(display, window):
    hint = XClassHint()
    if not x11.XGetClassHint(display, window, ctypes.byref(hint)):
        return None
    name = ctypes.string_at(hint.res_class) if hint.res_class else None
    for pointer in (hint.res_name, hint.res_class):
        if pointer:
            x11.XFree(pointer)
    return name


def paint(display, window, cursor):
    """Set the cursor on a window and everything below it."""
    pending = [window]
    while pending:
        current = pending.pop()
        x11.XDefineCursor(display, current, cursor)
        pending.extend(children(display, current))


def refresh(display, root, cursor):
    """Repaint every docked tray icon, and watch the bars carrying them.

    The bar window itself is skipped -- Polybar drives its own cursor there --
    and so is the tray module's padding, which is drawn by the bar. Only the
    per-icon wrapper windows and their embedded clients are painted.
    """
    for bar in children(display, root):
        if window_class(display, bar) != b"Polybar":
            continue
        x11.XSelectInput(display, bar, SUBSTRUCTURE_NOTIFY_MASK)
        for wrapper in children(display, bar):
            paint(display, wrapper, cursor)
    x11.XFlush(display)


def main() -> int:
    display = x11.XOpenDisplay(None)
    if not display:
        return 1
    cursor = xcursor.XcursorLibraryLoadCursor(display, b"pointer")
    root = x11.XDefaultRootWindow(display)
    # On root to catch bars that appear later -- Polybar is restarted wholesale
    # on every i3 reload and monitor hotplug.
    x11.XSelectInput(display, root, SUBSTRUCTURE_NOTIFY_MASK)

    event = ctypes.create_string_buffer(XEVENT_SIZE)
    refresh(display, root, cursor)
    while True:
        # Which event does not matter: a repaint is idempotent and cheap next to
        # deciding whether this particular one moved a tray icon.
        x11.XNextEvent(display, event)
        refresh(display, root, cursor)


if __name__ == "__main__":
    raise SystemExit(main())

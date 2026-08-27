#!/usr/bin/python3
"""Give Polybar's tray icons the click cursor Polybar's own modules get.

A tray icon is a foreign client window reparented into the bar, so X11 resolves
the cursor from that window and Polybar's `cursor-click = pointer` never applies.
Set the cursor on the embedded windows instead.

ctypes rather than python-xlib: only libXcursor loads the cursor from the active
Xcursor theme (a core font cursor would be an unthemed bitmap hand). The theme
name is declared char*, not c_char_p, or ctypes frees the pointer XFree needs.

Long-running because the cursor belongs to this X connection, and to repaint when
an applet docks late or Polybar restarts. Errors are ignored: a window can vanish
between the walk and the request, and Xlib's default handler would exit.
"""

from __future__ import annotations

import ctypes
import ctypes.util

SUBSTRUCTURE_NOTIFY_MASK = 1 << 19
XEVENT_SIZE = 256  # XEvent is a union; oversized scratch space is fine

Window = ctypes.c_ulong

x11 = ctypes.CDLL(ctypes.util.find_library("X11"))
xcursor = ctypes.CDLL(ctypes.util.find_library("Xcursor"))


class XClassHint(ctypes.Structure):
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
    """Repaint docked tray icons and watch the bars carrying them.

    The bar window and the tray module's padding are Polybar's own; only the
    per-icon wrappers and their embedded clients are painted.
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
    x11.XSelectInput(display, root, SUBSTRUCTURE_NOTIFY_MASK)

    event = ctypes.create_string_buffer(XEVENT_SIZE)
    refresh(display, root, cursor)
    while True:
        x11.XNextEvent(display, event)
        refresh(display, root, cursor)


if __name__ == "__main__":
    raise SystemExit(main())

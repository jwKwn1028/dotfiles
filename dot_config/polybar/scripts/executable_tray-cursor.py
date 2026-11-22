#!/usr/bin/python3
"""Apply themed pointer cursors to XEmbed tray clients.

Keep the X connection alive and repaint when icons dock; tolerate vanished windows."""

from __future__ import annotations

import ctypes
import ctypes.util

SUBSTRUCTURE_NOTIFY_MASK = 1 << 19
XEVENT_SIZE = 256  # XEvent is a union; oversized scratch space is fine
CREATE_NOTIFY, MAP_NOTIFY, REPARENT_NOTIFY = 16, 19, 21

Window = ctypes.c_ulong

x11 = ctypes.CDLL(ctypes.util.find_library("X11"))
xcursor = ctypes.CDLL(ctypes.util.find_library("Xcursor"))


class XClassHint(ctypes.Structure):
    _fields_ = [("res_name", ctypes.c_void_p), ("res_class", ctypes.c_void_p)]


class EventHead(ctypes.Structure):
    """Shared X event prefix; parent is valid only for ReparentNotify."""
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("event", Window), ("window", Window), ("parent", Window)]


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
    """Set cursors on tray clients and watch their bars."""
    for bar in children(display, root):
        if window_class(display, bar) != b"Polybar":
            continue
        x11.XSelectInput(display, bar, SUBSTRUCTURE_NOTIFY_MASK)
        for wrapper in children(display, bar):
            paint(display, wrapper, cursor)
    x11.XFlush(display)


def needs_refresh(display, root, head):
    """Ignore events that cannot dock tray icons."""
    if head.type not in (CREATE_NOTIFY, MAP_NOTIFY, REPARENT_NOTIFY):
        return False
    if head.event != root:  # inside a bar
        return True
    if head.type == REPARENT_NOTIFY and head.parent != root:
        return True  # possibly an applet moving into a tray wrapper
    # A new bar: wait for its map, as WM_CLASS may not be set at creation.
    return head.type != CREATE_NOTIFY and window_class(display, head.window) == b"Polybar"


def main() -> int:
    display = x11.XOpenDisplay(None)
    if not display:
        return 1
    cursor = xcursor.XcursorLibraryLoadCursor(display, b"pointer")
    root = x11.XDefaultRootWindow(display)
    x11.XSelectInput(display, root, SUBSTRUCTURE_NOTIFY_MASK)

    event = ctypes.create_string_buffer(XEVENT_SIZE)
    head = EventHead.from_buffer(event)
    refresh(display, root, cursor)
    while True:
        x11.XNextEvent(display, event)
        if needs_refresh(display, root, head):
            refresh(display, root, cursor)


if __name__ == "__main__":
    raise SystemExit(main())

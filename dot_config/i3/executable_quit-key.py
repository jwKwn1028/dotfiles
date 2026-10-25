#!/usr/bin/python3
"""Make Ctrl+Q close windows of QUIT_CLASSES, apps that ignore it."""

from __future__ import annotations

import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from Xlib import X, XK, display as xdisplay, error as xerror

# Lowercase WM_CLASS class names.
QUIT_CLASSES = frozenset({"spotify", "kakaotalk.exe", "thunar"})


class StopWatcher(Exception):
    pass


def wants_quit_key(wm_class) -> bool:
    return bool(wm_class) and wm_class[-1].lower() in QUIT_CLASSES


def grab_masks(numlock: int) -> list[int]:
    locks = (0, X.LockMask, numlock, X.LockMask | numlock)
    return sorted({X.ControlMask | lock for lock in locks})


def quit_target(window: int | None, wm_class) -> int | None:
    return window if window and wants_quit_key(wm_class) else None


def close_window(window: int) -> None:
    try:
        subprocess.run(
            ["i3-msg", "-q", f"[id={window}] kill"],
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


class QuitKey:
    def __init__(self, display) -> None:
        self.display = display
        self.root = display.screen().root
        self.active_atom = display.intern_atom("_NET_ACTIVE_WINDOW")
        self.class_atom = display.intern_atom("WM_CLASS")
        self.target = None
        self.watched = None
        self.grabbed = False
        self.load_keyboard()
        self.root.change_attributes(event_mask=X.PropertyChangeMask)

    def load_keyboard(self) -> None:
        self.keycode = self.display.keysym_to_keycode(XK.XK_q)
        numlock = self.display.keysym_to_keycode(XK.XK_Num_Lock)
        mask = X.Mod2Mask
        for index, keycodes in enumerate(self.display.get_modifier_mapping()):
            if numlock and numlock in keycodes:
                mask = 1 << index
                break
        self.masks = grab_masks(mask)

    def set_grab(self, on: bool) -> None:
        if on == self.grabbed:
            return
        ignore = xerror.CatchError()
        for mask in self.masks:
            if on:
                self.root.grab_key(
                    self.keycode, mask, False,
                    X.GrabModeAsync, X.GrabModeAsync, onerror=ignore,
                )
            else:
                self.root.ungrab_key(self.keycode, mask, onerror=ignore)
        self.display.sync()
        self.grabbed = on

    def active_window(self) -> int | None:
        prop = self.root.get_full_property(self.active_atom, X.AnyPropertyType)
        if prop is None or not len(prop.value):
            return None
        return int(prop.value[0]) or None

    def watch(self, window: int | None) -> None:
        ignore = xerror.CatchError()
        if self.watched is not None:
            self.watched.change_attributes(event_mask=0, onerror=ignore)
        self.watched = None
        if window:
            self.watched = self.display.create_resource_object("window", window)
            self.watched.change_attributes(
                event_mask=X.PropertyChangeMask, onerror=ignore
            )

    def refresh(self) -> None:
        window = self.active_window()
        if (self.watched.id if self.watched else None) != window:
            self.watch(window)
        wm_class = None
        if self.watched is not None:
            try:
                wm_class = self.watched.get_wm_class()
            except xerror.XError:
                pass
        self.target = quit_target(window, wm_class)
        self.set_grab(self.target is not None)

    def handle(self, event) -> None:
        if event.type == X.KeyPress:
            if self.target is not None:
                close_window(self.target)
        elif event.type == X.PropertyNotify:
            if event.window.id == self.root.id and event.atom == self.active_atom:
                self.refresh()
            elif (
                event.atom == self.class_atom
                and self.watched is not None
                and event.window.id == self.watched.id
            ):
                self.refresh()
        elif event.type == X.MappingNotify and event.request != X.MappingPointer:
            self.display.refresh_keyboard_mapping(event)
            grabbed = self.grabbed
            self.set_grab(False)
            self.load_keyboard()
            self.set_grab(grabbed)

    def run(self) -> None:
        self.refresh()
        while True:
            self.handle(self.display.next_event())


def runtime_lock():
    runtime_dir = Path(
        os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    )
    runtime_dir.mkdir(parents=True, exist_ok=True)
    lock_file = (runtime_dir / "i3-quit-key.lock").open("a+")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_file.close()
        return None
    return lock_file


def main() -> int:
    lock_file = runtime_lock()
    if lock_file is None:
        return 0

    def stop(_signum, _frame):
        raise StopWatcher

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    try:
        while True:
            try:
                QuitKey(xdisplay.Display()).run()
            except StopWatcher:
                raise
            except Exception:
                time.sleep(1)
    except (StopWatcher, KeyboardInterrupt):
        return 0
    finally:
        lock_file.close()


if __name__ == "__main__":
    sys.exit(main())

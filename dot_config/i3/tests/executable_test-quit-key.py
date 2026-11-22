#!/usr/bin/python3

from __future__ import annotations

import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest

from Xlib import X


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("quit_key", ROOT / "quit-key.py")
assert SPEC is not None and SPEC.loader is not None
QUIT_KEY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(QUIT_KEY)


class QuitKeyTests(unittest.TestCase):
    def test_only_listed_classes_are_targets(self) -> None:
        self.assertEqual(QUIT_KEY.quit_target(42, ("spotify", "Spotify")), 42)
        self.assertEqual(QUIT_KEY.quit_target(42, ("kakaotalk.exe", "KakaoTalk.exe")), 42)
        self.assertEqual(QUIT_KEY.quit_target(42, ("Thunar", "Thunar")), 42)
        self.assertEqual(QUIT_KEY.quit_target(42, ("DesktopEditors", "ONLYOFFICE")), 42)
        self.assertIsNone(QUIT_KEY.quit_target(42, ("ghostty", "com.mitchellh.ghostty")))
        self.assertIsNone(QUIT_KEY.quit_target(42, ("kakaotalk.exe", "Wine")))

    def test_unclassed_or_absent_windows_are_not_targets(self) -> None:
        self.assertIsNone(QUIT_KEY.quit_target(42, None))
        self.assertIsNone(QUIT_KEY.quit_target(42, ()))
        self.assertIsNone(QUIT_KEY.quit_target(None, ("spotify", "Spotify")))
        self.assertIsNone(QUIT_KEY.quit_target(0, ("spotify", "Spotify")))

    def test_grabs_ctrl_q_under_every_lock_only(self) -> None:
        locks = (0, X.LockMask, X.Mod2Mask, X.LockMask | X.Mod2Mask)
        self.assertEqual(
            QUIT_KEY.grab_masks(X.Mod2Mask),
            sorted(X.ControlMask | lock for lock in locks),
        )

    def test_ctrl_w_targets_only_a_start_page(self) -> None:
        oo = ("DesktopEditors", "ONLYOFFICE")
        target = QUIT_KEY.start_page_target
        self.assertEqual(target(42, oo, "ONLYOFFICE"), 42)
        self.assertIsNone(target(42, oo, "Document1.docx — ONLYOFFICE"))
        self.assertIsNone(target(42, oo, None))
        self.assertIsNone(target(None, oo, "ONLYOFFICE"))
        self.assertIsNone(target(42, ("spotify", "Spotify"), "ONLYOFFICE"))
        self.assertIsNone(target(42, None, "ONLYOFFICE"))

    def test_grabs_follow_the_title_and_keys_close_their_target(self) -> None:
        q_key, w_key = 24, 25
        oo = FakeWindow(7, ("DesktopEditors", "ONLYOFFICE"), b"ONLYOFFICE")
        watcher = make_watcher(q_key, w_key, oo)
        watcher.refresh()
        self.assertEqual(watcher.grabbed, {q_key, w_key})

        oo.title = "Document1.docx — ONLYOFFICE".encode()
        watcher.refresh()
        self.assertEqual(watcher.grabbed, {q_key})
        self.assertEqual(watcher.root.ungrabbed, [w_key] * len(watcher.masks))

        closed = []
        original = QUIT_KEY.close_window
        QUIT_KEY.close_window = closed.append
        try:
            watcher.handle(SimpleNamespace(type=X.KeyPress, detail=w_key))
            watcher.handle(SimpleNamespace(type=X.KeyPress, detail=q_key))
        finally:
            QUIT_KEY.close_window = original
        self.assertEqual(closed, [7])

        other = FakeWindow(9, ("ghostty", "com.mitchellh.ghostty"), b"ONLYOFFICE")
        watcher.root.active = other
        watcher.refresh()
        self.assertEqual(watcher.grabbed, set())


class FakeWindow:
    def __init__(self, wid, wm_class, title) -> None:
        self.id, self.wm_class, self.title = wid, wm_class, title

    def get_wm_class(self):
        return self.wm_class

    def get_full_property(self, _atom, _type):
        return SimpleNamespace(value=self.title)

    def change_attributes(self, **_kwargs) -> None:
        pass


class FakeRoot:
    id = 1

    def __init__(self, active) -> None:
        self.active, self.ungrabbed = active, []

    def get_full_property(self, _atom, _type):
        return SimpleNamespace(value=[self.active.id])

    def grab_key(self, *_args, **_kwargs) -> None:
        pass

    def ungrab_key(self, keycode, _mask, **_kwargs) -> None:
        self.ungrabbed.append(keycode)


def make_watcher(q_key, w_key, active):
    root = FakeRoot(active)
    display = SimpleNamespace(
        create_resource_object=lambda _kind, wid: root.active
        if wid == root.active.id else None,
        sync=lambda: None,
    )
    watcher = object.__new__(QUIT_KEY.QuitKey)
    watcher.display, watcher.root = display, root
    watcher.active_atom = watcher.class_atom = 0
    watcher.name_atom = watcher.utf8_atom = 0
    watcher.targets, watcher.watched, watcher.grabbed = {}, None, set()
    watcher.quit_key, watcher.close_key = q_key, w_key
    watcher.masks = QUIT_KEY.grab_masks(X.Mod2Mask)
    return watcher


if __name__ == "__main__":
    unittest.main()

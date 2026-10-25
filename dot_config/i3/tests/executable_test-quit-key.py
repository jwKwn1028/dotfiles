#!/usr/bin/python3

from __future__ import annotations

import importlib.util
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()

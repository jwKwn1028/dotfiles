#!/usr/bin/python3

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "super_polybar_listener", ROOT / "super-polybar-listener.py"
)
assert SPEC is not None and SPEC.loader is not None
LISTENER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LISTENER)


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


class SuperGestureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.actions: list[str] = []
        self.gesture = LISTENER.SuperGesture(
            super_keycodes={133, 134},
            hold_seconds=0.25,
            on_tap=lambda: self.actions.append("tap"),
            on_hold_start=lambda: self.actions.append("hold-start"),
            on_hold_end=lambda: self.actions.append("hold-end"),
            on_hold_cancel=lambda: self.actions.append("hold-cancel"),
            clock=self.clock,
        )

    def test_quick_tap_fires_only_after_release(self) -> None:
        self.gesture.key_event("press", 133)
        self.clock.advance(0.1)
        self.assertEqual(self.actions, [])

        self.gesture.key_event("release", 133)
        self.assertEqual(self.actions, ["tap"])

    def test_hold_starts_at_threshold_and_ends_on_release(self) -> None:
        self.gesture.key_event("press", 133)
        self.clock.advance(0.249)
        self.gesture.poll()
        self.assertEqual(self.actions, [])

        self.clock.advance(0.002)
        self.gesture.poll()
        self.assertEqual(self.actions, ["hold-start"])

        self.clock.advance(1)
        self.gesture.poll()
        self.assertEqual(self.actions, ["hold-start"])

        self.gesture.key_event("release", 133)
        self.assertEqual(self.actions, ["hold-start", "hold-end"])

    def test_chord_before_threshold_cancels_standalone_action(self) -> None:
        self.gesture.key_event("press", 133)
        self.clock.advance(0.1)
        self.gesture.key_event("press", 38)
        self.clock.advance(0.3)
        self.gesture.poll()
        self.gesture.key_event("release", 38)
        self.gesture.key_event("release", 133)

        self.assertEqual(self.actions, [])

    def test_chord_after_hold_converts_hold_to_timed_peek(self) -> None:
        self.gesture.key_event("press", 133)
        self.clock.advance(0.3)
        self.gesture.poll()
        self.gesture.key_event("press", 10)
        self.gesture.key_event("release", 10)
        self.gesture.key_event("release", 133)

        self.assertEqual(self.actions, ["hold-start", "hold-cancel"])

    def test_other_key_held_before_super_is_a_chord(self) -> None:
        self.gesture.key_event("press", 64)
        self.gesture.key_event("press", 133)
        self.clock.advance(0.3)
        self.gesture.poll()
        self.gesture.key_event("release", 133)
        self.gesture.key_event("release", 64)

        self.assertEqual(self.actions, [])

    def test_both_super_keys_form_one_hold(self) -> None:
        self.gesture.key_event("press", 133)
        self.gesture.key_event("press", 134)
        self.clock.advance(0.3)
        self.gesture.poll()
        self.gesture.key_event("release", 133)
        self.assertEqual(self.actions, ["hold-start"])

        self.gesture.key_event("release", 134)
        self.assertEqual(self.actions, ["hold-start", "hold-end"])

    def test_shutdown_ends_an_active_hold(self) -> None:
        self.gesture.key_event("press", 133)
        self.clock.advance(0.3)
        self.gesture.poll()
        self.gesture.shutdown()

        self.assertEqual(self.actions, ["hold-start", "hold-end"])


class RawKeyParserTests(unittest.TestCase):
    def test_parses_raw_press_and_release(self) -> None:
        parser = LISTENER.RawKeyParser()
        self.assertIsNone(parser.feed_line("EVENT type 13 (RawKeyPress)"))
        self.assertIsNone(parser.feed_line("    device: 3 (12)"))
        self.assertEqual(parser.feed_line("    detail: 133"), ("press", 133))
        self.assertIsNone(parser.feed_line("EVENT type 14 (RawKeyRelease)"))
        self.assertEqual(parser.feed_line("    detail: 133"), ("release", 133))


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Exercise modifier release and focus guards without sending real X11 input."""

from pathlib import Path
import runpy
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, call, patch


SOURCE = Path(__file__).resolve().parent.parent / "executable_ghostty-tmux-mode"
if not SOURCE.exists():
    SOURCE = SOURCE.with_name("ghostty-tmux-mode")
main = runpy.run_path(str(SOURCE))["main"]
GLOBALS = main.__globals__


class FakeDisplay:
    def __init__(self, held=(), focus=(42, 42)):
        self.held = iter(held)
        self.focus = iter(focus)
        self.reads = 0
        self.root = SimpleNamespace(get_full_property=lambda *_: SimpleNamespace(value=[next(self.focus)]))

    def has_extension(self, _):
        return True

    def screen(self):
        return SimpleNamespace(root=self.root)

    def intern_atom(self, _):
        return 1

    def get_modifier_mapping(self):
        return [[*range(1, 9), 9]]

    def keycode_to_keysym(self, code, _):
        return GLOBALS["XK"].XK_Caps_Lock if code == 9 else code

    def query_keymap(self):
        self.reads += 1
        bitmap = bytearray(32)
        for code in next(self.held, ()):
            bitmap[code // 8] |= 1 << (code % 8)
        return bitmap

    def keysym_to_keycode(self, sym):
        return sym % 255 + 1

    def sync(self):
        pass


class GhosttyModeTests(unittest.TestCase):
    def invoke(self, display, *, grabbed=False, clock=None):
        self.input = Mock()
        self.sleep = Mock(side_effect=lambda _: self.input.assert_not_called())
        guard = Mock(return_value=grabbed)
        clock = clock or Mock(return_value=0)
        with patch.object(GLOBALS["display"], "Display", return_value=display), \
                patch.object(GLOBALS["xtest"], "fake_input", self.input), \
                patch.dict(GLOBALS, keyboard_grabbed=guard,
                           time=SimpleNamespace(monotonic=clock, sleep=self.sleep)), \
                patch("sys.argv", [str(SOURCE), "on"]):
            result = main()
        return result, guard

    def test_released_modifiers_use_one_keymap_and_send_the_whole_binding(self):
        display = FakeDisplay()
        result, guard = self.invoke(display)
        self.assertEqual(result, 0)
        self.assertEqual(display.reads, 1)
        guard.assert_called_once_with(display, display.root)
        presses = self.input.call_args_list[:4]
        releases = self.input.call_args_list[4:]
        self.assertEqual(len(releases), 4)
        self.assertTrue(all(call.args[1] == GLOBALS["X"].KeyPress for call in presses))
        self.assertTrue(all(call.args[1] == GLOBALS["X"].KeyRelease for call in releases))
        self.assertEqual([call.args[2] for call in presses], [call.args[2] for call in reversed(releases)])

    def test_waits_until_every_modifier_is_released_but_ignores_caps_lock(self):
        display = FakeDisplay(held=[(8,), (1, 8), (9,)])
        result, _ = self.invoke(display)
        self.assertEqual(result, 0)
        self.assertEqual(display.reads, 3)
        self.assertEqual(self.sleep.call_args_list, [call(0.01), call(0.01)])

    def test_held_modifier_times_out_without_sending_input(self):
        display = FakeDisplay(held=[(8,)])
        result, guard = self.invoke(display, clock=Mock(side_effect=[0, 1.01]))
        self.assertEqual(result, 1)
        self.assertEqual(display.reads, 1)
        self.input.assert_not_called()
        guard.assert_not_called()

    def test_focus_change_cancels_without_sending_input(self):
        result, guard = self.invoke(FakeDisplay(focus=(42, 43)))
        self.assertEqual(result, 1)
        self.input.assert_not_called()
        guard.assert_not_called()

    def test_keyboard_grab_cancels_without_sending_input(self):
        result, guard = self.invoke(FakeDisplay(), grabbed=True)
        self.assertEqual(result, 1)
        self.input.assert_not_called()
        guard.assert_called_once()


if __name__ == "__main__":
    unittest.main()

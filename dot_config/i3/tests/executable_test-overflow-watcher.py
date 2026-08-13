#!/usr/bin/python3
"""Target selection and packing rules for overflow-watcher.py.

Pure functions only: wrap order, target choice, and the room-for-one-more test
are fed synthetic workspace occupancy, so no i3 connection is involved. The
method names carry the cases; the non-obvious input is focus[0], which may name
a floating container that is not among `nodes`.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "overflow_watcher", ROOT / "overflow-watcher.py"
)
assert SPEC is not None and SPEC.loader is not None
WATCHER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(WATCHER)


class WrapOrderTests(unittest.TestCase):
    def test_starts_above_current_and_excludes_it(self) -> None:
        self.assertEqual(WATCHER.wrap_order(1), [2, 3, 4, 5, 6, 7, 8, 9, 10])

    def test_wraps_past_ten(self) -> None:
        self.assertEqual(WATCHER.wrap_order(9), [10, 1, 2, 3, 4, 5, 6, 7, 8])

    def test_from_last_workspace(self) -> None:
        self.assertEqual(WATCHER.wrap_order(10), [1, 2, 3, 4, 5, 6, 7, 8, 9])


class PickTargetTests(unittest.TestCase):
    def test_nearest_occupied_above_with_room(self) -> None:
        self.assertEqual(WATCHER.pick_target(2, {1: True, 5: True, 9: True}), 5)

    def test_cascades_past_packed_workspaces(self) -> None:
        self.assertEqual(WATCHER.pick_target(1, {1: False, 3: False, 4: True}), 4)

    def test_skips_empty_workspaces_in_favour_of_one_with_room(self) -> None:
        self.assertEqual(WATCHER.pick_target(6, {1: True, 2: True, 6: False}), 1)

    def test_takes_occupied_above_before_wrapping(self) -> None:
        self.assertEqual(WATCHER.pick_target(6, {1: True, 6: False, 7: True}), 7)

    def test_falls_back_to_first_empty_when_all_occupied_are_packed(self) -> None:
        self.assertEqual(WATCHER.pick_target(1, {1: False, 2: False, 3: False}), 4)

    def test_no_other_workspace_occupied_goes_to_next_number(self) -> None:
        self.assertEqual(WATCHER.pick_target(4, {4: False}), 5)

    def test_no_other_workspace_occupied_wraps(self) -> None:
        self.assertEqual(WATCHER.pick_target(10, {10: False}), 1)

    def test_everything_packed_falls_back_to_next_number(self) -> None:
        self.assertEqual(WATCHER.pick_target(3, {n: False for n in range(1, 11)}), 4)


class RoomForOneMoreTests(unittest.TestCase):
    WS = 1920 * 1080

    def room(self, parent_area, child_count, **kwargs):
        return WATCHER.room_for_one_more(
            parent_area, child_count, self.WS, 0.25, **kwargs
        )

    def test_single_window_workspace_has_room(self) -> None:
        self.assertTrue(self.room(self.WS, 1))

    def test_three_windows_still_fit_a_fourth_at_exactly_a_quarter(self) -> None:
        self.assertTrue(self.room(self.WS, 3))

    def test_four_windows_are_packed(self) -> None:
        self.assertFalse(self.room(self.WS, 4))

    def test_borders_do_not_make_an_exact_quarter_read_as_packed(self) -> None:
        self.assertTrue(self.room(int(self.WS * 0.995), 3))

    def test_nested_half_width_parent_is_packed_sooner(self) -> None:
        self.assertTrue(self.room(self.WS // 2, 1))
        self.assertFalse(self.room(self.WS // 2, 2))

    def test_tabbed_parent_always_has_room(self) -> None:
        self.assertTrue(self.room(self.WS // 4, 9, stacked=True))


class FakeCon:
    """Enough of an i3ipc container to exercise the focus-chain descent."""

    def __init__(self, id, nodes=(), focus=(), layout="splith"):
        self.id = id
        self.nodes = list(nodes)
        self.focus = list(focus)
        self.layout = layout
        self.parent = None
        for node in self.nodes:
            node.parent = self


class InsertionParentTests(unittest.TestCase):
    def test_empty_workspace_is_its_own_insertion_point(self) -> None:
        ws = FakeCon(1)
        self.assertIs(WATCHER.insertion_parent(ws), ws)

    def test_flat_workspace_returns_the_workspace(self) -> None:
        a, b = FakeCon(10), FakeCon(11)
        ws = FakeCon(1, nodes=[a, b], focus=[11, 10])
        self.assertIs(WATCHER.insertion_parent(ws), ws)

    def test_descends_into_the_focused_split(self) -> None:
        inner_a, inner_b = FakeCon(20), FakeCon(21)
        split = FakeCon(12, nodes=[inner_a, inner_b], focus=[21, 20])
        half = FakeCon(11)
        ws = FakeCon(1, nodes=[half, split], focus=[12, 11])
        self.assertIs(WATCHER.insertion_parent(ws), split)

    def test_floating_focus_falls_back_to_the_workspace(self) -> None:
        tiled = FakeCon(11)
        ws = FakeCon(1, nodes=[tiled], focus=[99, 11])
        self.assertIs(WATCHER.insertion_parent(ws), ws)


if __name__ == "__main__":
    unittest.main()

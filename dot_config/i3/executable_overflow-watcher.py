#!/usr/bin/python3
"""Cascade small arrivals within their source workspace group."""

from __future__ import annotations

import argparse
import sys

from i3ipc import Connection, Event

from workspace_groups import GroupError, identity, request

MAX_WS = 10

EPSILON = 0.01


def area(con) -> int:
    return con.rect.width * con.rect.height


def is_floating(con) -> bool:
    return (
        con.type == "floating_con"
        or bool(con.floating and "_on" in con.floating)
        or (con.parent is not None and con.parent.type == "floating_con")
    )


def wrap_order(current: int, max_ws: int = MAX_WS) -> list[int]:
    """Workspace numbers above `current`, wrapping 10 -> 1, `current` excluded."""
    base = ((current - 1) // max_ws) * max_ws
    return [base + (current - base + offset - 1) % max_ws + 1 for offset in range(1, max_ws)]


def room_for_one_more(parent_area, child_count, ws_area, fraction, stacked=False):
    """Would the next sibling in this container still clear the size floor?

    i3 attaches a moved container as a sibling of the target's focused container,
    so the arrival gets an even share -- unless the parent is tabbed or stacked.
    """
    share = parent_area if stacked else parent_area / (child_count + 1)
    return share >= (fraction - EPSILON) * ws_area


def pick_target(current: int, occupancy: dict[int, bool], max_ws: int = MAX_WS) -> int | None:
    """Where a too-small window should go.

    `occupancy` maps workspace number -> has room. Missing workspaces are empty.
    """
    order = wrap_order(current, max_ws)
    for num in order:
        if occupancy.get(num):
            return num
    for num in order:
        if num not in occupancy:
            return num
    return None


def insertion_parent(ws):
    """The container an arriving window will attach to on workspace `ws`.

    i3 descends the workspace's focus chain and attaches as a sibling of the leaf
    it lands on; a floating or absent focus leaves it at the top level.
    """
    con = ws
    while con.focus:
        following = next((c for c in con.nodes if c.id == con.focus[0]), None)
        if following is None:  # focus points at a floating container
            break
        con = following
    return ws if con is ws else con.parent


def workspace_has_room(ws, fraction: float) -> bool:
    # Only the arriving window is measured.
    parent = insertion_parent(ws)
    return room_for_one_more(
        area(parent),
        len(parent.nodes),
        area(ws),
        fraction,
        stacked=parent.layout in ("tabbed", "stacked"),
    )


class Watcher:
    def __init__(self, fraction: float, follow: bool, debug: bool) -> None:
        self.fraction = fraction
        self.follow = follow
        self.debug = debug
        self.workspace_of: dict[int, int] = {}
        self.self_moved: set[int] = set()

    def log(self, message: str) -> None:
        if self.debug:
            print(message, file=sys.stderr)

    def seed(self, tree) -> None:
        for ws in tree.workspaces():
            for leaf in ws.leaves():
                self.workspace_of[leaf.id] = ws.num

    def on_close(self, i3, event) -> None:
        if event.container is not None:
            self.workspace_of.pop(event.container.id, None)
            self.self_moved.discard(event.container.id)

    def on_window(self, i3, event) -> None:
        if event.container is None:
            return
        con_id = event.container.id

        if con_id in self.self_moved:
            # Cleared when our own move event arrives.
            self.self_moved.discard(con_id)
            return

        tree = i3.get_tree()
        con = tree.find_by_id(con_id)
        if con is None:
            return

        ws = con.workspace()
        previous = self.workspace_of.get(con_id)
        self.workspace_of[con_id] = ws.num if ws is not None else None

        if ws is None or identity(ws.num) is None:
            return
        if event.change == "move" and previous == ws.num:
            return
        if is_floating(con) or con.fullscreen_mode:
            return

        ws_area = area(ws)
        if not ws_area:
            return
        ratio = area(con) / ws_area
        if ratio >= self.fraction - EPSILON:
            return

        self.relocate(i3, con_id, ws.num)

    def relocate(self, i3, con_id: int, source: int) -> None:
        try:
            request("overflow", con_id=con_id, source_num=source,
                    fraction=self.fraction, follow=self.follow)
        except GroupError as error:
            self.log(str(error))


def get_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="overflow-watcher",
        description="Move a window off a workspace when it lands too small to be useful",
    )
    parser.add_argument(
        "-f",
        "--fraction",
        type=float,
        default=0.25,
        help="move the window when it covers less than this share of the "
        "workspace; default: 0.25",
    )
    parser.add_argument(
        "--no-follow",
        dest="follow",
        action="store_false",
        help="leave focus behind instead of following the window to its new workspace",
    )
    parser.add_argument(
        "-d", "--debug", action="store_true", help="print decisions to stderr"
    )
    return parser


def main() -> None:
    args = get_parser().parse_args()

    watcher = Watcher(fraction=args.fraction, follow=args.follow, debug=args.debug)
    i3 = Connection()
    watcher.seed(i3.get_tree())
    i3.on(Event.WINDOW_NEW, watcher.on_window)
    i3.on(Event.WINDOW_MOVE, watcher.on_window)
    i3.on(Event.WINDOW_CLOSE, watcher.on_close)
    i3.main()


if __name__ == "__main__":
    main()

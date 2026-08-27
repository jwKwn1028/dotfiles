#!/usr/bin/python3
"""Send a window to another workspace when it lands smaller than a quarter of the screen.

Companion to autotiling: autotiling picks the split direction, this decides when a
workspace is packed enough that the window belongs somewhere else. Walking
workspace numbers upward and wrapping 10 -> 1, the target is the first occupied
workspace that still has room, else the first empty one, else the next number.
Freshly opened windows and hand-offs from the manual bindings go through the same
rule; moving a window inside one workspace is a rearrange, not an arrival. A moved
window requests the same transient Polybar peek the workspace keybindings do,
overridable so a nested test session cannot drive the real bar.

Easy to get wrong:

- i3's integer division puts container rects a pixel or two under the ideal
  fraction, so an exact quarter must not read as smaller than a quarter.
- The event payload predates placement, so geometry is re-read from the tree.
- Two maps guard against self-judgement: con ids this watcher just moved, and
  con id -> workspace, which tells a rearrange from a hand-off.
- Nothing may focus the target workspace first: a criteria-matched move into the
  *visible* workspace silently does nothing while reporting success.
"""

from __future__ import annotations

import argparse
import os
import sys

from i3ipc import Connection, Event

MAX_WS = 10

PEEK = os.environ.get("I3_OVERFLOW_PEEK") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "polybar-peek.sh"
)

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
    return [(current + offset - 1) % max_ws + 1 for offset in range(1, max_ws)]


def room_for_one_more(parent_area, child_count, ws_area, fraction, stacked=False):
    """Would the next sibling in this container still clear the size floor?

    i3 attaches a moved container as a sibling of the target's focused container,
    so the arrival gets an even share -- unless the parent is tabbed or stacked.
    """
    share = parent_area if stacked else parent_area / (child_count + 1)
    return share >= (fraction - EPSILON) * ws_area


def pick_target(current: int, occupancy: dict[int, bool], max_ws: int = MAX_WS) -> int:
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
    return order[0]


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

        if ws is None or not 1 <= ws.num <= MAX_WS:  # scratchpad reports num -1
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

        occupancy = {}
        for other in tree.workspaces():
            if other.num == ws.num or not 1 <= other.num <= MAX_WS:
                continue
            if other.leaves():
                occupancy[other.num] = workspace_has_room(other, self.fraction)

        target = pick_target(ws.num, occupancy)
        self.log(
            f"con {con_id} covers {ratio:.3f} of workspace {ws.num} "
            f"(occupancy {occupancy}); moving to {target}"
        )
        self.relocate(i3, con_id, target)

    def relocate(self, i3, con_id: int, target: int) -> None:
        commands = [f"[con_id={con_id}] move container to workspace number {target}"]
        if self.follow:
            commands.append(f"[con_id={con_id}] focus")

        self.self_moved.add(con_id)
        results = i3.command("; ".join(commands))
        failures = [r.error for r in results if not r.success]
        if failures:
            self.self_moved.discard(con_id)
            self.log(f"move of con {con_id} to workspace {target} failed: {failures}")
        else:
            self.workspace_of[con_id] = target
            if os.access(PEEK, os.X_OK):
                i3.command(f"exec --no-startup-id {PEEK}")


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

#!/usr/bin/env python3
"""Edge gesture bookkeeping for top-edge-peek.py.

Only the state machine is exercised; it is fed synthetic pointer positions, so
no X server and no real Polybar are involved.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

# Loading the watcher by path would otherwise drop a __pycache__ beside it, in
# a directory chezmoi manages.
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("top_edge_peek", ROOT / "top-edge-peek.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# Laptop right of an external head, the layout this profile actually runs, and
# with the external offset downwards so the two tops differ.
MONITORS = [(1920, 0, 1920, 1200), (0, 120, 1920, 1080)]


class Recorder:
    def __init__(self):
        self.events = []

    def make(self, enter_px=2, leave_px=40):
        return module.EdgeGesture(
            on_hold_start=lambda: self.events.append("start"),
            on_hold_end=lambda: self.events.append("end"),
            enter_px=enter_px,
            leave_px=leave_px,
        )


def check(condition, message):
    if not condition:
        print(f"FAIL: {message}", file=sys.stderr)
        raise SystemExit(1)


def main() -> int:
    # Reaching the edge raises the bar once, not once per poll.
    rec = Recorder()
    g = rec.make()
    for _ in range(5):
        g.update(MONITORS, 2500, 0)
    check(rec.events == ["start"], f"edge should hold once, got {rec.events}")

    # The gap between enter and leave is the point: the bar appears under the
    # pointer, and moving around on it must not dismiss it.
    for y in (1, 10, 27, 40):
        g.update(MONITORS, 2500, y)
    check(rec.events == ["start"], f"bar dismissed while pointer on it: {rec.events}")

    g.update(MONITORS, 2500, 41)
    check(rec.events == ["start", "end"], f"leaving should release, got {rec.events}")

    # ...and it re-arms.
    g.update(MONITORS, 2500, 0)
    check(rec.events[-1] == "start", "gesture did not re-arm after release")

    # Hovering below the edge never raises it.
    rec = Recorder()
    g = rec.make()
    for y in (3, 50, 600, 1199):
        g.update(MONITORS, 2500, y)
    check(rec.events == [], f"non-edge positions raised the bar: {rec.events}")

    # A monitor whose top is not y=0 uses its own top edge, not the root's.
    rec = Recorder()
    g = rec.make()
    g.update(MONITORS, 500, 0)
    check(rec.events == [], "y=0 outside any monitor should do nothing")
    g.update(MONITORS, 500, 120)
    check(rec.events == ["start"], f"offset monitor top missed, got {rec.events}")
    g.update(MONITORS, 500, 161)
    check(rec.events == ["start", "end"], f"offset monitor leave missed: {rec.events}")

    # Crossing to the other head at its top edge keeps the bar up rather than
    # flapping, because both are the top of *a* monitor.
    rec = Recorder()
    g = rec.make()
    g.update(MONITORS, 500, 120)
    g.update(MONITORS, 2500, 0)
    check(rec.events == ["start"], f"crossing heads at the edge flapped: {rec.events}")

    # Pointer somewhere with no monitor at all (mid-hotplug) releases.
    g.update(MONITORS, 9000, 9000)
    check(rec.events == ["start", "end"], f"unknown position held on: {rec.events}")

    # release() is idempotent, since it runs on shutdown and on display loss.
    rec = Recorder()
    g = rec.make()
    g.release()
    check(rec.events == [], "release with no hold emitted an event")
    g.update(MONITORS, 2500, 0)
    g.release()
    g.release()
    check(rec.events == ["start", "end"], f"release not idempotent: {rec.events}")

    print("PASS: top-edge peek gesture")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Edge gesture bookkeeping for top-edge-peek.py.

Only the state machine is exercised; it is fed synthetic pointer positions, so
no X server and no real Polybar are involved. The watcher is imported through
the package rather than by path, which would drop a __pycache__ beside it in a
directory chezmoi manages. The fixture puts the laptop right of an external head,
the layout this profile actually runs, with the external offset downwards so the
two tops differ.

The method names carry the cases. The one they under-state: crossing to the other
head at its top edge must keep the bar up rather than flap, since both positions
are the top of *a* monitor.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("top_edge_peek", ROOT / "top-edge-peek.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

MONITORS = [(1920, 0, 1920, 1200), (0, 120, 1920, 1080)]


class Recorder:
    def __init__(self):
        self.events = []

    def make(self, enter_px=2, leave_px=40, suppressed=None):
        return module.EdgeGesture(
            on_hold_start=lambda: self.events.append("start"),
            on_hold_end=lambda: self.events.append("end"),
            enter_px=enter_px,
            leave_px=leave_px,
            suppressed=suppressed,
        )


def check(condition, message):
    if not condition:
        print(f"FAIL: {message}", file=sys.stderr)
        raise SystemExit(1)


def main() -> int:
    rec = Recorder()
    g = rec.make()
    for _ in range(5):
        g.update(MONITORS, 2500, 0)
    check(rec.events == ["start"], f"edge should hold once, got {rec.events}")

    for y in (1, 10, 27, 40):
        g.update(MONITORS, 2500, y)
    check(rec.events == ["start"], f"bar dismissed while pointer on it: {rec.events}")

    g.update(MONITORS, 2500, 41)
    check(rec.events == ["start", "end"], f"leaving should release, got {rec.events}")

    g.update(MONITORS, 2500, 0)
    check(rec.events[-1] == "start", "gesture did not re-arm after release")

    rec = Recorder()
    g = rec.make()
    for y in (3, 50, 600, 1199):
        g.update(MONITORS, 2500, y)
    check(rec.events == [], f"non-edge positions raised the bar: {rec.events}")

    rec = Recorder()
    g = rec.make()
    g.update(MONITORS, 500, 0)
    check(rec.events == [], "y=0 outside any monitor should do nothing")
    g.update(MONITORS, 500, 120)
    check(rec.events == ["start"], f"offset monitor top missed, got {rec.events}")
    g.update(MONITORS, 500, 161)
    check(rec.events == ["start", "end"], f"offset monitor leave missed: {rec.events}")

    rec = Recorder()
    g = rec.make()
    g.update(MONITORS, 500, 120)
    g.update(MONITORS, 2500, 0)
    check(rec.events == ["start"], f"crossing heads at the edge flapped: {rec.events}")

    g.update(MONITORS, 9000, 9000)
    check(rec.events == ["start", "end"], f"unknown position held on: {rec.events}")

    rec = Recorder()
    g = rec.make()
    g.release()
    check(rec.events == [], "release with no hold emitted an event")
    g.update(MONITORS, 2500, 0)
    g.release()
    g.release()
    check(rec.events == ["start", "end"], f"release not idempotent: {rec.events}")

    calls = []

    def external_is_fullscreen(monitors, x, y):
        calls.append((x, y))
        return x < 1920

    rec = Recorder()
    g = rec.make(suppressed=external_is_fullscreen)
    for _ in range(5):
        g.update(MONITORS, 500, 120)
    check(rec.events == [], f"peeked over a fullscreen screen: {rec.events}")
    check(len(calls) == 1, f"asked i3 once per poll, not once per entry: {calls}")

    g.update(MONITORS, 500, 161)
    g.update(MONITORS, 2500, 0)
    check(rec.events == ["start"], f"free head should still peek: {rec.events}")

    print("PASS: top-edge peek gesture")
    return 0


if __name__ == "__main__":
    sys.exit(main())

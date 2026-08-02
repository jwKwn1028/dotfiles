#!/usr/bin/env python3
"""Peek Polybar while the pointer rests against the top edge of a screen.

The standalone-Super hold gesture driven by the pointer instead of a key, so it
inherits that contract from polybar-peek.sh: the helper refuses to take over a
bar that was already visible, and hides the bar itself if the holder dies.

Polling, not an input region at the edge. An InputOnly window there would
swallow the clicks Polybar's modules need, and stacking it underneath flaps
instead -- showing the bar puts it above the region, which reads as a leave.
"""

from __future__ import annotations

import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from Xlib import display as xdisplay

# The pointer must reach this close to a monitor's top edge to raise the bar.
ENTER_PX = 2
# ...and get this far away to drop it. The gap is deliberate: the bar is 28px
# tall and appears under the pointer, so a single threshold would dismiss it the
# moment the pointer moved onto what it just revealed.
LEAVE_PX = 40
POLL_SECONDS = 0.1
# Outputs changing already restarts this process; re-reading is just insurance.
MONITOR_REFRESH_SECONDS = 5.0


class StopWatcher(Exception):
    pass


class EdgeGesture:
    """Hysteresis over the pointer's distance from the top of its monitor."""

    def __init__(self, on_hold_start, on_hold_end, enter_px, leave_px):
        self.on_hold_start = on_hold_start
        self.on_hold_end = on_hold_end
        self.enter_px = enter_px
        self.leave_px = leave_px
        self.holding = False

    def update(self, monitors, x, y) -> None:
        top = monitor_top(monitors, x, y)
        if top is None:
            # Off every known monitor (mid-hotplug); treat as away.
            self.release()
            return

        offset = y - top
        if not self.holding:
            if offset <= self.enter_px:
                self.holding = True
                self.on_hold_start()
        elif offset > self.leave_px:
            self.holding = False
            self.on_hold_end()

    def release(self) -> None:
        if self.holding:
            self.holding = False
            self.on_hold_end()


def monitor_top(monitors, x, y):
    """Top edge of the monitor under the pointer, or None if there is none."""
    for mx, my, width, height in monitors:
        if mx <= x < mx + width and my <= y < my + height:
            return my
    return None


def read_monitors(root):
    try:
        reply = root.xrandr_get_monitors()
    except Exception:
        return []
    return [
        (m.x, m.y, m.width_in_pixels, m.height_in_pixels)
        for m in reply.monitors
        if m.width_in_pixels > 0 and m.height_in_pixels > 0
    ]


def peek_command(script: Path, holder_pid: str, action: str) -> None:
    try:
        subprocess.run(
            [str(script), action, holder_pid],
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def runtime_lock():
    runtime_dir = Path(
        os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    )
    runtime_dir.mkdir(parents=True, exist_ok=True)
    lock_file = (runtime_dir / "i3-top-edge-peek.lock").open("a+")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_file.close()
        return None
    return lock_file


def positive_number(name, fallback):
    raw = os.environ.get(name, "")
    try:
        value = float(raw)
    except ValueError:
        return fallback
    return value if value > 0 else fallback


def main() -> int:
    lock_file = runtime_lock()
    if lock_file is None:
        return 0

    script = Path(__file__).resolve().parent / "polybar-peek.sh"
    holder_pid = str(os.getpid())
    enter_px = positive_number("I3_POLYBAR_EDGE_ENTER_PX", ENTER_PX)
    leave_px = positive_number("I3_POLYBAR_EDGE_LEAVE_PX", LEAVE_PX)
    poll = positive_number("I3_POLYBAR_EDGE_POLL_MS", POLL_SECONDS * 1000) / 1000

    gesture = EdgeGesture(
        on_hold_start=lambda: peek_command(script, holder_pid, "--hold-start"),
        on_hold_end=lambda: peek_command(script, holder_pid, "--hold-end"),
        enter_px=enter_px,
        leave_px=leave_px,
    )

    def stop(_signum, _frame):
        raise StopWatcher

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    try:
        while True:
            try:
                display = xdisplay.Display()
                root = display.screen().root
                monitors = read_monitors(root)
                refreshed = time.monotonic()

                while True:
                    now = time.monotonic()
                    if now - refreshed >= MONITOR_REFRESH_SECONDS:
                        monitors = read_monitors(root)
                        refreshed = now
                    pointer = root.query_pointer()
                    gesture.update(monitors, pointer.root_x, pointer.root_y)
                    time.sleep(poll)
            except StopWatcher:
                raise
            except Exception:
                # Drop the hold before reconnecting: this process is still
                # alive, so the helper's worker will not release it for us.
                gesture.release()
                time.sleep(1)
    except (StopWatcher, KeyboardInterrupt):
        return 0
    finally:
        gesture.release()
        lock_file.close()


if __name__ == "__main__":
    sys.exit(main())

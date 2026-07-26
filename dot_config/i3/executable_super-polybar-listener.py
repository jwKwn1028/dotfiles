#!/usr/bin/python3
"""Observe standalone Super gestures without grabbing keys from i3."""

from __future__ import annotations

import fcntl
import os
from pathlib import Path
import re
import select
import shutil
import signal
import subprocess
import sys
import time
from collections.abc import Callable


DEFAULT_HOLD_MS = 250
EVENT_RE = re.compile(r"\((RawKeyPress|RawKeyRelease)\)")
DETAIL_RE = re.compile(r"^\s*detail:\s*(\d+)\s*$")


class StopListener(Exception):
    """Raised by signal handlers to unwind through the active event stream."""


class RawKeyParser:
    """Turn the relevant lines from `xinput test-xi2` into key events."""

    def __init__(self) -> None:
        self.pending_kind: str | None = None

    def feed_line(self, line: str) -> tuple[str, int] | None:
        event = EVENT_RE.search(line)
        if event:
            self.pending_kind = (
                "press" if event.group(1) == "RawKeyPress" else "release"
            )
            return None

        if self.pending_kind is None:
            return None

        detail = DETAIL_RE.match(line)
        if not detail:
            return None

        result = (self.pending_kind, int(detail.group(1)))
        self.pending_kind = None
        return result


class SuperGesture:
    """Classify a Super-only tap or hold while rejecting all key chords."""

    def __init__(
        self,
        super_keycodes: set[int],
        hold_seconds: float,
        on_tap: Callable[[], None],
        on_hold_start: Callable[[], None],
        on_hold_end: Callable[[], None],
        on_hold_cancel: Callable[[], None],
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.super_keycodes = super_keycodes
        self.hold_seconds = hold_seconds
        self.on_tap = on_tap
        self.on_hold_start = on_hold_start
        self.on_hold_end = on_hold_end
        self.on_hold_cancel = on_hold_cancel
        self.clock = clock

        self.pressed: set[int] = set()
        self.super_down: set[int] = set()
        self.started_at: float | None = None
        self.chorded = False
        self.holding = False

    def _begin_hold_if_due(self, now: float) -> None:
        if (
            self.super_down
            and not self.chorded
            and not self.holding
            and self.started_at is not None
            and now - self.started_at >= self.hold_seconds
        ):
            self.on_hold_start()
            self.holding = True

    def poll(self, now: float | None = None) -> None:
        self._begin_hold_if_due(self.clock() if now is None else now)

    def seconds_until_hold(self, now: float | None = None) -> float | None:
        if (
            not self.super_down
            or self.chorded
            or self.holding
            or self.started_at is None
        ):
            return None
        current = self.clock() if now is None else now
        return max(0.0, self.hold_seconds - (current - self.started_at))

    def key_event(self, kind: str, keycode: int, now: float | None = None) -> None:
        current = self.clock() if now is None else now
        self._begin_hold_if_due(current)

        if kind == "press":
            already_pressed = keycode in self.pressed
            self.pressed.add(keycode)

            if keycode in self.super_keycodes:
                if keycode in self.super_down:
                    return
                if not self.super_down:
                    self.started_at = current
                    self.chorded = any(
                        code not in self.super_keycodes for code in self.pressed
                    )
                    self.holding = False
                self.super_down.add(keycode)
                return

            if self.super_down and not already_pressed:
                self.chorded = True
                if self.holding:
                    self.on_hold_cancel()
                    self.holding = False
            return

        if kind != "release":
            raise ValueError(f"unknown key event kind: {kind}")

        self.pressed.discard(keycode)
        if keycode not in self.super_keycodes or keycode not in self.super_down:
            return

        self.super_down.discard(keycode)
        if self.super_down:
            return

        if not self.chorded:
            if self.holding:
                self.on_hold_end()
            else:
                self.on_tap()

        self.started_at = None
        self.chorded = False
        self.holding = False

    def shutdown(self) -> None:
        if self.holding:
            self.on_hold_end()
        self.pressed.clear()
        self.super_down.clear()
        self.started_at = None
        self.chorded = False
        self.holding = False


class PeekCommands:
    def __init__(self, script: Path) -> None:
        self.script = script
        self.holder_pid = str(os.getpid())

    def _run(self, *args: str) -> None:
        try:
            subprocess.run(
                [str(self.script), *args],
                check=False,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass

    def tap(self) -> None:
        self._run()

    def hold_start(self) -> None:
        self._run("--hold-start", self.holder_pid)

    def hold_end(self) -> None:
        self._run("--hold-end", self.holder_pid)

    def hold_cancel(self) -> None:
        self._run("--hold-cancel", self.holder_pid)


def positive_milliseconds(name: str, fallback: int) -> int:
    raw = os.environ.get(name, "")
    try:
        value = int(raw)
    except ValueError:
        return fallback
    return value if value > 0 else fallback


def hold_milliseconds() -> int:
    peek_ms = positive_milliseconds("I3_POLYBAR_PEEK_MS", DEFAULT_HOLD_MS)
    return positive_milliseconds("I3_SUPER_HOLD_MS", peek_ms)


def resolve_super_keycodes() -> set[int]:
    override = os.environ.get("I3_SUPER_KEYCODES", "")
    if override:
        try:
            keycodes = {
                int(value)
                for value in re.split(r"[\s,]+", override.strip())
                if value
            }
        except ValueError:
            keycodes = set()
        if keycodes:
            return keycodes

    output = subprocess.check_output(
        ["xmodmap", "-pk"],
        text=True,
        stderr=subprocess.DEVNULL,
        timeout=5,
    )
    keycodes = set()
    for line in output.splitlines():
        if not re.search(r"\bSuper_[LR]\b", line):
            continue
        fields = line.split()
        if fields and fields[0].isdigit():
            keycodes.add(int(fields[0]))
    return keycodes


def input_command() -> list[str]:
    xinput = shutil.which("xinput")
    if xinput is None:
        raise FileNotFoundError("xinput is not installed")

    command = [xinput, "test-xi2", "--root"]
    stdbuf = shutil.which("stdbuf")
    if stdbuf is not None:
        command = [stdbuf, "-oL", *command]
    return command


def run_stream(gesture: SuperGesture) -> None:
    parser = RawKeyParser()
    process = subprocess.Popen(
        input_command(),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )
    if process.stdout is None:
        process.terminate()
        return

    fd = process.stdout.fileno()
    buffered = b""
    try:
        while True:
            now = time.monotonic()
            gesture.poll(now)
            timeout = gesture.seconds_until_hold(now)
            if timeout is None:
                timeout = 1.0
            else:
                timeout = min(timeout, 1.0)

            readable, _, _ = select.select([fd], [], [], timeout)
            if not readable:
                if process.poll() is not None:
                    return
                continue

            chunk = os.read(fd, 4096)
            if not chunk:
                return
            buffered += chunk

            while b"\n" in buffered:
                raw_line, buffered = buffered.split(b"\n", 1)
                event = parser.feed_line(raw_line.decode(errors="replace"))
                if event is not None:
                    gesture.key_event(*event)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def runtime_lock():
    runtime_dir = Path(
        os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    )
    runtime_dir.mkdir(parents=True, exist_ok=True)
    lock_file = (runtime_dir / "i3-super-polybar-listener.lock").open("a+")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock_file.close()
        return None
    return lock_file


def main() -> int:
    lock_file = runtime_lock()
    if lock_file is None:
        return 0

    directory = Path(__file__).resolve().parent
    commands = PeekCommands(directory / "polybar-peek.sh")
    gesture: SuperGesture | None = None

    def stop(_signum, _frame) -> None:
        raise StopListener

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    try:
        while True:
            try:
                super_keycodes = resolve_super_keycodes()
                if not super_keycodes:
                    raise RuntimeError("no Super keycodes found")
                gesture = SuperGesture(
                    super_keycodes=super_keycodes,
                    hold_seconds=hold_milliseconds() / 1000,
                    on_tap=commands.tap,
                    on_hold_start=commands.hold_start,
                    on_hold_end=commands.hold_end,
                    on_hold_cancel=commands.hold_cancel,
                )
                run_stream(gesture)
            except StopListener:
                raise
            except (OSError, RuntimeError, subprocess.SubprocessError):
                pass
            finally:
                if gesture is not None:
                    gesture.shutdown()
                    gesture = None
            time.sleep(1)
    except (StopListener, KeyboardInterrupt):
        return 0
    finally:
        lock_file.close()


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/python3
"""Save crashed i3 logs from shared memory before turning the log on again."""

from __future__ import annotations

import gzip
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "i3-crash-log.py"
if not SOURCE.is_file():
    SOURCE = ROOT / "executable_i3-crash-log.py"
SPEC = importlib.util.spec_from_file_location("i3_crash_log", SOURCE)
assert SPEC is not None and SPEC.loader is not None
CRASH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CRASH)

CRASH_LINE = b"11/27/2026 11:50:30 AM - ../src/sighandler.c:handle_signal:296 - i3 crashed. SIG: 11\n"


def shm(lines: bytes, size: int = 4096, older: bytes = b"") -> bytes:
    """An i3 log buffer: header, newest lines, then (if wrapped) older ones."""
    body = lines + older
    last_wrap = 16 + len(body) if older else size
    data = struct.pack("<IIII", 16 + len(lines), last_wrap, size, 1 if older else 0) + body
    return data + b"\0" * (size - len(data))


def dead_pid() -> int:
    process = subprocess.Popen(["true"])
    process.wait()
    return process.pid


class LogTextTests(unittest.TestCase):
    def test_unwrapped_log_is_read_to_the_next_write(self) -> None:
        self.assertEqual(CRASH.log_text(shm(b"a\nb\n")), b"a\nb\n")

    def test_wrapped_log_starts_with_older_lines_after_the_partial_one(self) -> None:
        data = shm(b"new 1\nnew 2\n", older=b"tial old\nold 2\nold 3\n")
        self.assertEqual(CRASH.log_text(data), b"old 2\nold 3\nnew 1\nnew 2\n")

    def test_short_buffer_reads_as_empty(self) -> None:
        self.assertEqual(CRASH.log_text(b"\0\0"), b"")


class RescueTests(unittest.TestCase):
    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.shm = self.root / "shm"
        self.logs = self.root / "state/crash"
        self.bin = self.root / "bin"
        for path in (self.shm, self.bin):
            path.mkdir(parents=True)
        self.calls = self.root / "calls"
        # i3-msg notes whether a crash log was saved before the log is turned on.
        (self.bin / "i3-msg").write_text(
            f'#!/bin/sh\nset -- "$@" "saved=$(ls {self.logs} 2>/dev/null | wc -l)"\n'
            f'echo "i3-msg $*" >>{self.calls}\n')
        (self.bin / "notify-send").write_text(f'#!/bin/sh\necho "notify-send $*" >>{self.calls}\n')
        for tool in self.bin.iterdir():
            tool.chmod(0o755)

    def run_script(self) -> list[str]:
        self.calls.unlink(missing_ok=True)
        env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}", HOME=str(self.root),
                   I3_CRASH_SHM_DIR=str(self.shm), I3_CRASH_LOG_DIR=str(self.logs))
        subprocess.run([sys.executable, str(SOURCE)], env=env, check=True, timeout=30)
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def saved(self) -> list[Path]:
        return sorted(self.logs.glob("i3-crash-*.log.gz"))

    def test_restarted_i3_crash_log_is_saved_before_logging_restarts(self) -> None:
        log = self.shm / f"i3-log-{os.getpid()}"
        log.write_bytes(shm(b"before\n" + CRASH_LINE))
        calls = self.run_script()
        [path] = self.saved()
        self.assertEqual(gzip.decompress(path.read_bytes()), b"before\n" + CRASH_LINE)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.logs.stat().st_mode & 0o777, 0o700)
        self.assertTrue(log.exists(), "the live i3 reuses its buffer")
        self.assertEqual(calls, [f"notify-send -u critical i3 crashed Log saved: ~/state/crash/{path.name}",
                                 "i3-msg -q shmlog on saved=1"])

    def test_same_crash_is_saved_once(self) -> None:
        (self.shm / f"i3-log-{os.getpid()}").write_bytes(shm(CRASH_LINE))
        self.run_script()
        self.assertEqual(self.run_script(), ["i3-msg -q shmlog on saved=1"])
        self.assertEqual(len(self.saved()), 1)

    def test_running_i3_without_a_crash_is_left_alone(self) -> None:
        log = self.shm / f"i3-log-{os.getpid()}"
        log.write_bytes(shm(b"normal restart\n"))
        self.assertEqual(self.run_script(), ["i3-msg -q shmlog on saved=0"])
        self.assertEqual(self.saved(), [])
        self.assertTrue(log.exists())

    def test_logs_of_dead_i3s_are_saved_if_crashed_and_removed(self) -> None:
        crashed = self.shm / f"i3-log-{dead_pid()}"
        crashed.write_bytes(shm(CRASH_LINE))
        killed = self.shm / f"i3-log-{dead_pid()}"
        killed.write_bytes(shm(b"killed\n"))
        self.run_script()
        self.assertEqual(len(self.saved()), 1)
        self.assertFalse(crashed.exists() or killed.exists())

    def test_other_files_are_ignored(self) -> None:
        for name in ("i3-log-abc", "other"):
            (self.shm / name).write_bytes(shm(CRASH_LINE))
        self.run_script()
        self.assertEqual(self.saved(), [])
        self.assertTrue((self.shm / "i3-log-abc").exists())

    def test_only_the_newest_logs_are_kept(self) -> None:
        self.logs.mkdir(parents=True)
        old = [f"i3-crash-200001{day:02}-120000-{day:08x}.log.gz" for day in range(1, 13)]
        for name in old:
            (self.logs / name).write_bytes(b"")
        (self.shm / f"i3-log-{os.getpid()}").write_bytes(shm(CRASH_LINE))
        self.run_script()
        names = [path.name for path in self.saved()]
        self.assertEqual(names[:-1], old[-(CRASH.KEEP - 1):])
        self.assertNotIn(names[-1], old)


if __name__ == "__main__":
    unittest.main()

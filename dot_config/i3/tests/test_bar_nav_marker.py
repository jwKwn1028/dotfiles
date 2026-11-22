#!/usr/bin/python3

from contextlib import ExitStack, closing
import importlib.util
import os
from pathlib import Path
import queue
import sys
import tempfile
import threading
import unittest
from unittest import mock

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "bar-nav-marker.py"
if not SOURCE.exists():
    SOURCE = ROOT / "executable_bar-nav-marker.py"
spec = importlib.util.spec_from_file_location("bar_nav_marker", SOURCE)
marker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(marker)


class FakeBlock:
    def __init__(self):
        self.rect = None
        self.visible = False

    def configure(self, *, x, y, width, height, stack_mode):
        self.rect = (x, y, width, height)

    def map(self):
        self.visible = True

    def unmap(self):
        self.visible = False


class FakeDisplay:
    def __init__(self):
        self.reader, self.writer = os.pipe()
        self.block = FakeBlock()
        self.draws = queue.Queue()
        self.waiting = threading.Event()
        self.closed = False
        self.disconnected = False

    def fileno(self):
        return self.reader

    def pending_events(self):
        self.waiting.set()
        if self.disconnected:
            raise OSError("X connection closed")
        return 0

    def sync(self):
        self.draws.put(self.block.rect if self.block.visible else None)

    def disconnect(self):
        self.disconnected = True
        os.write(self.writer, b"x")

    def close(self):
        if not self.closed:
            os.close(self.reader)
            os.close(self.writer)
            self.closed = True


class MarkerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.state = self.directory / "state"
        self.position = self.directory / "position"
        self.state.write_text("0\n")
        self.position.write_text("10 20 30 40\n")
        self.dsp = FakeDisplay()
        self.addCleanup(self.dsp.close)
        stack = ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(mock.patch.object(marker.display, "Display", return_value=self.dsp))
        stack.enter_context(mock.patch.object(marker, "make_block", return_value=self.dsp.block))
        self.read_rect = stack.enter_context(mock.patch.object(marker, "read_rect", wraps=marker.read_rect))
        self.results = queue.Queue()
        self.thread = None
        self.addCleanup(self.stop)

    def start(self):
        def run():
            try:
                self.results.put(marker.main(["marker", str(self.state), str(self.position)]))
            except BaseException as error:
                self.results.put(error)

        self.thread = threading.Thread(target=run, daemon=True)
        self.thread.start()

    def stop(self):
        self.state.unlink(missing_ok=True)
        if self.thread is not None:
            self.thread.join(2)
            if self.thread.is_alive() and not self.dsp.closed:
                self.dsp.disconnect()
                self.thread.join(2)
            self.assertFalse(self.thread.is_alive(), "marker did not stop")

    def draw(self, expected):
        self.assertEqual(self.dsp.draws.get(timeout=2), expected)

    def finished(self, error=None):
        result = self.results.get(timeout=2)
        if error is None:
            self.assertEqual(result, 0)
        else:
            self.assertIsInstance(result, error)
        self.thread.join(2)
        self.assertFalse(self.thread.is_alive())
        self.assertTrue(self.dsp.closed)

    def test_initial_position_without_periodic_reads(self):
        self.start()
        self.draw((10, 20, 30, 40))
        self.assertTrue(self.dsp.waiting.wait(2))
        (self.directory / "unrelated").write_text("change\n")
        self.state.write_text("1\n")
        with self.assertRaises(queue.Empty):
            self.dsp.draws.get(timeout=0.12)
        self.assertEqual(self.read_rect.call_count, 1)
        self.state.unlink()
        self.finished()

    def test_write_completion_and_truncation(self):
        self.start()
        self.draw((10, 20, 30, 40))
        with self.position.open("w") as output:
            output.write("50 60 70 80\n")
            output.flush()
            with self.assertRaises(queue.Empty):
                self.dsp.draws.get(timeout=0.08)
        self.draw((50, 60, 70, 80))
        self.position.write_text("")
        self.draw(None)
        self.state.unlink()
        self.finished()

    def test_replacement_deletion_and_recreation(self):
        self.start()
        self.draw((10, 20, 30, 40))
        replacement = self.directory / "replacement"
        replacement.write_text("11 22 33 44\n")
        replacement.replace(self.position)
        self.draw((11, 22, 33, 44))
        self.position.write_text("55 66 77 88\n")
        self.draw((55, 66, 77, 88))
        self.position.unlink()
        self.draw(None)
        self.position.write_text("10 20 30 40\n")
        self.draw((10, 20, 30, 40))
        self.state.unlink()
        self.finished()

    def test_state_removal_in_another_directory(self):
        directory = self.directory / "navigation"
        directory.mkdir()
        self.state = self.state.replace(directory / "state")
        self.start()
        self.draw((10, 20, 30, 40))
        self.state.rename(directory / "closed")
        self.finished()

    def test_missing_state_at_startup(self):
        self.state.unlink()
        self.start()
        self.finished()
        self.assertEqual(self.read_rect.call_count, 0)

    def test_change_during_display_setup_is_not_lost(self):
        def connect():
            self.position.write_text("90 80 70 60\n")
            return self.dsp

        with mock.patch.object(marker.display, "Display", side_effect=connect):
            self.start()
            self.draw((90, 80, 70, 60))
            self.state.unlink()
            self.finished()

    def test_x_disconnect_stops_waiting(self):
        self.start()
        self.draw((10, 20, 30, 40))
        self.assertTrue(self.dsp.waiting.wait(2))
        self.dsp.disconnect()
        self.finished(OSError)

    def test_directory_move_stops_watcher(self):
        directory = self.directory / "navigation"
        directory.mkdir()
        self.state = self.state.replace(directory / "state")
        self.position = self.position.replace(directory / "position")
        self.start()
        self.draw((10, 20, 30, 40))
        directory.rename(self.directory / "moved")
        self.finished(OSError)

    def test_overflow_requests_a_fresh_snapshot(self):
        with closing(marker.FileWatch(self.state, self.position)) as watcher:
            overflow = marker.EVENT_HEADER.pack(-1, marker.IN_Q_OVERFLOW, 0, 0)
            with mock.patch.object(marker.os, "read", return_value=overflow):
                self.assertTrue(watcher.changed())

    def test_failed_registration_closes_descriptor(self):
        before = set(os.listdir("/proc/self/fd"))
        with self.assertRaises(FileNotFoundError):
            marker.FileWatch(self.state, self.directory / "missing" / "position")
        self.assertEqual(set(os.listdir("/proc/self/fd")), before)


if __name__ == "__main__":
    unittest.main()

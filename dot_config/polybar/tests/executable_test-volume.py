#!/usr/bin/python3

import json
import fcntl
import ctypes
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "scripts/volume.py"
if not SOURCE.exists():
    SOURCE = ROOT / "scripts/executable_volume.py"

PACTL = '''#!/usr/bin/python3
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["VOLUME_TEST_ROOT"])
args = sys.argv[1:]
with (root / "calls").open("a") as stream:
    stream.write(json.dumps(dict(args=args, pid=os.getpid(), locale=os.environ.get("LC_ALL"))) + "\\n")
state = json.loads((root / "state.json").read_text())
if state.get("offline"):
    sys.exit(1)
if args == ["subscribe"]:
    with (root / "events").open("rb", buffering=0) as stream:
        (root / "ready").write_text(str(os.getpid()))
        while True:
            data = os.read(stream.fileno(), 65536)
            if not data:
                break
            os.write(sys.stdout.fileno(), data)
elif args == ["get-default-sink"]:
    print(state["default"])
elif args == ["--format=json", "list", "sinks"]:
    print("broken json" if state.get("malformed") else json.dumps(state["sinks"]))
elif args[0] == "set-sink-volume":
    sink = next(s for s in state["sinks"] if s["name"] == args[1])
    for channel, value in zip(sink["volume"].values(), args[2:], strict=True):
        channel["value"] = int(value)
    (root / "state.json").write_text(json.dumps(state))
else:
    sys.exit(2)
'''

IPC = '''#!/usr/bin/python3
import json
import os
from pathlib import Path
import sys

with (Path(os.environ["VOLUME_TEST_ROOT"]) / "ipc").open("a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
'''


class VolumeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="polybar-volume-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.script = self.directory / "polybar/scripts/volume.py"
        self.script.parent.mkdir(parents=True)
        self.script.write_text(SOURCE.read_text())
        config = (ROOT / "config.ini").read_text().replace("#6c7086", "#123456")
        (self.directory / "polybar/config.ini").write_text(config)
        binary = self.directory / "bin"
        binary.mkdir()
        for name, content in (("pactl", PACTL), ("polybar-msg", IPC)):
            path = binary / name
            path.write_text(content)
            path.chmod(0o755)
        self.environment = dict(os.environ, PATH=f"{binary}:/usr/bin:/bin",
                                XDG_RUNTIME_DIR=str(self.directory / "runtime"),
                                VOLUME_TEST_ROOT=str(self.directory), LC_ALL="invalid-locale")
        self.state = {"default": "speakers", "sinks": [
            self.sink("speakers", [16384, 49152]),
            self.sink("headphones", [22938, 22938]),
        ]}
        self.save()
        os.mkfifo(self.directory / "events")
        self.events = os.open(self.directory / "events", os.O_RDWR | os.O_NONBLOCK)
        self.addCleanup(os.close, self.events)
        self.watchers = []
        self.addCleanup(self.stop_watchers)

    def sink(self, name, values, muted=False):
        return dict(name=name, mute=muted,
                    volume={str(index): {"value": value} for index, value in enumerate(values)})

    def save(self):
        temporary = self.directory / "state.new"
        temporary.write_text(json.dumps(self.state))
        temporary.replace(self.directory / "state.json")

    def rows(self, name):
        path = self.directory / name
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def command(self, *args):
        return subprocess.run(["/usr/bin/python3", str(self.script), *args],
                              env=self.environment, text=True, capture_output=True, timeout=5)

    def wait_for(self, condition, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if condition():
                return
            for process in self.watchers:
                self.assertIsNone(process.poll(), "watcher exited unexpectedly")
            time.sleep(0.01)
        self.fail(f"condition not reached; calls={self.rows('calls')}; ipc={self.rows('ipc')}")

    def start(self):
        ready = self.directory / "ready"
        ready.unlink(missing_ok=True)
        updates = len(self.rows("ipc"))
        process = subprocess.Popen(["/usr/bin/python3", str(self.script), "watch"],
                                   env=self.environment, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.PIPE)
        self.watchers.append(process)
        self.wait_for(lambda: ready.exists() and ready.read_text().isdigit() and
                      len(self.rows("ipc")) >= updates + 2)
        return process

    def stop_watchers(self):
        for process in self.watchers:
            if process.poll() is None:
                process.terminate()
            try:
                _, error = process.communicate(timeout=4)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
                raise AssertionError("watcher did not stop")
            self.assertEqual(process.returncode, 0, error.decode())

    def emit(self, data=b"Event 'change' on sink #1\n"):
        os.write(self.events, data)

    def query_count(self):
        return sum(row["args"] == ["get-default-sink"] for row in self.rows("calls"))

    def test_label_uses_loudest_channel_and_shared_palette(self):
        result = self.command()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("75%", result.stdout)
        self.assertIn("󰕾", result.stdout)
        self.state["sinks"][0]["mute"] = True
        self.save()
        output = self.command().stdout
        self.assertIn("muted", output)
        self.assertIn("%{F#123456}", output)
        self.assertIn("󰝟", output)
        self.assertTrue(all(row["locale"] == "C" for row in self.rows("calls")))

    def test_missing_sink_and_invalid_reply_show_unavailable(self):
        self.state["sinks"] = []
        self.save()
        result = self.command()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("unavailable", result.stdout)
        self.state["malformed"] = True
        self.save()
        self.assertIn("unavailable", self.command().stdout)

    def test_scroll_limits_preserve_channel_balance(self):
        self.state["sinks"][0] = self.sink("speakers", [65490, 32768])
        self.save()
        self.assertEqual(self.command("up").returncode, 0)
        state = json.loads((self.directory / "state.json").read_text())
        values = [channel["value"] for channel in state["sinks"][0]["volume"].values()]
        self.assertEqual(values, [65536, 32791])
        setters = [row for row in self.rows("calls") if row["args"][0] == "set-sink-volume"]
        self.assertEqual(self.command("up").returncode, 0)
        self.assertEqual(len([row for row in self.rows("calls") if row["args"][0] == "set-sink-volume"]), len(setters))
        self.state["sinks"][0] = self.sink("speakers", [78643, 39322])
        self.save()
        self.assertEqual(self.command("up").returncode, 0)
        self.assertEqual(self.command("down").returncode, 0)
        state = json.loads((self.directory / "state.json").read_text())
        self.assertEqual([channel["value"] for channel in state["sinks"][0]["volume"].values()], [77988, 38994])
        self.state["sinks"][0] = self.sink("speakers", [100, 0])
        self.save()
        self.assertEqual(self.command("down").returncode, 0)
        state = json.loads((self.directory / "state.json").read_text())
        self.assertEqual([channel["value"] for channel in state["sinks"][0]["volume"].values()], [0, 0])

    def test_scroll_matches_the_original_libpulse_channel_scaling(self):
        class ChannelVolume(ctypes.Structure):
            _fields_ = [("channels", ctypes.c_uint8), ("values", ctypes.c_uint32 * 32)]

        pulse = ctypes.CDLL("libpulse.so.0")
        for name in ("pa_cvolume_inc", "pa_cvolume_dec", "pa_cvolume_scale"):
            getattr(pulse, name).argtypes = [ctypes.POINTER(ChannelVolume), ctypes.c_uint32]
        for values, direction in (([0, 0], 1), ([16384, 49152], 1), ([65490, 32768], 1),
                                  ([78643, 39322], 1), ([78643, 39322], -1), ([100, 0], -1)):
            with self.subTest(values=values, direction=direction):
                expected = ChannelVolume(len(values), (ctypes.c_uint32 * 32)(*values))
                if direction < 0:
                    pulse.pa_cvolume_dec(ctypes.byref(expected), 655)
                elif max(values) + 655 <= 65536:
                    pulse.pa_cvolume_inc(ctypes.byref(expected), 655)
                elif max(values) < 65536:
                    pulse.pa_cvolume_scale(ctypes.byref(expected), 65536)
                self.state["sinks"][0] = self.sink("speakers", values)
                self.save()
                result = self.command("up" if direction > 0 else "down")
                self.assertEqual(result.returncode, 0, result.stderr)
                state = json.loads((self.directory / "state.json").read_text())
                actual = [channel["value"] for channel in state["sinks"][0]["volume"].values()]
                self.assertEqual(actual, list(expected.values)[:len(values)])

    def test_concurrent_scrolls_apply_every_step_while_watching(self):
        self.state["sinks"][0] = self.sink("speakers", [32768, 32768])
        self.save()
        self.start()
        scrolls = [subprocess.Popen(["/usr/bin/python3", str(self.script), "up"],
                                    env=self.environment, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.PIPE)
                   for _ in range(10)]
        for process in scrolls:
            _, error = process.communicate(timeout=20)
            self.assertEqual(process.returncode, 0, error.decode())
        state = json.loads((self.directory / "state.json").read_text())
        values = [channel["value"] for channel in state["sinks"][0]["volume"].values()]
        self.assertEqual(values, [32768 + 10 * 655] * 2)

    def test_initial_update_reaches_both_twins_and_idle_does_not_poll(self):
        self.start()
        rows = self.rows("ipc")
        self.assertEqual([row[:3] for row in rows], [["action", "pulseaudio", "send"], ["action", "pulseaudio-sel", "send"]])
        self.assertEqual(rows[0][3], rows[1][3])
        self.emit(b"Event 'change' on sink-input #7\nEvent 'new' on source #2\nEvent 'remove' on client #8\n")
        time.sleep(0.2)
        self.assertEqual(self.query_count(), 1)
        self.assertEqual(len(self.rows("ipc")), 2)

    def test_default_sink_mute_and_unchanged_events(self):
        self.start()
        self.state["default"] = "headphones"
        self.save()
        self.emit(b"Event 'change' on server #0\n")
        self.wait_for(lambda: len(self.rows("ipc")) == 4)
        self.assertTrue(all("35%" in row[3] for row in self.rows("ipc")[-2:]))
        self.state["sinks"][1]["mute"] = True
        self.save()
        self.emit()
        self.wait_for(lambda: len(self.rows("ipc")) == 6)
        self.assertTrue(all("muted" in row[3] for row in self.rows("ipc")[-2:]))
        self.emit()
        self.wait_for(lambda: self.query_count() == 4)
        time.sleep(0.1)
        self.assertEqual(len(self.rows("ipc")), 6)

    def test_partial_lines_and_queued_burst_refresh_once(self):
        self.start()
        self.state["sinks"][0] = self.sink("speakers", [43909, 43909])
        self.save()
        self.emit(b"Event 'change' on si")
        time.sleep(0.1)
        self.assertEqual(self.query_count(), 1)
        self.emit(b"nk #1\n" + b"Event 'change' on sink #1\n" * 50)
        self.wait_for(lambda: len(self.rows("ipc")) == 4)
        self.assertTrue(all("67%" in row[3] for row in self.rows("ipc")[-2:]))
        time.sleep(0.25)
        self.assertEqual(self.query_count(), 2)

    def test_disconnect_reconnect_and_shutdown_reap_subscriber(self):
        process = self.start()
        subscriber = int((self.directory / "ready").read_text())
        self.state["offline"] = True
        self.save()
        os.kill(subscriber, signal.SIGTERM)
        self.wait_for(lambda: any("unavailable" in row[3] for row in self.rows("ipc")))
        self.state["offline"] = False
        self.state["default"] = "headphones"
        self.save()
        self.wait_for(lambda: "35%" in self.rows("ipc")[-1][3])
        current = int((self.directory / "ready").read_text())
        self.assertNotEqual(current, subscriber)
        process.terminate()
        process.communicate(timeout=4)
        self.watchers.remove(process)
        self.assertEqual(process.returncode, 0)
        for pid in (subscriber, current):
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)
        self.start()

    def test_second_watcher_exits_without_another_subscription(self):
        self.start()
        result = self.command("watch")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(row["args"] == ["subscribe"] for row in self.rows("calls")), 1)

    def test_replacement_waits_for_the_old_lock_to_be_released(self):
        runtime = self.directory / "runtime"
        runtime.mkdir()
        with (runtime / "polybar-volume.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            process = subprocess.Popen(["/usr/bin/python3", str(self.script), "watch"],
                                       env=self.environment, stdout=subprocess.DEVNULL,
                                       stderr=subprocess.PIPE)
            self.watchers.append(process)
            time.sleep(0.15)
            self.assertIsNone(process.poll())
            self.assertEqual(self.rows("calls"), [])
            fcntl.flock(lock, fcntl.LOCK_UN)
            self.wait_for(lambda: len(self.rows("ipc")) == 2)

    def test_invalid_action_does_not_control_audio(self):
        self.assertEqual(self.command("invalid").returncode, 2)
        self.assertEqual(self.rows("calls"), [])


if __name__ == "__main__":
    unittest.main()

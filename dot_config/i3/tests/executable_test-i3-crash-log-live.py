#!/usr/bin/python3
"""Crash a Xephyr i3, press r on its crash screen, and check its log was saved."""

from __future__ import annotations

import gzip
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "i3-crash-log.py"
if not SCRIPT.is_file():
    SCRIPT = ROOT / "executable_i3-crash-log.py"
sys.path.insert(0, str(SCRIPT.parent))
MARKER = b"i3 crashed. SIG: 11"


def wait(check, seconds=10.0):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if check():
            return True
        time.sleep(0.1)
    raise AssertionError(f"timed out waiting for {check.__name__}")


def main() -> int:
    import importlib.util
    spec = importlib.util.spec_from_file_location("i3_crash_log", SCRIPT)
    crash = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(crash)
    with tempfile.TemporaryDirectory(prefix="i3-crash-live-") as name:
        directory = Path(name)
        display = next(f":{index}" for index in range(40, 70) if not Path(f"/tmp/.X{index}-lock").exists())
        sock, logs, notes = directory / "i3.sock", directory / "logs", directory / "notifications"
        (directory / "bin").mkdir()
        notify = directory / "bin/notify-send"
        notify.write_text(f'#!/bin/sh\necho "$*" >>{notes}\n')
        notify.chmod(0o755)
        config = directory / "config"
        config.write_text(f"# i3 config file (v4)\nfont pango:monospace 10\nipc-socket {sock}\n"
                          f"exec_always --no-startup-id /usr/bin/python3 {SCRIPT}\n")
        env = dict(os.environ, DISPLAY=display, I3SOCK=str(sock), I3_CRASH_LOG_DIR=str(logs),
                   PATH=f"{directory / 'bin'}:{os.environ['PATH']}")
        processes = [subprocess.Popen(["Xephyr", display, "-screen", "800x600", "-ac", "-noreset"],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)]
        try:
            wait(lambda: subprocess.run(["xdpyinfo"], env=env, capture_output=True).returncode == 0)
            i3 = subprocess.Popen(["i3", "-c", str(config)], env=env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            processes.append(i3)
            shm = Path(f"/dev/shm/i3-log-{i3.pid}")

            def logging_on():  # Turning it on sets this root property; a restart clears it.
                atom = subprocess.run(["xprop", "-root", "I3_SHMLOG_PATH"], env=env, capture_output=True, text=True)
                return shm.name in atom.stdout

            wait(logging_on)
            subprocess.run(["i3-msg", "-q", "workspace before-crash"], env=env, timeout=5)
            os.kill(i3.pid, signal.SIGSEGV)

            def crash_screen():
                return MARKER in crash.log_text(shm.read_bytes())

            wait(crash_screen)
            time.sleep(0.5)
            subprocess.run(["xdotool", "key", "r"], env=env, check=True)

            def saved():
                return any(logs.glob("i3-crash-*.log.gz"))

            wait(saved)
            [path] = logs.glob("i3-crash-*.log.gz")
            text = gzip.decompress(path.read_bytes())
            assert MARKER in text and b"before-crash" in text, text[-500:]
            assert i3.poll() is None, "i3 did not restart in place"
            assert f"Log saved: {path}" in notes.read_text(), notes.read_text()

            def logging_restarted():
                return logging_on() and MARKER not in crash.log_text(shm.read_bytes())

            wait(logging_restarted)
        finally:
            for process in reversed(processes):
                process.terminate()
            for process in processes:
                try:
                    process.wait(5)
                except subprocess.TimeoutExpired:
                    process.kill()
            Path(f"/dev/shm/i3-log-{processes[-1].pid}").unlink(missing_ok=True)
    print("PASS: a crashed i3's log is saved after r on its crash screen, and logging restarts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

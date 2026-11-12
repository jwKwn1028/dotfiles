#!/usr/bin/python3

import configparser
import fcntl
import json
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import time


os.environ["LC_ALL"] = "C"
EVENT = re.compile(rb"Event '[^']+' on (?:sink|server) #[0-9]+$")
NORMAL = 65536
STEP = round(NORMAL / 100)


def pactl(*arguments):
    return subprocess.check_output(["pactl", *arguments], text=True,
                                   stderr=subprocess.DEVNULL, timeout=2).strip()


def sink_state():
    name = pactl("get-default-sink")
    sinks = json.loads(pactl("--format=json", "list", "sinks"))
    sink = next(sink for sink in sinks if sink["name"] == name)
    volumes = [channel["value"] for channel in sink["volume"].values()]
    if not volumes or any(type(value) is not int or value < 0 for value in volumes):
        raise ValueError("Invalid sink volume")
    return name, volumes, sink["mute"]


def label(color):
    try:
        _, volumes, muted = sink_state()
    except (OSError, ValueError, KeyError, StopIteration, subprocess.SubprocessError):
        return f"%{{F{color}}}%{{T2}}󰝟 %{{T-}}unavailable%{{F-}}"
    if muted:
        return f"%{{F{color}}}%{{T2}}󰝟 %{{T-}}muted%{{F-}}"
    percent = (max(volumes) * 100 + NORMAL // 2) // NORMAL
    return f"%{{F#ffffff}}%{{T2}}󰕾 %{{T-}}%{{F-}}{percent}%"


def runtime_dir():
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    runtime.mkdir(parents=True, exist_ok=True)
    return runtime


def adjust(direction):
    # Polybar does not wait for one scroll command before starting the next, so
    # serialize the read-modify-write; otherwise concurrent ticks drop steps.
    with (runtime_dir() / "polybar-volume-adjust.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        name, volumes, _ = sink_state()
        current = max(volumes)
        if direction > 0 and current >= NORMAL:
            return
        target = max(0, current + direction * STEP)
        if direction > 0:
            target = min(NORMAL, target)
        values = [value * target // current if current else target for value in volumes]
        pactl("set-sink-volume", name, *map(str, values))


def watch(color):
    with (runtime_dir() / "polybar-volume.lock").open("a+") as lock:
        deadline = time.monotonic() + 3
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    return
                time.sleep(0.05)

        def stop(*_):
            raise SystemExit(0)

        for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(number, stop)

        previous = None

        def publish(output):
            nonlocal previous
            if output == previous:
                return
            for module in ("pulseaudio", "pulseaudio-sel"):
                try:
                    subprocess.run(["polybar-msg", "action", module, "send", output],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   timeout=2, check=False)
                except (OSError, subprocess.SubprocessError):
                    pass
            previous = output

        while True:
            process = None
            try:
                process = subprocess.Popen(["pactl", "subscribe"], stdout=subprocess.PIPE,
                                           stderr=subprocess.DEVNULL)
                publish(label(color))
                pending = b""
                ended = False
                while not ended:
                    select.select([process.stdout], [], [])
                    chunks = []
                    for _ in range(16):
                        chunk = os.read(process.stdout.fileno(), 65536)
                        if not chunk:
                            ended = True
                            break
                        chunks.append(chunk)
                        if not select.select([process.stdout], [], [], 0)[0]:
                            break
                    lines = (pending + b"".join(chunks)).split(b"\n")
                    pending = lines.pop()
                    if any(EVENT.fullmatch(line) for line in lines):
                        publish(label(color))
            except (OSError, subprocess.SubprocessError):
                pass
            finally:
                if process is not None:
                    if process.poll() is None:
                        process.terminate()
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                    process.stdout.close()
            publish(f"%{{F{color}}}%{{T2}}󰝟 %{{T-}}unavailable%{{F-}}")
            time.sleep(1)


def main():
    action = sys.argv[1] if len(sys.argv) == 2 else "print" if len(sys.argv) == 1 else ""
    if action not in ("print", "watch", "up", "down"):
        print("usage: volume.py [print|watch|up|down]", file=sys.stderr)
        return 2
    config = configparser.ConfigParser(interpolation=None)
    config.read(Path(__file__).resolve().parent.parent / "config.ini")
    color = config.get("colors", "disabled")
    if action == "watch":
        watch(color)
    elif action == "print":
        print(label(color))
    else:
        try:
            adjust(1 if action == "up" else -1)
        except (OSError, ValueError, KeyError, StopIteration, subprocess.SubprocessError):
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

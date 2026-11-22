#!/usr/bin/python3
"""Workspace groups: controller, commands, and Polybar output."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path
import queue
import re
import shlex
import signal
import socket
import subprocess
import sys
import threading
import time

from workspace_groups import GroupError, identity, request, session_dir, socket_path, source_path, subscribe

LEGACY = re.compile(r"^bash .*/(focus-tracker|snap-watcher)\.sh$|^[^ ]*/python[^ ]* [^ ]*/(autotiling|overflow-watcher\.py)( |$)")


def serve():
    import i3ipc
    from group_controller import Controller
    from group_restore import Restore

    directory = session_dir()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (directory / "controller.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        stopped = threading.Event()
        events = queue.SimpleQueue()

        def stop(*_):
            stopped.set()
            events.put(("stop", "", None))

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        path = directory / "controller.sock"
        path.unlink(missing_ok=True)
        controller = Controller(i3ipc.Connection(socket_path=socket_path()), directory)
        controller.restore = Restore(controller)

        def forward(kind, event):
            if kind != "window" or event.change != "title":
                events.put((kind, event.change, getattr(getattr(event, "container", None), "id", None)))

        def listen():
            while not stopped.is_set():
                try:
                    connection = i3ipc.Connection(socket_path=socket_path())
                    for kind in ("window", "workspace", "output", "mode"):
                        connection.on(kind, lambda _, event, kind=kind: forward(kind, event))
                    events.put(("reconnect", "", None))
                    connection.main()
                    events.put(("disconnected", "i3 closed the connection", None))
                except Exception as error:
                    events.put(("disconnected", str(error), None))
                stopped.wait(0.5)

        def accept(server):
            while not stopped.is_set():
                try:
                    client, _ = server.accept()
                except OSError:
                    if stopped.wait(0.1):
                        return
                    continue
                client.settimeout(2)
                try:
                    with client.makefile("rb") as stream:
                        payload = json.loads(stream.readline(8 * 1024 * 1024))
                except Exception as error:
                    payload = error
                events.put(("client", client, payload))

        def answer(client, payload):
            try:
                if isinstance(payload, Exception):
                    raise payload
                action = payload.pop("action")
                if action == "subscribe":
                    client.settimeout(0.5)
                    subscribers.append(client)
                    return True
                if action == "stop":
                    stopped.set()
                    result = True
                else:
                    result = controller.dispatch(action, **payload)
                reply = dict(ok=True, result=result)
            except Exception as error:
                reply = dict(ok=False, error=str(error))
            try:
                client.sendall(json.dumps(reply).encode() + b"\n")
            except OSError:
                pass
            client.close()
            return False

        thread = threading.Thread(target=listen, daemon=True)
        thread.start()
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(path))
            server.listen(16)
            last_maintenance, lost_since = 0, None
            subscribers, last_push, dirty = [], None, True
            try:
                controller.recover_workers()
                controller.initialize()
                controller.restore.maintain()
                controller.resume_workers()
                threading.Thread(target=accept, args=(server,), daemon=True).start()
                while not stopped.is_set():
                    try:
                        batch = [events.get(timeout=max(0.0, last_maintenance + 1 - time.monotonic()))]
                    except queue.Empty:
                        batch = []
                    while batch and len(batch) < 200:
                        try:
                            batch.append(events.get_nowait())
                        except queue.Empty:
                            break
                    for kind, change, con_id in batch:
                        dirty = True
                        if kind == "client":
                            if answer(change, con_id):
                                last_push = None
                            continue
                        try:
                            if kind == "stop":
                                continue
                            if kind == "disconnected":
                                controller.ready = False
                                lost_since = lost_since or time.monotonic()
                            elif kind == "reconnect":
                                lost_since = None
                                controller.i3 = i3ipc.Connection(socket_path=socket_path())
                                controller.initialize()
                            else:
                                controller.on_event(kind, change, con_id)
                        except Exception as error:
                            controller.ready = False
                            print(f"Group event: {error}", file=sys.stderr, flush=True)
                    if time.monotonic() - last_maintenance >= 1:
                        if lost_since and time.monotonic() - lost_since > 10:
                            print("Group stop: i3 unreachable for 10 s", file=sys.stderr, flush=True)
                            break
                        try:
                            if not lost_since:
                                controller.restore.maintain()
                                controller.resume_workers()
                                if not controller.ready:
                                    dirty = True
                                    controller.select(controller.selected(), force=True)
                        except Exception as error:
                            print(f"Group recovery: {error}", file=sys.stderr, flush=True)
                        last_maintenance = time.monotonic()
                    if subscribers and (dirty or last_push is None):
                        try:
                            line = json.dumps(controller.bar_status()).encode() + b"\n"
                        except Exception:
                            line = json.dumps(dict(ready=False)).encode() + b"\n"
                        if line != last_push:
                            for subscriber in list(subscribers):
                                try:
                                    subscriber.sendall(line)
                                except OSError:
                                    subscribers.remove(subscriber)
                                    subscriber.close()
                            last_push = line
                        dirty = False
            finally:
                stopped.set()
                try:
                    server.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                for subscriber in subscribers:
                    subscriber.close()
                controller.ready = False
                controller.pause_workers(all_workers=True)
                controller.save()
                path.unlink(missing_ok=True)


def stop_legacy():
    marker = ("DISPLAY=" + os.environ.get("DISPLAY", "")).encode()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            command = (proc / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip()
            if LEGACY.search(command) and marker in (proc / "environ").read_bytes().split(b"\0"):
                os.kill(int(proc.name), signal.SIGTERM)
        except (OSError, ProcessLookupError):
            continue


def start():
    directory = session_dir()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (directory / "start.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            request("stop")
        except GroupError:
            pass
        deadline = time.monotonic() + 5
        while (directory / "controller.sock").exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        stop_legacy()
        with (directory / "controller.log").open("w") as log:
            subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "serve"],
                             start_new_session=True, stdin=subprocess.DEVNULL, stdout=log, stderr=log)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                if request("status")["ready"]:
                    return
            except GroupError:
                pass
            time.sleep(0.1)
        raise GroupError("Workspace controller did not start; see " + str(directory / "controller.log"))


def bar_text(status):
    if not status["ready"]:
        return "%{F#f38ba8}groups unavailable%{F-}"
    selected, groups = status["selected"], status["groups"]
    command = shlex.quote(str(source_path("workspace-action.sh")))
    urgent = {identity(ws["num"], groups)[0] for ws in status["workspaces"]
              if ws["urgent"] and identity(ws["num"], groups)}
    occupied = {window["group"][0] for window in status.get("windows", [])}

    colors = {name: os.environ.get("GROUP_" + name.upper(), default) for name, default in (
        ("foreground", "#e0e0e0"), ("primary", "#89b4fa"), ("disabled", "#6c7086"),
        ("alert", "#f38ba8"), ("focusblock", "#33ffffff"))}

    def button(text, action, color, active=False):
        background = f"%{{B{colors['focusblock']}}}" if active else ""
        return f"%{{A1:{command} {action}:}}{background}%{{F{colors[color]}}} {text} %{{F-}}%{{B-}}%{{A}}"

    def scroll(text, up, down):
        return f"%{{A4:{command} {up}:}}%{{A5:{command} {down}:}}{text}%{{A}}%{{A}}"

    tabs = "".join(button(group + ("!" if group in urgent and group != selected else ""),
                          "select " + group, "primary" if group == selected else
                          "alert" if group in urgent else "foreground", group == selected) for group in groups
                   if group == selected or group in occupied or group in urgent)
    slots = []
    for ws in sorted(status["workspaces"], key=lambda value: value["num"]):
        current = identity(ws["num"], groups)
        if not current or current[0] != selected:
            continue
        color = "primary" if ws["focused"] else "alert" if ws["urgent"] else "disabled" if ws["visible"] else "foreground"
        slots.append(button(str(current[1]), f"switch {current[1]} --group {selected} --click", color, ws["focused"]))
    return (scroll(tabs, "group-relative -1 --quiet", "group-relative 1 --quiet") +
            scroll(" | " + "".join(slots), f"cycle -1 --group {selected}", f"cycle 1 --group {selected}"))


def bar():
    previous = None
    while True:
        statuses = subscribe()
        while True:
            try:
                output = bar_text(next(statuses))
            except (GroupError, StopIteration):
                output = "%{F#f38ba8}groups unavailable%{F-}"
            if output != previous:
                print(output, flush=True)
                previous = output
            if "unavailable" in output:
                break
        time.sleep(1)


def window_menu():
    menu = request("window-menu")
    selected = subprocess.run(["rofi", "-dmenu", "-i", "-show-icons", "-format", "i", "-p", "Window"],
                              input=menu["menu"], text=True, stdout=subprocess.PIPE)
    if selected.returncode == 0 and selected.stdout.strip().isdigit():
        index = int(selected.stdout.strip())
        if 0 <= index < len(menu["ids"]):
            request("focus", value=menu["ids"][index])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action")
    parser.add_argument("value", nargs="?")
    parser.add_argument("--group")
    parser.add_argument("--click", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()
    try:
        if args.action == "serve":
            serve()
        elif args.action == "start":
            start()
        elif args.action == "bar":
            bar()
        elif args.action == "window-menu":
            window_menu()
        elif args.action == "path":
            print(session_dir())
        elif args.action == "request":
            payload = json.load(sys.stdin)
            print(json.dumps(request(payload.pop("action"), **payload)))
        else:
            values = dict(quiet=args.quiet)
            if args.value is not None:
                values["group" if args.action == "select" else "value"] = args.value
            if args.group:
                values["group"] = args.group
            if args.click:
                values["click"] = True
            result = request(args.action, **values)
            if args.action == "status":
                print(json.dumps(result))
            elif args.action == "placement":
                return 0 if result else 1
    except (GroupError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

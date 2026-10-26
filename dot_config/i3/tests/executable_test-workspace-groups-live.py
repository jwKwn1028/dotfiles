#!/usr/bin/python3
"""Exercise workspace groups in isolated Xephyr/i3 sessions."""

import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import uuid

import i3ipc

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


def wait(test, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = test()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for nested session")


def run(dual=False):
    directory = Path(tempfile.mkdtemp(prefix="i3-groups-live-"))
    processes = []
    try:
        for path in ROOT.iterdir():
            if path.is_file():
                target = directory / "i3" / path.name.removeprefix("executable_")
                target.parent.mkdir(exist_ok=True)
                shutil.copyfile(path, target)
                if path.name.startswith("executable_"):
                    target.chmod(0o755)
        display = next(f":{index}" for index in range(40, 70) if not Path(f"/tmp/.X{index}-lock").exists())
        config = directory / "config"
        sock = directory / "i3.sock"
        scratch_rule = next(line for line in (ROOT / "config").read_text().splitlines()
                            if line.startswith('for_window [class="^com[.]mitchellh[.]ghostty[.]scratchpad$"]'))
        config.write_text(f'# i3 config file (v4)\nfont pango:monospace 10\nipc-socket {sock}\nworkspace_auto_back_and_forth yes\nfocus_follows_mouse no\n{scratch_rule}\n')
        environment = dict(os.environ, DISPLAY=display, I3SOCK=str(sock), XDG_RUNTIME_DIR=str(directory / "runtime"),
                           I3_GROUP_PEEK="/bin/true", I3_GROUP_WORKERS="1", XDG_STATE_HOME=str(directory / "state"), PYTHONDONTWRITEBYTECODE="1")
        Path(environment["XDG_RUNTIME_DIR"]).mkdir(mode=0o700)
        processes.append(subprocess.Popen(["Xephyr", display, *( ["+xinerama"] if dual else []),
                                           "-screen", "1000x700", *(["-screen", "1000x700"] if dual else []),
                                           "-ac", "-noreset"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        wait(lambda: subprocess.run(["xdpyinfo"], env=environment, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL).returncode == 0)
        log = (directory / "i3.log").open("w")
        processes.append(subprocess.Popen(["i3", *(["--force-xinerama"] if dual else []), "-c", str(config)],
                                           env=environment, stdout=log, stderr=log))
        wait(sock.exists)
        i3 = i3ipc.Connection(socket_path=str(sock))
        helper = directory / "i3/workspace-groups.py"
        controller_log = (directory / "controller.log").open("w")
        processes.append(subprocess.Popen(["/usr/bin/python3", str(helper), "serve"], env=environment,
                                           stdout=controller_log, stderr=controller_log))

        def rpc(action, **values):
            result = subprocess.run(["/usr/bin/python3", str(helper), "request"], env=environment,
                                    input=json.dumps(dict(action=action, **values)), text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode:
                raise AssertionError(result.stderr)
            return json.loads(result.stdout)

        def started():
            try:
                return rpc("status")["ready"]
            except Exception:
                return False

        wait(started)

        def window(title):
            return next((con for con in i3.get_tree().leaves() if con.name == title), None)

        def open_window(title):
            processes.append(subprocess.Popen(["xterm", "-T", title, "-e", "sleep", "120"], env=environment,
                                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            return wait(lambda: window(title))

        def focused_number():
            focused = i3.get_tree().find_focused()
            return focused.workspace().num if focused else None

        def uniform(group):
            return all((ws.num - 1) // 10 == group for ws in i3.get_workspaces() if ws.visible)

        scratch_class = "com.mitchellh.ghostty.scratchpad"
        processes.append(subprocess.Popen(["xterm", "-class", scratch_class, "-T", "scratch-test", "-e", "sleep", "120"],
                                           env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        scratch = wait(lambda: window("scratch-test"))
        assert scratch.workspace().name == "__i3_scratch"
        i3.command(f"[con_id={scratch.id}] floating enable, resize set 800 500, move scratchpad")
        scratch_script = directory / "i3/scratch-terminal.sh"
        for slot in ([1, 4] if dual else [1]):
            rpc("switch", value=slot)
            subprocess.run(["bash", str(scratch_script)], env=environment, check=True)
            shown = window("scratch-test")
            floating = shown.parent if shown.parent.type == "floating_con" else shown
            usable = shown.workspace().rect
            assert abs(floating.rect.x - (usable.x + (usable.width - floating.rect.width) / 2)) <= 2
            assert abs(floating.rect.y - (usable.y + (usable.height - floating.rect.height) / 2)) <= 2
            subprocess.run(["bash", str(scratch_script)], env=environment, check=True)
            assert window("scratch-test").workspace().name == "__i3_scratch"
        i3.command(f"[con_id={scratch.id}] kill")
        print(f"PASS {'dual' if dual else 'single'}: scratch terminal centers on each monitor", flush=True)
        if "scratch-only" in sys.argv:
            rpc("stop")
            return
        rpc("switch", value=1, click=True)

        rpc("switch", value=4)
        a = open_window("group-a-original")
        rpc("select", group="B")
        assert uniform(1)
        rpc("switch", value=10)
        b = open_window("group-b-original")
        before = i3.get_tree().ipc_data
        assert rpc("relative", value=1) is False
        assert focused_number() == 20
        assert rpc("cycle", value=1)
        assert focused_number() == 11
        rpc("switch", value=4)
        transferred = open_window("transfer")
        rpc("transfer", value=1)
        assert window("transfer").workspace().num == 24
        assert focused_number() == 24 and uniform(2)
        assert window("group-a-original").workspace().num == 4
        assert window("group-b-original").workspace().num == 20
        assert rpc("transfer", value=1) is False
        rpc("select", group="A")
        assert focused_number() == 4
        rpc("focus", value=transferred.id)
        assert focused_number() == 24 and uniform(2)
        rpc("desktop")
        assert i3.get_tree().find_focused().workspace().name == "_desktop"
        rpc("select", group="B")
        assert uniform(1)
        rpc("select", group="C")
        assert rpc("switch", value=4, group="B", click=True) is False
        assert focused_number() == 24
        assert rpc("group-previous") and rpc("status")["selected"] == "B"
        assert rpc("group-previous") and focused_number() == 24
        rpc("kill-begin")
        rpc("select", group="A")
        assert rpc("kill", value=4) is False
        assert window("group-a-original")
        print(f"PASS {'dual' if dual else 'single'}: navigation, boundaries, transfer, views, stale clicks, kill guard", flush=True)

        session = subprocess.check_output(["/usr/bin/python3", str(helper), "path"], env=environment, text=True).strip()
        with socket.socket(socket.AF_UNIX) as subscriber:
            subscriber.settimeout(5)
            subscriber.connect(str(Path(session) / "controller.sock"))
            subscriber.sendall(b'{"action": "subscribe"}\n')
            stream = subscriber.makefile("rb")
            assert json.loads(stream.readline())["selected"] == "A"
            rpc("select", group="B")
            while (pushed := json.loads(stream.readline()))["selected"] != "B":
                pass
            assert all(set(window) == {"group"} for window in pushed["windows"])
        print(f"PASS {'dual' if dual else 'single'}: previous group and pushed bar status", flush=True)

        def settled(title):
            last, since, deadline = None, time.monotonic(), time.monotonic() + 8
            while time.monotonic() < deadline:
                con = window(title)
                now = con.workspace().num if con and con.workspace() else None
                if now != last:
                    last, since = now, time.monotonic()
                elif time.monotonic() - since > 0.8:
                    break
                time.sleep(0.05)
            return last

        rpc("switch", value=6)
        mover = open_window("mover")
        assert settled("mover") == 16
        rpc("select", group="C")
        rpc("switch", value=6)
        for index in range(1, 9):
            title = f"packed-{index}"
            open_window(title)
            if settled(title) != 26:
                i3.command(f'[title="^{title}$"] kill')
                wait(lambda: not window(title))
                break
        rpc("select", group="B")
        rpc("switch", value=6)
        i3.command(f"[con_id={mover.id}] focus")
        rpc("transfer", value=1)
        landed = settled("mover")
        assert landed != 26 and 21 <= landed <= 30, landed
        assert rpc("status")["selected"] == "C" and uniform(2)
        print(f"PASS {'dual' if dual else 'single'}: transfer into a packed slot overflows within the destination", flush=True)

        from workspace_groups import process_identity
        token = uuid.uuid4().hex
        rpc("restore-begin", group="B", token=token, owner=[os.getpid(), process_identity(os.getpid())])
        layout_path = directory / "restore-layout.json"
        launch_token = "i3-group-" + uuid.uuid4().hex
        mark = f"_group_{token}_2_0"
        layout_path.write_text(json.dumps(dict(name="12", num=12, layout="splith", nodes=[
            dict(type="con", marks=[mark], swallows=[dict(instance="^never-" + launch_token + "$")]) ])))
        rpc("restore-layout", token=token, workspace="12", path=str(layout_path))
        entry = dict(command=["xterm", "-name", launch_token, "-T", "restored", "-e", "sleep", "120"],
                     working_directory="/tmp", group_launch=dict(operation=token, token=launch_token,
                     group="B", slot=2, mark=mark))
        rpc("restore-launch", token=token, workspace="12", entry=entry)
        wait(lambda: window("restored") and window("restored").workspace().num == 12)
        wait(lambda: not any(node.ipc_data.get("swallows") and any(mark.startswith("_group_") for mark in node.marks) for node in i3.get_tree().descendants()))
        rpc("restore-end", token=token)
        assert window("group-a-original").workspace().num == 4
        assert window("transfer").workspace().num == 24
        print(f"PASS {'dual' if dual else 'single'}: owned restore placement and placeholder cleanup", flush=True)

        token = uuid.uuid4().hex
        rpc("restore-begin", group="B", token=token, owner=[os.getpid(), process_identity(os.getpid())])
        launch_token = "i3-group-" + uuid.uuid4().hex
        mark = f"_group_{token}_5_0"
        layout_path.write_text(json.dumps(dict(name="15", num=15, layout="splith", nodes=[
            dict(type="con", marks=[mark], swallows=[dict(instance="^never-" + launch_token + "$")]) ])))
        rpc("restore-layout", token=token, workspace="15", path=str(layout_path))
        entry = dict(command=["sh", "-c", 'sleep 1; exec xterm -T late -e sleep 120'],
                     working_directory="/tmp", group_launch=dict(operation=token, token=launch_token,
                     group="B", slot=5, mark=mark))
        rpc("restore-launch", token=token, workspace="15", entry=entry)
        rpc("select", group="C")
        wait(lambda: window("late") and window("late").workspace().num == 15)
        assert rpc("status")["selected"] == "C" and uniform(2)
        assert not any(node.ipc_data.get("swallows") and any(mark.startswith("_group_") for mark in node.marks) for node in i3.get_tree().descendants())
        print(f"PASS {'dual' if dual else 'single'}: cancellation, late arrivals, retained foreground", flush=True)

        rpc("select", group="A")
        rpc("kill-begin")
        rpc("kill-group")
        wait(lambda: not window("group-a-original"))
        assert window("group-b-original") and window("mover")
        print(f"PASS {'dual' if dual else 'single'}: Shift+K closes only the selected group", flush=True)

        assert rpc("kill-all-groups") is False
        rpc("kill-begin")
        rpc("kill-all-groups")
        wait(lambda: not rpc("status")["windows"])
        print(f"PASS {'dual' if dual else 'single'}: Shift+A closes every group", flush=True)
        rpc("stop")
    except Exception:
        if "i3" in locals():
            (directory / "failed-tree.json").write_text(json.dumps(i3.get_tree().ipc_data))
        print(f"Nested-session logs: {directory}", file=sys.stderr)
        for name in ("controller.log", "i3.log"):
            path = directory / name
            if path.exists():
                print(path.read_text()[-6000:], file=sys.stderr)
        raise
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    run(False)
    if "single" not in sys.argv:
        run(True)

#!/usr/bin/python3
"""Controller substitute for shell snapshot tests; real IPC is tested in Xephyr."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys

payload = json.load(sys.stdin)
action = payload["action"]
root = Path(os.environ["XDG_RUNTIME_DIR"])
state_path = root / "group-fixture.json"
state = json.loads(state_path.read_text()) if state_path.exists() else {}


def command(text):
    result = subprocess.run(["i3-msg", text], text=True, capture_output=True, check=True)
    if not all(reply.get("success") for reply in json.loads(result.stdout)):
        raise ValueError("could not select workspace")


def file_id(name):
    return re.sub(r'[/\\:*"<>|]', '', name)


try:
    if action == "status":
        print(json.dumps(dict(selected="A")))
        sys.exit(0)
    if action == "restore-begin":
        state = dict(token=payload["token"], paths={}, launched=[])
        subprocess.run(["i3-msg", "-t", "get_outputs"], check=True, stdout=subprocess.DEVNULL)
    elif action == "restore-layout":
        workspace = payload["workspace"]
        path = Path(payload["path"])
        directory = path.parent
        state["paths"][workspace] = str(directory)
        command("workspace --no-auto-back-and-forth " + json.dumps(workspace))
        outputs = json.loads(subprocess.check_output(["i3-msg", "-t", "get_outputs"], text=True))
        number = int(re.match(r"\d+", workspace)[0])
        if (number - 1) % 10 >= 2 and len(outputs) > 1:
            command("move workspace to output " + json.dumps(outputs[1]["name"]))
        append = directory / f"append_{file_id(workspace)}.json"
        if append.exists():
            command("append_layout " + json.dumps(str(append)))
        else:
            subprocess.run([os.environ["I3_RESURRECT"], "restore", "-w", workspace, "-d", str(directory),
                            "--layout-only"], check=True)
    elif action == "restore-launch":
        workspace = payload["workspace"]
        if workspace not in state["launched"]:
            subprocess.run([os.environ["I3_RESURRECT"], "restore", "-w", workspace, "-d", state["paths"][workspace],
                            "--programs-only"], check=True)
            state["launched"].append(workspace)
    elif action == "restore-focus":
        command("workspace --no-auto-back-and-forth " + json.dumps(payload["workspace"]))
    elif action == "restore-ready" and os.environ.get("WRONG_INSTANCE"):
        raise ValueError("A launched window is missing, ambiguous, or moved by the user")
    state_path.write_text(json.dumps(state))
    print("true")
except (OSError, ValueError, subprocess.CalledProcessError) as error:
    print(error, file=sys.stderr)
    sys.exit(1)

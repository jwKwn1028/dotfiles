#!/usr/bin/python3
"""Shared workspace identities and session controller client."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent
SLOTS = 10
SCRATCH_CLASS = "com.mitchellh.ghostty.scratchpad"


class GroupError(RuntimeError):
    pass


def definitions():
    path = Path(os.environ.get("I3_GROUP_CONFIG", ROOT / "workspace-groups.json"))
    groups = json.loads(path.read_text()) if path.exists() else {"A": 0, "B": 1, "C": 2}
    if (not isinstance(groups, dict) or not groups or
            any(not re.fullmatch(r"[A-Z][A-Z0-9_-]*", name) or type(index) is not int or
                index < 0 for name, index in groups.items()) or len(set(groups.values())) != len(groups)):
        raise GroupError("Groups require unique names and nonnegative, stable integer indices")
    return groups


def identity(number, groups=None):
    if type(number) is not int or number < 1:
        return None
    index, offset = divmod(number - 1, SLOTS)
    return next(((name, offset + 1) for name, value in (groups or definitions()).items()
                 if value == index), None)


def number(group, slot, groups=None):
    groups = groups or definitions()
    if group not in groups or type(slot) is not int or not 1 <= slot <= SLOTS:
        raise GroupError("Unknown group or slot outside 1–10")
    return groups[group] * SLOTS + slot


def numbers(group, groups=None):
    return [number(group, slot, groups) for slot in range(1, SLOTS + 1)]


def quote(value):
    return json.dumps(str(value), ensure_ascii=False)


def exact(value):
    return quote("^" + re.escape(str(value)) + "$")


def walk(node):
    yield node
    for key in ("nodes", "floating_nodes"):
        for child in node.get(key, []):
            yield from walk(child)


def source_path(name):
    path = ROOT / name
    return path if path.exists() else ROOT / ("executable_" + name)


def socket_path():
    value = os.environ.get("I3SOCK")
    if not value:
        value = subprocess.check_output(["i3", "--get-socketpath"], text=True).strip()
    if not value:
        raise GroupError("No i3 session socket")
    return value


def session_dir():
    key = hashlib.sha256((os.environ.get("DISPLAY", "") + "\0" + socket_path()).encode()).hexdigest()[:20]
    root = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/i3-user-{os.getuid()}"))
    return root / ("i3-groups-" + key)


def atomic_json(path, value):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".state-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def request(action, **values):
    address = str(session_dir() / "controller.sock")
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(15)
            client.connect(address)
            client.sendall(json.dumps(dict(action=action, **values)).encode() + b"\n")
            with client.makefile("rb") as stream:
                result = json.loads(stream.readline(8 * 1024 * 1024))
    except (OSError, ValueError) as error:
        raise GroupError(f"Workspace controller unavailable: {error}") from error
    if not result.get("ok"):
        raise GroupError(result.get("error", "Workspace action failed"))
    return result.get("result")


def subscribe():
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(5)
            client.connect(str(session_dir() / "controller.sock"))
            client.sendall(b'{"action": "subscribe"}\n')
            client.settimeout(None)
            with client.makefile("rb") as stream:
                for line in stream:
                    yield json.loads(line)
    except (OSError, ValueError) as error:
        raise GroupError(f"Workspace controller unavailable: {error}") from error


def process_identity(pid):
    try:
        text = Path(f"/proc/{int(pid)}/stat").read_text()
        fields = text[text.rfind(")") + 2:].split()
        if fields[0] == "Z":
            return None
        return fields[19]
    except (OSError, ValueError, IndexError):
        return None


def owner_alive(owner):
    return bool(owner and process_identity(owner[0]) == owner[1] and owner[1])


def filtered_tree(tree, group, groups=None):
    groups = groups or definitions()
    number(group, 1, groups)

    def filter_node(node):
        if node.get("type") == "workspace":
            current = identity(node.get("num"), groups)
            if not current or current[0] != group:
                return None
        if node.get("window_properties", {}).get("class") == SCRATCH_CLASS:
            return None
        result = dict(node)
        for key in ("nodes", "floating_nodes"):
            if key in node:
                result[key] = [value for child in node[key] if (value := filter_node(child)) is not None]
        if "focus" in result:
            children = {child["id"] for key in ("nodes", "floating_nodes") for child in result.get(key, [])}
            result["focus"] = [value for value in result["focus"] if value in children]
        return result

    return filter_node(tree)

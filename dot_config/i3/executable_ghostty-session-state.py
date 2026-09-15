#!/usr/bin/python3
"""Map i3's Ghostty windows to their shell directory and hpc/hpcz sessions."""

import json
import os
import re
import sys

PROC_ROOT = os.environ.get("I3_RESURRECT_PROC_ROOT", "/proc")
GHOSTTY_CLASS = "com.mitchellh.ghostty"
# The remote attach commands that hpc and hpcz pass to ssh.
SESSION_PATTERNS = (
    ("tmux", re.compile(r"\btmux attach-session -t =([A-Za-z0-9_-]+)")),
    ("zmx", re.compile(r"\bzmx attach ([A-Za-z0-9_-]+)")),
)


def proc_file(pid, name):
    return os.path.join(PROC_ROOT, str(pid), name)


def read_bytes(pid, name):
    try:
        with open(proc_file(pid, name), "rb") as stream:
            return stream.read()
    except OSError:
        return b""


def process_table():
    table = {}
    try:
        names = os.listdir(PROC_ROOT)
    except OSError:
        return table
    for name in names:
        if not name.isdigit():
            continue
        stat = read_bytes(name, "stat").decode("utf-8", "replace")
        start, end = stat.find("("), stat.rfind(")")
        fields = stat[end + 1 :].split()
        if start < 0 or end < start or len(fields) < 2 or not fields[1].isdigit():
            continue
        table[int(name)] = {
            "comm": stat[start + 1 : end],
            "ppid": int(fields[1]),
            "children": [],
        }
    for pid in sorted(table):
        parent = table.get(table[pid]["ppid"])
        if parent is not None:
            parent["children"].append(pid)
    return table


def window_id(pid):
    for entry in read_bytes(pid, "environ").split(b"\0"):
        if entry.startswith(b"WINDOWID="):
            return entry[len(b"WINDOWID=") :].decode("ascii", "replace")
    return None


def cwd(pid):
    try:
        return os.readlink(proc_file(pid, "cwd"))
    except OSError:
        return None


def shell_pid(table, pid):
    # Ghostty's `/bin/sh -c` wrapper never changes directory; its shell does.
    while table[pid]["comm"] == "sh" and len(table[pid]["children"]) == 1:
        pid = table[pid]["children"][0]
    return pid


def attached_session(table, root):
    pending, subtree = [root], []
    while pending:
        pid = pending.pop()
        subtree.append(pid)
        pending.extend(table[pid]["children"])
    for pid in sorted(subtree):
        if table[pid]["comm"] != "ssh":
            continue
        command = " ".join(
            arg.decode("utf-8", "replace")
            for arg in read_bytes(pid, "cmdline").split(b"\0")
        )
        for kind, pattern in SESSION_PATTERNS:
            match = pattern.search(command)
            if match:
                return {"kind": kind, "name": match.group(1)}
    return None


def surfaces_by_window(table):
    windows = {}
    for pid in sorted(table):
        if table[pid]["comm"] != "ghostty":
            continue
        for root in table[pid]["children"]:
            window = window_id(root)
            if window:
                windows.setdefault(window, []).append(root)
    return windows


def window_state(table, roots):
    directory, sessions = None, []
    for root in roots:
        session = attached_session(table, root)
        if session is None or session in sessions:
            continue
        if not sessions:
            directory = cwd(shell_pid(table, root))
        sessions.append(session)
    if directory is None and roots:
        directory = cwd(shell_pid(table, roots[0]))
    return directory, sessions


def ghostty_windows(node, workspace=None):
    # Same order as i3-resurrect's get_leaves: nodes, then floating nodes.
    if node.get("type") == "workspace":
        workspace = node.get("name")
    for child in (node.get("nodes") or []) + (node.get("floating_nodes") or []):
        props = child.get("window_properties") or {}
        if props.get("class") == GHOSTTY_CLASS and child.get("window") is not None:
            yield workspace, str(child["window"])
        yield from ghostty_windows(child, workspace)


def main():
    try:
        tree = json.load(sys.stdin)
    except Exception:
        print("[]")
        return

    table = process_table()
    surfaces = surfaces_by_window(table)
    states = []
    for workspace, window in ghostty_windows(tree):
        directory, sessions = window_state(table, surfaces.get(window, []))
        states.append(
            {
                "workspace": workspace,
                "window_id": window,
                "cwd": directory,
                "sessions": sessions,
            }
        )
    print(json.dumps(states))


if __name__ == "__main__":
    main()

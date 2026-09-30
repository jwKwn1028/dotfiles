#!/usr/bin/python3
"""Validate, publish, and inspect local i3 session snapshots. No desktop writes."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile


def read_json(path):
    with Path(path).open(encoding="utf-8") as stream:
        return json.load(stream)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def file_id(workspace):
    return re.sub(r'[/\\:*"<>|]', '', workspace)


def walk(node):
    yield node
    for key in ("nodes", "floating_nodes"):
        for child in node.get(key, []):
            yield from walk(child)


def workspace_node(tree, workspace):
    return next((node for node in walk(tree)
                 if node.get("type") == "workspace" and node.get("name") == workspace), None)


def validate_node(node):
    require(isinstance(node, dict), "layout node must be an object")
    for key in ("nodes", "floating_nodes"):
        require(isinstance(node.get(key, []), list), f"layout {key} must be an array")
        for child in node.get(key, []):
            validate_node(child)
    require(isinstance(node.get("swallows", []), list), "swallows must be an array")
    for rule in node.get("swallows", []):
        require(isinstance(rule, dict) and bool(rule), "empty or invalid swallow rule")
        for key, value in rule.items():
            require(isinstance(value, (str, int)), f"invalid swallow {key}")
            if key in ("class", "instance", "title", "window_role"):
                require(isinstance(value, str), f"swallow {key} must be a string")
            if key == "instance" and "ghostty-ws" in str(value):
                re.compile(value)


def validate(state, meta):
    workspaces = (meta / "workspaces.txt").read_text().splitlines()
    require(bool(workspaces), "no saved workspaces")
    ids = set()
    for workspace in workspaces:
        require(bool(workspace.strip()) and not any(ord(c) < 32 for c in workspace),
                "empty workspace name or control character")
        identifier = file_id(workspace)
        require(identifier and identifier not in ids, "duplicate workspace filename")
        ids.add(identifier)
        layout = read_json(state / f"workspace_{identifier}_layout.json")
        validate_node(layout)
        require(layout.get("name", workspace) == workspace, f"layout name differs: {workspace}")
        programs = read_json(state / f"workspace_{identifier}_programs.json")
        require(isinstance(programs, list), f"programs must be an array: {workspace}")
        for entry in programs:
            require(isinstance(entry, dict), "program entry must be an object")
            command = entry.get("command")
            require((isinstance(command, str) and bool(command.strip())) or
                    (isinstance(command, list) and bool(command) and
                     all(isinstance(arg, str) for arg in command) and bool(command[0])),
                    f"invalid command: {workspace}")
            require(isinstance(entry.get("working_directory"), str) and
                    bool(entry["working_directory"]), f"invalid working directory: {workspace}")

    focused = meta / "focused-workspace.txt"
    if focused.exists():
        name = focused.read_text().rstrip("\n")
        require(not name or name in workspaces, "focused workspace is absent from snapshot")
    route = meta / "labroute.txt"
    if route.exists():
        require(route.read_text().strip() in ("on", "off"), "invalid lab route state")
    for filename in ("zen-pages.json", "zathura-pages.json", "ghostty-sessions.json"):
        path = meta / filename
        if not path.exists():  # Older profiles may lack optional application metadata.
            continue
        entries = read_json(path)
        require(isinstance(entries, list), f"{filename} must be an array")
        seen = set()
        for entry in entries:
            require(isinstance(entry, dict) and isinstance(entry.get("workspace"), str),
                    f"invalid workspace in {filename}")
            require(isinstance(entry.get("window_id"), str), f"invalid window ID in {filename}")
            key = (entry["workspace"], entry["window_id"])
            require(key not in seen, f"duplicate window in {filename}")
            seen.add(key)
            if filename == "zen-pages.json":
                require(entry.get("browser", "zen") in ("zen", "helium") and
                        (entry.get("url") is None or isinstance(entry["url"], str)),
                        "invalid browser metadata")
            elif filename == "zathura-pages.json":
                require(isinstance(entry.get("filename"), str) and
                        type(entry.get("page")) is int and entry["page"] > 0,
                        "invalid PDF metadata")
            else:
                require(entry.get("cwd") is None or isinstance(entry["cwd"], str),
                        "invalid Ghostty directory")
                require(isinstance(entry.get("sessions"), list), "invalid Ghostty sessions")
                for session in entry["sessions"]:
                    require(isinstance(session, dict) and session.get("kind") in ("tmux", "zmx")
                            and isinstance(session.get("name"), str)
                            and re.fullmatch(r"[A-Za-z0-9_-]+", session["name"]),
                            "invalid remote session")
    return workspaces


def resolve(state, meta, previous=False):
    manifest = meta / "snapshot.json"
    if not manifest.exists():
        require(not previous, "no previous generation; this is a legacy profile")
        return state, meta
    data = read_json(manifest)
    require(isinstance(data, dict) and data.get("version") == 1, "invalid snapshot manifest")
    generation = data.get("previous" if previous else "current")
    require(isinstance(generation, str) and re.fullmatch(r"generation\.[A-Za-z0-9_-]+", generation),
            "snapshot generation is missing or invalid")
    directory = state / "snapshots" / generation
    require(directory.is_dir(), f"missing snapshot generation: {generation}")
    return directory / "state", directory / "meta"


def atomic_json(path, data):
    # The rename is the only publication point; readers never combine generations.
    fd, temporary = tempfile.mkstemp(prefix=".snapshot-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def archive_legacy(state, meta):
    if not (meta / "workspaces.txt").exists():
        return None
    try:
        workspaces = validate(state, meta)
    except (OSError, ValueError, TypeError, KeyError):
        # Leave an invalid legacy profile intact; do not advertise it as recoverable.
        return None
    directory = Path(tempfile.mkdtemp(prefix="generation.", dir=state / "snapshots"))
    (directory / "state").mkdir()
    (directory / "meta").mkdir()
    for workspace in workspaces:
        for kind in ("layout", "programs"):
            name = f"workspace_{file_id(workspace)}_{kind}.json"
            shutil.copyfile(state / name, directory / "state" / name)
    for name in ("workspaces.txt", "focused-workspace.txt", "labroute.txt", "zen-pages.json",
                 "zathura-pages.json", "ghostty-sessions.json", "tree.json"):
        if (meta / name).exists():
            shutil.copyfile(meta / name, directory / "meta" / name)
    return directory.name


def sync_generation(directory):
    for path in directory.rglob("*"):
        if path.is_file():
            with path.open("rb") as stream:
                os.fsync(stream.fileno())
    for path in (directory / "state", directory / "meta", directory, directory.parent, directory.parent.parent):
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def publish(state, meta, generation):
    require(re.fullmatch(r"generation\.[A-Za-z0-9_-]+", generation), "invalid generation name")
    directory = state / "snapshots" / generation
    validate(directory / "state", directory / "meta")
    # Flush the complete generation before committing its manifest.
    sync_generation(directory)
    previous = None
    if (meta / "snapshot.json").exists():
        resolve(state, meta)
        previous = read_json(meta / "snapshot.json")["current"]
    else:
        previous = archive_legacy(state, meta)
        if previous:
            sync_generation(state / "snapshots" / previous)
    atomic_json(meta / "snapshot.json", {"version": 1, "current": generation, "previous": previous})


def window_identity(tree, workspace):
    node = workspace_node(tree, workspace)
    require(node is not None, f"workspace disappeared during save: {workspace}")
    return [(entry["window"], entry.get("window_properties", {})) for entry in walk(node)
            if entry.get("window") is not None]


def browser_commands(state, meta, workspace):
    # Match metadata by window ID, then use the same leaves order as i3-resurrect.
    path = state / f"workspace_{file_id(workspace)}_programs.json"
    programs = read_json(path)
    node = workspace_node(read_json(meta / "tree.json"), workspace)
    require(node is not None, f"missing captured workspace: {workspace}")
    pages = {entry["window_id"]: entry for entry in read_json(meta / "zen-pages.json")
             if entry["workspace"] == workspace}
    for browser in ("zen", "helium"):
        windows = [entry for entry in walk(node) if entry.get("window") is not None and
                   entry.get("window_properties", {}).get("class", "").lower() == browser and
                   (entry.get("window_properties", {}).get("window_role") or "browser").lower() == "browser"]
        slots = []
        for entry in programs:
            command = entry["command"]
            if not isinstance(command, list):
                continue
            names = [Path(arg).name for arg in command]
            if browser == "zen":
                matches = ("app.zen_browser.zen" in command or
                           any(name in ("zen", "zen-browser") for name in names))
            else:
                matches = bool(names) and "helium" in names[0].lower()
            if matches:
                slots.append(entry)
        if len(windows) != len(slots):
            print(f"Browser pairing skipped on {workspace}: {browser} counts differ", file=sys.stderr)
            continue
        for window, entry in zip(windows, slots):
            page = pages.get(str(window["window"]))
            if not page or not page.get("url"):
                continue
            entry["command"] = [arg for arg in entry["command"] if arg != "--new-window" and
                                not re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", arg)] + ["--new-window", page["url"]]
    path.write_text(json.dumps(programs, indent=2) + "\n")


def readiness(state, workspace, tree):
    node = workspace_node(tree, workspace)
    if node is None:
        return "workspace is missing"
    layout = read_json(state / f"workspace_{file_id(workspace)}_layout.json")
    programs = read_json(state / f"workspace_{file_id(workspace)}_programs.json")
    expected = max(len(programs), sum(bool(entry.get("swallows")) for entry in walk(layout)))
    remaining = sum(bool(entry.get("swallows")) for entry in walk(node))
    windows = sum(entry.get("window") is not None and not entry.get("swallows") for entry in walk(node))
    if remaining:
        return f"{remaining} placeholder(s) remain"
    if windows < expected:
        return f"{windows}/{expected} expected windows are present"
    # Unique Ghostty instances provide a stronger identity check than counts.
    expected_instances = [rule["instance"] for entry in walk(layout) for rule in entry.get("swallows", [])
                          if "ghostty-ws" in rule.get("instance", "")]
    instances = [entry.get("window_properties", {}).get("instance", "") for entry in walk(node)
                 if entry.get("window") is not None]
    if any(not any(re.fullmatch(pattern, instance) for instance in instances) for pattern in expected_instances):
        return "expected Ghostty window instance is missing"
    return ""


def session_report(state, meta, completed):
    path = meta / "ghostty-sessions.json"
    if not path.exists():
        return
    attempted, manual = set(), set()
    workspaces = set((meta / "workspaces.txt").read_text().splitlines())
    for entry in read_json(path):
        workspace = entry["workspace"]
        if workspace not in workspaces:
            continue
        programs = read_json(state / f"workspace_{file_id(workspace)}_programs.json")
        for session in entry["sessions"]:
            kind, name = session["kind"], session["name"]
            command = ("hpc " if kind == "tmux" else "hpcz ") + name
            arg = f"--initial-command=env I3_RESURRECT_REMOTE_SESSION={kind}:{name} zsh"
            if workspace in completed and any(isinstance(p["command"], list) and arg in p["command"] for p in programs):
                attempted.add(command)
            else:
                manual.add(command)
    if attempted:
        print("Remote attach requested (unverified): " + ", ".join(sorted(attempted)))
    if manual - attempted:
        print("Reattach by hand: " + ", ".join(sorted(manual - attempted)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("validate", "resolve", "publish", "stable", "browsers", "ready", "sessions"))
    parser.add_argument("state", type=Path)
    parser.add_argument("meta", type=Path)
    parser.add_argument("value", nargs="?")
    parser.add_argument("--previous", action="store_true")
    args = parser.parse_args()
    try:
        if args.action == "resolve":
            print(json.dumps([str(path) for path in resolve(args.state, args.meta, args.previous)]))
        elif args.action == "validate":
            validate(args.state, args.meta)
        elif args.action == "publish":
            publish(args.state, args.meta, args.value)
        elif args.action == "stable":
            require(window_identity(read_json(args.meta / "tree.json"), args.value) ==
                    window_identity(json.load(sys.stdin), args.value),
                    f"windows changed during save: {args.value}; retry save")
        elif args.action == "browsers":
            browser_commands(args.state, args.meta, args.value)
        elif args.action == "ready":
            reason = readiness(args.state, args.value, json.load(sys.stdin))
            if reason:
                print(reason)
                return 1
        else:
            session_report(args.state, args.meta, set(json.loads(args.value)))
    except (OSError, ValueError, TypeError, KeyError, re.error) as error:
        print(f"Snapshot error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

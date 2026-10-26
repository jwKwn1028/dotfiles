#!/usr/bin/python3
"""Validate, publish, and inspect local i3 session snapshots. No desktop writes."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sys
import tempfile
import uuid

from workspace_groups import GroupError, SCRATCH_CLASS, filtered_tree, identity, numbers, validate_view


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
    if (meta / "session.json").exists():
        return validate_session(state, meta)["saved"]
    format_path = meta / "group-format.json"
    if format_path.exists():
        format_data = read_json(format_path)
        require(format_data.get("version") == 1 and format_data.get("slots") == 10,
                "unsupported group snapshot format")
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


def validate_session(state, meta):
    data = read_json(meta / "session.json")
    require(isinstance(data, dict) and data.get("version") == 1, "unsupported all-groups snapshot format")
    groups = data.get("groups")
    require(isinstance(groups, dict) and bool(groups) and
            all(isinstance(name, str) and re.fullmatch(r"[A-Z][A-Z0-9_-]*", name) and
                type(index) is int and index >= 0 for name, index in groups.items()) and
            len(set(groups.values())) == len(groups), "invalid saved group definitions")
    saved = data.get("saved")
    require(isinstance(saved, list) and bool(saved) and all(isinstance(group, str) and group in groups for group in saved) and
            len(saved) == len(set(saved)), "invalid saved group list")
    validate_view(data.get("view"), groups)
    for group in saved:
        child_state, child_meta = resolve(state / group, meta / group)
        require(not (child_meta / "session.json").exists(), "nested all-groups snapshots are invalid")
        workspaces = validate(child_state, child_meta)
        require(all(workspace_order(name)[0] in range(1, 11) for name in workspaces), "invalid logical slots")
        occupied_workspaces(child_state, child_meta)
    return data


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
    require(directory.is_dir(), f"missing snapshot generation: {generation}; delete {manifest} to start over")
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
                 "zathura-pages.json", "ghostty-sessions.json", "tree.json", "group-format.json"):
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
    for path in (state / "snapshots").glob("generation.*"):
        if path.name not in (generation, previous):
            shutil.rmtree(path, ignore_errors=True)


def window_identity(tree, workspace):
    node = workspace_node(tree, workspace)
    require(node is not None, f"workspace disappeared during save: {workspace}")
    return [(entry["window"], {key: value for key, value in entry.get("window_properties", {}).items()
                               if key != "title"})
            for entry in walk(node) if entry.get("window") is not None and
            entry.get("window_properties", {}).get("class") != SCRATCH_CLASS]


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


def expected_windows(state, workspace):
    layout = read_json(state / f"workspace_{file_id(workspace)}_layout.json")
    programs = read_json(state / f"workspace_{file_id(workspace)}_programs.json")
    return max(len(programs), sum(bool(entry.get("swallows")) for entry in walk(layout)))


def occupied_workspaces(state, meta):
    workspaces = (meta / "workspaces.txt").read_text().splitlines()
    occupied = [workspace for workspace in workspaces if expected_windows(state, workspace)]
    require(len(occupied) <= 10, "snapshot has more than 10 nonempty workspaces")
    return occupied


def quoted_program(entry):
    command = entry["command"]
    if isinstance(command, list):
        command = shlex.join(arg for arg in command if arg)
    directory = entry["working_directory"]
    if re.search(r'["\\$`\x00-\x1f\x7f]', directory):
        directory = str(Path.home())
    return dict(entry, command=command.replace("\\", "\\\\").replace('"', '\\"'),
                working_directory=directory)


def workspace_order(name):
    match = re.match(r"^(\d+)", name)
    return (int(match[1]) if match else float("inf"), name)


def prepare_restore(state, meta, tree, directory, group="A", operation=None, preserve_slots=False):
    """Plan group-scoped destinations and isolated launches."""
    require(isinstance(tree, dict) and tree.get("type") == "root", "invalid live i3 tree")
    saved = sorted(occupied_workspaces(state, meta), key=workspace_order)
    require(all(workspace_order(name)[0] in range(1, 11) for name in saved),
            "snapshot workspace identities must be logical slots 1–10")
    require(len({workspace_order(name)[0] for name in saved}) == len(saved), "duplicate saved logical slots")
    pool = numbers(group)
    names, occupied = {}, {}
    for node in walk(tree):
        if node.get("type") != "workspace":
            continue
        number = node.get("num", workspace_order(node["name"])[0])
        if number not in pool:
            continue  # Scratchpad and workspaces outside the numbered pool stay untouched.
        require(number not in names, f"multiple live workspaces use number {number}")
        names[number] = node["name"]
        windows = [child["window"] for child in walk(node) if child.get("window") is not None]
        if windows:
            occupied[number] = windows

    slots = [number for number in pool if number not in occupied] + sorted(occupied)
    if preserve_slots:
        slots = [pool[workspace_order(name)[0] - 1] for name in saved]
    plan = []
    for source, number in zip(saved, slots):
        destination = names.get(number, str(number))
        entry = dict(source_workspace=source, workspace=destination, merging=number in occupied)
        plan.append(entry)
        layout = read_json(state / f"workspace_{file_id(source)}_layout.json")
        for node in walk(layout):
            for rule in node.get("swallows", []):
                if len(rule) > 1:
                    rule.pop("title", None)
        # i3-resurrect selects the name embedded in the layout even when -w differs.
        layout["name"] = destination
        layout["num"] = number
        (directory / f"workspace_{file_id(destination)}_layout.json").write_text(json.dumps(layout) + "\n")
        programs = read_json(state / f"workspace_{file_id(source)}_programs.json")
        if operation:
            programs = launch_plan(layout, programs, operation, group, identity(number)[1])
            entry["layout"] = bool(layout["nodes"] or layout.get("floating_nodes"))
            (directory / f"workspace_{file_id(destination)}_layout.json").write_text(json.dumps(layout) + "\n")
        else:
            programs = [quoted_program(entry) for entry in programs]
        (directory / f"workspace_{file_id(destination)}_programs.json").write_text(json.dumps(programs) + "\n")
        if number in occupied:
            nodes = layout.get("nodes", []) + layout.get("floating_nodes", [])
            (directory / f"append_{file_id(destination)}.json").write_text(json.dumps([nodes]) + "\n")
            (directory / f"preserved_{file_id(destination)}.json").write_text(json.dumps(occupied[number]) + "\n")
    return plan


def readiness(state, workspace, tree):
    node = workspace_node(tree, workspace)
    if node is None:
        return "workspace is missing"
    layout = read_json(state / f"workspace_{file_id(workspace)}_layout.json")
    expected = expected_windows(state, workspace)
    path = state / f"preserved_{file_id(workspace)}.json"
    preserved = set(read_json(path)) if path.exists() else set()
    entries = [entry for entry in walk(node) if entry.get("window") not in preserved]
    remaining = sum(bool(entry.get("swallows")) for entry in entries)
    windows = sum(entry.get("window") is not None and not entry.get("swallows") for entry in entries)
    if remaining:
        return f"{remaining} placeholder(s) remain"
    if windows < expected:
        return f"{windows}/{expected} expected windows are present"
    # Unique Ghostty instances provide a stronger identity check than counts.
    expected_instances = [rule["instance"] for entry in walk(layout) for rule in entry.get("swallows", [])
                          if "ghostty-ws" in rule.get("instance", "")]
    instances = [entry.get("window_properties", {}).get("instance", "") for entry in entries
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


def capture_group(meta, tree, group):
    captured = filtered_tree(tree, group)
    workspaces = [node for node in walk(captured) if node.get("type") == "workspace" and
                  any(child.get("window") is not None for child in walk(node))]
    require(bool(workspaces), "selected group has no savable windows")
    nums = [node["num"] for node in workspaces]
    require(len(nums) == len(set(nums)), "duplicate numbered workspace identities")
    names = [node["name"] for node in sorted(workspaces, key=lambda node: node["num"])]
    focused = next((node["name"] for node in workspaces if
                    any(child.get("focused") for child in walk(node))), "")
    (meta / "tree.json").write_text(json.dumps(captured) + "\n")
    (meta / "workspaces.txt").write_text("\n".join(names) + "\n")
    (meta / "focused-workspace.txt").write_text(focused + "\n")


def clean_save(state, workspace):
    layout_path = state / f"workspace_{file_id(workspace)}_layout.json"
    layout = read_json(layout_path)
    removed = 0

    def clean(node):
        nonlocal removed
        if any(re.fullmatch(rule.get("class", "(?!)"), SCRATCH_CLASS)
               for rule in node.get("swallows", [])):
            removed += 1
            return None
        for key in ("nodes", "floating_nodes"):
            if key in node:
                node[key] = [value for child in node[key] if (value := clean(child)) is not None]
        if "marks" in node:
            node["marks"] = [mark for mark in node["marks"] if not mark.startswith("_group_")]
        return node

    clean(layout)
    path = state / f"workspace_{file_id(workspace)}_programs.json"
    programs = read_json(path)
    kept = [entry for entry in programs if not any(SCRATCH_CLASS in str(arg)
            for arg in (entry["command"] if isinstance(entry["command"], list) else [entry["command"]]))]
    require(not removed or len(programs) - len(kept) == removed,
            "cannot safely identify scratch-terminal launch entries")
    layout_path.write_text(json.dumps(layout) + "\n")
    path.write_text(json.dumps(kept) + "\n")


def normalize_group(state, meta, group):
    tree = read_json(meta / "tree.json")
    mapping = {node["name"]: str(identity(node["num"])[1]) for node in walk(tree)
               if node.get("type") == "workspace" and identity(node.get("num")) and
               identity(node["num"])[0] == group}
    names = (meta / "workspaces.txt").read_text().splitlines()
    payloads = []
    for source in names:
        target = mapping[source]
        layout = read_json(state / f"workspace_{file_id(source)}_layout.json")
        programs = read_json(state / f"workspace_{file_id(source)}_programs.json")
        tag = re.sub(r"[^A-Za-z0-9_-]", "_", source)
        old_prefix, new_prefix = f"ghostty-ws{tag}-", f"ghostty-ws{target}-"
        for node in walk(layout):
            for rule in node.get("swallows", []):
                if rule.get("instance", "").startswith("^" + old_prefix):
                    rule["instance"] = "^" + new_prefix + rule["instance"][len(old_prefix) + 1:]
        for entry in programs:
            if isinstance(entry["command"], list):
                entry["command"] = ["--x11-instance-name=" + new_prefix + arg[len("--x11-instance-name=" + old_prefix):]
                                    if arg.startswith("--x11-instance-name=" + old_prefix) else arg
                                    for arg in entry["command"]]
        layout.update(name=target, num=int(target))
        payloads.append((source, target, layout, programs))
    for source, _, _, _ in payloads:
        for kind in ("layout", "programs"):
            (state / f"workspace_{file_id(source)}_{kind}.json").unlink()
    for _, target, layout, programs in payloads:
        for kind, value in (("layout", layout), ("programs", programs)):
            (state / f"workspace_{target}_{kind}.json").write_text(json.dumps(value) + "\n")
    for filename in ("zen-pages.json", "zathura-pages.json", "ghostty-sessions.json"):
        path = meta / filename
        if path.exists():
            entries = [dict(entry, workspace=mapping[entry["workspace"]]) for entry in read_json(path)
                       if entry["workspace"] in names]
            path.write_text(json.dumps(entries) + "\n")
    for node in walk(tree):
        if node.get("type") == "workspace" and node["name"] in mapping:
            node["name"] = mapping[node["name"]]
            node["num"] = int(node["name"])
    (meta / "tree.json").write_text(json.dumps(tree) + "\n")
    focused = (meta / "focused-workspace.txt").read_text().strip()
    (meta / "focused-workspace.txt").write_text(mapping.get(focused, "") + "\n")
    (meta / "workspaces.txt").write_text("\n".join(mapping[name] for name in names) + "\n")
    (meta / "group-format.json").write_text(json.dumps(dict(version=1, slots=10, source_group=group)) + "\n")


def current_appimage(executable):
    path = Path(executable)
    if not path.is_absolute() or path.exists() or path.suffix != ".AppImage":
        return executable
    prefix = re.split(r"-\d", path.name, maxsplit=1)[0]
    candidates = sorted(path.parent.glob(prefix + "*.AppImage"), key=lambda candidate: candidate.stat().st_mtime)
    return str(candidates[-1]) if candidates else executable


def launch_plan(layout, programs, operation, group, slot):
    require(re.fullmatch(r"[a-f0-9]{32}", operation), "invalid restore operation identity")
    leaves = [node for node in walk(layout) if node.get("swallows")]
    if len(leaves) != len(programs):
        layout["nodes"], layout["floating_nodes"] = [], []
        leaves = [None] * len(programs)
    for index, (node, entry) in enumerate(zip(leaves, programs)):
        command = entry["command"]
        require(isinstance(command, list) and bool(command), "shell-string launches lack safe restore provenance")
        command = [current_appimage(command[0]), *command[1:]]
        require(Path(command[0]).name not in ("gtk-launch", "xdg-open", "dbus-send"),
                "desktop activation launch cannot establish new-window ownership")
        token = "i3-group-" + uuid.uuid4().hex
        executable = Path(command[0]).name
        if executable == "ghostty":
            command = [arg for arg in command if not arg.startswith("--x11-instance-name=")]
            command.append("--x11-instance-name=" + token)
        elif executable == "xterm":
            command = list(command)
            if "-name" in command:
                at = command.index("-name")
                del command[at:at + 2]
            command[1:1] = ["-name", token]
        mark = None
        if node is not None:
            mark = f"_group_{operation}_{slot}_{index}"
            node["swallows"] = [{"instance": "^never-" + token + "$"}]
            node["marks"] = [mark]
        entry["command"] = command
        entry["group_launch"] = dict(operation=operation, token=token, group=group, slot=slot, mark=mark)
    return programs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("validate", "resolve", "publish", "stable", "browsers", "ready",
                                           "occupied", "prepare-restore", "sessions", "capture-group", "clean-save", "normalize-group"))
    parser.add_argument("state", type=Path)
    parser.add_argument("meta", type=Path)
    parser.add_argument("value", nargs="?")
    parser.add_argument("--previous", action="store_true")
    parser.add_argument("--group", default="A")
    parser.add_argument("--operation")
    parser.add_argument("--preserve-slots", action="store_true")
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
        elif args.action == "occupied":
            print(json.dumps(occupied_workspaces(args.state, args.meta)))
        elif args.action == "prepare-restore":
            print(json.dumps(prepare_restore(args.state, args.meta, json.load(sys.stdin), Path(args.value),
                                             args.group, args.operation, args.preserve_slots)))
        elif args.action == "capture-group":
            capture_group(args.meta, json.load(sys.stdin), args.group)
        elif args.action == "clean-save":
            clean_save(args.state, args.value)
        elif args.action == "normalize-group":
            normalize_group(args.state, args.meta, args.group)
        elif args.action == "ready":
            reason = readiness(args.state, args.value, json.load(sys.stdin))
            if reason:
                print(reason)
                return 1
        else:
            session_report(args.state, args.meta, set(json.loads(args.value)))
    except (OSError, ValueError, TypeError, KeyError, GroupError, re.error) as error:
        print(f"Snapshot error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

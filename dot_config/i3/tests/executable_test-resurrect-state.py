#!/usr/bin/python3
"""Snapshot failure and recovery tests; every desktop command is a local mock."""

import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parent.parent


def source(name):
    path = ROOT / name
    return path if path.exists() else ROOT / ("executable_" + name)


SPEC = importlib.util.spec_from_file_location("snapshot", source("i3-resurrect-state.py"))
SNAPSHOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SNAPSHOT)


MOCK = r'''#!/usr/bin/python3
import json, os, pathlib, shlex, shutil, sys, time
root = pathlib.Path(os.environ["TEST_ROOT"])
tool, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with (root / "events").open("a") as stream:
    stream.write(json.dumps({"tool": tool, "args": args}) + "\n")
tree_path = root / "tree.json"
tree = json.loads(tree_path.read_text())
if tool == "i3-msg":
    if args == ["-t", "get_tree"]:
        print(json.dumps(tree))
    elif args == ["-t", "get_workspaces"]:
        print(json.dumps([dict(num=int(node["name"]), name=node["name"], focused=i == 0)
                          for i, node in enumerate(tree["nodes"])]))
    elif args == ["-t", "get_outputs"]:
        print('[{"name":"eDP","active":true}]')
    else:
        command = shlex.split(args[0])
        if "kill" in command and not os.environ.get("BLOCK_KILL"):
            tree["nodes"] = []
        if command[0] == "workspace":
            name = command[-1]
            if not any(node["name"] == name for node in tree["nodes"]):
                tree["nodes"].append(dict(type="workspace", name=name, nodes=[]))
        tree_path.write_text(json.dumps(tree))
        print(json.dumps([dict(success=not bool(os.environ.get("IPC_FAILURE")))]))
elif tool == "i3-resurrect":
    workspace = args[args.index("-w") + 1]
    directory = pathlib.Path(args[args.index("-d") + 1])
    if args[0] == "save":
        if os.environ.get("BLOCK_SAVE"):
            (root / "blocked").touch()
            deadline = time.monotonic() + 10
            while not (root / "release").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
        if os.environ.get("FAIL_SAVE") == workspace:
            sys.exit(7)
        for kind in ("layout", "programs"):
            name = f"workspace_{workspace}_{kind}.json"
            shutil.copyfile(root / "fixtures" / name, directory / name)
        if os.environ.get("CHANGE_TREE"):
            tree["nodes"][0]["nodes"][0]["window"] += 1
            tree_path.write_text(json.dumps(tree))
    elif "--layout-only" in args:
        if os.environ.get("FAIL_LAYOUT") == workspace:
            sys.exit(8)
        layout = json.loads((directory / f"workspace_{workspace}_layout.json").read_text())
        tree["nodes"] = [node for node in tree["nodes"] if node["name"] != workspace] + [layout]
        tree_path.write_text(json.dumps(tree))
    else:
        if os.environ.get("FAIL_PROGRAMS") == workspace:
            sys.exit(9)
        def fill(node):
            if node.get("swallows"):
                rule = node["swallows"][0]
                node.update(id=100, window=100, window_properties={
                    key: value.strip("^$").replace("\\", "") for key, value in rule.items()}, swallows=[])
                if os.environ.get("WRONG_INSTANCE"):
                    node["window_properties"]["instance"] = "wrong"
            for child in node.get("nodes", []) + node.get("floating_nodes", []):
                fill(child)
        for node in tree["nodes"]:
            if node["name"] == workspace and not os.environ.get("KEEP_PLACEHOLDERS"):
                fill(node)
                if os.environ.get("MISSING_WINDOW"):
                    node["nodes"] = []
        if os.environ.get("MISSING_WORKSPACE"):
            tree["nodes"] = [node for node in tree["nodes"] if node["name"] != workspace]
        if os.environ.get("CLOSE_LATER") == workspace:
            tree["nodes"] = [node for node in tree["nodes"] if node["name"] != "1"]
        tree_path.write_text(json.dumps(tree))
elif tool == "notify-send":
    with (root / "notifications").open("a") as stream:
        stream.write(args[-1] + "\n")
'''


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.state = self.root / "state"
        self.meta = self.root / "meta"
        self.applied = self.root / "i3"
        for path in (self.bin, self.state, self.meta, self.applied,
                     self.root / "runtime", self.root / "fixtures", self.root / "proc"):
            path.mkdir()
        for name in ("i3-resurrect-save-all.sh", "i3-resurrect-restore-all.sh",
                     "_resurrect-common.sh", "i3-resurrect-state.py", "_polybar-common.sh",
                     "_snap-common.sh", "ghostty-session-state.py"):
            (self.applied / name).write_text(source(name).read_text())
        (self.applied / "zen-url-state.py").write_text('print("[]")\n')
        for name in ("i3-msg", "i3-resurrect", "notify-send"):
            (self.bin / name).write_text(MOCK)
            (self.bin / name).chmod(0o755)
        (self.bin / "xdotool").write_text("#!/bin/sh\nexit 0\n")
        (self.bin / "xdotool").chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin", TEST_ROOT=str(self.root),
                        XDG_RUNTIME_DIR=str(self.root / "runtime"),
                        I3_RESURRECT=str(self.bin / "i3-resurrect"),
                        I3_SYSTEM_PYTHON="/usr/bin/python3",
                        I3_RESURRECT_PROC_ROOT=str(self.root / "proc"),
                        I3_RESURRECT_STATE_DIR=str(self.state), I3_RESURRECT_META_DIR=str(self.meta),
                        I3_RESURRECT_LAYOUT_DELAY="0", I3_RESURRECT_KILL_POLL_INTERVAL="0",
                        I3_RESURRECT_KILL_WAIT_ATTEMPTS="1", I3_RESURRECT_WAIT_ATTEMPTS="1",
                        I3_RESURRECT_POLL_INTERVAL="0", ZEN_LIVE_URL_CAPTURE="0",
                        TAILSCALE_REMOTE_MODE_FILE=str(self.root / "route-off"))
        self.live_tree(1)
        self.profile(1)

    def live_tree(self, count):
        self.write(self.root / "tree.json", dict(type="root", nodes=[
            dict(type="workspace", name=str(n), nodes=[dict(id=100+n, window=100+n,
                 window_properties={"class": "Example"})]) for n in range(1, count+1)]))

    def profile(self, count):
        (self.meta / "workspaces.txt").write_text("".join(f"{n}\n" for n in range(1, count+1)))
        for n in range(1, count+1):
            layout = dict(type="workspace", name=str(n), nodes=[{"swallows": [{"class": "^Example$"}]}])
            programs = [dict(command=["example"], working_directory="/tmp")]
            for directory in (self.state, self.root / "fixtures"):
                self.write(directory / f"workspace_{n}_layout.json", layout)
                self.write(directory / f"workspace_{n}_programs.json", programs)

    @staticmethod
    def write(path, data):
        path.write_text(json.dumps(data))

    def run_script(self, action="restore", *args, **overrides):
        return subprocess.run(["bash", str(self.applied / f"i3-resurrect-{action}-all.sh"), *args],
                              env=dict(self.env, **overrides), text=True, capture_output=True, timeout=15)

    def events(self):
        path = self.root / "events"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def killed(self):
        return any("kill" in " ".join(event["args"]) for event in self.events())

    def test_check_validates_without_desktop_calls_or_writes(self):
        before = set(self.root.rglob("*"))
        result = self.run_script("restore", "--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), [])
        self.assertEqual(before, set(self.root.rglob("*")))

    def test_bad_snapshots_never_close_windows(self):
        cases = [("state", "workspace_1_programs.json", "{broken"),
                 ("state", "workspace_1_layout.json", "[]"),
                 ("state", "workspace_1_programs.json", '[{"command":null}]'),
                 ("meta", "labroute.txt", "maybe"),
                 ("meta", "ghostty-sessions.json", '[{"workspace":"1"}]')]
        for directory, name, contents in cases:
            with self.subTest(name=name, contents=contents):
                path = self.root / directory / name
                original = path.read_text() if path.exists() else None
                path.write_text(contents)
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.killed(), result.stderr)
                if original is None:
                    path.unlink()
                else:
                    path.write_text(original)
        (self.state / "workspace_1_layout.json").unlink()
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.killed())

    def test_failed_save_keeps_last_complete_generation(self):
        self.assertEqual(self.run_script("save").returncode, 0)
        manifest = (self.meta / "snapshot.json").read_bytes()
        state, meta = SNAPSHOT.resolve(self.state, self.meta)
        original = (state / "workspace_1_programs.json").read_bytes()
        self.live_tree(2)
        self.profile(2)
        result = self.run_script("save", FAIL_SAVE="2")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.meta / "snapshot.json").read_bytes(), manifest)
        self.assertEqual((state / "workspace_1_programs.json").read_bytes(), original)
        self.assertEqual((meta / "workspaces.txt").read_text(), "1\n")
        self.assertEqual(self.run_script("restore", "--check").returncode, 0)

    def test_previous_generation_is_selectable(self):
        self.assertEqual(self.run_script("save").returncode, 0)
        first = SNAPSHOT.resolve(self.state, self.meta)
        self.live_tree(2)
        self.profile(2)
        self.assertEqual(self.run_script("save").returncode, 0)
        self.assertEqual(SNAPSHOT.resolve(self.state, self.meta, True), first)
        result = self.run_script("restore", "--previous")
        self.assertEqual(result.returncode, 0, result.stderr)
        restored = [event["args"][2] for event in self.events()
                    if event["tool"] == "i3-resurrect" and event["args"][0] == "restore"]
        self.assertEqual(restored, ["1", "1"])

    def test_first_save_archives_valid_legacy_snapshot(self):
        self.assertEqual(self.run_script("save").returncode, 0)
        state, meta = SNAPSHOT.resolve(self.state, self.meta, True)
        self.assertEqual(SNAPSHOT.validate(state, meta), ["1"])
        self.assertEqual((state / "workspace_1_programs.json").read_bytes(),
                         (self.state / "workspace_1_programs.json").read_bytes())

    def test_browser_metadata_is_joined_by_window_id_and_preserves_unknown_slots(self):
        for browser, command in (("zen", ["flatpak", "run", "app.zen_browser.zen"]),
                                 ("helium", ["helium"])):
            with self.subTest(browser=browser):
                self.write(self.meta / "tree.json", dict(type="workspace", name="1", nodes=[
                    dict(window=n, window_properties={"class": browser}) for n in (1, 2, 3)]))
                # Reversed order and a completely missing metadata entry are both safe.
                self.write(self.meta / "zen-pages.json", [
                    dict(workspace="1", window_id="3", browser=browser, url="https://three.test"),
                    dict(workspace="1", window_id="2", browser=browser, url="https://two.test")])
                programs = [dict(command=command.copy(), working_directory="/tmp") for _ in range(3)]
                path = self.state / "workspace_1_programs.json"
                self.write(path, programs)
                SNAPSHOT.browser_commands(self.state, self.meta, "1")
                result = SNAPSHOT.read_json(path)
                self.assertEqual(result[0]["command"], command)
                self.assertEqual(result[1]["command"][-1], "https://two.test")
                self.assertEqual(result[2]["command"][-1], "https://three.test")

    def test_browser_count_mismatch_leaves_commands_unchanged(self):
        self.write(self.meta / "tree.json", dict(type="workspace", name="1", nodes=[
            dict(window=n, window_properties={"class": "zen"}) for n in (1, 2)]))
        self.write(self.meta / "zen-pages.json", [dict(workspace="1", window_id="2", browser="zen",
                                                     url="https://two.test")])
        path = self.state / "workspace_1_programs.json"
        programs = [dict(command=["zen"], working_directory="/tmp")]
        self.write(path, programs)
        SNAPSHOT.browser_commands(self.state, self.meta, "1")
        self.assertEqual(SNAPSHOT.read_json(path), programs)

    def test_tree_changes_abort_save(self):
        result = self.run_script("save", CHANGE_TREE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("windows changed", result.stderr)
        self.assertFalse((self.meta / "snapshot.json").exists())

    def blocked_save(self):
        process = subprocess.Popen(["bash", str(self.applied / "i3-resurrect-save-all.sh")],
                                   env=dict(self.env, BLOCK_SAVE="1"), start_new_session=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def cleanup():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=5)
        self.addCleanup(cleanup)
        deadline = time.monotonic() + 5
        while not (self.root / "blocked").exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue((self.root / "blocked").exists())
        return process

    def test_overlapping_profiles_share_one_lock(self):
        process = self.blocked_save()
        for action in ("save", "restore"):
            result = self.run_script(action, I3_RESURRECT_STATE_DIR=str(self.root / "other-state"),
                                     I3_RESURRECT_META_DIR=str(self.root / "other-meta"))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("already running", result.stderr)
        self.assertFalse(self.killed())
        (self.root / "release").touch()
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, stdout + stderr)

    def test_interrupted_save_preserves_legacy_profile(self):
        before = (self.meta / "workspaces.txt").read_bytes()
        process = self.blocked_save()
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate(timeout=5)
        self.assertFalse((self.meta / "snapshot.json").exists())
        self.assertEqual((self.meta / "workspaces.txt").read_bytes(), before)
        self.assertEqual(list((self.state / "snapshots").iterdir()), [])
        self.assertEqual(self.run_script("restore", "--check").returncode, 0)

    def route(self, body):
        (self.meta / "labroute.txt").write_text("on\n")
        helper = self.root / "remote.zsh"
        helper.write_text('labroute() {\n' +
                          'print -r -- \'{"tool":"route","args":[]}\' >> "$TEST_ROOT/events"\n' + body + '\n}\n')
        self.env["I3_RESURRECT_REMOTE_HELPERS"] = str(helper)

    def test_route_failure_and_timeout_preserve_desktop(self):
        for body in ("return 1", "sleep 2"):
            with self.subTest(body=body):
                self.route(body)
                result = self.run_script(I3_RESURRECT_LABROUTE_TIMEOUT="0.05")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.killed())
                self.assertFalse(any(event["tool"] == "i3-resurrect" for event in self.events()))

    def test_route_is_ready_before_first_close(self):
        self.route("return 0")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        route = next(i for i, event in enumerate(events) if event["tool"] == "route")
        close = next(i for i, event in enumerate(events) if "kill" in " ".join(event["args"]))
        self.assertLess(route, close)

    def test_missing_windows_and_failed_commands_cannot_report_success(self):
        cases = [("MISSING_WORKSPACE", "workspace is missing"),
                 ("MISSING_WINDOW", "0/1 expected windows"),
                 ("KEEP_PLACEHOLDERS", "placeholder(s) remain"),
                 ("FAIL_LAYOUT", "layout restore failed"),
                 ("FAIL_PROGRAMS", "program launch failed"),
                 ("IPC_FAILURE", "could not select workspace")]
        for variable, reason in cases:
            with self.subTest(variable=variable):
                self.live_tree(1)
                result = self.run_script(**{variable: "1"})
                self.assertNotEqual(result.returncode, 0)
                report = SNAPSHOT.read_json(self.meta / "last-restore.json")
                self.assertEqual(report["workspaces"][0]["status"], "failed")
                self.assertIn(reason, report["workspaces"][0]["detail"])

    def test_final_check_catches_windows_lost_during_later_workspaces(self):
        self.live_tree(2)
        self.profile(2)
        result = self.run_script(CLOSE_LATER="2")
        self.assertNotEqual(result.returncode, 0)
        report = SNAPSHOT.read_json(self.meta / "last-restore.json")
        self.assertEqual([item["status"] for item in report["workspaces"]], ["failed", "ready"])

    def test_attach_requests_remain_explicitly_unverified(self):
        self.write(self.meta / "ghostty-sessions.json", [dict(workspace="1", window_id="101", cwd="/tmp",
                   sessions=[dict(kind="tmux", name="dev"), dict(kind="zmx", name="shell")])])
        self.write(self.state / "workspace_1_programs.json", [dict(working_directory="/tmp", command=[
            "ghostty", "--initial-command=env I3_RESURRECT_REMOTE_SESSION=tmux:dev zsh"])])
        self.assertEqual(self.run_script().returncode, 0)
        report = SNAPSHOT.read_json(self.meta / "last-restore.json")
        self.assertIn("Remote attach requested (unverified): hpc dev", report["sessions"])
        self.assertIn("Reattach by hand: hpcz shell", report["sessions"])
        self.live_tree(1)
        self.assertNotEqual(self.run_script(FAIL_PROGRAMS="1").returncode, 0)
        report = SNAPSHOT.read_json(self.meta / "last-restore.json")
        self.assertIn("Reattach by hand: hpc dev, hpcz shell", report["sessions"])
        self.assertNotIn("requested", report["sessions"])

    def test_wrong_ghostty_instance_is_not_ready(self):
        self.write(self.state / "workspace_1_layout.json", dict(type="workspace", name="1", nodes=[
            {"swallows": [{"class": "^com\\.mitchellh\\.ghostty$", "instance": "^ghostty-ws1-1$"}]}]))
        result = self.run_script(WRONG_INSTANCE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Ghostty window instance is missing", (self.meta / "last-restore.json").read_text())

    def test_programs_without_placeholders_still_require_windows(self):
        self.write(self.state / "workspace_1_layout.json", dict(type="workspace", name="1", nodes=[]))
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("0/1 expected windows", (self.meta / "last-restore.json").read_text())

    def test_workspace_list_without_final_newline_is_restored(self):
        (self.meta / "workspaces.txt").write_text("1")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        restored = [event for event in self.events() if event["tool"] == "i3-resurrect"]
        self.assertEqual(len(restored), 2)


if __name__ == "__main__":
    unittest.main()

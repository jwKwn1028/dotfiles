#!/usr/bin/python3
"""Group identities, snapshot portability, and relocation guards."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest import mock
import uuid

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from workspace_groups import GroupError, filtered_tree, identity, number  # noqa: E402
from group_controller import Controller  # noqa: E402

path = ROOT / "i3-resurrect-state.py"
if not path.exists():
    path = ROOT / "executable_i3-resurrect-state.py"
spec = importlib.util.spec_from_file_location("group_snapshot", path)
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)

path = ROOT / "workspace-groups.py"
if not path.exists():
    path = ROOT / "executable_workspace-groups.py"
spec = importlib.util.spec_from_file_location("group_entry", path)
entry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(entry)


def workspace(num, windows=()):
    return dict(type="workspace", id=num, num=num, name=str(num), nodes=[
        dict(id=value, window=value, window_properties={"class": "Example"}) for value in windows])


class GroupTests(unittest.TestCase):
    def test_roundtrip_and_stable_indices(self):
        groups = {"C": 2, "A": 0}
        for group in groups:
            for slot in range(1, 11):
                self.assertEqual(identity(number(group, slot, groups), groups), (group, slot))
        self.assertIsNone(identity(11, groups))
        for value in (-1, 0, 31, None):
            self.assertIsNone(identity(value))
        for slot in (0, 11):
            with self.assertRaises(GroupError):
                number("B", slot)

    def test_snapshot_capture_filters_other_groups_and_shown_scratch(self):
        a, b, c = workspace(1, [101]), workspace(13, [113]), workspace(21, [121])
        b["nodes"].append(dict(id=999, window=999,
                               window_properties={"class": "com.mitchellh.ghostty.scratchpad"}))
        tree = dict(type="root", nodes=[a, b, c])
        before = copy.deepcopy(tree)
        captured = filtered_tree(tree, "B")
        self.assertEqual([node["num"] for node in captured["nodes"]], [13])
        self.assertEqual([node["window"] for node in captured["nodes"][0]["nodes"]], [113])
        self.assertEqual(tree, before)

    def test_ordinary_relocation_cannot_request_another_group(self):
        con = SimpleNamespace(window=123, workspace=lambda: SimpleNamespace(name="14", num=14))
        controller = object.__new__(Controller)
        controller.groups = {"A": 0, "B": 1, "C": 2}
        controller.tree = lambda: SimpleNamespace(find_by_id=lambda _: con)
        controller.command = lambda _: self.fail("No IPC move may be issued")
        with self.assertRaisesRegex(GroupError, "cannot cross"):
            controller.move(99, "14", "C", 4)
        with self.assertRaisesRegex(GroupError, "source changed"):
            controller.move(99, "4", "A", 5)

    def test_duplicate_numeric_identities_reject_actions(self):
        controller = object.__new__(Controller)
        controller.groups = {"A": 0, "B": 1}
        controller.i3 = SimpleNamespace(get_tree=lambda: SimpleNamespace(workspaces=lambda: [
            SimpleNamespace(num=11), SimpleNamespace(num=11)]))
        with self.assertRaisesRegex(GroupError, "Multiple workspaces"):
            controller.tree()


class EntryTests(unittest.TestCase):
    def test_legacy_workers_match_but_controller_processes_do_not(self):
        for command in ("bash /cfg/i3/focus-tracker.sh", "bash /cfg/i3/snap-watcher.sh",
                        "/venvs/autotiling/bin/python /opt/bin/autotiling",
                        "/usr/bin/python3 /cfg/i3/overflow-watcher.py -d"):
            self.assertTrue(entry.LEGACY.search(command), command)
        for command in ("/usr/bin/python3 /cfg/i3/workspace-groups.py serve",
                        "bash /cfg/i3/kakaotalk-float-watcher.sh", "vim /cfg/i3/snap-watcher.sh"):
            self.assertFalse(entry.LEGACY.search(command), command)

    def test_bar_shows_selected_group_slots_and_inactive_urgency(self):
        groups = {"A": 0, "B": 1, "C": 2}
        workspaces = [dict(num=num, name=name, focused=num == 13, visible=num in (11, 13),
                           urgent=num == 25, output="eDP")
                      for num, name in ((1, "1"), (11, "11"), (13, "13: project"), (25, "25"))]
        windows = [dict(id=num, name="", group=list(identity(num, groups))) for num in (13, 25)]
        text = entry.bar_text(dict(ready=True, selected="B", groups=groups, workspaces=workspaces,
                                   windows=windows))
        self.assertIn(" C! ", text)
        self.assertNotIn("select A:", text)
        self.assertIn("select B:", text)
        self.assertIn("switch 3 --group B --click:", text)
        self.assertIn("select C:", text)
        self.assertNotIn("switch 5", text)
        self.assertNotIn(" 13 ", text)
        self.assertIn("cycle 1 --group B:", text)
        boundary = text.index("%{A4:", 1)
        tabs, slots = text[:boundary], text[boundary:]
        self.assertIn("group-relative 1 --quiet:", tabs)
        self.assertNotIn("cycle", tabs)
        self.assertNotIn("group-relative", slots)
        self.assertIn("unavailable", entry.bar_text(dict(ready=False)))


class SnapshotGroupsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.state, self.meta = self.root / "state", self.root / "meta"
        self.state.mkdir()
        self.meta.mkdir()

    def make_snapshot(self, group):
        num = number(group, 4)
        name = f"{num}: project"
        tree = dict(type="root", nodes=[dict(workspace(num, [101]), name=name)])
        snapshot.capture_group(self.meta, tree, group)
        layout = dict(name=name, nodes=[dict(swallows=[dict(instance=f"^ghostty-ws{num}__project-1$")])])
        program = dict(command=["ghostty", f"--x11-instance-name=ghostty-ws{num}__project-1",
                                "--initial-command=echo 14 /tmp/24 https://example.test/34"], working_directory="/tmp")
        for kind, value in (("layout", layout), ("programs", [program])):
            (self.state / f"workspace_{snapshot.file_id(name)}_{kind}.json").write_text(json.dumps(value))
        (self.meta / "ghostty-sessions.json").write_text(json.dumps([
            dict(workspace=name, window_id="101", cwd="/tmp", sessions=[])]))
        snapshot.normalize_group(self.state, self.meta, group)

    def test_all_source_destination_pairs_and_unique_launches(self):
        for source in ("A", "B", "C"):
            self.make_snapshot(source)
            self.assertEqual((self.meta / "workspaces.txt").read_text(), "4\n")
            for destination in ("A", "B", "C"):
                with self.subTest(source=source, destination=destination):
                    directory = self.root / (source + destination)
                    directory.mkdir()
                    occupied = number(destination, 1)
                    tree = dict(type="root", nodes=[workspace(occupied, [999])])
                    before = copy.deepcopy(tree)
                    operation = uuid.uuid4().hex
                    plan = snapshot.prepare_restore(self.state, self.meta, tree, directory,
                                                    destination, operation)
                    target = number(destination, 2)
                    self.assertEqual(plan[0]["workspace"], str(target))
                    programs = snapshot.read_json(directory / f"workspace_{target}_programs.json")
                    launch = programs[0]["group_launch"]
                    self.assertEqual((launch["group"], launch["slot"]), (destination, 2))
                    self.assertIn("--initial-command=echo 14 /tmp/24 https://example.test/34", programs[0]["command"])
                    layout = snapshot.read_json(directory / f"workspace_{target}_layout.json")
                    self.assertEqual(layout["nodes"][0]["swallows"], [{"instance": "^never-" + launch["token"] + "$"}])
                    self.assertEqual(tree, before)

    def test_full_destination_shares_only_its_own_slots(self):
        self.make_snapshot("A")
        tree = dict(type="root", nodes=[workspace(num, [1000 + num]) for num in range(11, 21)])
        directory = self.root / "restore"
        directory.mkdir()
        plan = snapshot.prepare_restore(self.state, self.meta, tree, directory, "B", uuid.uuid4().hex)
        self.assertEqual(plan, [dict(source_workspace="4", workspace="11", merging=True, layout=True)])
        self.assertEqual(snapshot.read_json(directory / "preserved_11.json"), [1011])

    def test_unsupported_launch_rejected_before_desktop_work(self):
        self.make_snapshot("B")
        path = self.state / "workspace_4_programs.json"
        path.write_text(json.dumps([dict(command=["xdg-open", "https://example.test"], working_directory="/tmp")]))
        directory = self.root / "restore"
        directory.mkdir()
        with self.assertRaisesRegex(ValueError, "ownership"):
            snapshot.prepare_restore(self.state, self.meta, dict(type="root", nodes=[]), directory,
                                     "C", uuid.uuid4().hex)

    def test_unpaired_placeholders_open_without_layout(self):
        self.make_snapshot("C")
        path = self.state / "workspace_4_programs.json"
        programs = json.loads(path.read_text())
        path.write_text(json.dumps(programs * 2))
        directory = self.root / "restore"
        directory.mkdir()
        plan = snapshot.prepare_restore(self.state, self.meta, dict(type="root", nodes=[]), directory,
                                        "A", uuid.uuid4().hex)
        self.assertFalse(plan[0]["layout"])
        layout = snapshot.read_json(directory / "workspace_1_layout.json")
        self.assertEqual((layout["nodes"], layout["floating_nodes"]), ([], []))
        launches = [entry["group_launch"] for entry in snapshot.read_json(directory / "workspace_1_programs.json")]
        self.assertEqual([launch["mark"] for launch in launches], [None, None])
        self.assertEqual(len({launch["token"] for launch in launches}), 2)

    def test_missing_appimage_resolves_to_newest_version(self):
        self.make_snapshot("A")
        apps = self.root / "apps"
        apps.mkdir()
        current = apps / "helium-0.19.4.1-x86_64.AppImage"
        current.write_text("")
        path = self.state / "workspace_4_programs.json"
        path.write_text(json.dumps([dict(command=[str(apps / "helium-0.14.5.1-x86_64.AppImage"), "--new-window",
                                                  "https://example.test"], working_directory="/tmp")]))
        directory = self.root / "restore"
        directory.mkdir()
        snapshot.prepare_restore(self.state, self.meta, dict(type="root", nodes=[]), directory, "B", uuid.uuid4().hex)
        command = snapshot.read_json(directory / "workspace_11_programs.json")[0]["command"]
        self.assertEqual(command, [str(current), "--new-window", "https://example.test"])

    def test_empty_group_does_not_publish(self):
        with self.assertRaisesRegex(ValueError, "no savable"):
            snapshot.capture_group(self.meta, dict(type="root", nodes=[workspace(1, [1])]), "B")
        self.assertFalse((self.meta / "workspaces.txt").exists())


class ShellClientTests(unittest.TestCase):
    def setUp(self):
        import workspace_groups
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        runtime = Path(self.temporary.name)
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), DISPLAY=":7",
                        I3SOCK=str(runtime / "i3" / "ipc-socket.42"))
        self.env.pop("I3_GROUP_HELPER", None)
        with mock.patch.dict(os.environ, self.env, clear=True):
            self.directory = workspace_groups.session_dir()
        self.directory.mkdir(parents=True)
        self.client = ROOT / "workspace-action.sh"
        if not self.client.exists():
            self.client = ROOT / "executable_workspace-action.sh"

    def exchange(self, args, *replies):
        received = []
        with socket.socket(socket.AF_UNIX) as server:
            server.bind(str(self.directory / "controller.sock"))
            server.listen(1)
            server.settimeout(5)

            def serve():
                for reply in replies:
                    client, _ = server.accept()
                    with client, client.makefile("rb") as stream:
                        received.append(json.loads(stream.readline()))
                        client.sendall(reply.encode() + b"\n")

            thread = threading.Thread(target=serve)
            thread.start()
            result = subprocess.run(["/bin/sh", str(self.client), *args], env=self.env,
                                    capture_output=True, text=True, timeout=10)
            thread.join(5)
        (self.directory / "controller.sock").unlink()
        self.stdout = result.stdout
        self.received = received
        return result.returncode, received[0] if received else None

    def run_client(self, *args):
        return subprocess.run(["/bin/sh", str(self.client), *args], env=self.env,
                              capture_output=True, text=True, timeout=10).returncode

    def test_requests_match_the_python_client(self):
        code, request = self.exchange(["switch", "3", "--group", "B", "--click"],
                                      '{"ok": true, "result": false}')
        self.assertEqual(code, 0)
        self.assertEqual(request, dict(action="switch", quiet=False, value="3", group="B", click=True))
        code, request = self.exchange(["group-relative", "-1", "--quiet"], '{"ok": true, "result": true}')
        self.assertEqual((code, request), (0, dict(action="group-relative", quiet=True, value="-1")))
        code, request = self.exchange(["select", "A"], '{"ok": true, "result": true}')
        self.assertEqual(request, dict(action="select", quiet=False, group="A"))

    def test_placement_and_errors_set_the_exit_status(self):
        self.assertEqual(self.exchange(["placement", "42"], '{"ok": true, "result": true}')[0], 0)
        self.assertEqual(self.exchange(["placement", "42"], '{"ok": true, "result": false}')[0], 1)
        self.assertEqual(self.exchange(["kill-begin"], '{"ok": false, "error": "no"}')[0], 1)
        self.assertEqual(self.run_client("kill-begin"), 1)

    def test_what_the_shell_cannot_express_goes_to_the_python_cli(self):
        code, request = self.exchange(["--quiet", "status"], '{"ok": true, "result": {"ready": true}}')
        self.assertEqual((code, request, self.stdout.strip()),
                         (0, dict(action="status", quiet=True), '{"ready": true}'))
        self.assertEqual(self.run_client("switch", "3", "--group", "--click"), 2)
        self.assertEqual(self.run_client("switch", "-1x"), 2)

    def test_window_menu_pipes_the_controller_menu_to_rofi(self):
        bin_dir = Path(self.temporary.name) / "bin"
        bin_dir.mkdir()
        rofi = bin_dir / "rofi"
        rofi.write_text('#!/bin/sh\ncat > "$ROFI_INPUT"\nprintf "%s\\n" "$ROFI_CHOICE"\n[ -n "$ROFI_CHOICE" ]\n')
        rofi.chmod(0o755)
        self.env.update(PATH=f"{bin_dir}:{self.env['PATH']}", ROFI_INPUT=str(bin_dir / "input"),
                        ROFI_CHOICE="1")
        menu = dict(menu="A:1  one\0icon\x1fa\nB:2  two\0icon\x1fb", ids=[11, 22])
        reply = json.dumps(dict(ok=True, result=menu))
        code, _ = self.exchange(["window-menu"], reply, '{"ok": true, "result": true}')
        self.assertEqual(code, 0)
        self.assertEqual(self.received, [dict(action="window-menu", quiet=False),
                                         dict(action="focus", quiet=False, value="22")])
        self.assertEqual((bin_dir / "input").read_bytes(), menu["menu"].encode())
        self.env["ROFI_CHOICE"] = ""
        self.assertEqual(self.exchange(["window-menu"], reply)[0], 0)
        self.assertEqual(len(self.received), 1)


class WindowMenuTests(unittest.TestCase):
    def test_menu_lines_use_cached_desktop_icons(self):
        with tempfile.TemporaryDirectory() as directory:
            apps = Path(directory, "data", "applications")
            apps.mkdir(parents=True)
            (apps / "org.example.Viewer.desktop").write_text(
                "[Desktop Entry]\nIcon=viewer\nStartupWMClass=Viewer\n")
            controller = Controller(SimpleNamespace(), directory)
            controller.status = lambda: dict(windows=[
                {"id": 11, "name": "one\ntwo", "class": "Viewer", "instance": "viewer", "group": ["A", 1]},
                {"id": 22, "name": "term", "class": "Term", "instance": "term", "group": ["B", 2]}])
            data = dict(XDG_DATA_HOME=str(Path(directory, "data")), XDG_DATA_DIRS=str(Path(directory, "none")))
            with mock.patch.dict(os.environ, data):
                self.assertEqual(controller.window_menu(), dict(
                    menu="A:1  one two\0icon\x1fviewer\nB:2  term\0icon\x1fterm", ids=[11, 22]))
                (apps / "term.desktop").write_text("[Desktop Entry]\nIcon=utilities-terminal\n")
                stamp = apps.stat()
                os.utime(apps, ns=(stamp.st_atime_ns, stamp.st_mtime_ns + 1))
                self.assertIn("\0icon\x1futilities-terminal", controller.window_menu()["menu"])

    def test_python_fallback_focuses_the_choice(self):
        calls = []

        def request(action, **values):
            calls.append((action, values))
            return dict(menu="A:1  one\0icon\x1fa", ids=[11]) if action == "window-menu" else True

        chosen = SimpleNamespace(returncode=0, stdout="0\n")
        with mock.patch.object(entry, "request", request), \
                mock.patch.object(entry.subprocess, "run", return_value=chosen) as run:
            entry.window_menu()
        self.assertEqual(run.call_args.kwargs["input"], "A:1  one\0icon\x1fa")
        self.assertEqual(calls, [("window-menu", {}), ("focus", {"value": 11})])


class StaticI3:
    """Two outputs whose visible workspaces never change; records commands."""

    def __init__(self, shown, windows=()):
        self.outputs = [SimpleNamespace(name="eDP-1", active=True, primary=True),
                        SimpleNamespace(name="DP-2", active=True, primary=False)]
        self.spaces = [SimpleNamespace(num=num, name=str(num), output=output, visible=True, urgent=False,
                                       focused=output == "eDP-1", id=1000 + num,
                                       leaves=lambda num=num: [SimpleNamespace(id=num)] if num in windows else [])
                       for output, num in shown.items()]
        self.commands = []
        self.tree_reads = 0

    def get_outputs(self):
        return self.outputs

    def get_workspaces(self):
        return self.spaces

    def get_tree(self):
        self.tree_reads += 1
        focused = SimpleNamespace(id=1, window=None, workspace=lambda: self.spaces[0])
        return SimpleNamespace(workspaces=lambda: self.spaces, find_focused=lambda: focused)

    def command(self, text):
        self.commands.append(text)
        return [SimpleNamespace(success=True, error=None)]

    def shown(self):
        """The slot each `focus output` in a reselect asked i3 to show."""
        result, output = {}, None
        for text in self.commands:
            if text.startswith("focus output "):
                output = json.loads(text.removeprefix("focus output "))
            elif text.startswith("workspace ") and output:
                result[output] = int(json.loads(text.split(" ", 2)[2]))
                output = None
        return result


class DisplayMemoryTests(unittest.TestCase):
    def reselect(self, shown, windows=(), how=lambda controller: controller.dispatch("reconcile")):
        i3 = StaticI3(shown, windows)
        with tempfile.TemporaryDirectory() as directory:
            how(Controller(i3, directory))
        return i3.shown()

    def test_primary_change_drops_memory_that_breaks_the_slot_policy(self):
        self.assertEqual(self.reselect({"eDP-1": 3, "DP-2": 1}, (1, 3),
                                       how=lambda controller: controller.on_event("output", "unspecified")),
                         {"eDP-1": 1, "DP-2": 3})

    def test_display_setup_replaces_empty_filler_but_keeps_occupied_slots(self):
        self.assertEqual(self.reselect({"eDP-1": 2, "DP-2": 4}), {"eDP-1": 1, "DP-2": 3})
        self.assertEqual(self.reselect({"eDP-1": 2, "DP-2": 4}, (2, 4)), {"eDP-1": 2, "DP-2": 4})

    def test_ordinary_reselect_keeps_an_empty_slot_the_user_chose(self):
        self.assertEqual(self.reselect({"eDP-1": 2, "DP-2": 4},
                                       how=lambda controller: controller.select("A", force=True)),
                         {"eDP-1": 2, "DP-2": 4})

    def test_reselect_reuses_the_tree_it_read(self):
        i3 = StaticI3({"eDP-1": 1, "DP-2": 3})
        with tempfile.TemporaryDirectory() as directory:
            Controller(i3, directory).select("A", force=True)
        self.assertLessEqual(i3.tree_reads, 4)


if __name__ == "__main__":
    unittest.main()

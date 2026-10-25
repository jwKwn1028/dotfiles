#!/usr/bin/python3
"""Group identities, snapshot portability, and relocation guards."""

import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
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


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/python3
"""Atomic all-groups snapshots, recovery, and cancellation."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import uuid

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from workspace_groups import GroupError, process_identity  # noqa: E402
from group_restore import Restore  # noqa: E402

path = ROOT / "i3-resurrect-session.py"
if not path.exists():
    path = ROOT / "executable_i3-resurrect-session.py"
spec = importlib.util.spec_from_file_location("resurrect_session", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
snapshot = module.snapshot


def tree():
    return dict(type="root", nodes=[dict(type="workspace", name=str(number), num=number, nodes=[
        dict(window=number + 100, window_properties={"class": "Example"})]) for number in (4, 16, 29)])


def child_snapshot(state, meta, group):
    state.joinpath("snapshots").mkdir(parents=True)
    meta.mkdir(parents=True)
    staging = Path(tempfile.mkdtemp(prefix="generation.", dir=state / "snapshots"))
    payload, metadata = staging / "state", staging / "meta"
    payload.mkdir()
    metadata.mkdir()
    (metadata / "workspaces.txt").write_text("4\n")
    (metadata / "group-format.json").write_text(json.dumps(dict(version=1, slots=10, source_group=group)))
    (payload / "workspace_4_layout.json").write_text(json.dumps(dict(name="4", nodes=[dict(swallows=[{"class": "Example"}])])))
    (payload / "workspace_4_programs.json").write_text(json.dumps([dict(command=["example"], working_directory="/tmp")]))
    snapshot.publish(state, meta, staging.name)


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        environment = patch.dict(os.environ, I3_RESURRECT_STATE_DIR=str(self.root / "state"),
                                 I3_RESURRECT_META_DIR=str(self.root / "meta"), XDG_RUNTIME_DIR=str(self.root / "runtime"))
        environment.start()
        self.addCleanup(environment.stop)
        self.session = module.Session()
        self.session.tree = tree
        self.view = dict(selected="C", views={"C": dict(slot=9, output="primary", outputs={"primary": 1, "external": 9})})
        self.calls = []
        self.rpc_calls = []
        self.fail = None
        self.cancelled = False
        self.session.rpc = self.rpc
        self.session.child = self.child

    def rpc(self, action, **values):
        self.rpc_calls.append((action, values))
        if action == "status":
            return dict(groups=self.session.groups)
        if action == "session-view":
            return self.view
        if action == "restore-session-status" and self.cancelled:
            raise GroupError("All-groups restore was cancelled")
        return True

    def child(self, action, state, meta, group, check=False, **values):
        self.calls.append((action, group, check, state, meta, values))
        if not check and self.fail == group:
            raise GroupError(f"Group {group}: launch failed")
        if action == "save" and not check:
            child_snapshot(state, meta, group)
        return f"Group {group} plan"

    def publish(self):
        self.session.save()
        self.calls.clear()
        self.rpc_calls.clear()

    def test_complete_save_is_one_recoverable_generation(self):
        self.publish()
        manifest = snapshot.read_json(self.session.meta / "snapshot.json")
        state, meta = snapshot.resolve(self.session.state, self.session.meta)
        data = snapshot.validate_session(state, meta)
        self.assertEqual(data["saved"], ["A", "B", "C"])
        self.assertEqual(data["view"], self.view)
        self.session.save()
        self.assertEqual(snapshot.read_json(self.session.meta / "snapshot.json")["previous"], manifest["current"])
        old_state, old_meta = snapshot.resolve(self.session.state, self.session.meta, previous=True)
        self.assertEqual(snapshot.validate_session(old_state, old_meta)["groups"], self.session.groups)

    def test_failed_group_does_not_publish_partial_session(self):
        self.publish()
        before = (self.session.meta / "snapshot.json").read_bytes()
        self.fail = "B"
        with self.assertRaisesRegex(GroupError, "Group B"):
            self.session.save()
        self.assertEqual((self.session.meta / "snapshot.json").read_bytes(), before)
        self.assertEqual(len(list((self.session.state / "snapshots").iterdir())), 1)

    def test_moving_windows_during_save_preserves_previous(self):
        self.publish()
        before = (self.session.meta / "snapshot.json").read_bytes()
        changed = tree()
        changed["nodes"][0]["nodes"][0]["window"] = 999
        with patch.object(self.session, "tree", side_effect=[tree(), changed]):
            with self.assertRaisesRegex(GroupError, "changed during save"):
                self.session.save()
        self.assertEqual((self.session.meta / "snapshot.json").read_bytes(), before)

    def test_empty_groups_are_skipped_and_empty_session_is_rejected(self):
        self.session.tree = lambda: dict(type="root", nodes=[tree()["nodes"][1]])
        self.publish()
        state, meta = snapshot.resolve(self.session.state, self.session.meta)
        self.assertEqual(snapshot.validate_session(state, meta)["saved"], ["B"])
        before = (self.session.meta / "snapshot.json").read_bytes()
        self.session.tree = lambda: dict(type="root", nodes=[])
        with self.assertRaisesRegex(GroupError, "No savable"):
            self.session.save()
        self.assertEqual((self.session.meta / "snapshot.json").read_bytes(), before)

    def test_check_does_not_acquire_lease_or_modify_snapshot(self):
        self.publish()
        before = {path: path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        self.session.restore(check=True)
        self.assertEqual(self.rpc_calls, [])
        self.assertTrue(all(call[2] for call in self.calls))
        self.assertEqual(before, {path: path.read_bytes() for path in self.root.rglob("*") if path.is_file()})

    def test_restore_keeps_snapshot_immutable_and_restores_view(self):
        self.publish()
        state, _ = snapshot.resolve(self.session.state, self.session.meta)
        generation = state.parent
        before = {path: path.read_bytes() for path in generation.rglob("*") if path.is_file()}
        self.session.restore()
        self.assertEqual([call[1] for call in self.calls if not call[2]], ["A", "B", "C"])
        for call in self.calls:
            if not call[2]:
                self.assertTrue(call[5]["report"].is_relative_to(self.session.meta / "reports"))
                self.assertIn("session", call[5])
        self.assertEqual(before, {path: path.read_bytes() for path in generation.rglob("*") if path.is_file()})
        actions = dict(self.rpc_calls)
        self.assertEqual(actions["restore-session-views"]["view"], self.view)
        self.assertIn("restore-session-ready", actions)
        self.assertIn("restore-session-end", actions)

    def test_failed_restore_group_reports_failure_and_continues(self):
        self.publish()
        self.fail = "B"
        with self.assertRaisesRegex(GroupError, "Group B"):
            self.session.restore()
        self.assertEqual([call[1] for call in self.calls if not call[2]], ["A", "B", "C"])
        report = snapshot.read_json(self.session.meta / "last-restore.json")
        self.assertEqual([group["status"] for group in report["groups"]], ["ready", "failed", "ready"])
        self.assertFalse(report["cancelled"])

    def test_manual_group_change_stops_later_groups(self):
        self.publish()
        child = self.child

        def cancel(*args, **kwargs):
            result = child(*args, **kwargs)
            if args[0] == "restore" and not kwargs.get("check"):
                self.cancelled = True
            return result

        self.session.child = cancel
        with self.assertRaisesRegex(GroupError, "cancelled"):
            self.session.restore()
        self.assertEqual([call[1] for call in self.calls if not call[2]], ["A"])
        self.assertTrue(snapshot.read_json(self.session.meta / "last-restore.json")["cancelled"])
        self.assertNotIn("restore-session-views", dict(self.rpc_calls))
        self.assertIn("restore-session-end", dict(self.rpc_calls))

    def test_changed_group_indices_are_rejected_before_desktop_work(self):
        self.publish()
        self.session.groups["B"] = 4
        with self.assertRaisesRegex(GroupError, "indices changed"):
            self.session.restore()
        self.assertEqual(self.rpc_calls, [])
        self.assertEqual(self.calls, [])

    def test_preserve_slots_shares_original_destination_only(self):
        self.publish()
        state, meta = snapshot.resolve(self.session.state, self.session.meta)
        child_state, child_meta = snapshot.resolve(state / "A", meta / "A")
        output = self.root / "plan"
        output.mkdir()
        plan = snapshot.prepare_restore(child_state, child_meta, tree(), output, "A", uuid.uuid4().hex, True)
        self.assertEqual(plan[0]["workspace"], "4")
        self.assertTrue(plan[0]["merging"])

    def test_inherited_lock_accepts_children_and_blocks_other_operations(self):
        command = ['bash', '-c', 'DIR="$1"; . "$DIR/_resurrect-common.sh"; notify() { :; }; resurrect_lock',
                   'session-lock-test', str(ROOT)]
        with self.session.lock():
            environment = dict(os.environ, I3_RESURRECT_PARENT_LOCK=str(self.session.lock_path))
            result = subprocess.run(command, env=environment, pass_fds=(9,), capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            environment.pop("I3_RESURRECT_PARENT_LOCK")
            result = subprocess.run(command, env=environment, capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_invalid_later_group_aborts_before_any_restore(self):
        self.publish()
        state, meta = snapshot.resolve(self.session.state, self.session.meta)
        child_state, _ = snapshot.resolve(state / "C", meta / "C")
        (child_state / "workspace_4_programs.json").write_text("broken")
        with self.assertRaises(ValueError):
            self.session.restore()
        self.assertEqual(self.calls, [])
        self.assertEqual(self.rpc_calls, [])


class ControllerSessionTests(unittest.TestCase):
    def setUp(self):
        self.owner = [os.getpid(), process_identity(os.getpid())]
        self.controller = SimpleNamespace(state=dict(leases={}, launches={}), groups={"A": 0, "B": 1, "C": 2},
                                          save=lambda: None, pause_workers=lambda: None, resume_workers=lambda: None)
        self.restore = Restore(self.controller)
        self.token = uuid.uuid4().hex
        self.restore.session_begin(self.token, self.owner, ["A", "B", "C"])

    def test_internal_group_transition_keeps_session_active(self):
        self.restore.cancel_group_change("B", self.token)
        self.assertTrue(self.restore.session_active())
        self.assertTrue(self.restore.reserved("C"))

    def test_user_group_change_cancels_session(self):
        self.restore.cancel_group_change("B")
        self.assertFalse(self.restore.session_active())
        self.assertFalse(self.restore.reserved("C"))
        with self.assertRaisesRegex(GroupError, "cancelled"):
            self.restore.session_lease(self.token)

    def test_wrong_parent_token_does_not_authorize_child(self):
        with self.assertRaisesRegex(GroupError, "cancelled"):
            self.restore.begin("B", self.owner, uuid.uuid4().hex, session=uuid.uuid4().hex)

    def test_completed_launches_survive_until_final_session_verification(self):
        self.controller.state["launches"]["launch"] = dict(session=self.token, operation="child", done=True,
                                                          owner=None, created=0)
        self.restore.maintain()
        self.assertIn("launch", self.controller.state["launches"])

    def test_owner_death_releases_session_reservations(self):
        self.controller.state["session_restore"]["owner"] = [99999999, "0"]
        self.restore.maintain()
        self.assertNotIn("session_restore", self.controller.state)
        self.assertFalse(self.restore.reserved("A"))


if __name__ == "__main__":
    unittest.main()

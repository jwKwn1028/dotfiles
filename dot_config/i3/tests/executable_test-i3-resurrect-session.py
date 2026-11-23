#!/usr/bin/python3
"""Atomic all-groups snapshots, recovery, and cancellation."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
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
SLOTS = {"A": 4, "B": 6, "C": 9}


def tree():
    return dict(type="root", nodes=[dict(type="workspace", name=str(number), num=number, nodes=[
        dict(window=number + 100, window_properties={"class": "Example"})]) for number in (4, 16, 29)])


def child_snapshot(state, meta, group):
    slot = SLOTS[group]
    state.joinpath("snapshots").mkdir(parents=True)
    meta.mkdir(parents=True)
    staging = Path(tempfile.mkdtemp(prefix="generation.", dir=state / "snapshots"))
    payload, metadata = staging / "state", staging / "meta"
    payload.mkdir()
    metadata.mkdir()
    (metadata / "workspaces.txt").write_text(f"{slot}\n")
    (metadata / "group-format.json").write_text(json.dumps(dict(version=1, slots=10, source_group=group)))
    (payload / f"workspace_{slot}_layout.json").write_text(json.dumps(dict(name=str(slot), nodes=[dict(swallows=[{"class": "Example"}])])))
    (payload / f"workspace_{slot}_programs.json").write_text(json.dumps([dict(command=["example"], working_directory="/tmp")]))
    snapshot.publish(state, meta, staging.name)


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        environment = patch.dict(os.environ, I3_RESURRECT_STATE_DIR=str(self.root / "state"),
                                 I3_RESURRECT_META_DIR=str(self.root / "meta"), XDG_RUNTIME_DIR=str(self.root / "runtime"),
                                 I3SOCK=str(self.root / "i3.sock"))
        environment.start()
        self.addCleanup(environment.stop)
        self.session = module.Session()
        self.session.tree = tree
        self.view = dict(selected="C", views={"C": dict(slot=9, output="primary", outputs={"primary": 1, "external": 9})})
        self.calls = []
        self.order = []
        self.interrupt = None
        self.bar_visible = True
        self.rpc_calls = []
        self.fail = None
        self.placements = {group: {str(slot): slot} for group, slot in SLOTS.items()}
        self.cancelled = False
        self.missing = [[]]
        self.session.rpc = self.rpc
        self.session.child = self.child
        self.session.polybar = self.polybar

    def polybar(self, function):
        self.order.append(function)
        if self.interrupt == function:
            self.interrupt = None
            raise InterruptedError("Snapshot interrupted")
        return self.bar_visible if function == "polybar_visible" else True

    def rpc(self, action, **values):
        self.rpc_calls.append((action, values))
        if action == "status":
            return dict(groups=self.session.groups)
        if action == "session-view":
            return self.view
        if action == "restore-session-status" and self.cancelled:
            raise GroupError("All-groups restore was cancelled")
        if action == "restore-session-missing":
            return self.missing.pop(0) if len(self.missing) > 1 else list(self.missing[0])
        if action == "restore-session-ready" and self.missing[-1]:
            raise GroupError("A launched window is missing, ambiguous, or moved by the user")
        return True

    def child(self, action, state, meta, group, check=False, **values):
        self.calls.append((action, group, check, state, meta, values))
        self.order.append(f"{action} {group}{' --check' if check else ''}")
        if not check and self.fail == group:
            raise GroupError(f"Group {group}: launch failed")
        if action == "save" and not check:
            child_snapshot(state, meta, group)
        if action == "restore" and not check:
            mapping = [dict(source_workspace=source, workspace=str(self.session.groups[group] * 10 + target))
                       for source, target in self.placements[group].items()]
            snapshot.atomic_json(values["report"] / "last-restore.json", dict(
                mapping=mapping, workspaces=[dict(entry, status="launched", detail="") for entry in mapping]))
        return f"Group {group} plan"

    def publish(self):
        self.session.save()
        self.calls.clear()
        self.order.clear()
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
        self.assertEqual(actions["restore-session-views"]["mappings"], self.placements)
        self.assertIn("restore-session-ready", actions)
        self.assertIn("restore-session-end", actions)

    def reports(self):
        token = next(path for path in (self.session.meta / "reports").iterdir())
        return {group: snapshot.read_json(token / group / "last-restore.json")["workspaces"][0]["status"]
                for group in SLOTS}

    def test_late_window_is_ready_after_one_wait_for_all_groups(self):
        self.publish()
        self.missing = [["16"], ["16"], []]
        self.session.restore()
        self.assertEqual(self.reports(), dict(A="ready", B="ready", C="ready"))

    def test_window_that_never_appears_fails_only_its_workspace(self):
        self.publish()
        self.session.armed_path().unlink()
        self.missing = [["16"]]
        with patch.dict(os.environ, I3_RESURRECT_SESSION_WAIT="0.3"):
            with self.assertRaisesRegex(GroupError, "missing"):
                self.session.restore()
        self.assertEqual(self.reports(), dict(A="ready", B="failed", C="ready"))
        self.assertFalse(self.session.may_autosave())

    def test_automatic_save_waits_for_a_restore_or_manual_save(self):
        self.assertTrue(self.session.may_autosave())
        self.publish()
        self.assertTrue(self.session.may_autosave())
        with patch.dict(os.environ, I3SOCK=str(self.root / "next-login.sock")):
            self.assertFalse(self.session.may_autosave())
            self.session.restore()
            self.assertTrue(self.session.may_autosave())

    def test_save_check_keeps_last_automatic_save_error(self):
        self.session.meta.mkdir()
        failure = self.session.meta / "auto-save-failed.txt"
        failure.write_text("Previous automatic save failed\n")
        with patch.object(module, "Session", return_value=self.session), \
                patch.object(module.signal, "signal"), \
                patch.object(sys, "argv", ["i3-resurrect-session.py", "save", "--check"]), patch("builtins.print"):
            self.assertEqual(module.main(), 0)
        self.assertEqual(failure.read_text(), "Previous automatic save failed\n")

    def test_failed_restore_says_automatic_saves_stay_off(self):
        self.publish()
        with patch.dict(os.environ, I3SOCK=str(self.root / "next-login.sock")), \
                patch.object(module, "Session", return_value=self.session), \
                patch.object(self.session, "restore", side_effect=GroupError("Restore failed")), \
                patch.object(module, "notify") as notify, patch.object(module.signal, "signal"), \
                patch.object(sys, "argv", ["i3-resurrect-session.py", "restore"]), patch("builtins.print"):
            self.assertEqual(module.main(), 1)
        notify.assert_called_once_with("Restore failed\nAutomatic saves stay off until Super+Ctrl+Y saves.")

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

    def test_groups_restore_validated_generations_inside_one_bar_toggle(self):
        self.publish()
        self.session.restore()
        state, meta = snapshot.resolve(self.session.state, self.session.meta)
        for _, group, _, child_state, child_meta, values in (call for call in self.calls if not call[2]):
            with self.subTest(group=group):
                self.assertEqual((child_state, child_meta), snapshot.resolve(state / group, meta / group))
                self.assertTrue(values["validated"])
        self.assertEqual(self.order, ["restore A --check", "restore B --check", "restore C --check", "polybar_visible",
                                      "polybar_hide_for_restore", "restore A", "restore B", "restore C",
                                      "polybar_show_after_restore"])
        self.order.clear()
        self.fail = "B"
        with self.assertRaises(GroupError):
            self.session.restore()
        self.assertEqual(self.order.count("polybar_show_after_restore"), 1)

    def test_interrupted_bar_toggle_cancels_the_restore_and_shows_the_bar(self):
        self.publish()
        checks = ["restore A --check", "restore B --check", "restore C --check", "polybar_visible"]
        groups = ["restore A", "restore B", "restore C"]
        for function, launched in (("polybar_hide_for_restore", []), ("polybar_show_after_restore", groups)):
            with self.subTest(interrupted=function):
                self.order.clear()
                self.rpc_calls.clear()
                self.interrupt = function
                with self.assertRaises(InterruptedError):
                    self.session.restore()
                self.assertEqual(self.order, checks + ["polybar_hide_for_restore", *launched,
                                                       *["polybar_show_after_restore"] * (2 if launched else 1)])
                self.assertIn("restore-session-end", [action for action, _ in self.rpc_calls])
        self.order.clear()
        self.bar_visible = False
        self.session.restore()
        self.assertEqual([call for call in self.order if call.startswith("polybar")], ["polybar_visible"])

    def test_bar_calls_let_cancellation_through(self):
        for error, outcome in ((InterruptedError("Snapshot interrupted"), InterruptedError), (OSError("no bash"), False)):
            with self.subTest(error=type(error).__name__), patch.object(module.subprocess, "run", side_effect=error):
                if outcome is False:
                    self.assertFalse(module.Session.polybar(self.session, "polybar_visible"))
                else:
                    with self.assertRaises(outcome):
                        module.Session.polybar(self.session, "polybar_visible")

    def test_restore_starts_the_lab_route_once_when_a_group_saved_it_on(self):
        log = self.root / "labroute.log"
        script = self.root / "labroute-restore.sh"
        script.write_text(f"echo started >>'{log}'\n")
        self.publish()
        state, meta = snapshot.resolve(self.session.state, self.session.meta)
        with patch.dict(os.environ, I3_RESURRECT_LABROUTE_RESTORE=str(script)):
            self.session.restore()
            self.assertFalse(log.exists())
            (snapshot.resolve(state / "B", meta / "B")[1] / "labroute.txt").write_text("on\n")
            self.session.restore(check=True)
            self.assertFalse(log.exists())
            self.session.restore()
        self.assertEqual(log.read_text(), "started\n")

    def test_restore_starts_tmux_once_only_for_a_saved_local_tmux_attach(self):
        log = self.root / "tmux-restore.log"
        script = self.root / "tmux-restore-if-empty"
        script.write_text(f"#!/bin/sh\necho started >>'{log}'\n")
        script.chmod(0o755)
        self.publish()
        with patch.dict(os.environ, I3_RESURRECT_TMUX_RESTORE=str(script)):
            self.session.restore()
            state, meta = snapshot.resolve(self.session.state, self.session.meta)
            child_state, _ = snapshot.resolve(state / "B", meta / "B")
            (child_state / f"workspace_{SLOTS['B']}_programs.json").write_text(json.dumps([dict(
                command=["ghostty", snapshot.LOCAL_TMUX_ARG + "d29yaw== zsh"], working_directory="/tmp")]))
            self.session.restore(check=True)
            self.assertFalse(log.exists())
            self.session.restore()
            for _ in range(40):
                if log.exists():
                    break
                time.sleep(0.05)
            time.sleep(0.2)
        self.assertEqual(log.read_text(), "started\n")

    def test_restore_passes_actual_destinations_to_saved_views(self):
        self.publish()
        self.placements = {group: {str(slot): index + 1} for index, (group, slot) in enumerate(SLOTS.items())}
        self.session.restore()
        self.assertEqual(dict(self.rpc_calls)["restore-session-views"]["mappings"], self.placements)

    def test_restore_keeps_saved_slots_and_moves_off_taken_ones_on_the_same_display(self):
        self.publish()
        state, meta = snapshot.resolve(self.session.state, self.session.meta)
        for taken, expected in ((1, SLOTS), (None, {group: slot - 1 for group, slot in SLOTS.items()})):
            for group, index in self.session.groups.items():
                with self.subTest(group=group, taken=taken or "saved slot"):
                    child_state, child_meta = snapshot.resolve(state / group, meta / group)
                    output = self.root / f"{group}{taken}"
                    output.mkdir()
                    num = index * 10 + (taken or SLOTS[group])
                    live = dict(type="root", nodes=[dict(type="workspace", name=str(num), num=num,
                                                         nodes=[dict(window=200 + index)])])
                    before = json.dumps(live)
                    plan = snapshot.prepare_restore(child_state, child_meta, live, output, group, uuid.uuid4().hex)
                    self.assertEqual(plan[0]["workspace"], str(index * 10 + expected[group]))
                    self.assertFalse(plan[0]["merging"])
                    self.assertEqual(json.dumps(live), before)

    def test_full_groups_share_only_their_own_occupied_slots(self):
        self.publish()
        state, meta = snapshot.resolve(self.session.state, self.session.meta)
        live = dict(type="root", nodes=[dict(type="workspace", name=str(num), num=num,
                                           nodes=[dict(window=num + 100)]) for num in range(1, 31)])
        for group, index in self.session.groups.items():
            with self.subTest(group=group):
                child_state, child_meta = snapshot.resolve(state / group, meta / group)
                output = self.root / group
                output.mkdir()
                plan = snapshot.prepare_restore(child_state, child_meta, live, output, group, uuid.uuid4().hex)
                self.assertEqual(plan[0]["workspace"], str(index * 10 + SLOTS[group]))
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
        (child_state / "workspace_9_programs.json").write_text("broken")
        with self.assertRaises(ValueError):
            self.session.restore()
        self.assertEqual(self.calls, [])
        self.assertEqual(self.rpc_calls, [])


class ControllerSessionTests(unittest.TestCase):
    def setUp(self):
        self.owner = [os.getpid(), process_identity(os.getpid())]
        self.controller = SimpleNamespace(state=dict(leases={}, launches={}, views={}), groups={"A": 0, "B": 1, "C": 2},
                                          save=lambda: None, pause_workers=lambda: None, resume_workers=lambda: None,
                                          select=lambda *args, **kwargs: True,
                                          target_output=lambda slot: "primary" if slot <= 2 else "external")
        self.restore = Restore(self.controller)
        self.token = uuid.uuid4().hex
        self.restore.session_begin(self.token, self.owner, ["A", "B", "C"])

    def test_internal_group_transition_keeps_session_active(self):
        self.restore.cancel_group_change("B", self.token)
        self.assertTrue(self.restore.session_active())
        self.assertTrue(self.restore.reserved("C"))

    def test_saved_focus_follows_new_slot_and_monitor(self):
        view = dict(selected="B", views={"B": dict(slot=6, output="external", outputs={"primary": 1, "external": 6})})
        self.restore.session_views(self.token, view, mappings={"B": {"6": 2}})
        self.assertEqual(self.controller.state["views"]["B"], dict(slot=2, output="primary", outputs={"primary": 2}))
        self.assertEqual(view["views"]["B"]["slot"], 6)

    def test_two_saved_output_views_can_swap_monitors_without_losing_focus(self):
        view = dict(selected="B", views={"B": dict(slot=6, output="external", outputs={"primary": 1, "external": 6})})
        self.restore.session_views(self.token, view, mappings={"B": {"1": 3, "6": 2}})
        self.assertEqual(self.controller.state["views"]["B"],
                         dict(slot=2, output="primary", outputs={"primary": 2, "external": 3}))

    def test_saved_output_views_collapsing_onto_one_monitor_keep_focused_slot(self):
        view = dict(selected="B", views={"B": dict(slot=6, output="external", outputs={"primary": 1, "external": 6})})
        self.controller.target_output = lambda slot: "primary"
        self.restore.session_views(self.token, view, mappings={"B": {"1": 2, "6": 3}})
        self.assertEqual(self.controller.state["views"]["B"], dict(slot=3, output="primary", outputs={"primary": 3}))

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

    def test_session_keeps_group_placeholders_until_it_ends(self):
        operation = uuid.uuid4().hex
        self.controller.state["leases"][operation] = dict(group="A", owner=self.owner, placeholders={"123": 5},
                                                          session=self.token, before=[])
        cleaned = []
        self.restore.cleanup_placeholders = lambda op, placeholders=None: cleaned.append((op, placeholders))
        self.restore.release(operation)
        self.assertEqual(cleaned, [])
        self.restore.session_end(self.token)
        self.assertEqual(cleaned, [(operation, {"123": 5})])

    def test_window_without_launch_identity_takes_the_oldest_launch_saved_like_it(self):
        self.restore.property = lambda window, name: None
        self.restore.x11_client_pid = lambda window: None
        zen = SimpleNamespace(window=7, window_instance="Navigator", window_class="zen", window_role="browser",
                              pid=None)
        rules = [{"class": "^zen$", "instance": "^Navigator$", "title": "^Inbox"}]
        self.controller.state["launches"].update(
            newer=dict(done=False, before=[], created=2, match=rules),
            older=dict(done=False, before=[], created=1, match=rules),
            other=dict(done=False, before=[], created=0, match=[{"class": "^helium$"}]))
        self.assertEqual(self.restore.window_token(zen), "older")
        dialog = SimpleNamespace(window=8, window_instance="Toolkit", window_class="zen", pid=None)
        self.assertIsNone(self.restore.window_token(dialog))

    def test_flatpak_window_uses_x11_host_pid_for_launch_token(self):
        self.restore.property = lambda window, name: None
        self.restore.display = SimpleNamespace(has_extension=lambda name: True,
                                               res_query_client_ids=lambda specs: SimpleNamespace(
                                                   ids=[SimpleNamespace(value=[12345])]))
        zen = SimpleNamespace(window=7, window_instance="Navigator", pid=2)
        self.controller.state["launches"]["one"] = dict(done=False, before=[])
        with patch.object(Path, "read_bytes", autospec=True, return_value=b"I3_GROUP_LAUNCH=one\x00") as read:
            self.assertEqual(self.restore.window_token(zen), "one")
        read.assert_called_once_with(Path("/proc/12345/environ"))

    def test_window_startup_id_takes_precedence_over_shared_browser_process(self):
        self.restore.property = lambda window, name: "second" if name == "_NET_STARTUP_ID" else None
        self.restore.x11_client_pid = lambda window: 12345
        window = SimpleNamespace(window=7, window_instance="Navigator", pid=2)
        self.controller.state["launches"].update(first=dict(done=False, before=[]),
                                                 second=dict(done=False, before=[]))
        with patch.object(Path, "read_bytes", return_value=b"I3_GROUP_LAUNCH=first\x00"):
            self.assertEqual(self.restore.window_token(window), "second")

    def test_missing_windows_are_named_by_workspace(self):
        self.controller.tree = lambda: SimpleNamespace(find_by_id=lambda con_id: None)
        self.controller.state["launches"]["launch"] = dict(session=self.token, operation="child", done=False,
                                                          workspace="16", group="B", slot=6)
        self.assertEqual(self.restore.dispatch("session-missing", token=self.token), ["16"])
        with self.assertRaisesRegex(GroupError, "workspace 16"):
            self.restore.dispatch("session-ready", token=self.token)

    def test_owner_death_releases_session_reservations(self):
        self.controller.state["session_restore"]["owner"] = [99999999, "0"]
        self.restore.maintain()
        self.assertNotIn("session_restore", self.controller.state)
        self.assertFalse(self.restore.reserved("A"))


if __name__ == "__main__":
    unittest.main()

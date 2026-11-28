#!/usr/bin/python3
"""Save or restore one atomic snapshot spanning every workspace group."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid

from workspace_groups import (ControllerUnavailable, GroupError, definitions, filtered_tree, identity, process_identity,
                              request, session_dir, source_path, validate_view, walk)

spec = importlib.util.spec_from_file_location("session_snapshot", source_path("i3-resurrect-state.py"))
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)


class Session:
    def __init__(self):
        root = Path.home() / ".config/i3"
        self.state = Path(os.environ.get("I3_RESURRECT_STATE_DIR", root / "resurrect-session"))
        self.meta = Path(os.environ.get("I3_RESURRECT_META_DIR", root / "resurrect-meta-session"))
        self.groups = definitions()
        self.lock_path = None

    def rpc(self, action, **values):
        """Retry while i3 restarts."""
        started, retried = time.monotonic(), False
        deadline = started + float(os.environ.get("I3_RESURRECT_CONTROLLER_WAIT", "180"))
        try:
            while True:
                try:
                    return self.rpc_once(action, **values)
                except ControllerUnavailable:
                    if time.monotonic() >= deadline:
                        raise
                    retried = True
                    time.sleep(0.5)
        finally:
            if retried:
                self.outage = getattr(self, "outage", 0) + time.monotonic() - started

    def rpc_once(self, action, **values):
        helper = os.environ.get("I3_RESURRECT_GROUP_HELPER")
        if not helper:
            return request(action, **values)
        result = subprocess.run([sys.executable, helper, "request"], text=True,
                                input=json.dumps(dict(action=action, **values)), capture_output=True)
        if result.returncode:
            raise GroupError(result.stderr.strip() or "Workspace controller request failed")
        return json.loads(result.stdout)

    def tree(self):
        return json.loads(subprocess.check_output(["i3-msg", "-t", "get_tree"], text=True))

    def identities(self, tree):
        result = {}
        for group in self.groups:
            for node in walk(filtered_tree(tree, group, self.groups)):
                if node.get("type") != "workspace":
                    continue
                windows = snapshot.window_identity(tree, node["name"])
                if windows:
                    if node["num"] in result:
                        raise ValueError("Duplicate live workspace number")
                    result[node["num"]] = sorted(windows, key=lambda value: value[0])
        return result

    def runtime_path(self, suffix):
        runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
        runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
        key = hashlib.sha256(os.environ.get("DISPLAY", "default").encode()).hexdigest()[:16]
        return (runtime / f"i3-resurrect-{key}.{suffix}").resolve()

    def armed_path(self):
        return session_dir() / "resurrect.armed"

    def arm(self):
        path = self.armed_path()
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        path.touch()

    def may_autosave(self):
        return not (self.meta / "snapshot.json").exists() or self.armed_path().exists()

    def wait_for_windows(self, token):
        start, wait = time.monotonic(), float(os.environ.get("I3_RESURRECT_SESSION_WAIT", "45"))
        while True:
            before = getattr(self, "outage", 0)
            missing = self.rpc("restore-session-missing", token=token)
            start += getattr(self, "outage", 0) - before  # Exclude restart time.
            if not missing or time.monotonic() >= start + wait:
                return missing
            time.sleep(0.25)

    @contextmanager
    def lock(self):
        path = self.runtime_path("lock")
        fd = os.open(path, os.O_CREAT | os.O_WRONLY, 0o600)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise GroupError("Another i3 save or restore is already running") from error
            if fd != 9:
                os.dup2(fd, 9)
            self.lock_path = path
            try:
                yield
            finally:
                self.lock_path = None
                if fd != 9:
                    os.close(9)
        finally:
            os.close(fd)

    def child(self, action, state, meta, group, check=False, session=None, report=None, validated=False):
        environment = dict(os.environ, I3_RESURRECT_STATE_DIR=str(state), I3_RESURRECT_META_DIR=str(meta),
                           I3_RESURRECT_GROUP=group, I3_RESURRECT_QUIET="1")
        for name in ("I3_RESURRECT_SESSION_TOKEN", "I3_RESURRECT_REPORT_DIR", "I3_RESURRECT_PARENT_LOCK",
                     "I3_RESURRECT_VALIDATED"):
            environment.pop(name, None)
        if self.lock_path:
            environment["I3_RESURRECT_PARENT_LOCK"] = str(self.lock_path)
        if session:
            environment["I3_RESURRECT_SESSION_TOKEN"] = session
        if report:
            environment["I3_RESURRECT_REPORT_DIR"] = str(report)
        if validated:
            environment["I3_RESURRECT_VALIDATED"] = "1"
        try:
            environment.setdefault("I3_RESURRECT_CONTROLLER", str(session_dir() / "controller.sock"))
        except (GroupError, OSError, subprocess.SubprocessError):
            pass
        command = ["bash", str(source_path(f"i3-resurrect-{action}-all.sh")), f"--group={group}"]
        if check:
            command.append("--check")
        process = subprocess.Popen(command, env=environment, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, pass_fds=(9,) if self.lock_path else (),
                                   start_new_session=True)
        try:
            output, error = process.communicate()
        except BaseException:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
            raise
        if process.returncode:
            raise GroupError(f"Group {group}: {(error or output).strip() or 'snapshot operation failed'}")
        return output.strip()

    def save(self, check=False):
        if check:
            self.child("save", self.state, self.meta, next(iter(self.groups)), check=True)
            return "All-groups save dependencies are available."
        with self.lock():
            status = self.rpc("status")
            if status["groups"] != self.groups:
                raise GroupError("Reload i3 after changing group definitions")
            view = validate_view(self.rpc("session-view"), self.groups)
            before = self.identities(self.tree())
            saved = [group for group in self.groups if any(identity(num, self.groups)[0] == group for num in before)]
            if not saved:
                raise GroupError("No savable windows; the previous all-groups snapshot is unchanged")
            self.state.joinpath("snapshots").mkdir(parents=True, exist_ok=True)
            self.meta.mkdir(parents=True, exist_ok=True)
            snapshot.resolve(self.state, self.meta)
            staging = Path(tempfile.mkdtemp(prefix="generation.", dir=self.state / "snapshots"))
            try:
                state, meta = staging / "state", staging / "meta"
                state.mkdir()
                meta.mkdir()
                for group in saved:
                    self.child("save", state / group, meta / group, group)
                if before != self.identities(self.tree()) or definitions() != self.groups:
                    raise GroupError("Windows or groups changed during save; retry when the desktop settles")
                (meta / "session.json").write_text(json.dumps(dict(version=1, groups=self.groups, saved=saved, view=view)) + "\n")
                snapshot.publish(self.state, self.meta, staging.name)
                self.arm()
            finally:
                pointer = self.meta / "snapshot.json"
                published = snapshot.read_json(pointer).get("current") if pointer.exists() else None
                if published != staging.name:
                    shutil.rmtree(staging, ignore_errors=True)
        return "Saved all groups: " + ", ".join(saved) + "."

    def restore(self, check=False, previous=False):
        if check:
            return self.restore_snapshot(previous, check=True)
        with self.lock():
            return self.restore_snapshot(previous)

    def start_labroute(self, children):
        """Bring a saved lab route up beside window creation; remote windows wait on its lock."""
        if not any((meta / "labroute.txt").is_file() and
                   (meta / "labroute.txt").read_text().splitlines()[:1] == ["on"] for _, meta in children.values()):
            return
        script = os.environ.get("I3_RESURRECT_LABROUTE_RESTORE") or str(source_path("labroute-restore.sh"))
        try:
            subprocess.run(["bash", script], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=10, check=False)
        except InterruptedError:
            raise
        except (OSError, subprocess.SubprocessError):
            pass

    def polybar(self, function):
        """Run a _polybar-common.sh function; True on success."""
        common = source_path("_polybar-common.sh")
        try:
            return subprocess.run(["bash", "-c", f'DIR=$1; . "$DIR/_polybar-common.sh"; {function}', "bash",
                                   str(common.parent)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=10).returncode == 0
        except InterruptedError:
            raise
        except (OSError, subprocess.SubprocessError):
            return False

    def start_tmux_restore(self, children):
        """Start one detached tmux restore; clients share its lock."""
        script = Path(os.environ.get("I3_RESURRECT_TMUX_RESTORE", Path.home() / ".local/bin/tmux-restore-if-empty"))
        if not (script.is_file() and os.access(script, os.X_OK)) or not any(
                snapshot.requests_local_tmux(state, meta) for state, meta in children.values()):
            return
        try:
            subprocess.Popen([str(script)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            pass  # ta retries.


    def restore_snapshot(self, previous, check=False):
        state, meta = snapshot.resolve(self.state, self.meta, previous)
        data = snapshot.validate_session(state, meta)
        if any(self.groups.get(group) != index for group, index in data["groups"].items()):
            raise GroupError("Saved groups are missing or their indices changed")
        plans = {}
        for group in data["saved"]:
            plans[group] = self.child("restore", state / group, meta / group, group, check=True)
        if check:
            return "\n".join(plans.values())
        if self.rpc("status")["groups"] != self.groups:
            raise GroupError("Reload i3 after changing group definitions")
        children = {group: snapshot.resolve(state / group, meta / group) for group in data["saved"]}
        self.start_labroute(children)
        self.start_tmux_restore(children)
        token = uuid.uuid4().hex
        self.rpc("restore-session-begin", token=token, owner=[os.getpid(), process_identity(os.getpid())],
                 groups=list(data["groups"]))
        results = []
        mappings = {}
        cancelled = False
        hidden = False
        try:
            if self.polybar("polybar_visible"):
                hidden = True
                self.polybar("polybar_hide_for_restore")
            for group in data["saved"]:
                self.rpc("restore-session-status", token=token)
                report = self.meta / "reports" / token / group
                report.mkdir(parents=True, exist_ok=True)
                try:
                    self.child("restore", *children[group], group, session=token, report=report, validated=True)
                    results.append(dict(group=group, status="ready"))
                except GroupError as error:
                    results.append(dict(group=group, status="failed", detail=str(error)))
                placement = report / "last-restore.json"
                if placement.exists():
                    mappings[group] = {str(snapshot.workspace_order(entry["source_workspace"])[0]):
                                       identity(snapshot.workspace_order(entry["workspace"])[0], self.groups)[1]
                                       for entry in snapshot.read_json(placement)["mapping"]}
                self.rpc("restore-session-status", token=token)
            if hidden and self.polybar("polybar_show_after_restore"):
                hidden = False
            missing = self.wait_for_windows(token)
            for group in data["saved"]:
                settle_report(self.meta / "reports" / token / group / "last-restore.json", missing)
            try:
                self.rpc("restore-session-ready", token=token)
            except GroupError as error:
                results.append(dict(group="(verification)", status="failed", detail=str(error)))
            self.rpc("restore-session-views", token=token, view=data["view"], mappings=mappings)
        except BaseException:
            cancelled = True
            raise
        finally:
            try:
                if hidden:
                    self.polybar("polybar_show_after_restore")
            finally:
                try:
                    self.rpc("restore-session-end", token=token)
                finally:
                    snapshot.atomic_json(self.meta / "last-restore.json", dict(snapshot=str(state), groups=results,
                                                                             cancelled=cancelled, operation=token))
        failures = [result["detail"] for result in results if result["status"] != "ready"]
        if failures:
            raise GroupError("All-groups restore finished with errors:\n" + "\n".join(failures))
        self.arm()
        return "Restored all groups: " + ", ".join(data["saved"]) + "."


def settle_report(path, missing):
    if not path.exists():
        return
    report = snapshot.read_json(path)
    for entry in report.get("workspaces", []):
        if entry.get("status") == "launched":
            late = entry["workspace"] in missing
            entry.update(status="failed" if late else "ready", detail="window did not appear in time" if late else "")
    snapshot.atomic_json(path, report)


def notify(message):
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "i3-resurrect", message], check=False)


def interrupted(*_):
    raise InterruptedError("Snapshot interrupted")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("save", "restore"))
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--previous", action="store_true")
    parser.add_argument("--auto", action="store_true",
                        help="save quietly, only once this login has restored or saved")
    args = parser.parse_args()
    if args.action == "save" and args.previous:
        parser.error("--previous is only valid for restore")
    if args.auto and (args.action != "save" or args.check):
        parser.error("--auto is only valid for save")
    os.umask(0o077)
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, interrupted)
    failure = None
    try:
        session = Session()
        failure = session.meta / "auto-save-failed.txt"
        if args.auto and not session.may_autosave():
            print("Skipped: no restore or manual save since login")
            return 0
        if args.action == "save":
            result = session.save(args.check)
            if not args.check:
                failure.unlink(missing_ok=True)
        else:
            result = session.restore(args.check, args.previous)
        print(result)
        if not args.check and not args.auto:
            notify(result)
        return 0
    except (OSError, ValueError, TypeError, KeyError, GroupError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        if args.auto and failure:
            failure.parent.mkdir(parents=True, exist_ok=True)
            failure.write_text(time.strftime("%Y-%m-%d %H:%M ") + str(error) + "\n")
        elif not args.check:
            paused = args.action == "restore" and failure and not session.may_autosave()
            notify(str(error) + ("\nAutomatic saves stay off until Super+Ctrl+Y saves." if paused else ""))
        return 1
    finally:
        if args.action == "restore" and not args.check and failure and failure.exists():
            notify("Last automatic save failed " + failure.read_text().strip() +
                   "; this restore used the snapshot before it.")
            failure.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())

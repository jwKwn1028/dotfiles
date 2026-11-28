#!/usr/bin/python3
"""Operation-owned restore placement and late-window routing."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from types import SimpleNamespace

from workspace_groups import (GroupError, exact, identity, number, owner_alive,
                              process_identity, quote, validate_view, walk)


def rule_matches(con, rule):
    fields = dict(zip(("class", "instance", "window_role"), (
        getattr(con, "window_class", None), getattr(con, "window_instance", None), getattr(con, "window_role", None))))
    keys = [key for key in fields if key in rule]
    try:
        return bool(keys) and all(re.search(rule[key], fields[key] or "") for key in keys)
    except (re.error, TypeError):
        return False


class Restore:
    def __init__(self, controller):
        self.controller = controller
        self.processes = {}
        self.display = None
        self.started, self.started_at = time.monotonic(), time.time()
        self.unmapped = {}  # window -> first seen hidden

    @property
    def state(self):
        return self.controller.state

    def xdisplay(self):
        if self.display is None:
            from Xlib.display import Display
            self.display = Display()
        return self.display

    def property(self, window, name):
        from Xlib import X
        display = self.xdisplay()
        try:
            value = display.create_resource_object("window", window).get_full_property(
                display.intern_atom(name), X.AnyPropertyType)
            if value is None:
                return None
            data = value.value
            return data.decode(errors="replace").rstrip("\0") if isinstance(data, bytes) else list(data)
        except Exception:
            return None

    def x11_client_pid(self, window):
        from Xlib.error import XError
        from Xlib.ext import res

        display = self.xdisplay()
        if not display.has_extension(res.extname):
            return None
        try:
            ids = display.res_query_client_ids([{"client": window, "mask": res.LocalClientPIDMask}]).ids
        except XError:
            return None
        return next((entry.value[0] for entry in ids if entry.value and entry.value[0] > 0), None)

    def tag_placeholder(self, window, token):
        from Xlib import Xatom
        display = self.xdisplay()
        display.create_resource_object("window", window).change_property(
            display.intern_atom("_I3_GROUP_PLACEHOLDER"), Xatom.STRING, 8, token.encode())
        display.sync()

    def remove_placeholder(self, window, token):
        display = self.xdisplay()
        display.grab_server()
        try:
            if self.property(window, "_I3_GROUP_PLACEHOLDER") == token:
                display.create_resource_object("window", window).destroy()
            display.sync()
        finally:
            display.ungrab_server()
            display.sync()

    def reserved(self, *groups):
        session = self.state.get("session_restore", {})
        return ((self.session_active() and any(group in session["groups"] for group in groups)) or
                any(not lease.get("cancelled") and lease["group"] in groups
                    for lease in self.state["leases"].values()))

    def session_active(self):
        session = self.state.get("session_restore")
        return bool(session and not session.get("cancelled") and owner_alive(session["owner"]))

    def session_lease(self, token):
        session = self.state.get("session_restore", {})
        if not self.session_active() or session.get("token") != token:
            raise GroupError("All-groups restore was cancelled or its owner exited")
        return session

    def session_begin(self, token, owner, groups):
        if (not re.fullmatch(r"[a-f0-9]{32}", token) or not owner_alive(owner) or
                not isinstance(groups, list) or not groups or len(set(groups)) != len(groups) or
                any(group not in self.controller.groups for group in groups)):
            raise GroupError("Invalid all-groups restore request")
        if self.session_active() or self.state["leases"]:
            raise GroupError("Another restore owns placement")
        self.controller.pause_workers()
        self.state["session_restore"] = dict(token=token, owner=owner, groups=groups, cancelled=False)
        self.controller.save()
        return token

    def session_end(self, token):
        session = self.state.get("session_restore", {})
        if session.get("token") != token:
            return
        session["cancelled"] = True
        for operation in list(self.state["leases"]):
            self.release(operation, cancelled=True)
        for operation, placeholders in session.get("placeholders", {}).items():
            self.cleanup_placeholders(operation, placeholders)
        self.state.pop("session_restore", None)
        self.controller.save()
        self.controller.resume_workers()

    def session_views(self, token, view, mappings=None):
        self.session_lease(token)
        view = validate_view(view, self.controller.groups)
        for group, mapping in (mappings or {}).items():
            if (group not in self.controller.groups or not isinstance(mapping, dict) or
                    any(source not in {str(slot) for slot in range(1, 11)} or
                        type(target) is not int or target not in range(1, 11)
                        for source, target in mapping.items()) or len(set(mapping.values())) != len(mapping)):
                raise GroupError("Invalid restored workspace mapping")
            remembered = view["views"].get(group)
            if not remembered or not mapping:
                continue
            slot = mapping.get(str(remembered["slot"]), remembered["slot"])
            output = (self.controller.target_output(slot) if str(remembered["slot"]) in mapping else
                      remembered.get("output", self.controller.target_output(slot)))
            outputs = {name: value for name, value in remembered["outputs"].items() if str(value) not in mapping}
            for value in remembered["outputs"].values():
                if str(value) in mapping:
                    target = mapping[str(value)]
                    outputs[self.controller.target_output(target)] = target
            outputs[output] = slot
            remembered.update(slot=slot, output=output, outputs=outputs)
        self.state["views"].update(view["views"])
        return self.controller.select(view["selected"], force=True, restore_session=token, remember_view=False)

    def lease(self, token):
        lease = self.state["leases"].get(token)
        if not lease or lease.get("cancelled") or not owner_alive(lease["owner"]):
            raise GroupError("Restore was cancelled or its owner exited")
        return lease

    def cleanup_placeholders(self, operation, placeholders=None):
        lease = self.state["leases"].get(operation, {})
        placeholders = lease.get("placeholders", {}) if placeholders is None else placeholders
        for node in walk(self.controller.tree().ipc_data):
            if (node.get("swallows") and node.get("window") and
                    any(mark.startswith("_group_" + operation + "_") for mark in node.get("marks", []))):
                window = node["window"]
                if str(window) not in placeholders:
                    self.tag_placeholder(window, operation)
                self.remove_placeholder(window, operation)
        for window in placeholders:
            self.remove_placeholder(int(window), operation)
        lease["placeholders"] = {}

    def release(self, operation, cancelled=False):
        lease = self.state["leases"].get(operation)
        if not lease:
            return
        lease["cancelled"] = bool(cancelled or lease.get("cancelled"))
        self.controller.save()
        session = self.state.get("session_restore", {})
        if not lease["cancelled"] and lease.get("session") and self.session_active() and \
                session.get("token") == lease["session"]:
            # Keep placeholders for late arrivals.
            session.setdefault("placeholders", {})[operation] = lease["placeholders"]
        else:
            self.cleanup_placeholders(operation)
        self.state["leases"].pop(operation, None)
        self.controller.save()
        self.controller.resume_workers()

    def cancel_group_change(self, group, session_token=None):
        session = self.state.get("session_restore")
        if session and session.get("token") != session_token:
            session["cancelled"] = True
            self.controller.save()
        for operation, lease in list(self.state["leases"].items()):
            if lease["group"] != group:
                self.release(operation, cancelled=True)
        self.controller.resume_workers()

    def forget_window(self, con_id):
        for launch in self.state["launches"].values():
            if launch.get("window") == con_id:
                launch["transferred"] = True
                launch["done"] = True
        self.controller.save()

    def begin(self, group, owner, token, session=None):
        number(group, 1, self.controller.groups)
        if not re.fullmatch(r"[a-f0-9]{32}", token):
            raise GroupError("Invalid restore operation identity")
        if not owner_alive(owner):
            raise GroupError("Restore owner is not alive")
        if self.state["leases"]:
            raise GroupError("Another restore owns placement")
        if session:
            if group not in self.session_lease(session)["groups"]:
                raise GroupError("Group is outside the all-groups restore")
        elif self.session_active():
            raise GroupError("An all-groups restore owns placement")
        self.controller.cleanup_mode()
        self.controller.select(group, restore_session=session)
        self.controller.pause_workers()
        self.state["leases"][token] = {"group": group, "owner": owner, "placeholders": {},
                                      "session": session,
                                      "before": [con.window for con in self.controller.tree().leaves() if con.window]}
        self.controller.save()
        return token

    def layout(self, token, workspace, path):
        lease = self.lease(token)
        layout = json.loads(Path(path).read_text())
        slot = identity(int(layout["num"]), self.controller.groups)
        if not slot or slot[0] != lease["group"] or layout["name"] != workspace:
            raise GroupError("Restore layout is outside its reserved group")
        self.controller.select(lease["group"], slot[1])
        nodes = layout.get("nodes", []) + layout.get("floating_nodes", [])
        for node in walk(layout):
            if node.get("swallows"):
                marks = node.get("marks", [])
                if not any(mark.startswith("_group_" + token + "_") for mark in marks):
                    raise GroupError("Restore placeholder lacks operation identity")
        target = self.controller.directory / ("layout-" + token + ".json")
        target.write_text(json.dumps([nodes]))
        try:
            ws = self.controller.workspace(lease["group"], slot[1])
            if not ws.leaves() and layout.get("layout") in ("splith", "splitv", "tabbed", "stacked"):
                self.controller.command(f"layout {layout['layout']}")
            self.controller.command(f"append_layout {quote(target)}")
            for node in walk(self.controller.tree().ipc_data):
                if (node.get("swallows") and node.get("window") and
                        any(mark.startswith("_group_" + token + "_") for mark in node.get("marks", []))):
                    self.tag_placeholder(node["window"], token)
                    lease["placeholders"][str(node["window"])] = node["id"]
            self.controller.save()
        finally:
            target.unlink(missing_ok=True)
        return True

    def launch(self, token, workspace, entry):
        lease = self.lease(token)
        route = entry.get("group_launch", {})
        if route.get("operation") != token or route.get("group") != lease["group"]:
            raise GroupError("Launch does not belong to this restore")
        number(route["group"], route["slot"], self.controller.groups)
        command = entry["command"]
        if not isinstance(command, list) or not command or not all(isinstance(arg, str) for arg in command):
            raise GroupError("Restore requires an argument array with verifiable launch identity")
        launch_id = route["token"]
        if launch_id in self.state["launches"]:
            raise GroupError("Launch token already used")
        record = dict(route, workspace=workspace, before=lease["before"], created=time.time(),
                      owner=None, window=None, done=False, session=lease.get("session"))
        self.state["launches"][launch_id] = record
        self.controller.save()
        environment = dict(os.environ, I3_GROUP_LAUNCH=launch_id, DESKTOP_STARTUP_ID=launch_id)
        directory = Path(entry["working_directory"])
        if not directory.is_dir():
            directory = Path.home()
        try:
            process = subprocess.Popen(command, cwd=directory, env=environment, start_new_session=True,
                                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.processes[launch_id] = process
            record["owner"] = [process.pid, process_identity(process.pid)]
            self.controller.save()
        except OSError:
            record["done"] = True
            self.controller.save()
            raise
        return launch_id

    def window_token(self, con):
        pending = {token for token, launch in self.state["launches"].items()
                   if not launch.get("done") and con.window not in launch["before"]}
        if not pending:
            return None
        instance = con.window_instance or ""
        startup = self.property(con.window, "_NET_STARTUP_ID")
        matches = {token for token in pending if token in (instance, startup)}
        if matches:
            return next(iter(matches)) if len(matches) == 1 else None
        # XRes returns the host PID for sandboxed clients.
        pid = self.x11_client_pid(con.window) or con.pid
        if not pid:
            property_pid = self.property(con.window, "_NET_WM_PID")
            pid = property_pid[0] if property_pid else None
        environment = []
        if pid:
            try:
                environment = Path(f"/proc/{int(pid)}/environ").read_bytes().split(b"\0")
            except (OSError, ValueError):
                pass
        matches.update(token for token in pending if ("I3_GROUP_LAUNCH=" + token).encode() in environment)
        if not matches:
            # Reused browser tokens fall back to the oldest matching launch.
            launches = self.state["launches"]
            fits = [token for token in pending if any(rule_matches(con, rule) for rule in launches[token].get("match", []))]
            return min(fits, key=lambda token: launches[token].get("created", 0), default=None)
        return next(iter(matches)) if len(matches) == 1 else None

    def route(self, con):
        if not con.window:
            return False
        token = self.window_token(con)
        if token is None:
            return False
        launch = self.state["launches"][token]
        controller = self.controller
        group, slot = launch["group"], launch["slot"]
        foreground = controller.selected()
        foreground_slot = controller.current_slot()
        tree = controller.tree()
        placeholder = next((node for node in tree.descendants()
                            if launch["mark"] in (node.marks or []) and node.ipc_data.get("swallows")), None)
        if placeholder and placeholder.window:
            controller.command(f"[con_id={con.id}] swap container with con_id {placeholder.id}")
            self.remove_placeholder(placeholder.window, launch["operation"])
        else:
            name = controller.workspace_name(group, slot)
            ws = con.workspace()
            if ws and ws.num != number(group, slot, controller.groups):
                controller.command(f"[con_id={con.id} workspace={exact(ws.name)}] move --no-auto-back-and-forth container to workspace {quote(name)}")
        moved = controller.tree().find_by_window(con.window)
        if not moved or not moved.workspace() or moved.workspace().num != number(group, slot, controller.groups):
            launch["error"] = "new window did not reach its captured destination"
        else:
            launch.update(window=moved.id, xwindow=con.window, done=True)
            controller.known[moved.id] = moved.workspace().num
            controller.overflow_seen.add(moved.id)
        controller.save()
        if foreground != group:
            controller.select(foreground, foreground_slot, force=True)
        return True

    def hidden_windows(self):
        """Unmapped, never-managed normal top-level windows."""
        from Xlib import X
        display = self.xdisplay()
        atom = display.intern_atom
        state, kind, normal = atom("WM_STATE"), atom("_NET_WM_WINDOW_TYPE"), atom("_NET_WM_WINDOW_TYPE_NORMAL")
        role, transient = atom("WM_WINDOW_ROLE"), atom("WM_TRANSIENT_FOR")
        found = []
        for window in display.screen().root.query_tree().children:
            try:
                attributes = window.get_attributes()
                types = window.get_full_property(kind, X.AnyPropertyType)
                if (attributes.override_redirect or attributes.map_state != X.IsUnmapped or
                        window.get_full_property(state, X.AnyPropertyType) or
                        window.get_full_property(transient, X.AnyPropertyType) or
                        not types or normal not in types.value):
                    continue
                instance, cls = window.get_wm_class() or ("", "")
                value = window.get_full_property(role, X.AnyPropertyType)
                found.append(SimpleNamespace(window=window.id, window_instance=instance, window_class=cls,
                                             window_role=value.value.decode(errors="replace") if value else "", pid=None))
            except Exception:
                continue
        return found

    def map_window(self, window):
        display = self.xdisplay()
        display.create_resource_object("window", window).map()
        display.flush()

    def show_stranded(self):
        """Show restore windows whose map request died with the old i3."""
        now = time.monotonic()
        hidden = {con.window: con for con in self.hidden_windows()}
        self.unmapped = {window: self.unmapped.get(window, now) for window in hidden}
        for window, seen in self.unmapped.items():
            # Hidden 2 s: not about to be shown.
            token = self.window_token(hidden[window]) if now - seen >= 2 else None
            if token and self.state["launches"][token]["created"] < self.started_at:
                self.map_window(window)
                print(f"Restore: showed window {window:#x} left hidden by an i3 restart", file=sys.stderr, flush=True)

    def maintain(self):
        session = self.state.get("session_restore")
        if session and not owner_alive(session["owner"]):
            self.session_end(session["token"])
        for operation, lease in list(self.state["leases"].items()):
            if not owner_alive(lease["owner"]):
                self.release(operation, cancelled=True)
        for token, process in list(self.processes.items()):
            if process.poll() is not None:
                self.processes.pop(token, None)
        pending = [launch for launch in self.state["launches"].values() if not launch.get("done")]
        if pending:
            for con in self.controller.tree().leaves():
                if con.window:
                    self.route(con)
            # Launches older than this controller outlived a restart.
            if time.monotonic() - self.started < 60 and any(launch["created"] < self.started_at for launch in pending):
                self.show_stranded()
        for token, launch in list(self.state["launches"].items()):
            session = self.state.get("session_restore", {})
            retained = self.session_active() and launch.get("session") == session.get("token")
            if launch.get("done") and launch["operation"] not in self.state["leases"] and not retained:
                self.state["launches"].pop(token, None)
            elif (not retained and not owner_alive(launch.get("owner")) and time.time() - launch["created"] > 120 and
                  launch["operation"] not in self.state["leases"]):
                self.state["launches"].pop(token, None)
        self.controller.save()

    def missing_launches(self, launches):
        tree = self.controller.tree()
        missing = []
        for launch in launches:
            con = tree.find_by_id(launch.get("window")) if launch.get("window") else None
            if not con and launch.get("xwindow"):
                con = tree.find_by_window(launch["xwindow"])  # Container IDs change when i3 restarts.
            if (not launch.get("done") or launch.get("error") or launch.get("transferred") or
                    not con or not con.workspace() or
                    con.workspace().num != number(launch["group"], launch["slot"])):
                missing.append(launch["workspace"])
        return sorted(set(missing))

    def ready_launches(self, launches):
        missing = self.missing_launches(launches)
        if missing:
            raise GroupError("A launched window is missing, ambiguous, or moved by the user "
                             f"(workspace {', '.join(missing)})")
        return True

    def dispatch(self, action, **values):
        if action == "session-begin":
            return self.session_begin(**values)
        if action == "session-status":
            self.session_lease(values["token"])
            return True
        if action == "session-views":
            return self.session_views(**values)
        if action in ("session-ready", "session-missing"):
            self.session_lease(values["token"])
            launches = [launch for launch in self.state["launches"].values()
                        if launch.get("session") == values["token"]]
            return self.ready_launches(launches) if action == "session-ready" else self.missing_launches(launches)
        if action == "session-end":
            self.session_end(values["token"])
            return True
        if action == "begin":
            return self.begin(**values)
        if action == "layout":
            return self.layout(**values)
        if action == "launch":
            return self.launch(**values)
        if action == "status":
            self.lease(values["token"])
            return True
        if action == "ready":
            self.lease(values["token"])
            launches = [launch for launch in self.state["launches"].values()
                        if launch["operation"] == values["token"] and launch["workspace"] == values["workspace"]]
            return self.ready_launches(launches)
        if action == "focus":
            lease = self.lease(values["token"])
            ws = next((ws for ws in self.controller.tree().workspaces() if ws.name == values["workspace"]), None)
            current = identity(ws.num, self.controller.groups) if ws else None
            if not current or current[0] != lease["group"]:
                raise GroupError("Restore focus is outside its reserved group")
            return self.controller.select(current[0], current[1])
        if action == "end":
            self.release(values["token"], values.get("cancelled", False))
            return True
        raise GroupError("Unknown restore operation")

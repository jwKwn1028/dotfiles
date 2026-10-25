#!/usr/bin/python3
"""Operation-owned restore placement and late-window routing."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import time

from workspace_groups import (GroupError, exact, identity, number, owner_alive,
                              process_identity, quote, walk)


class Restore:
    def __init__(self, controller):
        self.controller = controller
        self.processes = {}
        self.display = None

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
        return any(not lease.get("cancelled") and lease["group"] in groups
                   for lease in self.state["leases"].values())

    def lease(self, token):
        lease = self.state["leases"].get(token)
        if not lease or lease.get("cancelled") or not owner_alive(lease["owner"]):
            raise GroupError("Restore was cancelled or its owner exited")
        return lease

    def cleanup_placeholders(self, operation):
        lease = self.state["leases"].get(operation, {})
        for node in walk(self.controller.tree().ipc_data):
            if (node.get("swallows") and node.get("window") and
                    any(mark.startswith("_group_" + operation + "_") for mark in node.get("marks", []))):
                window = node["window"]
                if str(window) not in lease.get("placeholders", {}):
                    self.tag_placeholder(window, operation)
                self.remove_placeholder(window, operation)
        for window in lease.get("placeholders", {}):
            self.remove_placeholder(int(window), operation)
        lease["placeholders"] = {}

    def release(self, operation, cancelled=False):
        lease = self.state["leases"].get(operation)
        if not lease:
            return
        lease["cancelled"] = bool(cancelled or lease.get("cancelled"))
        self.controller.save()
        self.cleanup_placeholders(operation)
        self.state["leases"].pop(operation, None)
        self.controller.save()
        self.controller.resume_workers()

    def cancel_group_change(self, group):
        for operation, lease in list(self.state["leases"].items()):
            if lease["group"] != group:
                self.release(operation, cancelled=True)

    def forget_window(self, con_id):
        for launch in self.state["launches"].values():
            if launch.get("window") == con_id:
                launch["transferred"] = True
                launch["done"] = True
        self.controller.save()

    def begin(self, group, owner, token):
        number(group, 1, self.controller.groups)
        if not re.fullmatch(r"[a-f0-9]{32}", token):
            raise GroupError("Invalid restore operation identity")
        if not owner_alive(owner):
            raise GroupError("Restore owner is not alive")
        if self.state["leases"]:
            raise GroupError("Another restore owns placement")
        self.controller.cleanup_mode()
        self.controller.select(group)
        self.controller.pause_workers()
        self.state["leases"][token] = {"group": group, "owner": owner, "placeholders": {},
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
                      owner=None, window=None, done=False)
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
        instance = con.window_instance or ""
        startup = self.property(con.window, "_NET_STARTUP_ID")
        pid = con.pid
        if not pid:
            property_pid = self.property(con.window, "_NET_WM_PID")
            pid = property_pid[0] if property_pid else None
        environment = []
        if pid:
            try:
                environment = Path(f"/proc/{int(pid)}/environ").read_bytes().split(b"\0")
            except (OSError, ValueError):
                pass
        matches = []
        for token, launch in self.state["launches"].items():
            if launch.get("done") or con.window in launch["before"]:
                continue
            if (instance == token or startup == token or
                    ("I3_GROUP_LAUNCH=" + token).encode() in environment):
                matches.append(token)
        return matches[0] if len(matches) == 1 else None

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
            launch.update(window=moved.id, done=True)
            controller.known[moved.id] = moved.workspace().num
            controller.overflow_seen.add(moved.id)
        controller.save()
        if foreground != group:
            controller.select(foreground, foreground_slot, force=True)
        return True

    def maintain(self):
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
        for token, launch in list(self.state["launches"].items()):
            if launch.get("done") and launch["operation"] not in self.state["leases"]:
                self.state["launches"].pop(token, None)
            elif (not owner_alive(launch.get("owner")) and time.time() - launch["created"] > 120 and
                  launch["operation"] not in self.state["leases"]):
                self.state["launches"].pop(token, None)
        self.controller.save()

    def dispatch(self, action, **values):
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
            tree = self.controller.tree()
            for launch in launches:
                con = tree.find_by_id(launch.get("window")) if launch.get("window") else None
                if (not launch.get("done") or launch.get("error") or launch.get("transferred") or
                        not con or not con.workspace() or
                        con.workspace().num != number(launch["group"], launch["slot"])):
                    raise GroupError("A launched window is missing, ambiguous, or moved by the user")
            return True
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

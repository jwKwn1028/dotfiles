#!/usr/bin/python3
"""Serialized workspace operations for one i3 session."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

from workspace_groups import (GroupError, SCRATCH_CLASS, atomic_json, definitions, exact,
                              identity, number, owner_alive, quote, source_path)


class Controller:
    def __init__(self, i3, directory):
        self.i3 = i3
        self.directory = Path(directory)
        self.groups = definitions()
        self.path = self.directory / "state.json"
        try:
            self.state = json.loads(self.path.read_text())
            if self.state.get("version") != 1:
                raise ValueError("state version")
        except (OSError, ValueError):
            self.state = {"version": 1, "selected": None, "views": {}, "previous": {},
                          "history": [], "desktop": None, "leases": {}, "launches": {}}
        self.state.setdefault("leases", {})
        self.state.setdefault("launches", {})
        for group, index in self.state.get("definitions", {}).items():
            if group in self.groups and self.groups[group] != index:
                raise GroupError(f"Cannot renumber existing group {group}")
        self.state["definitions"] = self.groups
        self.transition = False
        self.ready = False
        self.workers = {}
        self.known = {}
        self.overflow_seen = set()
        self.last_outputs = None
        self.last_view = None
        self.mode = "default"
        self.overflow_module = None
        self.overflow_options = (0.25, True)
        self.restore = None

    def tree(self):
        tree = self.i3.get_tree()
        seen = set()
        for ws in tree.workspaces():
            if identity(ws.num, self.groups):
                if ws.num in seen:
                    raise GroupError(f"Multiple workspaces use number {ws.num}")
                seen.add(ws.num)
        return tree

    def command(self, command):
        results = self.i3.command(command)
        errors = [result.error for result in results if not result.success]
        if not results or errors:
            raise GroupError("; ".join(errors) or "No IPC reply")

    def save(self):
        atomic_json(self.path, self.state)

    def selected(self):
        group = self.state.get("selected")
        if group not in self.groups:
            focused = self.tree().find_focused()
            ws = focused.workspace() if focused else None
            current = identity(ws.num, self.groups) if ws else None
            group = current[0] if current else next(iter(self.groups))
            self.state["selected"] = group
        return group

    def outputs(self):
        outputs = [output for output in self.i3.get_outputs() if output.active and not output.name.startswith("__")]
        return sorted(outputs, key=lambda output: (not output.primary, output.name))

    def target_output(self, slot, outputs=None):
        outputs = outputs or self.outputs()
        if not outputs:
            raise GroupError("No active outputs")
        return outputs[0].name if slot <= 2 or len(outputs) == 1 else outputs[1].name

    def workspace(self, group, slot, tree=None):
        target = number(group, slot, self.groups)
        return next((ws for ws in (tree or self.tree()).workspaces() if ws.num == target), None)

    def workspace_name(self, group, slot, tree=None):
        ws = self.workspace(group, slot, tree)
        return ws.name if ws else str(number(group, slot, self.groups))

    def current_slot(self, group=None):
        group = group or self.selected()
        focused = self.tree().find_focused()
        ws = focused.workspace() if focused else None
        current = identity(ws.num, self.groups) if ws else None
        if current and current[0] == group:
            return current[1]
        return self.state["views"].get(group, {}).get("slot", 1)

    def remember(self):
        group = self.selected()
        view = self.state["views"].setdefault(group, {"outputs": {}, "slot": 1})
        multiple = len(self.outputs()) > 1
        for ws in self.i3.get_workspaces():
            current = identity(ws.num, self.groups)
            if not current or current[0] != group:
                continue
            if ws.visible and (multiple or not view.get("multi")):
                view["outputs"][ws.output] = current[1]
            if ws.focused:
                view.update(slot=current[1], output=ws.output)
        if multiple:
            view["multi"] = True
        focused = self.tree().find_focused()
        if focused and focused.window and focused.window_class != SCRATCH_CLASS:
            history = self.state["history"]
            if not history or history[0] != focused.id:
                self.state["history"] = ([focused.id] + [value for value in history if value != focused.id])[:2]
        self.save()

    def cleanup_mode(self):
        name = self.mode
        if name == "default":
            return
        helper = ("kill-workspace-mode.sh" if name.startswith("kill workspace") else
                  "bar-nav.sh" if name == " " or name.startswith("bar") else "window-mode.sh")
        path = source_path(helper)
        if path.exists():
            subprocess.run(["bash", str(path), "close"], timeout=5, check=False,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           env=dict(os.environ, I3_GROUP_TRANSITION="1"))
        self.command('mode "default"')
        self.mode = "default"
        self.state.pop("kill_group", None)

    def ensure_workspace(self, group, slot):
        name = self.workspace_name(group, slot)
        output = self.target_output(slot)
        self.command(f"focus output {quote(output)}")
        self.command(f"workspace --no-auto-back-and-forth {quote(name)}")
        self.command(f"move workspace to output {quote(output)}")
        return name

    def select(self, group, slot=None, force=False, external=False):
        number(group, slot or 1, self.groups)
        old = self.selected()
        if group == old and slot is None and not force and self.state.get("desktop") is None:
            return False
        if self.restore and group != old:
            self.restore.cancel_group_change(group)
        self.cleanup_mode()
        self.remember()
        self.transition = True
        self.ready = False
        try:
            self.state["desktop"] = None
            outputs = self.outputs()
            view = self.state["views"].get(group, {})
            wanted = {}
            used = set()
            for index, output in enumerate(outputs):
                fallback = 1 if index == 0 else min(3 + index - 1, 10)
                chosen = view.get("outputs", {}).get(output.name, fallback)
                if len(outputs) == 1:
                    chosen = slot or view.get("slot", 1)
                if chosen not in range(1, 11) or chosen in used:
                    chosen = next(value for value in [fallback, *range(1, 11)] if value not in used)
                wanted[output.name] = chosen
                used.add(chosen)
            final_slot = slot or view.get("slot", next(iter(wanted.values())))
            final_output = self.target_output(final_slot)
            if slot is None and len(outputs) > 1 and view.get("output") in wanted:
                final_output = view["output"]
                final_slot = wanted[final_output]
            if len(outputs) == 1:
                final_output = outputs[0].name
            wanted[final_output] = final_slot
            for output in wanted:
                if output != final_output and wanted[output] == final_slot:
                    wanted[output] = next(value for value in range(1, 11) if value not in wanted.values())
            tree = self.tree()
            placed = {ws.num: ws.output for ws in self.i3.get_workspaces()}
            for ws in tree.workspaces():
                current = identity(ws.num, self.groups)
                if current:
                    output = self.target_output(current[1], outputs)
                    if placed.get(ws.num) != output:
                        self.command(f"[con_id={ws.id}] move workspace to output {quote(output)}")
            for output, local in wanted.items():
                name = self.workspace_name(group, local)
                self.command(f"focus output {quote(output)}")
                self.command(f"workspace --no-auto-back-and-forth {quote(name)}")
                self.command(f"move workspace to output {quote(output)}")
            name = self.workspace_name(group, final_slot)
            self.command(f"workspace --no-auto-back-and-forth {quote(name)}")
            live = [ws for ws in self.i3.get_workspaces() if ws.visible]
            if any(not identity(ws.num, self.groups) or identity(ws.num, self.groups)[0] != group for ws in live):
                raise GroupError("Visible workspaces did not settle in the requested group")
            if group != old:
                self.state["previous_group"] = old
            self.state["selected"] = group
            self.ready = True
            self.remember()
            self.last_view = self.view_signature()
            return True
        except Exception:
            focused = self.tree().find_focused()
            ws = focused.workspace() if focused else None
            current = identity(ws.num, self.groups) if ws else None
            if current:
                self.state["selected"] = current[0]
            self.save()
            raise
        finally:
            self.transition = False

    def view_signature(self):
        return tuple((ws.name, ws.output, ws.focused) for ws in self.i3.get_workspaces() if ws.visible)

    def focus_window(self, con_id):
        con = self.tree().find_by_id(int(con_id))
        if not con or not con.window:
            raise GroupError("Window is no longer available")
        ws = con.workspace()
        current = identity(ws.num, self.groups) if ws else None
        if current:
            self.select(current[0], current[1])
        elif con.scratchpad_state == "none" and con.window_class != SCRATCH_CLASS:
            raise GroupError("Window is outside managed groups")
        self.command(f"[con_id={con.id}] focus")
        self.remember()
        return True

    def focused_window(self):
        con = self.tree().find_focused()
        if not con or not con.window or con.window_class == SCRATCH_CLASS:
            raise GroupError("Focus one ordinary window first")
        ws = con.workspace()
        current = identity(ws.num, self.groups) if ws else None
        if not current or con.scratchpad_state not in (None, "none"):
            raise GroupError("Window is outside managed groups")
        return con, ws, current

    def move(self, con_id, source_name, group, slot, transfer=False, follow=True):
        tree = self.tree()
        con = tree.find_by_id(con_id)
        ws = con.workspace() if con else None
        source = identity(ws.num, self.groups) if ws else None
        if not con or not con.window or not source or ws.name != source_name:
            raise GroupError("Window source changed; move cancelled")
        if not transfer and source[0] != group:
            raise GroupError("Ordinary moves cannot cross groups")
        target = number(group, slot, self.groups)
        if target == ws.num:
            return False
        if self.restore and self.restore.reserved(source[0], group):
            raise GroupError("Finish or cancel the active restore before moving this window")
        name = self.workspace_name(group, slot, tree)
        self.command(f"[con_id={con_id} workspace={exact(source_name)}] move --no-auto-back-and-forth container to workspace {quote(name)}")
        moved = self.tree().find_by_id(con_id)
        if not moved or moved.workspace().num != target:
            raise GroupError("i3 did not complete the requested move")
        self.known[con_id] = target
        self.overflow_seen.discard(con_id)
        if transfer and self.restore:
            self.restore.forget_window(con_id)
        if follow:
            self.select(group, slot)
            self.command(f"[con_id={con_id}] focus")
            self.overflow(con_id, target, *self.overflow_options)
        self.remember()
        return True

    def placement_allowed(self, con_id=None, workspace=None):
        if not self.ready or self.transition:
            return False
        if con_id is not None:
            con = self.tree().find_by_id(int(con_id))
            if not con or not con.workspace():
                return False
            if self.restore and self.restore.window_token(con):
                return False
            workspace = con.workspace().num
        current = identity(workspace, self.groups)
        return bool(current and not (self.restore and self.restore.reserved(current[0])))

    def overflow(self, con_id, source_num, fraction=0.25, follow=True):
        self.overflow_options = (fraction, follow)
        if not self.placement_allowed(con_id) or con_id in self.overflow_seen:
            return False
        tree = self.tree()
        con = tree.find_by_id(con_id)
        ws = con.workspace() if con else None
        source = identity(source_num, self.groups)
        if not con or not ws or ws.num != source_num or not source:
            return False
        if self.overflow_module is None:
            spec = importlib.util.spec_from_file_location("group_overflow", source_path("overflow-watcher.py"))
            self.overflow_module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.overflow_module)
        module = self.overflow_module
        if module.is_floating(con) or con.fullscreen_mode or module.area(ws) <= 0:
            return False
        if module.area(con) >= (fraction - module.EPSILON) * module.area(ws):
            return False
        candidates = module.wrap_order(source_num)
        occupied = {other.num: module.workspace_has_room(other, fraction) for other in tree.workspaces()
                    if other.num in candidates and other.leaves()}
        ordered = [num for num in candidates if occupied.get(num)] + [num for num in candidates if num not in occupied]
        self.overflow_seen.add(con_id)
        if not ordered:
            print(f"Overflow: group {source[0]} is full; window {con_id} stays on slot {source[1]}",
                  file=sys.stderr, flush=True)
            return False
        target = ordered[0]
        destination = next((value for value in tree.workspaces() if value.num == target), None)
        name = destination.name if destination else str(target)
        self.command(f"[con_id={con_id} workspace={exact(ws.name)}] move --no-auto-back-and-forth container to workspace {quote(name)}")
        moved = self.tree().find_by_id(con_id)
        if not moved or not moved.workspace() or moved.workspace().num != target:
            return False
        self.known[con_id] = target
        if follow and self.selected() == source[0]:
            self.select(source[0], identity(target, self.groups)[1])
            self.command(f"[con_id={con_id}] focus")
            self.peek()
        self.remember()
        return True

    def peek(self):
        path = Path(os.environ.get("I3_GROUP_PEEK", source_path("polybar-peek.sh")))
        if path.exists():
            subprocess.Popen([str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def dispatch(self, action, **values):
        self.tree()
        group = self.selected()
        changed = False
        if action == "status":
            return self.status()
        if action == "placement":
            return self.placement_allowed(values.get("con_id", values.get("value")), values.get("workspace"))
        if action.startswith("restore-"):
            return self.restore.dispatch(action[8:], **values)
        if action == "overflow":
            return self.overflow(**values)
        if action == "reconcile":
            return self.select(group, force=True)
        if action == "select":
            changed = self.select(values["group"])
        elif action == "group-previous":
            target = self.state.get("previous_group")
            if target not in self.groups or target == group:
                return False
            changed = self.select(target)
        elif action in ("group-relative", "transfer"):
            current = group
            if action == "transfer":
                con, ws, source = self.focused_window()
                current = source[0]
            names = list(self.groups)
            target = names.index(current) + int(values["value"])
            if not 0 <= target < len(names):
                return False
            if action == "transfer":
                changed = self.move(con.id, ws.name, names[target], source[1], transfer=True)
            else:
                changed = self.select(names[target])
        elif action in ("switch", "relative", "cycle", "prev", "next", "move", "move-relative"):
            if values.get("group") and values["group"] != group:
                return False
            slot = self.current_slot()
            if action in ("move", "move-relative"):
                con, ws, source = self.focused_window()
                group, slot = source
            target = int(values.get("value", 0))
            if action in ("relative", "cycle", "move-relative"):
                target = slot + target
                if action != "relative":
                    target = (target - 1) % 10 + 1
            if action in ("prev", "next"):
                slots = sorted(identity(ws.num, self.groups)[1] for ws in self.tree().workspaces()
                               if identity(ws.num, self.groups) and identity(ws.num, self.groups)[0] == group)
                if len(slots) < 2:
                    return False
                target = slots[(slots.index(slot) + (1 if action == "next" else -1)) % len(slots)]
            if not 1 <= target <= 10:
                return False
            if action in ("move", "move-relative"):
                changed = self.move(con.id, ws.name, group, target)
            else:
                if target == slot:
                    if action != "switch" or values.get("click"):
                        return False
                    target = self.state["previous"].get(group)
                    if target is None or target == slot:
                        return False
                changed = self.select(group, target)
                if changed:
                    self.state["previous"][group] = slot
        elif action == "focus":
            changed = self.focus_window(values["value"])
        elif action == "previous-window":
            history = self.state["history"]
            if len(history) > 1:
                changed = self.focus_window(history[1])
        elif action == "desktop":
            context = self.state.get("desktop")
            if context:
                changed = self.select(context["group"], context["slot"])
            else:
                self.remember()
                context = {"group": group, "slot": self.current_slot()}
                self.command('workspace --no-auto-back-and-forth "_desktop"')
                self.state["desktop"] = context
                changed = True
        elif action == "kill-begin":
            self.state["kill_group"] = group
        elif action == "kill":
            if self.state.get("kill_group") != group:
                self.cleanup_mode()
                return False
            ws = self.workspace(group, int(values["value"]))
            if ws:
                self.command(f"[workspace={exact(ws.name)}] kill")
            self.command('mode "default"')
            self.state.pop("kill_group", None)
        elif action in ("kill-group", "kill-all-groups"):
            scope = self.state.get("kill_group")
            if scope is None or (action == "kill-group" and scope != group):
                self.cleanup_mode()
                return False
            windows = [con.id for ws in self.tree().workspaces()
                       if identity(ws.num, self.groups) and
                       (action == "kill-all-groups" or identity(ws.num, self.groups)[0] == group)
                       for con in ws.leaves() if con.window and con.window_class != SCRATCH_CLASS]
            if windows:
                self.command("; ".join(f"[con_id={con_id}] kill" for con_id in windows))
            self.state.pop("kill_group", None)
        elif action in ("direction", "output"):
            con, ws, source = self.focused_window()
            visible = self.i3.get_workspaces()
            if any(not identity(value.num, self.groups) or identity(value.num, self.groups)[0] != source[0]
                   for value in visible if value.visible):
                raise GroupError("Outputs must show the same group before moving a window")
            if self.restore and self.restore.reserved(source[0]):
                raise GroupError("Window belongs to an active restore")
            if action == "direction":
                direction = values["value"]
                if direction not in ("left", "right", "up", "down"):
                    raise GroupError("Invalid direction")
                self.command(f"[con_id={con.id} workspace={exact(ws.name)}] move {direction}")
            else:
                self.command(f"[con_id={con.id} workspace={exact(ws.name)}] move container to output next")
                self.command(f"[con_id={con.id}] focus")
            self.remember()
        else:
            raise GroupError(f"Unknown workspace action: {action}")
        self.save()
        if changed and not values.get("quiet") and action != "cycle":
            self.peek()
        return changed

    def bar_status(self):
        status = self.status()
        status["windows"] = [{"group": window["group"]} for window in status["windows"]]
        return status

    def status(self):
        return {"selected": self.selected(), "groups": self.groups, "ready": self.ready,
                "workspaces": [dict(name=ws.name, num=ws.num, focused=ws.focused,
                                    visible=ws.visible, urgent=ws.urgent, output=ws.output)
                               for ws in self.i3.get_workspaces()],
                "windows": [{"id": con.id, "name": con.name or "", "class": con.window_class or "",
                             "instance": con.window_instance or "",
                             "group": identity(con.workspace().num, self.groups)}
                            for con in self.tree().leaves() if con.window and con.workspace() and
                            identity(con.workspace().num, self.groups) and con.window_class != SCRATCH_CLASS]}

    def initialize(self):
        tree = self.tree()
        self.known = {con.id: ws.num for ws in tree.workspaces() for con in ws.leaves()}
        focused = tree.find_focused()
        ws = focused.workspace() if focused else None
        current = identity(ws.num, self.groups) if ws else None
        if current and not (focused.window and self.restore and self.restore.window_token(focused)):
            self.state["selected"] = current[0]
        if hasattr(self.i3, "get_binding_state"):
            self.mode = self.i3.get_binding_state().name
        self.selected()
        self.select(self.selected(), force=True)
        self.last_outputs = tuple(output.name for output in self.outputs())

    def on_event(self, kind, change, con_id=None):
        if kind == "mode":
            self.mode = change
            return
        if kind == "output" or change == "reload":
            self.select(self.selected(), force=True)
            return
        tree = self.tree()
        con = tree.find_by_id(con_id) if con_id else None
        if kind == "window" and change == "close":
            self.known.pop(con_id, None)
            self.overflow_seen.discard(con_id)
        if kind == "window" and change == "new" and con:
            ws = con.workspace()
            current = identity(ws.num, self.groups) if ws else None
            if self.restore and self.restore.route(con):
                return
            self.known[con.id] = ws.num if ws else None
            self.overflow_seen.discard(con.id)
            if current and current[0] != self.selected() and con.focused:
                self.select(self.selected(), force=True)
                return
        if change == "focus":
            focused = tree.find_focused()
            if kind == "window" and (not focused or focused.id != con_id):
                return
            ws = focused.workspace() if focused else None
            current = identity(ws.num, self.groups) if ws else None
            if current and current[0] != self.selected():
                self.select(current[0], current[1], external=True)
            elif current:
                self.remember()
        if kind == "workspace" and change in ("move", "rename", "init", "empty"):
            if self.view_signature() != self.last_view and not self.state.get("desktop"):
                visible = self.i3.get_workspaces()
                if any(identity(ws.num, self.groups) and identity(ws.num, self.groups)[0] != self.selected()
                       for ws in visible if ws.visible):
                    self.select(self.selected(), force=True)
        self.last_view = self.view_signature()

    def pause_workers(self, all_workers=False):
        import signal
        targets = {name: process for name, process in self.workers.items() if all_workers or name != "overflow"}
        for process in targets.values():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
        for process in targets.values():
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=1)
        for name in targets:
            self.workers.pop(name, None)
        self.record_workers()

    def record_workers(self):
        from workspace_groups import process_identity
        self.state["workers"] = {name: [process.pid, process_identity(process.pid)]
                                 for name, process in self.workers.items()}
        self.save()

    def recover_workers(self):
        import signal
        for owner in self.state.get("workers", {}).values():
            if owner_alive(owner):
                try:
                    os.killpg(owner[0], signal.SIGTERM)
                except ProcessLookupError:
                    pass
        self.state["workers"] = {}
        self.save()

    def resume_workers(self):
        if os.environ.get("I3_GROUP_WORKERS", "1") == "0":
            return
        commands = {"overflow": ["/usr/bin/python3", str(source_path("overflow-watcher.py"))]}
        if not self.state["leases"]:
            commands.update(snap=["bash", str(source_path("snap-watcher.sh"))],
                            autotiling=[str(Path.home() / ".local/bin/autotiling")])
        for name, command in commands.items():
            if name in self.workers and self.workers[name].poll() is None:
                continue
            if not Path(command[-1]).exists():
                continue
            self.workers[name] = subprocess.Popen(command, start_new_session=True,
                                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.record_workers()

#!/usr/bin/python3
"""Scratch-terminal centering after mapping, resizing, and monitor changes."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scratch-terminal.sh"
if not SCRIPT.exists():
    SCRIPT = ROOT / "executable_scratch-terminal.sh"

MOCK = r'''#!/usr/bin/python3
import fcntl, json, os, pathlib, sys
path = pathlib.Path(os.environ["SCRATCH_TEST_STATE"])
lock = path.with_suffix(".lock").open("w")
fcntl.flock(lock, fcntl.LOCK_EX)
state = json.loads(path.read_text())
if pathlib.Path(sys.argv[0]).name == "ghostty":
    state.update(exists=True, visible=False)
elif sys.argv[1:] == ["-t", "get_tree"]:
    state["reads"] += 1
    state["visible_reads"] += int(state["visible"])
    if state.get("resize") and state["reads"] == 3:
        state.update(width=1100, height=646)
    rect = dict(x=1920, y=28, width=1920, height=1172) if state["visible"] else dict(x=0,y=0,width=0,height=0)
    nodes = [dict(id=99, window=100, window_properties=dict(
        **{"class":"com.mitchellh.ghostty.scratchpad"}),
        rect=dict(x=state["x"],y=state["y"],width=state["width"],height=state["height"]))] if state["exists"] else []
    print(json.dumps(dict(type="workspace", name="2" if state["visible"] else "__i3_scratch",
                         rect=rect, nodes=nodes)))
elif sys.argv[1:] == ["-t", "get_workspaces"]:
    print('[{"name":"2","visible":true,"focused":true}]')
else:
    command = sys.argv[1]
    state["commands"].append(command)
    if "scratchpad show" in command:
        state["visible"] = True
    elif "move scratchpad" in command:
        state["visible"] = False
    if "move position center" in command:
        state["centers"] += 1
        state["x"] = 1920 + (1920 - state["width"]) // 2
        state["y"] = 28 + (1172 - state["height"]) // 2
    print('[{"success":true}]')
path.write_text(json.dumps(state))
'''


class ScratchTests(unittest.TestCase):
    def run_terminal(self, exists=True, visible=False, resize=False):
        with tempfile.TemporaryDirectory() as name:
            directory = Path(name)
            script = directory / "scratch-terminal.sh"
            script.write_text(SCRIPT.read_text())
            state_path = directory / "state.json"
            state_path.write_text(json.dumps(dict(exists=exists, visible=visible, resize=resize,
                                                 reads=0, visible_reads=0, commands=[], centers=0, x=1428, y=-323, width=984, height=646)))
            for command in ("i3-msg", "ghostty"):
                path = directory / command
                path.write_text(MOCK)
                path.chmod(0o755)
            environment = dict(os.environ, PATH=str(directory) + ":/usr/bin:/bin",
                               XDG_RUNTIME_DIR=str(directory), SCRATCH_TEST_STATE=str(state_path))
            result = subprocess.run(["bash", str(script)], env=environment, text=True,
                                    capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(state_path.read_text())

    def assert_centered(self, state):
        self.assertTrue(state["visible"])
        self.assertEqual(state["centers"], 1)
        self.assertEqual(state["x"], 1920 + (1920 - state["width"]) // 2)
        self.assertEqual(state["y"], 28 + (1172 - state["height"]) // 2)

    def test_reveal_recenters_in_offset_laptop_workspace(self):
        state = self.run_terminal()
        self.assert_centered(state)
        self.assertEqual((state["width"], state["height"]), (984, 646))

    def test_new_window_settles_hidden_and_is_revealed_once(self):
        state = self.run_terminal(exists=False)
        self.assert_centered(state)
        self.assertEqual(state["visible_reads"], 0)
        self.assertEqual(sum("scratchpad show" in command for command in state["commands"]), 1)
        self.assertIn("move position center", state["commands"][-1])

    def test_late_resize_is_recentered(self):
        state = self.run_terminal(exists=False, resize=True)
        self.assert_centered(state)
        self.assertEqual(state["width"], 1100)

    def test_visible_window_only_hides(self):
        state = self.run_terminal(visible=True)
        self.assertFalse(state["visible"])
        self.assertEqual(state["centers"], 0)


if __name__ == "__main__":
    unittest.main()

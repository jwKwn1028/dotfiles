#!/usr/bin/env python3

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / "dot_zsh/rc.d/20-helix-mode.zsh"
if not MODULE.exists():
    MODULE = Path.home() / ".zsh/rc.d/20-helix-mode.zsh"
PROMPT = "clear-test>"


@unittest.skipUnless(shutil.which("zsh") and shutil.which("tmux"), "zsh or tmux is not installed")
class ClearScreenTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / ".zshrc").write_text(f'source "{MODULE}"\nPS1="{PROMPT} "\n')
        self.socket = f"clear-test-{os.getpid()}"
        self.addCleanup(self.tmux, "kill-server", check=False)

    def tmux(self, *arguments, check=True):
        return subprocess.run(["tmux", "-L", self.socket, "-f", "/dev/null", *arguments],
                              capture_output=True, text=True, check=check).stdout

    def wait_for(self, condition, message):
        deadline = time.monotonic() + 5
        while not condition():
            if time.monotonic() > deadline:
                self.fail(f"{message}: {self.screen()!r}")
            time.sleep(0.05)

    def screen(self):
        return self.tmux("capture-pane", "-p", "-t", "t").rstrip("\n")

    def history(self):
        return int(self.tmux("display-message", "-p", "-t", "t", "#{history_size}"))

    def test_ctrl_l_clears_screen_and_scrollback(self):
        for scroll_on_clear in ("off", "on"):
            with self.subTest(scroll_on_clear=scroll_on_clear):
                self.tmux("kill-server", check=False)
                self.tmux("new-session", "-d", "-s", "t", "-x", "60", "-y", "10",
                          f"env -i PATH={os.environ['PATH']} TERM=tmux-256color "
                          f"HOME={self.root} ZDOTDIR={self.root} zsh -d")
                self.tmux("set", "-g", "scroll-on-clear", scroll_on_clear)
                self.wait_for(lambda: PROMPT in self.screen(), "No prompt")
                self.tmux("send-keys", "-t", "t", "for i in {1..30}; do print old-$i; done", "Enter")
                self.wait_for(lambda: self.history() > 0 and self.screen().endswith(PROMPT),
                              "Output did not scroll")
                self.tmux("send-keys", "-t", "t", "C-l")
                self.wait_for(lambda: self.screen() == PROMPT and self.history() == 0,
                              f"history={self.history()}")


if __name__ == "__main__":
    unittest.main()

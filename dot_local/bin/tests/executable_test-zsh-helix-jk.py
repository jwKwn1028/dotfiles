#!/usr/bin/env python3
"""jk leaves insert mode when typed, but stays text in tmux send-keys bursts."""

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
PLUGIN = Path.home() / ".zsh/plugins/zsh-helix-mode"
PROMPT = "jk-test>"


@unittest.skipUnless(shutil.which("zsh") and shutil.which("tmux"), "zsh or tmux is not installed")
@unittest.skipUnless((PLUGIN / "zsh-helix-mode.plugin.zsh").exists(), "zsh-helix-mode is not installed")
class JkTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / ".zsh/plugins").mkdir(parents=True)
        (self.root / ".zsh/plugins/zsh-helix-mode").symlink_to(PLUGIN)
        (self.root / ".zshrc").write_text(f'source "{MODULE}"\nPS1="{PROMPT} "\n')
        self.socket = f"jk-test-{os.getpid()}"
        self.addCleanup(self.tmux, "kill-server", check=False)
        self.tmux("new-session", "-d", "-s", "t", "-x", "80", "-y", "10",
                  f"env -i PATH={os.environ['PATH']} TERM=tmux-256color "
                  f"HOME={self.root} ZDOTDIR={self.root} zsh -d")
        self.wait_for(lambda: PROMPT in self.screen(), "No prompt")

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

    def cursor(self):
        return self.tmux("display-message", "-p", "-t", "t", "#{cursor_shape}").strip()

    def test_send_keys_burst_keeps_jk(self):
        # Like tmux-resurrect: the command and C-m in one send-keys.
        self.tmux("send-keys", "-t", "t", "print -r -- out:1jki2jk", "C-m")
        self.wait_for(lambda: "\nout:" in self.screen(), "Command did not run")
        self.assertIn("\nout:1jki2jk\n", self.screen() + "\n")

    def test_burst_before_the_prompt_keeps_jk(self):
        # Sent before zsh has drawn its prompt.
        self.tmux("new-window", "-t", "t:2",
                  f"env -i PATH={os.environ['PATH']} TERM=tmux-256color "
                  f"HOME={self.root} ZDOTDIR={self.root} zsh -d")
        self.tmux("send-keys", "-t", "t:2", "print -r -- out:early-jki-jk", "C-m")
        screen = lambda: self.tmux("capture-pane", "-p", "-t", "t:2")
        deadline = time.monotonic() + 5
        while "\nout:" not in screen():
            self.assertLess(time.monotonic(), deadline, screen())
            time.sleep(0.05)
        self.assertIn("\nout:early-jki-jk\n", screen())

    def test_typed_jk_returns_to_normal_mode(self):
        self.tmux("send-keys", "-t", "t", "-l", "print -r -- out:typed")
        self.wait_for(lambda: self.screen().endswith("out:typed"), "Text not drawn")
        self.wait_for(lambda: self.cursor() == "bar", "Not in insert mode")
        for key in "jk":
            self.tmux("send-keys", "-t", "t", "-l", key)
            time.sleep(0.1)
        self.wait_for(lambda: self.cursor() == "block", "jk did not enter normal mode")
        self.tmux("send-keys", "-t", "t", "Enter")
        self.wait_for(lambda: "\nout:" in self.screen(), "Command did not run")
        self.assertIn("\nout:typed\n", self.screen() + "\n")


if __name__ == "__main__":
    unittest.main()

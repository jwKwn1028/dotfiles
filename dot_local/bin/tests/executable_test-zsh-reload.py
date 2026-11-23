#!/usr/bin/env python3

import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import termios
import time
import unittest


ROOT = Path(__file__).resolve().parents[3]
MODULE = ROOT / "dot_zsh/rc.d/31-reload.zsh"
if not MODULE.exists():
    MODULE = Path.home() / ".zsh/rc.d/31-reload.zsh"
PROMPT = b"reload-test> "


def terminal_session():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


class Shell:
    def __init__(self, environment):
        self.fd, slave = pty.openpty()
        self.process = subprocess.Popen([shutil.which("zsh"), "-d"], env=environment,
                                        stdin=slave, stdout=slave, stderr=slave,
                                        preexec_fn=terminal_session)
        os.close(slave)
        try:
            self.read_prompt()
        except BaseException:
            self.close()
            raise

    def read_prompt(self):
        output = b""
        deadline = time.monotonic() + 5
        while PROMPT not in output:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.fd], [], [], remaining)[0]:
                raise AssertionError(f"No prompt: {output!r}")
            chunk = os.read(self.fd, 65536)
            if not chunk:
                raise AssertionError(f"Shell exited: {output!r}")
            output += chunk
        return output.decode(errors="replace")

    def send(self, command):
        os.write(self.fd, command.encode() + b"\n")

    def command(self, command):
        self.send(command)
        return self.read_prompt()

    def close(self):
        if self.process.poll() is None:
            self.send("kill -CONT %1 2>/dev/null; kill %1 2>/dev/null; exit")
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        os.close(self.fd)


@unittest.skipUnless(shutil.which("zsh"), "zsh is not installed")
class ReloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        modules = self.root / ".zsh/rc.d"
        modules.mkdir(parents=True)
        shutil.copyfile(MODULE, modules / MODULE.name)
        (self.root / "runtime").mkdir()
        (self.root / "work").mkdir()
        (self.root / ".zshrc").write_text(
            'export RELOAD_TEST_COUNT=$(( ${RELOAD_TEST_COUNT:-0} + 1 ))\n'
            'HISTFILE=$HOME/history; HISTSIZE=100; SAVEHIST=100\n'
            'source "$HOME/.zsh/rc.d/31-reload.zsh"\n'
            'PS1="reload-test> "\n'
            'print -r -- "START:$RELOAD_TEST_COUNT"\n')
        self.environment = dict(PATH=os.environ["PATH"], HOME=str(self.root),
                                ZDOTDIR=str(self.root), XDG_RUNTIME_DIR=str(self.root / "runtime"),
                                TERM="dumb", TMUX="test-server,1,0")
        self.marker = self.root / f"runtime/zsh-reload-{os.geteuid()}/request"

    def shell(self, **changes):
        shell = Shell(dict(self.environment, **changes))
        self.addCleanup(shell.close)
        return shell

    def test_one_request_reloads_existing_local_shells_once(self):
        first, second = self.shell(), self.shell()
        second.command('cd "$HOME/work"; export KEEP=kept; print -s history-kept')
        self.assertIn("START:2", first.command("sz-all"))
        self.assertIn("START:2", second.command(":"))
        output = second.command('print -r -- "$PWD|$KEEP"')
        self.assertIn(f"{self.root}/work|kept", output)
        self.assertIn("history-kept", (self.root / "history").read_text())
        self.assertNotIn("START:", second.command(":"))
        self.assertNotIn("START:", self.shell().command(":"))

    def test_foreground_command_finishes_before_reload(self):
        first, second = self.shell(), self.shell()
        second.send("sleep 0.3; print FINISHED")
        first.command("sz-all")
        output = second.read_prompt()
        self.assertIn("START:2", output)
        self.assertLess(output.rindex("FINISHED"), output.index("START:2"))

    def test_running_and_stopped_jobs_defer_reload(self):
        for stopped in (False, True):
            with self.subTest(stopped=stopped):
                first, second = self.shell(), self.shell()
                second.command("sleep 1 &" + (" kill -STOP $!; sleep 0.05" if stopped else ""))
                first.command("sz-all")
                self.assertNotIn("START:", second.command(":"))
                output = second.command("kill -CONT %1; wait" if stopped else "wait")
                self.assertIn("START:2", output)

    def test_ssh_shells_and_shells_outside_tmux_do_not_reload(self):
        first = self.shell()
        excluded = [self.shell(**{name: "remote"}) for name in ("SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY")]
        excluded.append(self.shell(TMUX=""))
        first.command("sz-all")
        for shell in excluded:
            self.assertNotIn("START:", shell.command(":"))
        marker = self.marker.read_bytes()
        for shell in excluded[:-1]:
            self.assertIn("run from a local interactive shell", shell.command("sz-all"))
            self.assertEqual(self.marker.read_bytes(), marker)

    def test_invalid_syntax_does_not_publish_a_request(self):
        first = self.shell()
        broken = self.root / ".zsh/rc.d/99-broken.zsh"
        broken.write_text("if then\n")
        self.assertIn("fix the syntax error", first.command("sz-all"))
        self.assertFalse(self.marker.exists())
        broken.unlink()
        self.assertIn("START:2", first.command("sz-all"))

    def test_delayed_shell_rechecks_syntax_without_repeated_errors(self):
        first, second = self.shell(), self.shell()
        first.command("sz-all")
        broken = self.root / ".zsh/rc.d/99-broken.zsh"
        broken.write_text("if then\n")
        output = second.command(":")
        self.assertIn("fix the syntax error", output)
        self.assertNotIn("START:", output)
        self.assertNotIn("fix the syntax error", second.command(":"))
        broken.unlink()
        first.command("sz-all")
        self.assertIn("START:2", second.command(":"))


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Exercise the real shell wrappers on a PTY with a mocked shutdown backend."""

import errno
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[3]
BIN_DIR = Path(__file__).resolve().parents[1]


def source_path(source, target):
    path = ROOT / source
    return path if path.exists() else ROOT / target


class PoweroffConfirmationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shells = {}
        for shell, source, target in [
            ("bash", "dot_bashrc", ".bashrc"),
            ("zsh", "dot_zsh/rc.d/30-aliases.zsh", ".zsh/rc.d/30-aliases.zsh"),
        ]:
            executable = shutil.which(shell)
            if executable is None:
                raise RuntimeError(f"{shell} is required for these tests")
            # Read only the real wrapper, avoiding unrelated shell startup actions.
            text = source_path(source, target).read_text()
            match = re.search(r"^poweroff\(\) \{\n.*?^\}", text, re.M | re.S)
            if match is None:
                raise RuntimeError(f"poweroff wrapper missing from {source}")
            flags = ["--noprofile", "--norc"] if shell == "bash" else ["-df"]
            cls.shells[shell] = [
                executable, *flags, "-c", match.group() + '\npoweroff "$@"', shell,
            ]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="poweroff-confirm-test-")
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        mock_bin = directory / "bin"
        mock_bin.mkdir()
        helper = BIN_DIR / "executable_poweroff-confirm"
        if not helper.exists():
            helper = BIN_DIR / "poweroff-confirm"
        shutil.copyfile(helper, mock_bin / "poweroff-confirm")
        (mock_bin / "bash").symlink_to(shutil.which("bash"))
        (mock_bin / "hostname").write_text("#!/bin/sh\nprintf 'test-host\\n'\n")
        (mock_bin / "systemctl").write_text(
            '#!/bin/sh\nprintf "%s\\n" "$*" >>"$POWER_ACTION_LOG"\n'
            'exit "${POWER_ACTION_STATUS:-0}"\n'
        )
        for name in ["poweroff-confirm", "hostname", "systemctl"]:
            (mock_bin / name).chmod(0o755)
        self.log = directory / "actions"
        self.env = {
            **os.environ, "PATH": str(mock_bin), "POWER_ACTION_LOG": str(self.log),
            "POWER_ACTION_STATUS": "0",
        }
        # Prevent inherited shell injection from bypassing the mock backend.
        self.env.pop("BASH_ENV", None)
        self.env.pop("ENV", None)
        for key in list(self.env):
            if key.startswith("BASH_FUNC_"):
                self.env.pop(key)

    def actions(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def run_terminal(self, shell, answer=None, action_status=0):
        self.log.unlink(missing_ok=True)
        env = {**self.env, "POWER_ACTION_STATUS": str(action_status)}
        started = time.monotonic()
        pid, master = pty.fork()
        if pid == 0:
            try:
                signal.signal(signal.SIGINT, signal.SIG_DFL)
                os.execve(self.shells[shell][0], self.shells[shell], env)
            finally:
                os._exit(127)
        output = bytearray()
        sent = False
        reaped = False
        try:
            while time.monotonic() - started < 15:
                if select.select([master], [], [], 0.05)[0]:
                    try:
                        output.extend(os.read(master, 4096))
                    except OSError as exc:
                        if exc.errno != errno.EIO:
                            raise
                if not sent and b"(10s timeout): " in output:
                    self.assertIn(b"Power off test-host? [y/N]", output)
                    if answer is not None:
                        os.write(master, answer)
                    sent = True
                finished, status = os.waitpid(pid, os.WNOHANG)
                if finished:
                    reaped = True
                    self.assertTrue(sent, output.decode(errors="replace"))
                    return os.waitstatus_to_exitcode(status), bytes(output), time.monotonic() - started
            self.fail(f"{shell}: confirmation failed to exit within 15 seconds")
        finally:
            if not reaped:
                os.killpg(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(master)

    def test_explicit_confirmation(self):
        for shell in self.shells:
            for answer in [b"y\n", b"Y\n", b"yes\n", b"YES\n", b"YeS\n"]:
                with self.subTest(shell=shell, answer=answer):
                    status, _, _ = self.run_terminal(shell, answer)
                    self.assertEqual(status, 0)
                    self.assertEqual(self.actions(), ["poweroff"])

    def test_blank_no_and_unrecognized_input_cancel(self):
        for shell in self.shells:
            for answer in [b"\n", b"n\n", b"no\n", b"yes please\n"]:
                with self.subTest(shell=shell, answer=answer):
                    status, _, _ = self.run_terminal(shell, answer)
                    self.assertEqual(status, 1)
                    self.assertEqual(self.actions(), [])

    def test_timeout_and_partial_input_cancel(self):
        for shell in self.shells:
            for answer in [None, b"y"]:
                with self.subTest(shell=shell, answer=answer):
                    status, output, elapsed = self.run_terminal(shell, answer)
                    self.assertEqual(status, 1)
                    self.assertGreaterEqual(elapsed, 9)
                    self.assertIn(b"No confirmation received; cancelled.", output)
                    self.assertEqual(self.actions(), [])

    def test_ctrl_c_cancels(self):
        for shell in self.shells:
            with self.subTest(shell=shell):
                status, _, _ = self.run_terminal(shell, b"y\x03")
                self.assertIn(status, [130, -signal.SIGINT])
                self.assertEqual(self.actions(), [])

    def test_eof_cancels(self):
        for shell in self.shells:
            with self.subTest(shell=shell):
                status, _, _ = self.run_terminal(shell, b"\x04")
                self.assertEqual(status, 1)
                self.assertEqual(self.actions(), [])

    def test_systemctl_failure_propagates(self):
        for shell in self.shells:
            with self.subTest(shell=shell):
                status, _, _ = self.run_terminal(shell, b"yes\n", action_status=42)
                self.assertEqual(status, 42)
                self.assertEqual(self.actions(), ["poweroff"])

    def test_missing_terminal_ignores_piped_confirmation(self):
        for shell in self.shells:
            with self.subTest(shell=shell):
                result = subprocess.run(
                    self.shells[shell], input="yes\n", env=self.env,
                    capture_output=True, text=True, start_new_session=True, timeout=3,
                )
                self.assertEqual(result.returncode, 1)
                self.assertIn("requires a controlling terminal", result.stderr)
                self.assertEqual(self.actions(), [])

    def test_arguments_are_rejected(self):
        for shell in self.shells:
            for args in [["--force"], ["now"], ["--", "now"]]:
                with self.subTest(shell=shell, args=args):
                    result = subprocess.run(
                        [*self.shells[shell], *args], env=self.env, capture_output=True,
                        text=True, start_new_session=True, timeout=3,
                    )
                    self.assertEqual(result.returncode, 2)
                    self.assertIn("accepts no arguments", result.stderr)
                    self.assertEqual(self.actions(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)

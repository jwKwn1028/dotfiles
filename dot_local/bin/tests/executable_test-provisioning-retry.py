#!/usr/bin/python3
"""Check package sources and retry behavior using isolated chezmoi state."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[3]
if not (ROOT / ".chezmoidata/packages.toml").is_file() and shutil.which("chezmoi"):
    result = subprocess.run(["chezmoi", "source-path"], text=True, capture_output=True)
    if result.returncode == 0:
        ROOT = Path(result.stdout.strip())


class ProvisioningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.chezmoi = shutil.which("chezmoi")
        manifest = ROOT / ".chezmoidata/packages.toml"
        if not cls.chezmoi or not manifest.is_file():
            raise unittest.SkipTest("chezmoi source state is unavailable")
        cls.packages = tomllib.loads(manifest.read_text())["packages"]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="provisioning-retry-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.destination = self.root / "destination"
        self.bin = self.root / "bin"
        for directory in (self.source, self.destination, self.bin):
            directory.mkdir()
        self.config = self.root / "config.toml"
        self.config.write_text("")
        self.log = self.root / "attempts"
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin",
                        ATTEMPT_LOG=str(self.log), SIMULATE_FAILURE="0")
        mock = self.bin / "flatpak"
        mock.write_text(
            '#!/bin/sh\n'
            'if [ "$1" = install ]; then\n'
            '  printf "%s\\n" "$*" >> "$ATTEMPT_LOG"\n'
            '  [ "$SIMULATE_FAILURE" = 0 ] || exit 42\n'
            'fi\nexit 0\n'
        )
        mock.chmod(0o755)

    def command(self, source):
        return [self.chezmoi, "--config", str(self.config), "--source", str(source),
                "--destination", str(self.destination), "--persistent-state",
                str(self.root / "state.boltdb"), "--cache", str(self.root / "cache")]

    def render(self, machine_class="desktop"):
        template = ROOT / "run_once_after_20-install-flatpaks.sh.tmpl"
        result = subprocess.run(
            self.command(ROOT) + ["execute-template", "--override-data",
                                  json.dumps({"class": machine_class})],
            input=template.read_text(), text=True, capture_output=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        script = self.source / "run_once_after_20-install-flatpaks.sh"
        script.write_text(result.stdout)

    def apply(self, failure="0"):
        return subprocess.run(self.command(self.source) + ["apply"],
                              env=dict(self.env, SIMULATE_FAILURE=failure),
                              text=True, capture_output=True, timeout=15)

    def attempts(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_noble_package_sources(self):
        self.assertIn("fastfetch", self.packages["apt"]["common"])
        self.assertIn("ppa:zhangsongcui3371/fastfetch", self.packages["apt"]["ppas"])
        self.assertNotIn("taskwarrior-tui", self.packages["apt"]["common"])
        self.assertIn({"crate": "taskwarrior-tui", "bin": "taskwarrior-tui"},
                      self.packages["cargo"]["registry"])
        self.assertNotIn("taskwarrior", self.packages["apt"]["common"])

    def test_desktop_class_installs_flatpak(self):
        self.assertIn("flatpak", self.packages["apt"]["desktop"])
        installer = ROOT / "run_once_before_10-install-apt-packages.sh.tmpl"
        self.assertIn("range .packages.apt.desktop", installer.read_text())

    def test_codex_parser_dependencies(self):
        self.assertTrue({"python3", "python3-tomlkit"} <= set(self.packages["apt"]["common"]))
        merger = ROOT / "private_dot_codex/modify_private_config.toml"
        self.assertEqual(merger.read_text().splitlines()[0], "#!/usr/bin/python3")

    def test_failed_install_retries_until_success(self):
        self.render()
        result = self.apply("1")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(len(self.attempts()), 1)
        self.assertIn("--or-update", self.attempts()[0])
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.attempts()), 2)
        result = self.apply("1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.attempts()), 2)

    def test_missing_flatpak_remains_pending(self):
        self.render()
        isolated = self.root / "isolated-bin"
        isolated.mkdir()
        (isolated / "bash").symlink_to(shutil.which("bash"))
        self.env["PATH"] = str(isolated)
        result = self.apply()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("flatpak is required", result.stderr)
        (isolated / "flatpak").symlink_to(self.bin / "flatpak")
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.attempts()), 1)

    def test_server_skips_desktop_apps(self):
        self.render("server")
        result = self.apply("1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.attempts(), [])


if __name__ == "__main__":
    unittest.main()

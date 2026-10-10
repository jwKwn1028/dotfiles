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
        self.env = dict(os.environ, HOME=str(self.destination),
                        PATH=f"{self.bin}:/usr/bin:/bin",
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

    def mock(self, name, body, interpreter="/bin/sh"):
        path = self.bin / name
        path.write_text(f"#!{interpreter}\n{body}")
        path.chmod(0o755)

    def render(self, machine_class="desktop", *,
               script_name="run_once_after_20-install-flatpaks.sh", data=None):
        template = ROOT / f"{script_name}.tmpl"
        overrides = {"class": machine_class}
        overrides.update(data or {})
        result = subprocess.run(
            self.command(ROOT) + ["execute-template", "--override-data",
                                  json.dumps(overrides)],
            input=template.read_text(), text=True, capture_output=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        script = self.source / script_name
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
        self.assertIn("latexmk", self.packages["apt"]["desktop"])
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

    def assert_cargo_retry(self, failing_binary):
        self.env.update(TEST_BIN=str(self.bin), FAILING_CARGO_BIN=failing_binary)
        self.mock("cargo", '''
if [ "$2" = --git ]; then binary=retry-test-git; else binary=retry-test-registry; fi
printf '%s\\n' "$binary" >> "$ATTEMPT_LOG"
if [ "$SIMULATE_FAILURE" = 1 ] && [ "$binary" = "$FAILING_CARGO_BIN" ]; then
    exit 42
fi
printf '#!/bin/sh\\nexit 0\\n' > "$TEST_BIN/$binary"
chmod +x "$TEST_BIN/$binary"
''')
        for name in ("starship", "zoxide"):
            self.mock(name, "exit 0\n")
        (self.destination / "miniconda3").mkdir()
        self.render("server", script_name="run_once_after_30-install-cli-tools.sh",
                    data={"packages": {"cargo": {
                        "registry": [{"crate": "retry-test", "bin": "retry-test-registry"}],
                        "git": [{"url": "https://example.invalid/retry.git",
                                 "bin": "retry-test-git", "package": "retry-test"}],
                    }}})
        result = self.apply("1")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("provisioning incomplete", result.stderr)
        self.assertEqual(self.attempts(), ["retry-test-registry", "retry-test-git"])
        successful = "retry-test-git" if failing_binary == "retry-test-registry" else "retry-test-registry"
        self.assertTrue((self.bin / successful).is_file())
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.attempts(), ["retry-test-registry", "retry-test-git", failing_binary])
        result = self.apply("1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.attempts()), 3)

    def test_registry_cargo_failure_retries(self):
        self.assert_cargo_retry("retry-test-registry")

    def test_git_cargo_failure_retries(self):
        self.assert_cargo_retry("retry-test-git")

    def font_fixture(self):
        self.mock("curl", '''
printf '%s\\n' "$4" >> "$ATTEMPT_LOG"
[ "$SIMULATE_FAILURE" = 0 ] || exit 22
printf '%s' "$4" > "$3"
''')
        self.mock("unzip", '''
import os
from pathlib import Path
import sys
if os.environ.get("UNPACK_FAILURE") == "1":
    sys.exit(1)
url = Path(sys.argv[2]).read_text()
fonts = {
    "JuliaMono": {"JuliaMono-Regular.ttf": "JuliaMono"},
    "NanumGothicCoding": {"NanumGothicCoding.ttf": "NanumGothicCoding"},
    "JetBrainsMono": {"JetBrainsMono.ttf": "JetBrainsMono Nerd Font"},
}
files = next((files for name, files in fonts.items() if name in url), {
    "NewCMSans10-Regular.otf": "NewComputerModernSans10",
    "NewCMMath-Regular.otf": "NewComputerModernMath",
})
directory = Path(sys.argv[4])
directory.mkdir(parents=True)
for name, family in files.items():
    (directory / name).write_text(family)
''', interpreter="/usr/bin/python3")
        self.mock("fc-list", '''
import os
from pathlib import Path
if os.environ.get("UNRESOLVED_FONTS") != "1":
    for font in (Path(os.environ["HOME"]) / ".local/share/fonts").rglob("*"):
        if font.is_file():
            print(font.read_text())
''', interpreter="/usr/bin/python3")
        self.mock("fc-cache", "exit 0\n")
        self.render(script_name="run_once_after_50-install-fonts.sh")
        return 3 + len(self.packages["fonts"]["archives"])

    def test_font_download_failure_retries(self):
        count = self.font_fixture()
        result = self.apply("1")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Font provisioning incomplete", result.stderr)
        self.assertEqual(len(self.attempts()), count)
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.attempts()), count * 2)
        result = self.apply("1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.attempts()), count * 2)

    def test_font_unpack_failure_retries(self):
        count = self.font_fixture()
        self.env["UNPACK_FAILURE"] = "1"
        result = self.apply()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(len(self.attempts()), count)
        self.env["UNPACK_FAILURE"] = "0"
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.attempts()), count * 2)

    def test_unresolved_fonts_remain_pending(self):
        count = self.font_fixture()
        self.env["UNRESOLVED_FONTS"] = "1"
        result = self.apply()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("still unresolved", result.stderr)
        self.assertEqual(len(self.attempts()), count)
        self.env["UNRESOLVED_FONTS"] = "0"
        result = self.apply()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.attempts()), count)


if __name__ == "__main__":
    unittest.main()

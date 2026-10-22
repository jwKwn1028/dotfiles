#!/usr/bin/python3
"""Check shared provisioning helpers with temporary profiles and mocked sudo."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
if not (ROOT / ".chezmoiscripts").is_dir() and shutil.which("chezmoi"):
    ROOT = Path(subprocess.check_output(["chezmoi", "source-path"], text=True).strip())
HELPERS = ROOT / ".chezmoitemplates/script-helpers"


class ProvisioningHelperTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="provisioning-helper-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ)

    def run_shell(self, script, *args, shell="bash", content=None):
        return subprocess.run([shell, "-eu", "-c", script, "helper-test", *map(str, args)],
                              input=content, text=True, capture_output=True,
                              env=self.env, timeout=15)

    def test_profile_precedence_and_path_filtering(self):
        root = self.root / "profiles with spaces"
        for name in ("selected", "default", "rest", "space profile"):
            (root / name).mkdir(parents=True)
        outside = self.root / "outside"
        outside.mkdir()
        (root / "regular-file").touch()
        profiles = root / "profiles.ini"
        defaults = "[Profile0]\nPath=rest\n[Profile1]\nPath=default\nDefault=1\n"
        invalid = "".join(f"[Install{i}]\nDefault={candidate}\n" for i, candidate in
                          enumerate(("", ".", "..", str(outside), "../outside",
                                     "selected/../../outside", "selected/..")))
        cases = (
            ("installation", defaults + "[InstallABC]\nDefault=selected\n", "selected"),
            ("default", defaults + "[InstallABC]\nDefault=missing\n", "default"),
            ("remaining", "[Profile0]\nPath=rest\n", "rest"),
            ("CRLF and spaces", "[Profile0]\r\nPath=space profile\r\nDefault=1\r\n",
             "space profile"),
            ("unsafe paths", invalid + "[Profile0]\nPath=rest\n", "rest"),
            ("no directory", "[Profile0]\nPath=regular-file\n", None),
        )
        for name, content, selected in cases:
            with self.subTest(name=name):
                profiles.write_bytes(content.encode())
                result = self.run_shell('. "$1"; select_mozilla_profile "$2" "$3"',
                                        HELPERS / "mozilla-profile.sh", root, profiles)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, f"{root / selected}\n" if selected else "")

    @unittest.skipUnless(shutil.which("chezmoi"), "chezmoi is unavailable")
    def test_rendered_profile_scripts_select_and_preserve_profiles(self):
        apps = (
            ("60-configure-zen", ".var/app/app.zen_browser.zen/.zen"),
            ("62-configure-firefox", ".mozilla/firefox"),
            ("65-configure-thunderbird", ".thunderbird"),
        )
        for name, relative_root in apps:
            with self.subTest(app=name):
                home = self.root / name
                root = home / relative_root
                for profile in ("selected", "default", "rest"):
                    (root / profile).mkdir(parents=True)
                (root / "profiles.ini").write_text(
                    "[Profile0]\nPath=rest\n[Profile1]\nPath=default\nDefault=1\n"
                    "[InstallABC]\nDefault=selected\n")
                handlers = root / "selected/handlers.json"
                handlers.write_text('{"keep":"local"}\n')
                chrome = home / ".local/share/thunderbird-chrome"
                chrome.mkdir(parents=True)
                for asset in ("thunar.css", "userChrome.css", "userContent.css"):
                    (chrome / asset).write_text("/* fixture */\n")
                template = ROOT / ".chezmoiscripts" / f"run_onchange_after_{name}-profile.sh.tmpl"
                rendered = subprocess.run(
                    ["chezmoi", "--source", str(ROOT), "execute-template", "--override-data",
                     json.dumps({"chezmoi": {"os": "linux", "homeDir": str(home)},
                                 "class": "desktop"})],
                    input=template.read_text(), text=True, capture_output=True, timeout=15)
                self.assertEqual(rendered.returncode, 0, rendered.stderr)
                script = home / "configure.sh"
                script.write_text(rendered.stdout)
                self.env["HOME"] = str(home)
                result = self.run_shell('bash "$1"', script)
                self.assertEqual(result.returncode, 0, result.stderr)
                user_js = root / "selected/user.js"
                self.assertTrue(user_js.is_file())
                self.assertEqual(user_js.stat().st_mode & 0o777, 0o600)
                self.assertFalse((root / "default/user.js").exists())
                self.assertFalse((root / "rest/user.js").exists())
                self.assertEqual(handlers.read_text(), '{"keep":"local"}\n')
                modified = user_js.stat().st_mtime_ns
                result = self.run_shell('bash "$1"', script)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(user_js.stat().st_mtime_ns, modified)

    def config_fixture(self):
        binary = self.root / "bin"
        binary.mkdir()
        temporary = self.root / "tmp"
        temporary.mkdir()
        self.log = self.root / "installs"
        self.env.update(PATH=f"{binary}:/usr/bin:/bin", TMPDIR=str(temporary),
                        INSTALL_LOG=str(self.log), CONFIG_OWNER="0:0", INSTALL_FAIL="0")
        mocks = {
            "stat": '''import os, sys
from pathlib import Path
mode = Path(sys.argv[-1]).stat().st_mode & 0o777
print(f"{os.environ['CONFIG_OWNER']}:{mode:o}")
''',
            "sudo": '''import json, os, sys
with open(os.environ["INSTALL_LOG"], "a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
if os.environ["INSTALL_FAIL"] == "1":
    sys.exit(42)
args = sys.argv[1:]
for option in ("-o", "-g"):
    index = args.index(option)
    del args[index:index + 2]
os.execvp(args[0], args)
''',
        }
        for name, content in mocks.items():
            path = binary / name
            path.write_text("#!/usr/bin/python3\n" + content)
            path.chmod(0o755)

    def install_config(self, target, content="setting=one\n", *options):
        return self.run_shell(
            '. "$1"; shift; install_config "$@"; printf "changed=%s\\n" "$changed"',
            HELPERS / "install-root-config.sh", target, *options, shell="sh", content=content)

    def installs(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_config_content_permissions_and_ownership(self):
        self.config_fixture()
        target = self.root / "settings.conf"
        for count, content, mode, owner in (
            (1, "setting=one\n", None, "0:0"),
            (1, "setting=one\n", None, "0:0"),
            (2, "setting=two\n", None, "0:0"),
            (3, "setting=two\n", 0o600, "0:0"),
            (4, "setting=two\n", None, "1000:1000"),
        ):
            with self.subTest(count=count, mode=mode, owner=owner):
                previous = len(self.installs()) if self.log.exists() else 0
                if mode:
                    target.chmod(mode)
                self.env["CONFIG_OWNER"] = owner
                result = self.install_config(target, content)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(result.stdout.endswith(f"changed={int(count != previous)}\n"))
                self.assertEqual(len(self.installs()), count)
                self.assertEqual(target.read_text(), content)
                self.assertEqual(target.stat().st_mode & 0o777, 0o644)
                self.assertEqual(list((self.root / "tmp").iterdir()), [])

    def test_config_parent_creation(self):
        self.config_fixture()
        target = self.root / "missing/settings.conf"
        result = self.install_config(target, "setting=one\n", "-D")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(target.is_file())
        self.assertIn("-D", self.installs()[0])

    def test_config_failure_aborts_and_cleans_up(self):
        self.config_fixture()
        self.env["INSTALL_FAIL"] = "1"
        target = self.root / "settings.conf"
        result = self.install_config(target)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("changed=", result.stdout)
        self.assertFalse(target.exists())
        self.assertEqual(list((self.root / "tmp").iterdir()), [])


if __name__ == "__main__":
    unittest.main()

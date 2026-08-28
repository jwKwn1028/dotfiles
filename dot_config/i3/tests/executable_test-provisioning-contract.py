#!/usr/bin/python3
"""Keep desktop runtime consumers paired with provisioning declarations."""

from __future__ import annotations

import os
from pathlib import Path
import tomllib
import unittest


I3_ROOT = Path(__file__).resolve().parent.parent
POLYBAR_ROOT = I3_ROOT.parent / "polybar"


def managed_file(root: Path, target_name: str) -> Path:
    applied = root / target_name
    if applied.exists():
        return applied
    source_state = applied.with_name(f"executable_{applied.name}")
    if source_state.exists():
        return source_state
    raise AssertionError(f"missing runtime consumer: {target_name}")


def source_file(target_name: str) -> Path:
    return managed_file(I3_ROOT, target_name)


def polybar_file(target_name: str) -> Path:
    return managed_file(POLYBAR_ROOT, target_name)


def package_manifest() -> Path | None:
    configured = os.environ.get("CHEZMOI_PACKAGE_MANIFEST")
    candidates = []
    if configured:
        candidates.append(Path(configured))
    candidates.append(I3_ROOT.parent.parent / ".chezmoidata" / "packages.toml")
    return next((path for path in candidates if path.is_file()), None)


class ProvisioningContractTests(unittest.TestCase):
    def manifest_data(self) -> tuple[Path, dict]:
        manifest = package_manifest()
        if manifest is None:
            self.skipTest("chezmoi package manifest is unavailable in the applied tree")

        with manifest.open("rb") as stream:
            return manifest, tomllib.load(stream)

    def test_system_python_imports_are_provisioned(self) -> None:
        _, data = self.manifest_data()
        packages = set(data["packages"]["apt"]["i3_x11"])
        contracts = (
            (
                "python3-i3ipc",
                source_file("overflow-watcher.py"),
                "from i3ipc import",
            ),
            (
                "python3-xlib",
                source_file("top-edge-peek.py"),
                "from Xlib import",
            ),
            (
                "python3-lz4",
                source_file("zen-url-state.py"),
                "import lz4.block",
            ),
        )

        for package, consumer, import_marker in contracts:
            with self.subTest(package=package, consumer=consumer.name):
                source = consumer.read_text(encoding="utf-8")
                self.assertIn(import_marker, source)
                self.assertIn(
                    package,
                    packages,
                    f"{consumer.name} requires {package} in packages.apt.i3_x11",
                )

    def test_i3_runtime_commands_are_provisioned(self) -> None:
        _, data = self.manifest_data()
        packages = set(data["packages"]["apt"]["i3_x11"])
        config = source_file("config")
        contracts = (
            ("xfce4-terminal", config, "xfce4-terminal"),
            ("xfce4-settings", config, "xfsettingsd"),
            ("xfce4-power-manager", config, "xfce4-power-manager"),
            ("xfce4-taskmanager", config, "xfce4-taskmanager"),
            ("gnome-keyring", config, "gnome-keyring-daemon"),
            ("libnotify-bin", source_file("bar-nav.sh"), "notify-send"),
            ("x11-utils", source_file("bar-nav.sh"), "xwininfo"),
            ("x11-xserver-utils", source_file("display-setup.sh"), "xrandr"),
            ("xinput", source_file("super-polybar-listener.py"), 'shutil.which("xinput")'),
            ("pulseaudio-utils", source_file("bar-nav.sh"), "pactl"),
            ("zenity", polybar_file("scripts/confirm-poweroff.sh"), "zenity"),
            ("xss-lock", config, "xss-lock"),
            ("unclutter-xfixes", config, "unclutter-xfixes"),
            ("policykit-1-gnome", config, "polkit-gnome-authentication-agent-1"),
        )

        for package, consumer, command_marker in contracts:
            with self.subTest(package=package, consumer=consumer.name):
                source = consumer.read_text(encoding="utf-8")
                self.assertIn(command_marker, source)
                self.assertIn(
                    package,
                    packages,
                    f"{command_marker} requires {package} in packages.apt.i3_x11",
                )

    def test_autotiling_is_pipx_provisioned(self) -> None:
        manifest, data = self.manifest_data()
        apps = data["packages"]["pipx"]["apps"]
        self.assertIn({"package": "autotiling", "bin": "autotiling"}, apps)

        config = source_file("config").read_text(encoding="utf-8")
        self.assertIn("~/.local/bin/autotiling --limit 6", config)
        self.assertIn('pkill -f "[/]autotiling( |$)"', config)

        installer = manifest.parent.parent / "run_once_after_30-install-cli-tools.sh.tmpl"
        self.assertTrue(installer.is_file(), f"missing pipx installer: {installer}")
        installer_source = installer.read_text(encoding="utf-8")
        self.assertIn("range .packages.pipx.apps", installer_source)
        self.assertIn("pipx install {{ .package | quote }}", installer_source)

    def test_helium_transient_deferrals_retry(self) -> None:
        manifest, _ = self.manifest_data()
        template = manifest.parent.parent / "run_onchange_after_70-configure-helium-profile.sh.tmpl"
        source = template.read_text(encoding="utf-8")
        self.assertIn("# Preferences profile state:", source)
        self.assertIn("close it and rerun chezmoi apply", source)
        self.assertIn("could not read Helium preferences", source)
        self.assertGreaterEqual(source.count("exit 1"), 2)

    def test_agent_state_uses_modify_allowlist(self) -> None:
        manifest, _ = self.manifest_data()
        source_root = manifest.parent.parent
        expected = {
            "private_dot_claude": ["modify_private_settings.json"],
            "private_dot_codex": ["modify_private_config.toml"],
        }

        for directory, allowed_files in expected.items():
            with self.subTest(directory=directory):
                actual_files = sorted(
                    str(path.relative_to(source_root / directory))
                    for path in (source_root / directory).rglob("*")
                    if path.is_file()
                )
                self.assertEqual(allowed_files, actual_files)

        gitignore = (source_root / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("!private_dot_claude/modify_private_settings.json", gitignore)
        self.assertIn("!private_dot_codex/modify_private_config.toml", gitignore)

        chezmoiignore = (source_root / ".chezmoiignore").read_text(encoding="utf-8")
        self.assertIn("!/.claude/settings.json", chezmoiignore)
        self.assertIn("!/.codex/config.toml", chezmoiignore)


if __name__ == "__main__":
    unittest.main()

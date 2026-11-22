#!/usr/bin/python3
"""Keep desktop runtime consumers paired with provisioning declarations."""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
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
                "python3-i3ipc",
                source_file("workspace-groups.py"),
                "import i3ipc",
            ),
            (
                "python3-xlib",
                source_file("top-edge-peek.py"),
                "from Xlib import",
            ),
            (
                "python3-xlib",
                source_file("group_restore.py"),
                "from Xlib",
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
            ("pulseaudio-utils", polybar_file("scripts/volume.py"), "pactl"),
            ("zenity", polybar_file("scripts/confirm-poweroff.sh"), "zenity"),
            ("xss-lock", config, "xss-lock"),
            ("i3lock", source_file("lock.sh"), "exec i3lock -n"),
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

    def test_ghostty_appimage_is_pinned(self) -> None:
        manifest, data = self.manifest_data()
        packages = data["packages"]
        self.assertNotIn("ghostty", packages["apt"]["i3_x11"])
        app = packages["appimage"]["ghostty"]
        self.assertNotIn(app["legacy_ppa"], packages["apt"]["ppas"])
        for arch in ("amd64", "arm64"):
            self.assertRegex(app[arch]["sha256"], r"^[0-9a-f]{64}$")
        self.assertIn("exec --no-startup-id ghostty +new-window", source_file("config").read_text())
        installer = manifest.parent.parent / ".chezmoiscripts/run_once_after_99-install-ghostty.sh.tmpl"
        self.assertIn(".packages.appimage.ghostty", installer.read_text())

    def test_autotiling_is_pipx_provisioned(self) -> None:
        manifest, data = self.manifest_data()
        apps = data["packages"]["pipx"]["apps"]
        self.assertIn({"package": "autotiling", "bin": "autotiling"}, apps)

        controller = source_file("group_controller.py").read_text(encoding="utf-8")
        self.assertIn('".local/bin/autotiling"', controller)

        installer = (manifest.parent.parent / ".chezmoiscripts" /
                     "run_once_after_30-install-cli-tools.sh.tmpl")
        self.assertTrue(installer.is_file(), f"missing pipx installer: {installer}")
        installer_source = installer.read_text(encoding="utf-8")
        self.assertIn("range .packages.pipx.apps", installer_source)
        self.assertIn("pipx install {{ .package | quote }}", installer_source)

    def test_i3lock_color_build_is_pinned(self) -> None:
        manifest, data = self.manifest_data()
        build = data["packages"]["source"]["i3lock_color"]
        self.assertRegex(build["commit"], r"^[0-9a-f]{40}$")
        self.assertIn(".c.", build["tag"], "lock.sh detects i3lock-color by '.c.' in its version")
        self.assertIn("i3lock", data["packages"]["apt"]["i3_x11"], "apt i3lock ships /etc/pam.d/i3lock")
        self.assertIn("*.c.*)", source_file("lock.sh").read_text(encoding="utf-8"))

        installer = (manifest.parent.parent / ".chezmoiscripts" /
                     "run_once_after_95-build-i3lock-color.sh.tmpl")
        self.assertTrue(installer.is_file(), f"missing i3lock-color installer: {installer}")
        source = installer.read_text(encoding="utf-8")
        self.assertIn(".packages.source.i3lock_color", source)
        self.assertIn('"$actual" != "$commit"', source)
        self.assertIn("--prefix=/usr/local", source)

    def test_zathura_build_is_pinned(self) -> None:
        manifest, data = self.manifest_data()
        root = manifest.parent.parent
        components = ("girara", "zathura", "zathura_pdf_poppler")
        for name in components:
            with self.subTest(component=name):
                self.assertRegex(data["packages"]["source"][name]["commit"], r"^[0-9a-f]{40}$")
        for package in ("zathura", "zathura-pdf-poppler"):
            self.assertNotIn(package, data["packages"]["apt"]["i3_x11"], "apt would add a second zathura")

        installer = root / ".chezmoiscripts" / "run_once_after_96-build-zathura.sh.tmpl"
        self.assertTrue(installer.is_file(), f"missing zathura installer: {installer}")
        source = installer.read_text(encoding="utf-8")
        for name in components:
            self.assertIn(f".packages.source.{name}", source)
        self.assertIn('"$actual" != "$commit"', source)
        self.assertIn('prefix="$HOME/.local"', source)

        forward_search = (root / "dot_local/bin/executable_hx-fwd-search").read_text(encoding="utf-8")
        self.assertIn("--synctex-forward", forward_search)
        self.assertIn("-Dsynctex=enabled", source)

        completion = (root / "dot_zsh/rc.d/25-completion.zsh").read_text(encoding="utf-8")
        self.assertIn('"$HOME/.local/share/zsh/site-functions"', completion)

    def test_personal_projects_are_pinned(self) -> None:
        manifest, data = self.manifest_data()
        root = manifest.parent.parent
        projects = data["packages"]["git"]
        for name in ("hxp", "remote_tools"):
            with self.subTest(project=name):
                self.assertRegex(projects[name]["commit"], r"^[0-9a-f]{40}$")
                self.assertNotIn("url", projects[name], "the GitHub address comes from githubUser")
        self.assertEqual(projects["hxp"]["install"], ["./install.sh", "--no-config"])

        installer = (root / ".chezmoiscripts/run_once_after_99-clone-projects.sh.tmpl").read_text()
        self.assertIn("range $name, $p := .packages.git", installer)
        self.assertIn('[[ "$(git -C "$partial" rev-parse HEAD)" != "$commit" ]]', installer)

        # Consumers look where the manifest clones.
        jobmon = (root / "dot_zsh/rc.d/52-jobmon.zsh.tmpl").read_text()
        self.assertIn("$HOME/{{ .packages.git.remote_tools.dir }}", jobmon)
        self.assertIn('"$HPC_JOBMON_TOOLS_DIR/shell/jobmon.zsh"', jobmon)
        self.assertIn('source "$HOME/.zsh/hxp-main.zsh"',
                      (root / "dot_zsh/rc.d/70-integrations.zsh").read_text())
        self.assertIn('"hxp-sessions"', (root / "dot_local/bin/executable_tmux-resurrect-post-save").read_text())
        self.assertIn(" hxp-resume ", (root / "dot_tmux.conf").read_text())
        # --no-config leaves these to this repo.
        for config in ("dot_config/zathura/zathurarc", "dot_config/sioyek/prefs_user.config",
                       "dot_config/sioyek/keys_user.config"):
            self.assertTrue((root / config).is_file(), f"missing {config}")
        self.assertIn("sioyek", data["packages"]["apt"]["i3_x11"])
        self.assertIn("inotify-tools", data["packages"]["apt"]["desktop"], "hxp's watcher needs inotifywait")

    def test_pinned_projects_are_pushed_and_provide_what_configs_use(self) -> None:
        """Require pushed pins with the interfaces used here."""
        _, data = self.manifest_data()
        needs = {"hxp": ("bin/hxp-sessions", "bin/hxp-resume", "zsh/hxp-main.zsh", "install.sh"),
                 "remote_tools": ("shell/jobmon.zsh",)}
        for name, paths in needs.items():
            project = data["packages"]["git"][name]
            checkout = Path.home() / project["dir"]
            commit = project["commit"]
            with self.subTest(project=name):
                if not (checkout / ".git").exists():
                    self.skipTest(f"no checkout at {checkout}")

                def git(*args: str) -> subprocess.CompletedProcess:
                    return subprocess.run(["git", "-C", str(checkout), *args], capture_output=True, text=True)

                bump = f"commit and push {name}, then set packages.git.{name}.commit"
                self.assertEqual(git("cat-file", "-e", f"{commit}^{{commit}}").returncode, 0,
                                 f"pinned {commit[:7]} is not in {checkout}; {bump}")
                self.assertTrue(git("branch", "-r", "--contains", commit).stdout.strip(),
                                f"pinned {commit[:7]} is on no remote branch, so fresh machines cannot clone it; {bump}")
                for path in paths:
                    self.assertEqual(git("cat-file", "-e", f"{commit}:{path}").returncode, 0,
                                     f"pinned {commit[:7]} lacks {path}; {bump}")
                if name == "hxp":
                    self.assertIn("--no-config", git("show", f"{commit}:install.sh").stdout,
                                  f"pinned {commit[:7]}'s installer would link viewer configs; {bump}")

    def test_helium_transient_deferrals_retry(self) -> None:
        manifest, _ = self.manifest_data()
        template = (manifest.parent.parent / ".chezmoiscripts" /
                    "run_onchange_after_70-configure-helium-profile.sh.tmpl")
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
        self.assertIn("!.claude/settings.json", chezmoiignore)
        self.assertIn("!.codex/config.toml", chezmoiignore)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/python3
"""Cross-check i3 bar navigation against the Polybar module configuration."""

from __future__ import annotations

import os
from pathlib import Path
import re
import shlex
import unittest


I3_ROOT = Path(__file__).resolve().parent.parent
BAR_NAV = I3_ROOT / "bar-nav.sh"
if not BAR_NAV.exists():
    BAR_NAV = I3_ROOT / "executable_bar-nav.sh"
RESTORE = I3_ROOT / "i3-resurrect-restore-all.sh"
if not RESTORE.exists():
    RESTORE = I3_ROOT / "executable_i3-resurrect-restore-all.sh"

POLYBAR_CONFIG = Path(
    os.environ.get("I3_POLYBAR_CONFIG", I3_ROOT.parent / "polybar" / "config.ini")
)
POLYBAR_ROOT = POLYBAR_CONFIG.parent


def bash_array(source: str, name: str) -> list[str]:
    match = re.search(
        rf"^{re.escape(name)}=\(\s*(.*?)\s*\)$",
        source,
        flags=re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"missing Bash array: {name}")
    return shlex.split(match.group(1))


class ConfigConsistencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bar_nav = BAR_NAV.read_text(encoding="utf-8")
        cls.polybar = POLYBAR_CONFIG.read_text(encoding="utf-8")
        cls.restore = RESTORE.read_text(encoding="utf-8")

    def test_parallel_navigation_arrays_have_the_same_length(self) -> None:
        names = (
            "modules",
            "tray_class",
            "click_left",
            "click_left_opens",
            "click_right",
            "click_right_opens",
            "scroll_down",
            "scroll_up",
        )
        lengths = {name: len(bash_array(self.bar_nav, name)) for name in names}
        self.assertEqual(
            len(set(lengths.values())),
            1,
            f"bar-nav parallel arrays drifted: {lengths}",
        )

    def test_navigable_polybar_modules_have_adjacent_selected_twins(self) -> None:
        modules = bash_array(self.bar_nav, "modules")
        tray_classes = bash_array(self.bar_nav, "tray_class")
        sections = set(
            re.findall(r"^\[module/([^]]+)]$", self.polybar, flags=re.MULTILINE)
        )
        layouts = [
            shlex.split(value)
            for value in re.findall(
                r"^modules-(?:left|center|right)\s*=\s*(.+)$",
                self.polybar,
                flags=re.MULTILINE,
            )
        ]

        for module, tray_class in zip(modules, tray_classes, strict=True):
            if tray_class:
                continue
            twin = f"{module}-sel"
            self.assertIn(module, sections)
            self.assertIn(twin, sections)
            self.assertTrue(
                any(
                    any(
                        tokens[index : index + 2] == [module, twin]
                        for index in range(len(tokens) - 1)
                    )
                    for tokens in layouts
                ),
                f"{module} and {twin} are not adjacent in a bar module list",
            )

    def test_power_menu_uses_current_actions_and_safe_commands(self) -> None:
        self.assertNotRegex(self.polybar, r"\bmenu-(?:open|close)(?:-|\b)")
        self.assertRegex(
            self.polybar,
            r"(?m)^menu-0-0-exec\s*=.*confirm-poweroff\.sh poweroff$",
        )
        self.assertRegex(
            self.polybar,
            r"(?m)^menu-0-1-exec\s*=.*confirm-poweroff\.sh reboot$",
        )
        self.assertRegex(self.polybar, r"(?m)^menu-0-2-exec\s*=\s*xflock4$")
        self.assertRegex(
            self.polybar, r"(?m)^menu-0-3-exec\s*=\s*#powermenu\.open\.1$"
        )
        self.assertRegex(
            self.polybar, r"(?m)^menu-1-0-exec\s*=\s*#powermenu\.open\.0$"
        )

    def test_resurrect_restore_uses_shared_polybar_helpers(self) -> None:
        self.assertIn('. "$DIR/_polybar-common.sh"', self.restore)
        self.assertNotIn("set_polybar_visibility()", self.restore)
        self.assertNotIn("wait_for_polybar_state()", self.restore)
        self.assertIn("polybar_set_state hide 0", self.restore)
        self.assertIn("polybar_set_state show 1", self.restore)

    def test_desktop_python_entrypoints_use_the_system_interpreter(self) -> None:
        entrypoints = [
            *I3_ROOT.glob("*.py"),
            *(I3_ROOT / "tests").glob("*.py"),
            *(POLYBAR_ROOT / "scripts").glob("*.py"),
        ]
        self.assertTrue(entrypoints)
        for path in entrypoints:
            first_line = path.read_text(encoding="utf-8").splitlines()[0]
            self.assertEqual(first_line, "#!/usr/bin/python3", str(path))


if __name__ == "__main__":
    unittest.main()

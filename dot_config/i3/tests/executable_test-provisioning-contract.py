#!/usr/bin/python3
"""Keep system-Python desktop imports paired with their apt packages."""

from __future__ import annotations

import os
from pathlib import Path
import tomllib
import unittest


I3_ROOT = Path(__file__).resolve().parent.parent


def source_file(target_name: str) -> Path:
    applied = I3_ROOT / target_name
    if applied.exists():
        return applied
    source_state = I3_ROOT / f"executable_{target_name}"
    if source_state.exists():
        return source_state
    raise AssertionError(f"missing runtime consumer: {target_name}")


def package_manifest() -> Path | None:
    configured = os.environ.get("CHEZMOI_PACKAGE_MANIFEST")
    candidates = []
    if configured:
        candidates.append(Path(configured))
    candidates.append(I3_ROOT.parent.parent / ".chezmoidata" / "packages.toml")
    return next((path for path in candidates if path.is_file()), None)


class ProvisioningContractTests(unittest.TestCase):
    def test_system_python_imports_are_provisioned(self) -> None:
        manifest = package_manifest()
        if manifest is None:
            self.skipTest("chezmoi package manifest is unavailable in the applied tree")

        with manifest.open("rb") as stream:
            data = tomllib.load(stream)
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


if __name__ == "__main__":
    unittest.main()

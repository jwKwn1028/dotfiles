#!/usr/bin/python3
"""Export serialized GdkPixdata resources as PNG files usable by GTK CSS."""

from pathlib import Path
import sys

import gi

gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf


def export_pixbufs(directory: Path) -> int:
    converted = 0
    for path in directory.glob("*.png"):
        data = path.read_bytes()
        if data.startswith(b"GdkP"):
            pixbuf = GdkPixbuf.Pixbuf.new_from_inline(data, True)
            pixbuf.savev(str(path), "png", [], [])
            converted += 1
    return converted


if __name__ == "__main__":
    print(f"Exported {export_pixbufs(Path(sys.argv[1]))} pixbuf resources as PNG.")

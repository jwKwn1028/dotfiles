#!/usr/bin/env python3
"""Diagnostic counts must not become file names or unsafe restore paths."""

import os
from pathlib import Path
import runpy
import tempfile

HELPER = Path(__file__).resolve().parent.parent / "executable_tmux-resurrect-helix"
if not HELPER.exists():
    HELPER = HELPER.with_name("tmux-resurrect-helix")
screen = runpy.run_path(str(HELPER))["screen"]

INACTIVE = "\x1b[38;2;59;66;97m\x1b[48;2;31;35;53m"
ACTIVE = "\x1b[38;2;169;177;214m"
ERROR = "\x1b[38;2;219;75;75m"
WARNING = "\x1b[38;2;224;175;104m"


def rendered(header, name):
    return (header + "\n" + INACTIVE + "       /long/path/other" + ERROR + "●" +
            INACTIVE + " 3 " + WARNING + "●" + INACTIVE + " 1  1 sel  16:1 11% python │" +
            "\x1b[38;2;41;45;62m\x1b[48;2;122;162;247m N \x1b[0m" +
            ACTIVE + "  " + name + ERROR + "●" + ACTIVE + " 3 " + WARNING +
            "●" + ACTIVE + " 1  1 sel  38:20 28% python\n")


with tempfile.TemporaryDirectory(prefix="helix-statusline-") as directory:
    cwd = os.path.realpath(directory)
    (Path(cwd) / "nested").mkdir()
    partial = Path(cwd) / "nested/lo"
    partial.write_text("This existing prefix is not the displayed file.\n")
    header = INACTIVE + " startup.py " + ACTIVE + " long_module.py[+]"
    raw = rendered(header, str(partial))
    screen.__globals__["tmux"] = lambda *args: raw
    _, rows = screen("%1", cwd, existing_only=False)
    assert rows[0][1] == [str(Path(cwd) / "long_module.py"), 38, 20, True], rows
    _, rows = screen("%1", cwd)
    assert rows[0][1] == [None, 38, 20, True], rows

    # Focused tab in the middle and at the end (Helix pads after the last).
    for header, expected in (
        (ACTIVE + " first module.py " + INACTIVE + " last.py ", "first module.py"),
        (INACTIVE + " first.py " + ACTIVE + " last module.py[+] ", "last module.py"),
    ):
        raw = rendered(header, str(partial))
        _, rows = screen("%1", cwd, existing_only=False)
        assert Path(rows[0][1][0] or "").name == expected, rows
        _, rows = screen("%1", cwd)
        assert rows[0][1][0] is None, rows

    # Spaces and wide characters stay in the name.
    raw = rendered(INACTIVE + " startup.py " + ACTIVE + " my notes 한글.py", str(partial))
    _, rows = screen("%1", cwd, existing_only=False)
    assert Path(rows[0][1][0]).name == "my notes 한글.py", rows

    # No identifiable tab: no name.
    raw = rendered(ACTIVE + "first source line", str(partial))
    _, rows = screen("%1", cwd, existing_only=False)
    assert rows[0][1][0] is None, rows

    complete = Path(cwd) / "complete.py"
    complete.write_text("pass\n")
    raw = "N  " + str(complete) + " ● 3 ● 1  1 sel  5:2 20% python\n"
    _, rows = screen("%1", cwd)
    assert rows[0][0] == [str(complete), 5, 2, True], rows

    # A real name containing a dot and a count is kept.
    literal = Path(cwd) / "literal● 3"
    literal.write_text("literal\n")
    raw = "N  " + str(literal) + "  1 sel  1:1 50% text\n"
    _, rows = screen("%1", cwd)
    assert rows[0][0][0] == str(literal), rows

print("PASS: Helix diagnostic overlap uses the highlighted filename for labels and never saves a clipped restore path")

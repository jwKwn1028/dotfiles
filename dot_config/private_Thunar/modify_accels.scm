#!/usr/bin/env python3
import re
import sys

ACCELS = {
    "<Actions>/ThunarWindow/open-parent": "minus",
    "<Actions>/ThunarStandardView/back": "<Shift>h",
    "<Actions>/ThunarStandardView/forward": "<Shift>l",
    "<Actions>/ThunarActionManager/copy-2": "y",
    "<Actions>/ThunarActionManager/cut-2": "x",
    "<Actions>/ThunarActionManager/paste-2": "p",
    "<Actions>/ThunarActionManager/move-to-trash": "d",
    "<Actions>/ThunarActionManager/delete": "<Shift>d",
    "<Actions>/ThunarStandardView/rename": "r",
    "<Actions>/ThunarStandardView/create-folder": "a",
    "<Actions>/ThunarWindow/show-hidden": "period",
    "<Actions>/ThunarWindow/search": "s",
    "<Actions>/ThunarWindow/new-tab": "t",
    "<Actions>/ThunarWindow/close-window": "q",
}
ENTRY = re.compile(r'^\s*;?\s*\(gtk_accel_path "([^"]+)" "([^"]*)"\)\s*$')


def entry(path: str) -> str:
    return f'(gtk_accel_path "{path}" "{ACCELS[path]}")'


out: list[str] = []
seen: set[str] = set()
for line in sys.stdin.read().splitlines():
    match = ENTRY.match(line)
    if match and match[1] in ACCELS:
        if match[1] not in seen:
            seen.add(match[1])
            out.append(line if match[2] == ACCELS[match[1]] else entry(match[1]))
        continue
    out.append(line)
out += [entry(path) for path in ACCELS if path not in seen]
sys.stdout.write("\n".join(out) + "\n")

#!/usr/bin/python3
"""Save the in-memory log of an i3 that crashed, then turn that log on.

i3 logs to shared memory only while `shmlog` is on. A restart, including `r`
on the crash screen, turns it off but leaves the old log until it is turned on
again, so this runs at every i3 start, before turning it on.
"""

from __future__ import annotations

import gzip
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import time

SHM = Path(os.environ.get("I3_CRASH_SHM_DIR", "/dev/shm"))
LOGS = Path(os.environ.get("I3_CRASH_LOG_DIR", Path.home() / ".local/state/i3/crash"))
KEEP = 10
MARKER = b"i3 crashed. SIG:"
HEADER = struct.Struct("<IIII")  # next write, last wrap, size, wrap count


def log_text(data: bytes) -> bytes:
    """The log oldest first, as i3-dump-log prints it."""
    if len(data) < HEADER.size:
        return b""
    next_write, last_wrap, _size, _wraps = HEADER.unpack_from(data)
    older = b""
    if data[next_write:next_write + 1] not in (b"", b"\0"):  # Wrapped at least once.
        older = data[next_write:last_wrap]
        older = older[older.find(b"\n") + 1:]  # The first old line is partly overwritten.
    return (older + data[HEADER.size:next_write]).replace(b"\0", b"")


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    return True


def save(text: bytes) -> Path | None:
    digest = hashlib.sha256(text[-65536:]).hexdigest()[:8]
    if any(LOGS.glob(f"i3-crash-*-{digest}.log.gz")):
        return None
    LOGS.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = LOGS / f"i3-crash-{time.strftime('%Y%m%d-%H%M%S')}-{digest}.log.gz"
    temporary = path.with_suffix(".tmp")
    with gzip.open(temporary, "wb") as out:
        out.write(text)
    temporary.chmod(0o600)
    temporary.replace(path)
    return path


def rescue() -> list[Path]:
    saved = []
    for shm in sorted(SHM.glob("i3-log-*")):
        try:
            pid = int(shm.name.removeprefix("i3-log-"))
            if shm.stat().st_uid != os.getuid():
                continue
            text = log_text(shm.read_bytes())
        except (ValueError, OSError):
            continue
        if MARKER in text and (path := save(text)):
            saved.append(path)
        if not alive(pid):
            shm.unlink(missing_ok=True)  # Its i3 is gone; free the memory.
    for old in sorted(LOGS.glob("i3-crash-*.log.gz"))[:-KEEP]:
        old.unlink(missing_ok=True)
    return saved


def main() -> int:
    for path in rescue():
        shown = str(path).replace(str(Path.home()), "~", 1)
        try:
            subprocess.run(["notify-send", "-u", "critical", "i3 crashed", f"Log saved: {shown}"], check=False)
        except OSError:
            pass
    return subprocess.run(["i3-msg", "-q", "shmlog on"], check=False, timeout=10).returncode


if __name__ == "__main__":
    raise SystemExit(main())

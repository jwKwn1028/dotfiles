#!/usr/bin/python3

"""End-to-end check of overflow-watcher.py against a real, throwaway i3.

Starts Xephyr, runs i3 + autotiling + the watcher inside it, drives real xterms
through every rule, then tears the whole thing down. The running session is
never touched. Needs Xephyr, xterm and autotiling available.

    ./test-overflow-live.py           # single screen, then dual screen
    ./test-overflow-live.py single    # one screen only
    ./test-overflow-live.py dual      # two screens only (workspaces 7-10 on the second)

Unlike test-overflow-watcher.py, which exercises the pure functions in
milliseconds, this one takes a couple of minutes and catches what unit tests
cannot: whether i3 actually carries out the commands the watcher issues.
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from i3ipc import Connection

HERE = Path(__file__).resolve().parent
WATCHER = HERE.parent / "overflow-watcher.py"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))

i3: Connection = None  # set by boot()
PEEK_LOG: Path = None  # a stub stands in for polybar-peek.sh; see boot()
RESULTS: list[tuple[bool, str, object, object]] = []


# --------------------------------------------------------------- the nested wm
def free_display() -> int:
    for n in range(20, 40):
        if not Path(f"/tmp/.X{n}-lock").exists():
            return n
    raise RuntimeError("no free display number")


def write_config(path: Path, socket: Path, dual: bool) -> None:
    lines = [
        "# i3 config file (v4)",
        f"ipc-socket {socket}",
        "font pango:DejaVu Sans 10",
        "default_border pixel 1",
        "hide_edge_borders smart",
        # Mirrors the real config; it makes "workspace number N" while already on
        # N jump away, which the driver has to account for.
        "workspace_auto_back_and_forth yes",
    ]
    if dual:
        # Same split as the real config: 1-6 on the primary, 7-10 on the other.
        lines += [f"workspace {n}  output xinerama-0" for n in range(1, 7)]
        lines += [f"workspace {n} output xinerama-1" for n in range(7, 11)]
    path.write_text("\n".join(lines) + "\n")


def wait_for(predicate, timeout=15.0, step=0.05):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(step)
    return None


def boot(dual: bool, workdir: Path) -> list[subprocess.Popen]:
    """Bring up Xephyr + i3 + autotiling + the watcher; return what to kill later."""
    global i3, PEEK_LOG

    display = f":{free_display()}"
    # The socket lives under XDG_RUNTIME_DIR because a UNIX path is capped at
    # 108 bytes and a temp dir blows straight past it.
    socket = RUNTIME / f"i3-overflow-test{display[1:]}.sock"
    socket.unlink(missing_ok=True)
    config = workdir / "i3.config"
    write_config(config, socket, dual)

    screens = ["-screen", "1920x1080"] * (2 if dual else 1)
    procs = [
        subprocess.Popen(
            ["Xephyr", display, *(["+xinerama"] if dual else []), *screens, "-ac", "-noreset"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
        )
    ]
    env = {**os.environ, "DISPLAY": display}
    env.pop("I3SOCK", None)
    if not wait_for(lambda: subprocess.run(
        ["xdpyinfo"], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    ).returncode == 0):
        raise RuntimeError(f"Xephyr never came up on {display}")

    # i3 reads RandR, which Xephyr does not emulate, so a second screen only
    # shows up as a separate output under --force-xinerama.
    procs.append(subprocess.Popen(
        ["i3", *(["--force-xinerama"] if dual else []), "-c", str(config)],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
    ))
    if not wait_for(socket.exists):
        raise RuntimeError("nested i3 never created its socket")

    i3 = Connection(socket_path=str(socket))
    env["I3SOCK"] = str(socket)

    # Never let the nested session run the real polybar-peek.sh: it drives
    # Polybar over IPC, which ignores DISPLAY, and would leave the session's own
    # bar stuck on screen. This stub records the calls instead.
    PEEK_LOG = workdir / "peeks"
    PEEK_LOG.touch()
    stub = workdir / "peek-stub.sh"
    stub.write_text(f'#!/bin/sh\necho peek >> "{PEEK_LOG}"\n')
    stub.chmod(0o755)
    env["I3_OVERFLOW_PEEK"] = str(stub)
    autotiling = shutil.which("autotiling") or os.path.expanduser("~/.local/bin/autotiling")
    for argv in ([autotiling, "--limit", "6"], [sys.executable, str(WATCHER)]):
        procs.append(subprocess.Popen(
            argv, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        ))
    time.sleep(1.5)  # let both subscribe before the first window opens
    return procs


def shutdown(procs: list[subprocess.Popen]) -> None:
    for proc in reversed(procs):
        proc.terminate()
    for proc in reversed(procs):
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


# ------------------------------------------------------------------- the driver
def tree():
    return i3.get_tree()


def xterms(t=None):
    return [c for c in (t or tree()).leaves() if c.window_class == "XTerm"]


def ws_of(title, t=None):
    for c in xterms(t):
        if c.name == title:
            ws = c.workspace()
            return ws.num if ws else None
    return None


def ratios(num):
    for ws in tree().workspaces():
        if ws.num == num:
            a = ws.rect.width * ws.rect.height
            return sorted(round(c.rect.width * c.rect.height / a, 3) for c in ws.leaves()) if a else []
    return []


def occupied_map():
    return {ws.num: len(ws.leaves()) for ws in sorted(tree().workspaces(), key=lambda w: w.num)
            if ws.leaves()}


def current_ws():
    ws = tree().find_focused().workspace()
    return ws.num if ws else None


def goto(num):
    # workspace_auto_back_and_forth would bounce us away if we asked twice.
    if current_ws() != num:
        i3.command(f"workspace number {num}")
        wait_for(lambda: current_ws() == num, timeout=5)
    return current_ws()


def settle(title, quiet=0.7, timeout=8.0):
    """Wait until the window's workspace stops changing; the watcher may move it."""
    deadline = time.time() + timeout
    last, stable_since = ws_of(title), time.time()
    while time.time() < deadline:
        time.sleep(0.05)
        now = ws_of(title)
        if now != last:
            last, stable_since = now, time.time()
        elif time.time() - stable_since >= quiet:
            break
    return last


def spawn(title, on=None):
    """Open an xterm on workspace `on`; return where it ends up once things settle."""
    if on is not None:
        landed = goto(on)
        assert landed == on, f"wanted workspace {on}, got {landed}"
    opened = current_ws()
    i3.command(f"exec --no-startup-id xterm -T {title} -e sh -c 'sleep 100000'")
    if not wait_for(lambda: ws_of(title) is not None, timeout=20):
        raise RuntimeError(f"{title} never appeared")
    return opened, settle(title)


def kill_all():
    i3.command('[class="XTerm"] kill')
    wait_for(lambda: not xterms(), timeout=15)
    goto(1)


def pack(num, tag):
    """Open windows on `num` until one overflows; leave it packed. Returns the count."""
    for n in range(1, 9):
        title = f"{tag}{n}"
        _, landed = spawn(title, on=num)
        if landed != num:
            i3.command(f'[title="^{title}$"] kill')
            wait_for(lambda: ws_of(title) is None, timeout=5)
            return n - 1
    return 8


def check(name, got, expected, detail=""):
    ok = got == expected
    RESULTS.append((ok, name, got, expected))
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}: got {got}, expected {expected} {detail}")


# ---------------------------------------------------------------- the scenarios
def single_screen():
    print("\nS1  a workspace fills up, the overflow goes to the next empty one")
    kill_all()
    seen = []
    for n in range(1, 6):
        opened, landed = spawn(f"a{n}", on=1)
        seen.append(landed)
        print(f"    window {n}: opened on ws{opened} -> ws{landed}   ws1={ratios(1)} ws2={ratios(2)}")
    check("S1 the first three stay put", seen[:3], [1, 1, 1])
    check("S1 the fourth overflows to the first empty workspace", seen[3], 2)
    check("S1 nothing left on ws1 is under a quarter", min(ratios(1)) >= 0.25, True,
          f"sizes={ratios(1)}")

    print("\nS2  cascade past packed workspaces (ws1 packed, ws3 packed, ws4 has room)")
    kill_all()
    print(f"    ws1 packed with {pack(1, 'b')} windows")
    print(f"    ws3 packed with {pack(3, 'c')} windows")
    spawn("d1", on=4)
    print(f"    occupancy before: {occupied_map()}")
    opened, landed = spawn("e1", on=1)
    check("S2 skips packed ws3 and lands on ws4", landed, 4)

    print("\nS3  wrap past workspace 10 to the first occupied one with room")
    kill_all()
    print(f"    ws10 packed with {pack(10, 'f')} windows")
    spawn("g1", on=2)
    print(f"    occupancy before: {occupied_map()}")
    opened, landed = spawn("h1", on=10)
    check("S3 wraps 10 -> 2", landed, 2)

    print("\nS4  nothing else occupied -> the next workspace number, wrapping")
    kill_all()
    print(f"    ws10 packed with {pack(10, 'i')} windows")
    opened, landed = spawn("j1", on=10)
    check("S4 wraps 10 -> 1", landed, 1)

    print("\nS5  a manual move into a packed workspace bounces onward")
    kill_all()
    print(f"    ws3 packed with {pack(3, 'k')} windows")
    spawn("l1", on=4)
    spawn("m1", on=1)
    print(f"    occupancy before: {occupied_map()}")
    # Exactly what move-to-workspace.sh issues for $mod+Shift+<n>.
    i3.command('[title="^m1$"] move container to workspace number 3; workspace number 3')
    check("S5 manual move to packed ws3 lands on ws4", settle("m1"), 4)

    print("\nS6  rearranging inside one workspace is left alone")
    kill_all()
    print(f"    ws1 packed with {pack(1, 'n')} windows, sizes={ratios(1)}")
    before = len(ratios(1))
    i3.command('[title="^n3$"] focus')
    i3.command("move left")
    landed = settle("n3")
    print(f"    after 'move left': sizes={ratios(1)}")
    check("S6 'move left' keeps the window on ws1", landed, 1)
    check("S6 ws1 still holds every window", len(ratios(1)), before)

    print("\nS7  a small floating window is not evicted")
    kill_all()
    spawn("o1", on=1)
    spawn("o2", on=1)
    i3.command('[title="^o2$"] floating enable, resize set 300 200')
    landed = settle("o2")
    con = [c for c in xterms() if c.name == "o2"][0]
    print(f"    o2 floating={con.floating} rect={con.rect.width}x{con.rect.height}")
    check("S7 a 300x200 floating window stays put", landed, 1)

    print("\nS8  the scratchpad is not treated as a workspace")
    kill_all()
    spawn("p1", on=1)
    spawn("p2", on=1)
    i3.command('[title="^p2$"] move scratchpad')
    wait_for(lambda: ws_of("p2") == -1, timeout=5)
    # __i3_scratch reports num -1; the watcher must leave it alone.
    check("S8 a scratchpad window is not bounced to a workspace", ws_of("p2"), -1)

    print("\nS10  a hand-off asks Polybar for a peek, an ordinary window does not")
    kill_all()
    peeks = lambda: len(PEEK_LOG.read_text().split())
    print(f"    ws1 packed with {pack(1, 'r')} windows")
    before = peeks()
    spawn("s1", on=2)  # roomy workspace, nothing moves
    quiet = wait_for(lambda: peeks() > before, timeout=2) or peeks()
    check("S10 no peek when the window simply stays put", peeks(), before)
    opened, landed = spawn("t1", on=1)  # ws1 is packed, so this one is handed off
    wait_for(lambda: peeks() > before, timeout=5)
    print(f"    window moved to ws{landed}, peek calls {before} -> {peeks()}")
    check("S10 a relocated window triggers exactly one peek", peeks(), before + 1)

    print("\nS11  every workspace packed: hand off once anyway, never ping-pong")
    kill_all()
    for num in range(1, 11):
        pack(num, f"z{num}_")
    print(f"    occupancy: {occupied_map()}")
    peeks = lambda: len(PEEK_LOG.read_text().split())
    before = peeks()
    opened, landed = spawn("last", on=5)
    print(f"    new window on ws{opened} -> ws{landed}, size {ratios(landed)}")
    check("S11 falls back to the next workspace number", landed, 6)
    # One hop only: the watcher's own move is swallowed by the self_moved guard,
    # so a window with nowhere good to go settles instead of circling.
    time.sleep(3)
    check("S11 stays put afterwards", ws_of("last"), 6)
    check("S11 only one peek, so only one move", peeks(), before + 1)
    check("S11 every workspace still holds its windows", len(occupied_map()), 10)


def dual_screen():
    print("\nS9  two screens: workspaces 1-6 on the first, 7-10 on the second")
    kill_all()
    print(f"    ws6 packed with {pack(6, 'q')} windows")
    print(f"    occupancy before: {occupied_map()}  (7-10 never opened)")
    opened, landed = spawn("r1", on=6)
    check("S9a nothing else occupied -> ws7, the first empty", landed, 7)

    kill_all()
    print(f"    ws6 packed with {pack(6, 's')} windows")
    spawn("t1", on=8)
    spawn("u1", on=2)
    print(f"    occupancy before: {occupied_map()}")
    opened, landed = spawn("v1", on=6)
    check("S9b ws8 has room -> crosses to the second screen", landed, 8)

    kill_all()
    print(f"    ws6 packed with {pack(6, 'w')} windows")
    spawn("y1", on=1)
    print(f"    occupancy before: {occupied_map()}  (7-10 still never opened)")
    opened, landed = spawn("z1", on=6)
    check("S9c 7-10 empty but ws1 occupied -> wraps past 6 to ws1", landed, 1)


def run(mode: str) -> None:
    import tempfile

    workdir = Path(tempfile.mkdtemp(prefix="overflow-live-"))
    print(f"=== {mode} screen ===")
    procs = boot(dual=(mode == "dual"), workdir=workdir)
    try:
        (dual_screen if mode == "dual" else single_screen)()
        kill_all()
    finally:
        shutdown(procs)
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    if not WATCHER.exists():
        sys.exit(f"cannot find {WATCHER}")
    for missing in [b for b in ("Xephyr", "xterm", "i3") if not shutil.which(b)]:
        sys.exit(f"{missing} is not installed")

    for mode in (sys.argv[1:] or ["single", "dual"]):
        run(mode)

    failed = [r for r in RESULTS if not r[0]]
    print("\n" + "=" * 62)
    for ok, name, *_ in RESULTS:
        print(f"{'PASS' if ok else 'FAIL'}  {name}")
    print(f"{len(RESULTS) - len(failed)}/{len(RESULTS)} passed")
    sys.exit(1 if failed else 0)

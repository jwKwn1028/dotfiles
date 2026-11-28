#!/usr/bin/env python3
"""Restore focus across sessions before clients attach, using the real plugin."""

import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

BIN = Path(__file__).resolve().parent.parent
SOURCE = BIN / "executable_tmux-resurrect-focus"
CONFIG = BIN.parent.parent / "dot_tmux.conf"
if not SOURCE.exists():
    SOURCE, CONFIG = BIN / "tmux-resurrect-focus", Path.home() / ".tmux.conf"
PLUGIN = Path.home() / ".tmux/plugins/tmux-resurrect/scripts"
TMUX = shutil.which("tmux")
if not TMUX or not (PLUGIN / "restore.sh").is_file():
    print("SKIP: tmux and tmux-resurrect are required")
    sys.exit(0)

with tempfile.TemporaryDirectory(prefix="resurrect-focus-") as directory:
    root = Path(directory)
    socket, saved = root / "tmux.sock", root / "snapshot"
    bin_dir = root / "bin"
    bin_dir.mkdir()
    log = root / "calls"
    (bin_dir / "tmux").write_text(
        '#!/bin/sh\n[ "${FOCUS_TRACE-}" != 1 ] || printf "call\\n" >> "$FOCUS_LOG"\n'
        + "exec " + shlex.quote(TMUX) + ' "$@"\n')
    entry = bin_dir / "tmux-resurrect-focus"
    entry.write_text("#!/bin/sh\nFOCUS_TRACE=1 exec " + shlex.join([sys.executable, "-B", str(SOURCE)]) + ' "$@"\n')
    for path in bin_dir.iterdir():
        path.chmod(0o755)
    env = {key: value for key, value in os.environ.items() if key not in ("TMUX", "TMUX_PANE")}
    env.update(TMUX=f"{socket},0,0", PATH=f"{bin_dir}:{env['PATH']}", FOCUS_LOG=str(log), TERM="xterm-256color")
    hook = re.search(r"^set -g @resurrect-hook-post-restore-all '(.*)'$", CONFIG.read_text(), re.M)[1]
    hook = hook.replace("~/.local/bin/tmux-resurrect-focus", shlex.quote(str(entry)))

    def tmux(*args):
        return subprocess.run([TMUX, "-S", str(socket), *args], env=env,
                              capture_output=True, text=True, check=True).stdout

    def configure():
        for option, value in (("base-index", "1"), ("pane-base-index", "1"),
                              ("renumber-windows", "on"), ("default-shell", "/bin/sh"),
                              ("default-command", "exec /bin/sh"), ("@resurrect-dir", str(saved)),
                              ("@resurrect-processes", "false"),
                              ("@resurrect-hook-pre-restore-all", "tmux set -s @resurrect-restoring 1"),
                              ("@resurrect-hook-post-restore-all", hook)):
            tmux("set", "-g", option, value)

    def focus():
        sessions = {}
        for line in tmux("list-windows", "-a", "-F",
                         "#{session_name}\t#{window_index}\t#{window_active}\t#{window_flags}\t#{window_zoomed_flag}").splitlines():
            session, window, active, flags, zoomed = line.split("\t")
            data = sessions.setdefault(session, dict(active=None, alternate=None, panes={}, zoomed=[]))
            if active == "1":
                data["active"] = window
            if "-" in flags:
                data["alternate"] = window
            if zoomed == "1":
                data["zoomed"].append(window)
        for line in tmux("list-panes", "-a", "-F",
                         "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_active}").splitlines():
            session, window, pane, active = line.split("\t")
            if active == "1":
                sessions[session]["panes"][window] = pane
        return sessions

    try:
        tmux("-f", "/dev/null", "new-session", "-d", "-s", "0", "-x", "120", "-y", "30", "sleep 300")
        configure()
        sessions = ("alpha", "alpha-extra", "beta space")
        for index, session in enumerate(sessions):
            tmux("new-session", "-d", "-s", session, "sleep 300")
            for window in range(1, 4):
                target = f"={session}:{window}"
                if window > 1:
                    tmux("new-window", "-d", "-t", target, "sleep 300")
                tmux("split-window", "-hd", "-t", target, "sleep 300")
                tmux("select-pane", "-t", f"{target}.{1 + (index + window) % 2}")
            tmux("select-window", "-t", f"={session}:{1 + (index + 1) % 3}")
            tmux("select-window", "-t", f"={session}:{1 + index % 3}")
        tmux("resize-pane", "-Z", "-t", "=alpha:2")
        tmux("resize-pane", "-Z", "-t", "=beta space:1")
        tmux("new-session", "-d", "-s", "linked", "-t", "=alpha")
        tmux("select-window", "-t", "=linked:1")
        tmux("select-window", "-t", "=linked:3")
        tmux("kill-session", "-t", "=0")
        expected = focus()
        tmux("run-shell", shlex.quote(str(PLUGIN / "save.sh")) + " quiet")
        tmux("kill-server")
        time.sleep(0.1)
        tmux("-f", "/dev/null", "new-session", "-d", "-s", "0", "-x", "120", "-y", "30", "sleep 300")
        configure()
        assert not tmux("list-clients").strip()
        tmux("run-shell", shlex.quote(str(PLUGIN / "restore.sh")))
        actual = focus()
        assert actual == expected, json.dumps(dict(expected=expected, actual=actual), indent=2)
        assert log.read_text().splitlines() == ["call"], log.read_text()
        assert not tmux("show", "-sqv", "@resurrect-restoring").strip()
        assert tmux("show", "-sqv", "@resurrect-armed").strip() == "1"
        spaced = root / "snapshot with spaces.txt"
        shutil.copy(saved / "last", spaced)
        subprocess.run([str(entry), str(spaced)], env=env, check=True)
        assert focus() == expected, focus()
        assert log.read_text().splitlines() == ["call", "call"], log.read_text()
    finally:
        subprocess.run([TMUX, "-S", str(socket), "kill-server"], env=env, capture_output=True)

print("PASS: one tmux batch restores pane focus, zoom and window history across ordinary and grouped sessions without attached clients")

#!/usr/bin/env python3
"""tmux-resurrect-post-save rebuilds saved pane lines from a live tmux server."""

import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

BIN_DIR = Path(__file__).resolve().parent.parent
SCRIPT = BIN_DIR / "executable_tmux-resurrect-post-save"
if not SCRIPT.exists():
    SCRIPT = BIN_DIR / "tmux-resurrect-post-save"
PROCESSES = 'btop hx hpc hpcz micro fancy-cat sysmon "yazi->y" "~^ssh [-A-Za-z0-9_.@:=/ ]+$"'

if not shutil.which("tmux") or not shutil.which("zsh"):
    print("SKIP: tmux and zsh are required")
    sys.exit(0)

with tempfile.TemporaryDirectory(prefix="resurrect-post-save-") as directory:
    root = Path(directory)
    docs = Path(os.path.realpath(root / "docs"))
    docs.mkdir()
    (docs / "doc.pdf").write_text("")
    socket_path = root / "tmux.sock"
    env = {key: value for key, value in os.environ.items() if key != "TMUX_PANE"}
    env["TMUX"] = f"{socket_path},0,0"

    def tmux(*args):
        return subprocess.run(["tmux", "-S", str(socket_path), *args], env=env,
                              capture_output=True, text=True, check=True).stdout

    keys = {
        # A PDF opened from Yazi, with the title Yazi leaves empty.
        "0": f"cd {docs} && ARGV0=yazi zsh -fc 'ARGV0=fancy-cat tail -f doc.pdf; :'",
        "1": "sleep 300",
        # Listed programs under an unlisted one are its own business.
        "2": "ARGV0=claude zsh -fc 'tail -f /dev/null; :'",
        "3": "ARGV0=ssh python3 -c 'import time; time.sleep(300)' host 'tmux attach-session -t =work'",
    }
    expected = {
        "0": f"fancy-cat -f {docs}/doc.pdf",
        "1": "sysmon 2",
        "2": "claude -fc 'tail -f /dev/null; :'",
        "3": "hpc work",
    }
    try:
        tmux("-f", "/dev/null", "new-session", "-d", "-s", "t", "-x", "120", "-y", "30", "--", "zsh", "-f")
        tmux("set", "-g", "@resurrect-processes", PROCESSES)
        for window in "123":
            tmux("new-window", "-d", "-t", f"t:{window}", "--", "zsh", "-f")
        for window, command in keys.items():
            tmux("send-keys", "-t", f"t:{window}", command, "Enter")
        tmux("select-pane", "-t", "t:0", "-T", "")
        tmux("set", "-p", "-t", "t:1", "@resurrect-command", "sysmon 2")

        others = ["window\tt\t0\tzsh\t1\t:*\tlayout\t:\n", "state\tt\t\n"]
        saved = root / "save.txt"
        deadline = time.monotonic() + 10
        while True:
            # As resurrect writes them for an empty title: shifted, wrong command.
            panes = [f"pane\tt\t{w}\t{int(w == '0')}\t:\t0\t:/x\t1\tzsh\t123\t:npm exec x\n" for w in "0123"]
            saved.write_text("".join(panes + others))
            subprocess.run(["python3", str(SCRIPT), str(saved)], env=env, check=True)
            lines = saved.read_text().splitlines(keepends=True)
            fields = {line.split("\t")[2]: line.rstrip("\n").split("\t") for line in lines if line.startswith("pane\t")}
            got = {window: fields[window][10][1:] for window in fields}
            if got == expected or time.monotonic() > deadline:
                break
            time.sleep(0.2)

        assert got == expected, got
        assert lines[-2:] == others, lines[-2:]
        for window, line in fields.items():
            assert len(line) == 11 and all(line), line
        assert fields["0"][6] and fields["0"][7] == f":{docs}", fields["0"]
    finally:
        subprocess.run(["tmux", "-S", str(socket_path), "kill-server"], env=env, capture_output=True)

print("PASS: pane lines rebuilt from live tmux")

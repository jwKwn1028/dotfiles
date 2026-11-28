#!/usr/bin/env python3
"""Verify filename labels in real editors, through Yazi and restored Helix."""

import base64
import json
import os
from pathlib import Path
import re
import runpy
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch

BIN = Path(__file__).resolve().parent.parent
ROOT = BIN.parent.parent
SOURCE = BIN / "executable_tmux-editor-titles"
HELIX = BIN / "executable_tmux-resurrect-helix"
if not SOURCE.exists():
    SOURCE, HELIX = BIN / "tmux-editor-titles", BIN / "tmux-resurrect-helix"
    ROOT = Path.home()
CONFIG = ROOT / "dot_config" if (ROOT / "dot_config").is_dir() else ROOT / ".config"
TMUX_CONFIG = ROOT / "dot_tmux.conf" if (ROOT / "dot_tmux.conf").exists() else ROOT / ".tmux.conf"


def check_update_batches():
    for disappearing in (None, "%1"):
        titles = runpy.run_path(str(SOURCE), run_name="titles")["update"].__globals__
        calls, reads, labels = [], [], {}
        names = {f"%{index}": f"buffer-{index}.txt" for index in range(20)}
        activity = "0"

        def fake_tmux(socket, *args):
            calls.append(args)
            if args[0] == "list-panes":
                return "\n".join("\t".join((pane, "123", "/dev/pts/1", "0", "0", labels.get(pane, ""),
                                            activity, "editor")) for pane in names)
            if args[0] == "show-options":
                return "off\n"
            if args[0] == "set-window-option":
                assert args[-1] == "off", args  # Preserve the existing global setting.
                return ""
            commands, command = [], []
            for arg in (*args, ";"):
                if arg == ";":
                    commands.append(command)
                    command = []
                else:
                    command.append(arg)
            for command in commands:
                pane = command[command.index("-t") + 1]
                if pane == disappearing:
                    raise subprocess.CalledProcessError(1, command)
                if "-pu" in command:
                    labels.pop(pane, None)
                else:
                    labels[pane] = command[-1]
            return ""

        def read_filename(socket, pane, *rest):
            reads.append(pane)
            return names[pane]

        with patch.dict(titles, tmux=fake_tmux, editor=lambda *args: ("vim", 123, ["vim"]), filename=read_filename):
            titles["update"]("fake-socket", None)
            assert labels == {pane: name for pane, name in names.items() if pane != disappearing}, labels
            if disappearing is None:
                assert len(calls) == 4, calls  # List, one write batch, read/reapply rename setting.
                before = len(reads)
                calls.clear()
                titles["update"]("fake-socket", None)
                assert len(calls) == 1 and len(reads) == before, (calls, reads)
                names["%3"] = ""
                activity = "1"  # Redraw invalidates the cache.
                titles["update"]("fake-socket", None)
                assert "%3" not in labels, labels
            else:
                # A failure after the first mutation must not prevent later labels.
                assert labels["%19"] == names["%19"]
                writes = [args for args in calls if args[0] == "set-option"]
                assert len(writes) == 21 and ";" in writes[0], writes


check_update_batches()

if any(not shutil.which(command) for command in ("tmux", "hx", "micro", "nano", "vim", "yazi", "zsh")):
    print("SKIP: tmux, hx, micro, nano, vim, yazi and zsh are required")
    sys.exit(0)

with tempfile.TemporaryDirectory(prefix="tmux-editor-titles-") as directory:
    root = Path(directory)
    a, b = root / "first notes.txt", root / "second notes.txt"
    for file in (a, b):
        file.write_text("first line\nsecond line\n")
    config = root / "config"
    (root / "runtime").mkdir(mode=0o700)
    shutil.copytree(CONFIG / "helix", config / "helix")
    (config / "micro").mkdir()
    shutil.copy(CONFIG / "micro/settings.json", config / "micro/settings.json")
    shutil.copytree(CONFIG / "micro/colorschemes", config / "micro/colorschemes")
    (config / "micro/bindings.json").write_text(json.dumps({"Alt-.": "NextTab", "Alt-,": "PreviousTab"}))
    (config / "yazi").mkdir()
    (config / "yazi/yazi.toml").write_text("""[opener]
edit = [{ run = 'hx %s', block = true }]
[open]
rules = [{ url = "*", use = "edit" }]
""")
    nanorc = root / "nanorc"
    nanorc.write_text("set minibar\nset constantshow\nset stateflags\nset multibuffer\nbind M-. nextbuf main\n")
    for source, name in ((SOURCE, "tmux-editor-titles"), (HELIX, "tmux-resurrect-helix")):
        (root / "bin").mkdir(exist_ok=True)
        shutil.copy(source, root / "bin" / name)
        (root / "bin" / name).chmod(0o755)
    socket = str(root / "tmux.sock")
    env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_CACHE_HOME=str(root / "cache"),
               XDG_STATE_HOME=str(root / "state"), XDG_RUNTIME_DIR=str(root / "runtime"), MICRO_CONFIG_HOME=str(config / "micro"),
               YAZI_CONFIG_HOME=str(config / "yazi"), TMUX=f"{socket},0,0", PATH=f"{root / 'bin'}:{os.environ['PATH']}")
    env.pop("TMUX_PANE", None)
    rename = re.search(r"^setw -g automatic-rename-format '(.*)'$", TMUX_CONFIG.read_text(), re.M)[1]

    def tmux(*args):
        return subprocess.run(["tmux", "-S", socket, *args], env=env,
                              capture_output=True, text=True, check=True).stdout

    def send(target, text):
        tmux("send-keys", "-t", target, "-l", text)
        tmux("send-keys", "-t", target, "Enter")

    def capture(target):
        return tmux("capture-pane", "-p", "-t", target)

    def wait(target, predicate):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.1)
        name = tmux("display-message", "-p", "-t", target, "#{window_name}|#{E:automatic-rename-format}").strip()
        raise AssertionError(f"{target}: {name}\n{capture(target)}")

    def label(target, expected, once=True):
        def check():
            if once:
                subprocess.run(["python3", "-B", str(SOURCE), socket], env=env, check=True)
            return tmux("show-options", "-pqv", "-t", target, "@editor_filename").strip() == expected
        wait(target, check)
        if expected:
            wait(target, lambda: tmux("display-message", "-p", "-t", target, "#{window_name}").strip() == expected)

    watcher = None
    try:
        tmux("-f", "/dev/null", "new-session", "-d", "-s", "t", "-x", "130", "-y", "25", "sleep 120")
        tmux("set-window-option", "-g", "automatic-rename-format", rename)
        # Labels remain literal tmux arguments, including separator-like filenames.
        unusual = (";", "trailing;", "backslash\\;", "semi;colon '\"$()`{}")
        literal_panes = [tmux("new-window", "-d", "-P", "-F", "#{pane_id}", "sleep 120").strip()
                         for _ in unusual]
        literal_labels = dict(zip(literal_panes, unusual))
        titles = runpy.run_path(str(SOURCE), run_name="titles")["update"].__globals__
        tmux("set-window-option", "-g", "automatic-rename", "off")
        with patch.dict(titles, editor=lambda *args: ("vim", 123, ["vim"]),
                        filename=lambda socket, pane, *rest: literal_labels.get(pane, "")):
            titles["update"](socket, None)
        for pane, expected in literal_labels.items():
            assert tmux("show-options", "-pqv", "-t", pane, "@editor_filename").rstrip("\n") == expected
            tmux("kill-window", "-t", pane)
        assert tmux("show-options", "-gwv", "automatic-rename").strip() == "off"
        tmux("set-window-option", "-g", "automatic-rename", "on")
        commands = {
            "1": ["hx", str(a), str(b)],
            "2": ["micro", str(a), str(b)],
            "3": ["nano", "-f", str(nanorc), str(a), str(b)],
            "4": ["vim", "-Nu", "NONE", "-n", "-i", "NONE", "-c", "set title titlelen=0 titlestring=editor:%t", "--", str(a), str(b)],
            "5": ["yazi", str(a)],
            "6": ["python3", "-c", "import time; time.sleep(120)", str(a)],
        }
        state = dict(options=[], views=[[str(a), 1, 1]], hidden=[], split=None, focus=0, cwd=str(root))
        payload = base64.urlsafe_b64encode(json.dumps(state).encode()).decode()
        commands["7"] = [str(root / "bin/tmux-resurrect-helix"), payload]
        for number, command in commands.items():
            target = f"t:{number}"
            tmux("new-window", "-d", "-t", target, "-c", str(root), "--", "zsh", "-f")
            send(target, "TERM=xterm-256color " + shlex.join(command))
        for number in ("1", "2", "3", "4", "7"):
            label(f"t:{number}", a.name)
        label("t:6", "")
        # Buffer switches must change the label rather than retaining argv[1].
        send("t:1", ":open 'second notes.txt'")
        tmux("send-keys", "-t", "t:2", "M-.")
        tmux("send-keys", "-t", "t:3", "M-.")
        send("t:4", ":next")
        send("t:7", ":open 'second notes.txt'")
        for number in ("1", "2", "3", "4", "7"):
            label(f"t:{number}", b.name)
        # Nano replaces its line count with state flags while modified.
        tmux("send-keys", "-t", "t:3", "-l", "x")
        label("t:3", b.name)
        send("t:1", ":open 'not saved.txt'")
        label("t:1", "not saved.txt")
        # Use the real Yazi opener, including its blocking child process.
        wait("t:5", lambda: "first notes.txt" in capture("t:5"))
        tmux("send-keys", "-t", "t:5", "Enter")
        label("t:5", a.name)
        send("t:5", ":qa!")
        label("t:5", "")
        send("t:7", ":qa!")
        label("t:7", "")
        tmux("rename-window", "-t", "t:4", "manual name")
        send("t:4", ":previous")
        wait("t:4", lambda: "editor:first notes.txt" in tmux("display-message", "-p", "-t", "t:4", "#{pane_title}"))
        subprocess.run(["python3", "-B", str(SOURCE), socket], env=env, check=True)
        assert tmux("display-message", "-p", "-t", "t:4", "#{window_name}").strip() == "manual name"
        # Idle panes are not re-read; a redraw is.
        titles = runpy.run_path(str(SOURCE), run_name="titles")["update"].__globals__
        screen = runpy.run_path(str(HELIX))["screen"]
        os.environ["TMUX"] = env["TMUX"]
        hx_pane, reads, read = tmux("display-message", "-p", "-t", "t:1", "#{pane_id}").strip(), [], titles["filename"]
        titles["filename"] = lambda socket, pane, *rest: reads.append(pane) or read(socket, pane, *rest)
        time.sleep(1.1)
        titles["update"](socket, screen)
        time.sleep(1.1)
        before = reads.count(hx_pane)
        titles["update"](socket, screen)
        assert reads.count(hx_pane) == before == 1, reads
        send("t:1", ":open 'second notes.txt'")
        wait("t:1", lambda: titles["update"](socket, screen) or
             tmux("show-options", "-pqv", "-t", "t:1", "@editor_filename").strip() == b.name)
        # The watcher updates titles without input hooks and is one per server.
        watcher = subprocess.Popen(["python3", "-B", str(SOURCE), "--watch", socket], env=env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        send("t:1", ":open 'first notes.txt'")
        label("t:1", a.name, once=False)
        duplicate = subprocess.run(["python3", "-B", str(SOURCE), "--watch", socket], env=env,
                                   capture_output=True, text=True, timeout=5)
        assert duplicate.returncode == 0 and watcher.poll() is None, duplicate.stderr
        tmux("kill-server")
        assert watcher.wait(timeout=5) == 0, watcher.stderr.read()
    finally:
        subprocess.run(["tmux", "-S", socket, "kill-server"], env=env, capture_output=True)
        if watcher is not None and watcher.poll() is None:
            watcher.terminate()
            watcher.wait(timeout=5)

print("PASS: editor filenames follow active buffers in Helix, Micro, nano and Vim, including Yazi and restored wrappers; labels clear on exit")

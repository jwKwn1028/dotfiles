#!/usr/bin/env python3
"""Save live Helix panes, reopen the saved commands, and inspect editor state."""

import base64
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

BIN_DIR = Path(__file__).resolve().parent.parent
SCRIPT = BIN_DIR / "executable_tmux-resurrect-post-save"
HELPER = BIN_DIR / "executable_tmux-resurrect-helix"
if not SCRIPT.exists():
    SCRIPT = BIN_DIR / "tmux-resurrect-post-save"
    HELPER = BIN_DIR / "tmux-resurrect-helix"
HELIX_CONFIG = BIN_DIR.parent.parent / "dot_config/helix"
if not HELIX_CONFIG.is_dir():
    HELIX_CONFIG = Path.home() / ".config/helix"

if any(not shutil.which(command) for command in ("tmux", "hx", "zsh", "git")):
    print("SKIP: tmux, hx, zsh and git are required")
    sys.exit(0)

with tempfile.TemporaryDirectory(prefix="resurrect-helix-") as directory:
    root = Path(os.path.realpath(directory))
    project, outside = root / "project", root / "outside"
    for folder in (project / "src", outside, project / "logs"):
        folder.mkdir(parents=True)
    quoted = "both 'and`\" %%sh{false}.txt"
    names = ["notes.txt", "src/main.txt", "hidden.txt", "foreign.txt", "my notes 한글.txt", quoted,
             "it's %sh{false}.txt", "a_rather_long_directory_name/deeper/report_draft_final.txt"]
    for name in names:
        file = project / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text("".join(f"line {n}\n" for n in range(1, 301)))
    (outside / "foreign.txt").write_text("".join(f"outside {n}\n" for n in range(1, 101)))
    many = [f"many/overflow_module_number_{n}_analysis.txt" for n in range(1, 9)]
    for name in many:
        (project / name).parent.mkdir(exist_ok=True)
        (project / name).write_text("line 1\n")
    # Buffers are looked up among the repository's files; ignored output is skipped.
    (project / ".gitignore").write_text("output/\n")
    (project / "output").mkdir()
    (project / "output/notes.txt").write_text("ignored\n")
    subprocess.run(["git", "init", "-q", str(project)], check=True)
    config = root / "config/helix"
    config.mkdir(parents=True)
    (root / "config/zsh").mkdir()
    shutil.copy(HELIX_CONFIG / "config.toml", config)
    shutil.copytree(HELIX_CONFIG / "themes", config / "themes")
    custom = project / "custom.toml"
    custom.write_text((config / "config.toml").read_text().replace(
        'line-number = "relative"', 'line-number = "absolute"'))
    (root / "bin").mkdir()
    shutil.copy(HELPER, root / "bin/tmux-resurrect-helix")
    (root / "bin/tmux-resurrect-helix").chmod(0o755)
    socket_path = root / "tmux.sock"
    env = {key: value for key, value in os.environ.items() if key != "TMUX_PANE"}
    env.update(TMUX=f"{socket_path},0,0", XDG_CONFIG_HOME=str(root / "config"),
               XDG_CACHE_HOME=str(root / "cache"), XDG_STATE_HOME=str(root / "state"),
               XDG_RUNTIME_DIR=str(root / "runtime"),
               ZDOTDIR=str(root / "config/zsh"),
               PATH=f"{root / 'bin'}:{env['PATH']}")

    def tmux(*args):
        return subprocess.run(["tmux", "-S", str(socket_path), *args], env=env,
                              capture_output=True, text=True, check=True).stdout

    def send(target, text):
        tmux("send-keys", "-t", target, "-l", text)
        tmux("send-keys", "-t", target, "Enter")

    def capture(target):
        return tmux("capture-pane", "-p", "-t", target)

    def wait_for(target, predicate):
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            text = capture(target)
            if predicate(text):
                return text
            time.sleep(0.05)
        raise AssertionError(f"Helix did not reach expected state in {target}:\n{text}")

    query = 0

    def current(target):
        # Ask Helix itself, independently of the statusline parser being tested.
        global query
        query += 1
        marker = f"restore-probe-{query}:"
        send(target, ':echo "' + marker + '%{buffer_name}:%{cursor_line}:%{cursor_column}"')
        text = wait_for(target, lambda text: text.splitlines()[-1].strip().startswith(marker))
        name, row, col = text.splitlines()[-1].strip()[len(marker):].rsplit(":", 2)
        cwd = tmux("display-message", "-p", "-t", target, "#{pane_current_path}").strip()
        return str((Path(cwd) / name).resolve()), int(row), int(col)

    def save(target, path):
        session, window = target.split(":")
        path.write_text(f"pane\t{session}\t{window}\t0\t:\t0\t:/x\t1\tzsh\t123\t:hx\n")
        before = geometry(target)
        subprocess.run(["python3", "-B", str(SCRIPT), str(path)], env=env, check=True)
        assert geometry(target) == before, (target, before, geometry(target))
        fields = path.read_text().rstrip("\n").split("\t")
        command = fields[10][1:]
        words = shlex.split(command)
        state = json.loads(base64.urlsafe_b64decode(words[1])) if words[0] == "tmux-resurrect-helix" else None
        return command, state

    def geometry(target):
        return (tmux("display-message", "-p", "-t", target,
                     "#{window_width}\t#{window_height}\t#{window_layout}\t#{window_zoomed_flag}\t#{pane_id}"),
                tmux("show-options", "-w", "-t", target))

    def pending(target):
        return tmux("show-options", "-pqv", "-t", target, "@resurrect-command").strip()

    def move(target, key, count=1):
        for _ in range(count):
            tmux("send-keys", "-t", target, "C-w", key)
        time.sleep(0.1)

    def buffers(target):
        found = set()
        for _ in range(12):
            name = current(target)[0]
            if name in found:
                return found
            found.add(name)
            send(target, ":buffer-next")
        raise AssertionError("buffer iteration did not wrap")

    def view(name, row, col):
        return (str(project / name), row, col)

    # launch, setup actions, restored visible views, focus, hidden files, split
    cases = [
        ("hx 'my notes 한글.txt:5' ../outside/foreign.txt", [("i", "x", "Escape")],
         [view("my notes 한글.txt", 5, 2)], 0, {str(outside / "foreign.txt")}, None),
        ("hx notes.txt:5:3 src/main.txt:7:2 hidden.txt:15:2", [":vsplit src/main.txt", ":open src/main.txt:7:2", ("C-w", "h")],
         [view("notes.txt", 5, 3), view("src/main.txt", 7, 2)], 0, {str(project / "hidden.txt")}, "vsplit"),
        ("hx --hsplit notes.txt:20:3 src/main.txt:9:2", [("C-w", "k")],
         [view("notes.txt", 20, 3), view("src/main.txt", 9, 2)], 0, set(), "hsplit"),
        ("hx --vsplit notes.txt:5 src/main.txt:7:2", [("C-w", "s")],
         [view("src/main.txt", 7, 2)], 0, {str(project / "notes.txt")}, None),
        # Basename lookup can select a different nearby file.
        ("hx notes.txt", [":open ../outside/foreign.txt", ":open notes.txt"],
         [view("notes.txt", 1, 1)], 0, {str(project / "foreign.txt")}, None),
        ("hx -c custom.toml --log logs/custom.log -vv notes.txt:40:3", [],
         [view("notes.txt", 40, 3)], 0, set(), None),
        ("hx notes.txt:10:2", [":vsplit \"it's %%sh{false}.txt\"", ":open \"it's %%sh{false}.txt:15:3\""],
         [view("notes.txt", 10, 2), view("it's %sh{false}.txt", 15, 3)], 1, set(), "vsplit"),
        ("hx --hsplit notes.txt:5:2 src/main.txt:20:3 hidden.txt:10:4", [("C-w", "k")],
         [view("notes.txt", 5, 2), view("src/main.txt", 20, 3), view("hidden.txt", 10, 4)], 1, set(), "hsplit"),
        ("hx -w src src/main.txt:12:3", [], [view("src/main.txt", 12, 3)], 0, set(), None),
        (shlex.join(["hx", "--vsplit", "notes.txt:10:2", quoted + ":20:3"]), [],
         [view("notes.txt", 10, 2), view(quoted, 20, 3)], 1, set(), "vsplit"),
        ("hx notes.txt:5:3", [":vsplit notes.txt", ":open notes.txt:25:2", ("C-w", "h")],
         [view("notes.txt", 5, 3), view("notes.txt", 25, 2)], 0, set(), "vsplit"),
        ("hx notes.txt:5:2", [("C-w", "s"), ":open notes.txt:60:3"],
         [view("notes.txt", 5, 2), view("notes.txt", 60, 3)], 1, set(), "hsplit"),
        ("hx --vsplit notes.txt:40:3 src/main.txt:7 a_rather_long_directory_name/deeper/report_draft_final.txt", [],
         [view("notes.txt", 40, 3), view("src/main.txt", 7, 1),
          view(names[-1], 1, 1)], 2, set(), "vsplit"),
        ("hx notes.txt:10:2", [f":vsplit {names[-1]}", f":open {names[-1]}:20:3"],
         [view("notes.txt", 10, 2), view(names[-1], 20, 3)], 1, set(), "vsplit"),
        ("hx --vsplit notes.txt:40:3 src/main.txt:7 a_rather_long_directory_name/deeper/report_draft_final.txt", [],
         [view("notes.txt", 40, 3), view("src/main.txt", 7, 1),
          view(names[-1], 1, 1)], 2, set(), "vsplit"),
        # Later buffers: sibling and cwd searches.
        ("hx notes.txt", [":open hidden.txt", ":open a_rather_long_directory_name/deeper/report_draft_final.txt",
                          ":open notes.txt", ":vsplit src/main.txt"],
         [view("notes.txt", 1, 1), view("src/main.txt", 1, 1)], 1,
         {str(project / "hidden.txt"), str(project / names[-1])}, "vsplit"),
        # More tabs than the buffer bar shows.
        ("hx notes.txt " + " ".join(many), [], [view("notes.txt", 1, 1)], 0,
         {str(project / name) for name in many}, None),
        # A buffer outside the working directory after :cd (as Yazi's Ctrl+Y does).
        ("hx src/main.txt", [":cd src", ":open ../notes.txt", ":open main.txt"],
         [view("src/main.txt", 1, 1)], 0, {str(project / "notes.txt")}, None),
    ]
    try:
        tmux("-f", "/dev/null", "new-session", "-d", "-s", "t", "-x", "160", "-y", "35", "sleep 300")
        tmux("set", "-g", "@resurrect-processes", "hx tmux-resurrect-helix")
        tmux("set", "-gw", "window-size", "manual")
        for number, (launch, actions, visible, focus, hidden, split) in enumerate(cases, 1):
            source, restored = f"t:{number}", f"t:{number + 20}"
            tmux("new-window", "-d", "-t", source, "-c", str(project), "--", "zsh", "-f")
            if number in (14, 15):
                tmux("split-window", "-hd", "-t", source, "sleep 300")
                tmux("set-window-option", "-t", source, "window-size", "manual")
                if number == 15:
                    tmux("resize-pane", "-Z", "-t", source)
            send(source, "TERM=xterm-256color " + launch)
            wait_for(source, lambda text: " sel" in text)
            for action in actions:
                if isinstance(action, str):
                    send(source, action)
                else:
                    for key in action:
                        tmux("send-keys", "-t", source, key)
                time.sleep(0.15)
            before = current(source)
            command, state = save(source, root / "save.txt")
            assert state is not None, (number, command)
            assert state["split"] == split, (number, state, capture(source))
            assert state["focus"] == focus, (number, state)
            assert before == visible[focus], (number, before, visible)
            if number == 6:
                assert state["options"] == ["-c", str(custom), "--log", str(project / "logs/custom.log"), "-vv"], state
            tmux("new-window", "-d", "-t", restored, "-c", str(project), "--", "zsh", "-f")
            if number in (14, 15):
                tmux("split-window", "-hd", "-t", restored, "sleep 300")
                tmux("set-window-option", "-t", restored, "window-size", "manual")
                if number == 15:
                    tmux("resize-pane", "-Z", "-t", restored)
            before_restore = geometry(restored)
            send(restored, "TERM=xterm-256color " + command)
            wait_for(restored, lambda text: text.count(" sel") == len(visible))
            wait_for(restored, lambda text: not pending(restored))
            assert geometry(restored) == before_restore, (number, before_restore, geometry(restored))
            # Re-saving the reopened editor checks wrapper traversal, too.
            deadline = time.monotonic() + 12
            while True:
                _, again = save(restored, root / "again.txt")
                if (again and again["views"] == [list(v) for v in visible] and
                        again["focus"] == focus and again["options"] == state["options"]):
                    break
                assert time.monotonic() < deadline, (number, again, state)
                time.sleep(0.05)
            assert current(restored) == visible[focus], (number, capture(restored))
            if not split:
                command_name = tmux("display-message", "-p", "-t", restored, "#{pane_current_command}").strip()
                assert command_name == "hx", (number, command_name)
            if split:
                backward, forward = ("h", "l") if split == "vsplit" else ("k", "j")
                move(restored, backward, len(visible))
                for index, expected in enumerate(visible):
                    assert current(restored) == expected, (number, index, capture(restored))
                    if index + 1 < len(visible):
                        move(restored, forward)
            found, wanted = buffers(restored), {path for path, _, _ in visible} | hidden
            assert found == wanted, (number, sorted(found - wanted), sorted(wanted - found))
            if number == 6:
                send(restored, ":get-option line-number")
                wait_for(restored, lambda text: "absolute" in text.splitlines()[-1])
            tmux("kill-window", "-t", source)
            tmux("kill-window", "-t", restored)
        # A fully drawn name that is no file ([scratch]) saves without resizing.
        tmux("new-window", "-d", "-t", "t:40", "-c", str(project), "--", "zsh", "-f")
        send("t:40", "TERM=xterm-256color hx")
        wait_for("t:40", lambda text: "[scratch]" in text)
        tmux("set-hook", "-g", "window-resized", "set -g @resized 1")
        started = time.monotonic()
        command, state = save("t:40", root / "scratch.txt")
        assert (command, state) == ("hx", None) and time.monotonic() - started < 1, (command, state)
        assert not tmux("show-options", "-gqv", "@resized").strip(), "saving [scratch] resized the window"
    finally:
        subprocess.run(["tmux", "-S", str(socket_path), "kill-server"], env=env, capture_output=True)

print("PASS: Helix restores files, cursors, startup buffers and simple splits including repeated files and clipped paths; tmux geometry is preserved")

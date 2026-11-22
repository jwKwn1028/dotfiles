#!/usr/bin/env python3
"""tmux-resurrect-alt-screens drops empty prompts from a shell pane's saved text."""

import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path

BIN_DIR = Path(__file__).resolve().parent.parent
SCRIPT = BIN_DIR / "executable_tmux-resurrect-alt-screens"
if not SCRIPT.exists():
    SCRIPT = BIN_DIR / "tmux-resurrect-alt-screens"
BANNER = BIN_DIR.parent.parent / "dot_zsh/rc.d/15-banner.zsh.tmpl"
if not BANNER.is_file():
    BANNER = Path.home() / ".zsh/rc.d/15-banner.zsh"

if not shutil.which("tmux"):
    print("SKIP: tmux is required")
    sys.exit(0)

PROMPT = "\n\x1b[1m\x1b[34m…/dir\x1b[0m on \x1b[1m\x1b[35m main\x1b[0m \n\x1b[1m\x1b[32m❯\x1b[0m "
TYPED = PROMPT.rstrip(" ")
NORMAL = PROMPT.replace("❯", "❮")
HEAD = ("\n\x1b[1m\x1b[38;2;134;190;67m" + " " * 30 + "Welcome Back\x1b[0m\n\x1b[38;5;245m" + " " * 28
        + "2026-01-01 00:00:00\x1b[39m\n\n")
OFF = TYPED + " poweroff\nPower off host? [y/N] (10s timeout): y\n"
output = "\x1b[32m✓\x1b[0m\n\n\x1b[32m❯\x1b[0m\nImportant test result\n"
saved = (TYPED + " ls\nfile1\n" + PROMPT + "\n" + NORMAL + "\n" + TYPED + " run-tests\n" + output
         + OFF + HEAD + PROMPT + "\n").lstrip("\n")
merged = (TYPED + " ls\nfile1\n" + TYPED + " run-tests\n" + output).lstrip("\n")

with tempfile.TemporaryDirectory(prefix="resurrect-alt-screens-") as directory:
    root = Path(directory)
    contents = root / "pane_contents"
    contents.mkdir()
    (contents / "pane-work desk:0.0").write_text(saved)
    (contents / "pane-work desk:1.0").write_text("full-screen app\n")
    archive = root / "pane_contents.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(contents, arcname="./pane_contents")
    shutil.rmtree(contents)
    socket_path = root / "tmux.sock"
    env = {key: value for key, value in os.environ.items() if key != "TMUX_PANE"}
    env["TMUX"] = f"{socket_path},0,0"
    tmux = ["tmux", "-S", str(socket_path)]
    try:
        subprocess.run([*tmux, "-f", "/dev/null", "new-session", "-d", "-s", "work desk", "--", "zsh", "-f"],
                       env=env, check=True)
        subprocess.run([*tmux, "set", "-g", "@resurrect-dir", str(root)], env=env, check=True)
        subprocess.run([*tmux, "new-window", "-d", "-t", "=work desk:1", "--", "sh", "-c",
                        r"printf 'shell screen\n\033[?1049happ screen\n'; exec sleep 15"], env=env, check=True)
        deadline = time.monotonic() + 3
        while subprocess.check_output([*tmux, "display", "-p", "-t", "=work desk:1", "#{alternate_on}"],
                                      env=env, text=True).strip() != "1":
            assert time.monotonic() < deadline, "alternate screen did not activate"
            time.sleep(0.05)
        subprocess.run(["sh", str(SCRIPT)], env=env, check=True)

        functions = re.findall(r"(?ms)^_zsh_banner_[a-z]+\(\) \{\n.*?^\}", BANNER.read_text())
        (root / ".zshrc").write_text("\n".join(functions) + """
setopt promptsubst
ZSH_BANNER_ACTIVE=1 ZSH_BANNER_TEXT='Restore banner 100%' ZSH_BANNER_COLOR='#86BE43'
ZSH_BANNER_TIME='2026-01-01 12:34:56' ZSH_BANNER_TASKLIST=''
PROMPT='ready %# '
_zsh_banner_install
""")
        subprocess.run([*tmux, "new-window", "-d", "-t", "=work desk:2", "-e", f"ZDOTDIR={root}",
                        "--", "zsh", "-i"], env=env, check=True)
        capture = [*tmux, "capture-pane", "-pJ", "-S", "-", "-t", "=work desk:2"]
        deadline = time.monotonic() + 3
        while "Restore banner 100%" not in subprocess.check_output(capture, env=env, text=True):
            assert time.monotonic() < deadline, "Zsh banner did not appear"
            time.sleep(0.05)
        for width, height in ((95, 16), (70, 8), (92, 25)):
            subprocess.run([*tmux, "resize-window", "-t", "=work desk:2", "-x", str(width), "-y", str(height)],
                           env=env, check=True)
            time.sleep(0.2)
        redraw = subprocess.check_output(capture, env=env, text=True)
        assert redraw.count("Restore banner 100%") == 1, "Zsh banner repeated after a tmux resize"
    finally:
        subprocess.run([*tmux, "kill-server"], env=env, capture_output=True)
    with tarfile.open(archive) as tar:
        got = tar.extractfile("./pane_contents/pane-work desk:0.0").read().decode()
        alternate = tar.extractfile("./pane_contents/pane-work desk:1.0").read().decode()
    assert got == merged, repr(got)
    assert alternate == "shell screen\n", repr(alternate)

print("PASS: saved pane cleanup preserves output and tmux resizes keep one startup banner")

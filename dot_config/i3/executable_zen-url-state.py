#!/usr/bin/env python3
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time

try:
    import lz4.block
except Exception:
    print("[]")
    sys.exit(0)


URL_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


BROWSER_CLASSES = {"zen": "zen", "helium": "helium"}


def normalize_title(title):
    title = title or ""
    for suffix in (
        " \u2014 Zen Browser",
        " - Zen Browser",
        " \u2014 Zen",
        " - Zen",
        " \u2014 Helium",
        " - Helium",
    ):
        if title.endswith(suffix):
            title = title[: -len(suffix)]
            break
    return " ".join(title.split())


def is_reopenable_url(url):
    return bool(url and URL_RE.match(url) and url != "about:blank")


def decode_mozlz4(path):
    raw = path.read_bytes()
    if raw.startswith(b"mozLz40\0"):
        raw = raw[8:]
        raw = lz4.block.decompress(raw)
    return json.loads(raw.decode("utf-8"))


def profile_for_session_file(path):
    if path.parent.name == "sessionstore-backups":
        return path.parent.parent
    return path.parent


def firefox_session_files():
    home = pathlib.Path.home()
    roots = os.environ.get(
        "ZEN_PROFILE_ROOTS",
        os.pathsep.join(
            [
                str(home / ".var/app/app.zen_browser.zen/.zen"),
                str(home / ".zen"),
            ]
        ),
    )
    relpaths = (
        "sessionstore-backups/recovery.jsonlz4",
        "sessionstore.jsonlz4",
        "sessionstore-backups/previous.jsonlz4",
    )
    found = []
    for root_name in roots.split(os.pathsep):
        if not root_name:
            continue
        root = pathlib.Path(root_name).expanduser()
        if not root.is_dir():
            continue
        for profile in root.iterdir():
            if not profile.is_dir():
                continue
            for relpath in relpaths:
                path = profile / relpath
                if path.is_file():
                    try:
                        found.append((path.stat().st_mtime, path))
                    except OSError:
                        pass
    found.sort(key=lambda item: item[0], reverse=True)
    return [path for _mtime, path in found]


def zen_session_files():
    home = pathlib.Path.home()
    roots = os.environ.get(
        "ZEN_PROFILE_ROOTS",
        os.pathsep.join(
            [
                str(home / ".var/app/app.zen_browser.zen/.zen"),
                str(home / ".zen"),
            ]
        ),
    )
    found = []
    for root_name in roots.split(os.pathsep):
        if not root_name:
            continue
        root = pathlib.Path(root_name).expanduser()
        if not root.is_dir():
            continue
        for profile in root.iterdir():
            path = profile / "zen-sessions.jsonlz4"
            if path.is_file():
                try:
                    found.append((path.stat().st_mtime, path))
                except OSError:
                    pass
    found.sort(key=lambda item: item[0], reverse=True)
    return [path for _mtime, path in found]


def selected_entry(tab):
    entries = tab.get("entries") or []
    tab_index = tab.get("index") or len(entries)
    try:
        entry_index = int(tab_index) - 1
    except (TypeError, ValueError):
        entry_index = len(entries) - 1
    if entry_index < 0 or entry_index >= len(entries):
        return None
    return entries[entry_index]


def page_from_entry(entry, profile, path, window_index, browser="zen"):
    url = entry.get("url") or ""
    title = entry.get("title") or ""
    if not is_reopenable_url(url):
        return None
    return {
        "title": title,
        "title_key": normalize_title(title),
        "url": url,
        "profile": str(profile),
        "session_file": str(path),
        "session_window_index": window_index,
        "browser": browser,
    }


def pages_from_firefox_session(path):
    profile = profile_for_session_file(path)
    try:
        data = decode_mozlz4(path)
    except Exception:
        return []

    pages = []
    for window_index, window in enumerate(data.get("windows", [])):
        tabs = window.get("tabs") or []
        selected = window.get("selected") or 1
        try:
            selected_index = int(selected) - 1
        except (TypeError, ValueError):
            selected_index = 0
        if selected_index < 0 or selected_index >= len(tabs):
            continue

        entry = selected_entry(tabs[selected_index])
        if not entry:
            continue

        page = page_from_entry(entry, profile, path, window_index)
        if page:
            pages.append(page)
    return pages


def pages_from_zen_session(path):
    profile = path.parent
    try:
        data = decode_mozlz4(path)
    except Exception:
        return []

    pages = []
    for tab_index, tab in enumerate(data.get("tabs") or []):
        entry = selected_entry(tab)
        if not entry:
            continue
        page = page_from_entry(entry, profile, path, tab_index)
        if page:
            pages.append(page)
    return pages


def active_pages():
    pages = []
    loaded_firefox_profiles = set()

    for path in zen_session_files():
        pages.extend(pages_from_zen_session(path))

    for path in firefox_session_files():
        profile = profile_for_session_file(path)
        if profile in loaded_firefox_profiles:
            continue
        loaded_firefox_profiles.add(profile)
        pages.extend(pages_from_firefox_session(path))
    return pages


def walk_i3(node, workspace=None):
    if node.get("type") == "workspace":
        workspace = node.get("name") or workspace

    props = node.get("window_properties") or {}
    window_class = (props.get("class") or "").lower()
    window_role = (props.get("window_role") or "").lower()
    browser = BROWSER_CLASSES.get(window_class)
    if node.get("window") is not None and browser:
        if not window_role or window_role == "browser":
            title = props.get("title") or node.get("name") or ""
            yield {
                "workspace": workspace,
                "window_id": str(node.get("window")),
                "title": title,
                "title_key": normalize_title(title),
                "browser": browser,
            }

    for child in (node.get("nodes") or []) + (node.get("floating_nodes") or []):
        yield from walk_i3(child, workspace)


def match_pages(windows, pages):
    by_title = {}
    for index, page in enumerate(pages):
        by_title.setdefault(page["title_key"], []).append((index, page))

    used = set()
    title_occurrences = {}
    matches = []
    for window_index, window in enumerate(windows):
        key = window["title_key"]
        occurrence = title_occurrences.get(key, 0)
        title_occurrences[key] = occurrence + 1

        window_browser = window.get("browser", "zen")
        selected = None
        candidates = [
            (i, p)
            for i, p in by_title.get(key, [])
            if i not in used and p.get("browser", "zen") == window_browser
        ]
        if candidates:
            selected = candidates[min(occurrence, len(candidates) - 1)]

        if selected is None:
            continue

        page_index, page = selected
        used.add(page_index)
        matches.append(
            {
                "workspace": window["workspace"],
                "window_id": window["window_id"],
                "title": window["title"],
                "page_title": page["title"],
                "url": page["url"],
                "profile": page["profile"],
                "session_file": page["session_file"],
                "session_window_index": page["session_window_index"],
                "browser": window_browser,
            }
        )
    return matches


def command_available(name):
    return shutil.which(name) is not None


def run_command(args, input_text=None, timeout=1.5):
    try:
        completed = subprocess.run(
            args,
            input=input_text,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
            check=False,
        )
    except Exception:
        return None
    if completed.returncode != 0:
        return None
    return completed.stdout


def clipboard_text():
    return run_command(
        ["xclip", "-selection", "clipboard", "-out", "-target", "UTF8_STRING"],
        timeout=2.0,
    )


def restore_clipboard(text):
    if text is None:
        return
    run_command(
        ["xclip", "-selection", "clipboard", "-in"],
        input_text=text,
        timeout=2.0,
    )


def xdotool(*args, timeout=1.5):
    return run_command(["xdotool", *args], timeout=timeout)


def live_url_for_window(window_id):
    if not window_id:
        return None

    # The save binding may still have modifiers physically down. Let them
    # settle, then ask xdotool to clear any remaining modifiers for each key.
    xdotool("windowactivate", "--sync", str(window_id), timeout=2.0)
    time.sleep(0.08)
    xdotool("key", "--clearmodifiers", "ctrl+l")
    time.sleep(0.08)
    xdotool("key", "--clearmodifiers", "ctrl+c")
    time.sleep(0.08)
    url = (clipboard_text() or "").strip()
    xdotool("key", "--clearmodifiers", "Escape")

    if is_reopenable_url(url):
        return url
    return None


def live_page_state(windows):
    if os.environ.get("ZEN_LIVE_URL_CAPTURE", "1") == "0":
        return []
    if not os.environ.get("DISPLAY"):
        return []
    if not command_available("xdotool") or not command_available("xclip"):
        return []

    active_window = (xdotool("getactivewindow") or "").strip()
    saved_clipboard = clipboard_text()
    matches = []

    try:
        for window in windows:
            url = live_url_for_window(window.get("window_id"))
            if not url:
                continue
            matches.append(
                {
                    "workspace": window["workspace"],
                    "window_id": window["window_id"],
                    "title": window["title"],
                    "page_title": normalize_title(window["title"]),
                    "url": url,
                    "profile": "",
                    "session_file": "live-address-bar",
                    "session_window_index": 0,
                    "browser": window.get("browser", "zen"),
                }
            )
    finally:
        restore_clipboard(saved_clipboard)
        if active_window:
            xdotool("windowactivate", "--sync", active_window, timeout=2.0)

    return matches


def main():
    try:
        tree = json.load(sys.stdin)
    except Exception:
        print("[]")
        return

    windows = list(walk_i3(tree))
    live_matches = live_page_state(windows)
    live_window_ids = {match["window_id"] for match in live_matches}
    remaining_windows = [
        window for window in windows if window["window_id"] not in live_window_ids
    ]
    pages = active_pages()
    matches = live_matches + match_pages(remaining_windows, pages)
    print(json.dumps(matches, ensure_ascii=False))


if __name__ == "__main__":
    main()

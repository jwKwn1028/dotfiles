#!/usr/bin/python3
"""URL recovery for i3-resurrect, as implemented by zen-url-state.py.

Everything here runs off synthetic session stores and a synthetic i3 tree: no
browser, no X11. The live address-bar fallback is covered only at its gates,
since past them it drives xdotool and the clipboard; the point of the gates is
that a headless save never reaches that code.
"""

from __future__ import annotations

import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "zen-url-state.py"
if not SOURCE.is_file():
    SOURCE = ROOT / "executable_zen-url-state.py"
SPEC = importlib.util.spec_from_file_location("zen_url_state", SOURCE)
assert SPEC is not None and SPEC.loader is not None
ZEN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ZEN)

import lz4.block  # noqa: E402  the subject bails out without it, so import after


def mozlz4(payload) -> bytes:
    return b"mozLz40\0" + lz4.block.compress(json.dumps(payload).encode("utf-8"))


def entry(url, title="T"):
    return {"url": url, "title": title}


class NormalizeTitleTests(unittest.TestCase):
    def test_strips_each_known_browser_suffix(self) -> None:
        for suffix in (
            " — Zen Browser", " - Zen Browser", " — Zen",
            " - Zen", " — Helium", " - Helium",
        ):
            self.assertEqual(ZEN.normalize_title("Docs" + suffix), "Docs")

    def test_strips_only_one_suffix(self) -> None:
        self.assertEqual(ZEN.normalize_title("Docs - Zen - Zen"), "Docs - Zen")
        # Two different suffixes apply in turn; only the trailing one goes, or a
        # page genuinely titled "Docs - Helium" loses half its name.
        self.assertEqual(ZEN.normalize_title("Docs - Helium - Zen"), "Docs - Helium")

    def test_collapses_whitespace(self) -> None:
        self.assertEqual(ZEN.normalize_title("  a \t b\nc  "), "a b c")

    def test_accepts_none(self) -> None:
        self.assertEqual(ZEN.normalize_title(None), "")

    def test_leaves_an_unsuffixed_title_alone(self) -> None:
        self.assertEqual(ZEN.normalize_title("Zen Browser docs"), "Zen Browser docs")


class ReopenableUrlTests(unittest.TestCase):
    def test_accepts_schemed_urls(self) -> None:
        for url in ("https://x.test/a", "file:///tmp/a", "view-source:https://x.test"):
            self.assertTrue(ZEN.is_reopenable_url(url), url)

    def test_rejects_blank_and_unschemed(self) -> None:
        for url in ("", None, "about:blank", "x.test/a", "/tmp/a", "://x"):
            self.assertFalse(ZEN.is_reopenable_url(url), repr(url))

    def test_keeps_other_about_pages(self) -> None:
        self.assertTrue(ZEN.is_reopenable_url("about:config"))


class DecodeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def test_reads_compressed_and_plain_json(self) -> None:
        packed = self.dir / "a.jsonlz4"
        packed.write_bytes(mozlz4({"k": 1}))
        self.assertEqual(ZEN.decode_mozlz4(packed), {"k": 1})

        plain = self.dir / "b.json"
        plain.write_bytes(b'{"k": 2}')
        self.assertEqual(ZEN.decode_mozlz4(plain), {"k": 2})

    def test_profile_is_the_dir_above_a_backup(self) -> None:
        self.assertEqual(
            ZEN.profile_for_session_file(
                Path("/p/prof/sessionstore-backups/recovery.jsonlz4")
            ),
            Path("/p/prof"),
        )
        self.assertEqual(
            ZEN.profile_for_session_file(Path("/p/prof/sessionstore.jsonlz4")),
            Path("/p/prof"),
        )


class SelectedEntryTests(unittest.TestCase):
    def test_index_is_one_based(self) -> None:
        tab = {"index": 1, "entries": [entry("https://a.test"), entry("https://b.test")]}
        self.assertEqual(ZEN.selected_entry(tab)["url"], "https://a.test")

    def test_missing_index_takes_the_last_entry(self) -> None:
        tab = {"entries": [entry("https://a.test"), entry("https://b.test")]}
        self.assertEqual(ZEN.selected_entry(tab)["url"], "https://b.test")

    def test_unparsable_index_takes_the_last_entry(self) -> None:
        tab = {"index": "junk", "entries": [entry("https://a.test"), entry("https://b.test")]}
        self.assertEqual(ZEN.selected_entry(tab)["url"], "https://b.test")

    def test_out_of_range_index_is_no_entry(self) -> None:
        self.assertIsNone(ZEN.selected_entry({"index": 9, "entries": [entry("https://a.test")]}))
        self.assertIsNone(ZEN.selected_entry({"index": -1, "entries": [entry("https://a.test")]}))

    def test_a_zero_index_means_absent(self) -> None:
        # Session-store indices are 1-based, so 0 is not a position; it falls
        # back to the last entry the way a missing index does.
        tab = {"index": 0, "entries": [entry("https://a.test"), entry("https://b.test")]}
        self.assertEqual(ZEN.selected_entry(tab)["url"], "https://b.test")

    def test_no_entries_is_no_entry(self) -> None:
        self.assertIsNone(ZEN.selected_entry({"entries": []}))
        self.assertIsNone(ZEN.selected_entry({}))


class SessionParsingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def write(self, name, payload):
        path = self.dir / name
        path.write_bytes(mozlz4(payload))
        return path

    def test_firefox_window_takes_its_selected_tab(self) -> None:
        path = self.write("sessionstore.jsonlz4", {
            "windows": [{
                "selected": 2,
                "tabs": [
                    {"index": 1, "entries": [entry("https://one.test", "One")]},
                    {"index": 1, "entries": [entry("https://two.test", "Two")]},
                ],
            }],
        })
        pages = ZEN.pages_from_firefox_session(path)
        self.assertEqual([p["url"] for p in pages], ["https://two.test"])
        self.assertEqual(pages[0]["browser"], "zen")
        self.assertEqual(pages[0]["session_window_index"], 0)
        self.assertEqual(pages[0]["title_key"], "Two")

    def test_firefox_out_of_range_selection_is_skipped(self) -> None:
        path = self.write("sessionstore.jsonlz4", {
            "windows": [{"selected": 5, "tabs": [{"entries": [entry("https://a.test")]}]}],
        })
        self.assertEqual(ZEN.pages_from_firefox_session(path), [])

    def test_firefox_unreopenable_selection_is_skipped(self) -> None:
        path = self.write("sessionstore.jsonlz4", {
            "windows": [{"selected": 1, "tabs": [{"entries": [entry("about:blank")]}]}],
        })
        self.assertEqual(ZEN.pages_from_firefox_session(path), [])

    def test_a_corrupt_session_file_yields_nothing(self) -> None:
        path = self.dir / "broken.jsonlz4"
        path.write_bytes(b"mozLz40\0not-lz4-at-all")
        self.assertEqual(ZEN.pages_from_firefox_session(path), [])
        self.assertEqual(ZEN.pages_from_zen_session(path), [])

    def test_zen_sessions_are_a_flat_tab_list(self) -> None:
        path = self.write("zen-sessions.jsonlz4", {
            "tabs": [
                {"index": 1, "entries": [entry("https://one.test", "One")]},
                {"index": 1, "entries": [entry("about:blank", "Blank")]},
                {"index": 1, "entries": [entry("https://three.test", "Three")]},
            ],
        })
        pages = ZEN.pages_from_zen_session(path)
        self.assertEqual([p["url"] for p in pages], ["https://one.test", "https://three.test"])
        self.assertEqual([p["session_window_index"] for p in pages], [0, 2])


class SessionDiscoveryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "profiles"
        self.root.mkdir()
        self._saved = os.environ.get("ZEN_PROFILE_ROOTS")
        os.environ["ZEN_PROFILE_ROOTS"] = str(self.root)
        self.addCleanup(self.restore_env)

    def restore_env(self) -> None:
        if self._saved is None:
            os.environ.pop("ZEN_PROFILE_ROOTS", None)
        else:
            os.environ["ZEN_PROFILE_ROOTS"] = self._saved

    def profile(self, name, files, mtimes=None):
        prof = self.root / name
        (prof / "sessionstore-backups").mkdir(parents=True)
        for rel in files:
            path = prof / rel
            path.write_bytes(mozlz4({"windows": []}))
            if mtimes and rel in mtimes:
                os.utime(path, (mtimes[rel], mtimes[rel]))
        return prof

    def test_newest_session_file_comes_first(self) -> None:
        self.profile("p1", ["sessionstore.jsonlz4",
                            "sessionstore-backups/recovery.jsonlz4"],
                     {"sessionstore.jsonlz4": 1000,
                      "sessionstore-backups/recovery.jsonlz4": 2000})
        found = ZEN.firefox_session_files()
        self.assertEqual([p.name for p in found], ["recovery.jsonlz4", "sessionstore.jsonlz4"])

    def test_a_missing_root_is_not_an_error(self) -> None:
        os.environ["ZEN_PROFILE_ROOTS"] = str(self.root / "nope")
        self.assertEqual(ZEN.firefox_session_files(), [])
        self.assertEqual(ZEN.zen_session_files(), [])

    def test_zen_sessions_are_found_per_profile(self) -> None:
        prof = self.profile("p1", [])
        (prof / "zen-sessions.jsonlz4").write_bytes(mozlz4({"tabs": []}))
        self.assertEqual([p.parent.name for p in ZEN.zen_session_files()], ["p1"])

    def test_only_the_newest_file_per_firefox_profile_is_read(self) -> None:
        # recovery and sessionstore both describe the same profile; reading both
        # would list every window twice.
        prof = self.root / "p1"
        (prof / "sessionstore-backups").mkdir(parents=True)
        payload = {"windows": [{"selected": 1,
                                "tabs": [{"entries": [entry("https://a.test", "A")]}]}]}
        (prof / "sessionstore.jsonlz4").write_bytes(mozlz4(payload))
        (prof / "sessionstore-backups/recovery.jsonlz4").write_bytes(mozlz4(payload))
        self.assertEqual([p["url"] for p in ZEN.active_pages()], ["https://a.test"])


class WalkTreeTests(unittest.TestCase):
    @staticmethod
    def con(wid, cls, title, role=None, **extra):
        props = {"class": cls, "title": title}
        if role is not None:
            props["window_role"] = role
        return {"type": "con", "window": wid, "window_properties": props, **extra}

    def tree(self, *children):
        return {"type": "workspace", "name": "3", "nodes": list(children)}

    def test_reports_browser_windows_with_their_workspace(self) -> None:
        found = list(ZEN.walk_i3(self.tree(self.con(1, "zen", "Docs - Zen"))))
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0]["workspace"], "3")
        self.assertEqual(found[0]["window_id"], "1")
        self.assertEqual(found[0]["title_key"], "Docs")
        self.assertEqual(found[0]["browser"], "zen")

    def test_matches_the_class_case_insensitively(self) -> None:
        found = list(ZEN.walk_i3(self.tree(self.con(1, "Helium", "Mail - Helium"))))
        self.assertEqual([w["browser"] for w in found], ["helium"])

    def test_ignores_other_applications(self) -> None:
        self.assertEqual(list(ZEN.walk_i3(self.tree(self.con(1, "Ghostty", "shell")))), [])

    def test_ignores_non_browser_roles(self) -> None:
        self.assertEqual(
            list(ZEN.walk_i3(self.tree(self.con(1, "zen", "Save", role="Popup")))), [])
        self.assertEqual(
            len(list(ZEN.walk_i3(self.tree(self.con(1, "zen", "Docs", role="browser"))))), 1)

    def test_ignores_containers_without_a_window(self) -> None:
        split = {"type": "con", "window": None,
                 "window_properties": {"class": "zen"}, "nodes": []}
        self.assertEqual(list(ZEN.walk_i3(self.tree(split))), [])

    def test_descends_into_floating_windows(self) -> None:
        ws = {"type": "workspace", "name": "4", "nodes": [],
              "floating_nodes": [{"type": "con", "nodes": [self.con(7, "zen", "F")]}]}
        found = list(ZEN.walk_i3(ws))
        self.assertEqual([(w["window_id"], w["workspace"]) for w in found], [("7", "4")])


class MatchPagesTests(unittest.TestCase):
    @staticmethod
    def window(wid, title, browser="zen", workspace="1"):
        return {"workspace": workspace, "window_id": str(wid), "title": title,
                "title_key": ZEN.normalize_title(title), "browser": browser}

    @staticmethod
    def page(url, title, browser="zen"):
        return {"title": title, "title_key": ZEN.normalize_title(title), "url": url,
                "profile": "/p", "session_file": "/p/s", "session_window_index": 0,
                "browser": browser}

    def test_matches_on_the_normalised_title(self) -> None:
        matches = ZEN.match_pages(
            [self.window(1, "Docs - Zen")], [self.page("https://d.test", "Docs")])
        self.assertEqual([m["url"] for m in matches], ["https://d.test"])
        self.assertEqual(matches[0]["window_id"], "1")

    def test_an_unmatched_window_is_dropped(self) -> None:
        self.assertEqual(
            ZEN.match_pages([self.window(1, "Nothing")], [self.page("https://d.test", "Docs")]),
            [])

    def test_a_page_is_never_given_to_two_windows(self) -> None:
        matches = ZEN.match_pages(
            [self.window(1, "Docs"), self.window(2, "Docs")],
            [self.page("https://d.test", "Docs")])
        self.assertEqual([m["window_id"] for m in matches], ["1"])

    def test_same_titled_windows_take_pages_in_order(self) -> None:
        matches = ZEN.match_pages(
            [self.window(1, "Docs"), self.window(2, "Docs")],
            [self.page("https://a.test", "Docs"), self.page("https://b.test", "Docs")])
        self.assertEqual([(m["window_id"], m["url"]) for m in matches],
                         [("1", "https://a.test"), ("2", "https://b.test")])

    def test_a_page_of_another_browser_is_not_used(self) -> None:
        self.assertEqual(
            ZEN.match_pages([self.window(1, "Mail", browser="helium")],
                            [self.page("https://m.test", "Mail", browser="zen")]),
            [])

    def test_each_browser_matches_its_own_page(self) -> None:
        matches = ZEN.match_pages(
            [self.window(1, "Mail", browser="helium"), self.window(2, "Mail")],
            [self.page("https://zen.test", "Mail"),
             self.page("https://hel.test", "Mail", browser="helium")])
        self.assertEqual({m["window_id"]: m["url"] for m in matches},
                         {"1": "https://hel.test", "2": "https://zen.test"})

    def test_the_match_carries_the_page_provenance(self) -> None:
        matches = ZEN.match_pages([self.window(1, "Docs", workspace="7")],
                                  [self.page("https://d.test", "Docs")])
        self.assertEqual(matches[0]["workspace"], "7")
        self.assertEqual(matches[0]["session_file"], "/p/s")
        self.assertEqual(matches[0]["profile"], "/p")


class LiveCaptureGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.saved = {k: os.environ.get(k) for k in ("ZEN_LIVE_URL_CAPTURE", "DISPLAY")}
        self.addCleanup(self.restore)
        self.calls = []
        real = ZEN.command_available
        ZEN.command_available = lambda name: self.calls.append(name) or True
        self.addCleanup(setattr, ZEN, "command_available", real)

    def restore(self) -> None:
        for key, value in self.saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_the_opt_out_skips_the_capture(self) -> None:
        os.environ["ZEN_LIVE_URL_CAPTURE"] = "0"
        os.environ["DISPLAY"] = ":0"
        self.assertEqual(ZEN.live_page_state([{"window_id": "1"}]), [])
        self.assertEqual(self.calls, [])

    def test_a_headless_save_skips_the_capture(self) -> None:
        os.environ.pop("ZEN_LIVE_URL_CAPTURE", None)
        os.environ.pop("DISPLAY", None)
        self.assertEqual(ZEN.live_page_state([{"window_id": "1"}]), [])
        self.assertEqual(self.calls, [])

    def test_missing_tools_skip_the_capture(self) -> None:
        os.environ.pop("ZEN_LIVE_URL_CAPTURE", None)
        os.environ["DISPLAY"] = ":0"
        ZEN.command_available = lambda name: False
        self.assertEqual(ZEN.live_page_state([{"window_id": "1"}]), [])


class MainTests(unittest.TestCase):
    def run_main(self, stdin_text):
        out, err = io.StringIO(), sys.stdout
        stdin = sys.stdin
        sys.stdin, sys.stdout = io.StringIO(stdin_text), out
        try:
            ZEN.main()
        finally:
            sys.stdin, sys.stdout = stdin, err
        return out.getvalue().strip()

    def test_unreadable_input_prints_an_empty_list(self) -> None:
        self.addCleanup(setattr, ZEN, "live_page_state", ZEN.live_page_state)
        self.assertEqual(self.run_main("not json"), "[]")

    def test_a_live_url_wins_over_the_session_store(self) -> None:
        # The session file lags behind the address bar, so a window answered live
        # must not also be matched from disk.
        real_live, real_pages = ZEN.live_page_state, ZEN.active_pages
        self.addCleanup(setattr, ZEN, "live_page_state", real_live)
        self.addCleanup(setattr, ZEN, "active_pages", real_pages)
        ZEN.live_page_state = lambda windows: [{
            "workspace": "1", "window_id": "1", "title": "Docs", "page_title": "Docs",
            "url": "https://live.test", "profile": "", "session_file": "live-address-bar",
            "session_window_index": 0, "browser": "zen"}]
        ZEN.active_pages = lambda: [
            {"title": "Docs", "title_key": "Docs", "url": "https://stale.test",
             "profile": "/p", "session_file": "/p/s", "session_window_index": 0,
             "browser": "zen"},
            {"title": "Mail", "title_key": "Mail", "url": "https://mail.test",
             "profile": "/p", "session_file": "/p/s", "session_window_index": 1,
             "browser": "zen"}]
        tree = {"type": "workspace", "name": "1", "nodes": [
            {"type": "con", "window": 1,
             "window_properties": {"class": "zen", "title": "Docs"}},
            {"type": "con", "window": 2,
             "window_properties": {"class": "zen", "title": "Mail"}}]}
        result = json.loads(self.run_main(json.dumps(tree)))
        self.assertEqual({m["window_id"]: m["url"] for m in result},
                         {"1": "https://live.test", "2": "https://mail.test"})


if __name__ == "__main__":
    unittest.main()

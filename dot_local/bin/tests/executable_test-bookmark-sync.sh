#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(dirname "$(readlink -f "$0")")"
SOURCE_ROOT="$(readlink -f "$TEST_DIR/../../..")"
SYNC="$SOURCE_ROOT/executable_dot_sync-zen-to-helium-bookmarks.sh"
[ -r "$SYNC" ] || SYNC="$HOME/.sync-zen-to-helium-bookmarks.sh"

TEST_TMP="$(mktemp -d)"
ZEN="$TEST_TMP/places.sqlite"
HEL="$TEST_TMP/Default/Bookmarks"
READY="$TEST_TMP/writer-ready"
STOP="$TEST_TMP/writer-stop"
WRITER_PID=
cleanup() {
    touch "$STOP" 2>/dev/null || true
    if [ -n "$WRITER_PID" ]; then
        wait "$WRITER_PID" 2>/dev/null || true
    fi
    rm -rf -- "$TEST_TMP"
}
trap cleanup EXIT
mkdir -p "${HEL%/*}"
printf '%s\n' '{"old":true}' >"$HEL"

status=0
KEEP_BACKUPS=invalid bash "$SYNC" --dry-run >/dev/null 2>&1 || status=$?
[ "$status" -eq 2 ] || {
    printf 'FAIL: invalid KEEP_BACKUPS exited %s instead of 2\n' "$status" >&2
    exit 1
}

python3 - "$ZEN" "$READY" "$STOP" <<'PY' &
import pathlib, sqlite3, sys, time

db, ready, stop = map(pathlib.Path, sys.argv[1:])
con = sqlite3.connect(db)
con.execute("PRAGMA journal_mode=WAL")
con.execute("PRAGMA wal_autocheckpoint=0")
con.execute("CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT)")
con.execute("""CREATE TABLE moz_bookmarks (
    id INTEGER PRIMARY KEY, parent INTEGER, type INTEGER, title TEXT,
    fk INTEGER, dateAdded INTEGER, lastModified INTEGER, position INTEGER
)""")
con.executemany("INSERT INTO moz_places(id,url) VALUES (?,?)", [
    (1, "https://example.com/toolbar"),
    (2, "https://example.com/menu"),
])
con.executemany(
    "INSERT INTO moz_bookmarks VALUES (?,?,?,?,?,?,?,?)",
    [
        (10, 3, 1, "Toolbar", 1, 1000, 1000, 0),
        (11, 2, 1, "Menu", 2, 2000, 2000, 0),
    ],
)
con.commit()
ready.touch()
while not stop.exists():
    time.sleep(0.02)
con.close()
PY
WRITER_PID=$!
for _ in $(seq 1 100); do
    [ -e "$READY" ] && break
    sleep 0.02
done
[ -e "$READY" ] || {
    printf 'FAIL: WAL fixture did not become ready\n' >&2
    exit 1
}

env ZEN_PLACES="$ZEN" HELIUM_BOOKMARKS="$HEL" KEEP_BACKUPS=1 \
    bash "$SYNC" --force >"$TEST_TMP/sync-out"
python3 - "$HEL" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    doc = json.load(fh)
def count_urls(node):
    if node["type"] == "url":
        return 1
    return sum(count_urls(child) for child in node.get("children", []))
count = sum(count_urls(root) for root in doc["roots"].values())
if count != 2:
    raise SystemExit(f"expected 2 bookmarks from live WAL snapshot, got {count}")
PY

env ZEN_PLACES="$ZEN" HELIUM_BOOKMARKS="$HEL" KEEP_BACKUPS=1 \
    bash "$SYNC" --force >/dev/null
[ "$(find "${HEL%/*}" -maxdepth 1 -name 'Bookmarks.bak-*' | wc -l)" -eq 1 ] || {
    printf 'FAIL: KEEP_BACKUPS=1 did not retain exactly one backup\n' >&2
    exit 1
}

LOCK_FILE="${HEL%/*}/.sync-zen-to-helium-bookmarks.lock"
exec 8>"$LOCK_FILE"
flock -n 8
status=0
env ZEN_PLACES="$ZEN" HELIUM_BOOKMARKS="$HEL" KEEP_BACKUPS=1 \
    SYNC_LOCK_WAIT_SECONDS=0 \
    bash "$SYNC" --dry-run >/dev/null 2>"$TEST_TMP/lock-err" || status=$?
exec 8>&-
[ "$status" -ne 0 ] && grep -Fq 'another bookmark sync' "$TEST_TMP/lock-err" || {
    printf 'FAIL: bookmark sync lock did not reject a concurrent run\n' >&2
    exit 1
}

touch "$STOP"
wait "$WRITER_PID"
WRITER_PID=
printf 'PASS: bookmark sync uses a consistent WAL snapshot and serialized writes\n'

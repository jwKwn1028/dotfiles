#!/usr/bin/env bash
#
# sync-zen-to-helium-bookmarks.sh
#
# Mirror the bookmarks from the Zen browser (Firefox-based, places.sqlite)
# into the Helium browser (Chromium-based, "Bookmarks" JSON file).
#
# Zen is treated as the single source of truth: every run rebuilds Helium's
# bookmark tree to match Zen exactly (folders, URLs, order). A timestamped
# backup of Helium's current bookmarks is made before anything is written, so
# the operation is always reversible.
#
#   Zen toolbar         -> Helium "Bookmarks bar"
#   Zen menu + unfiled  -> Helium "Other bookmarks"
#   Zen mobile          -> Helium "Mobile bookmarks"
#
# Usage:
#   ./sync-zen-to-helium-bookmarks.sh [--dry-run] [--force]
#
#   --dry-run   Show what would be synced without writing anything.
#   --force     Proceed even if Helium appears to be running (NOT recommended:
#               Helium overwrites this file when it closes).
#
# Override auto-detected paths with environment variables:
#   ZEN_PLACES=/path/to/places.sqlite
#   HELIUM_BOOKMARKS=/path/to/Bookmarks
#
set -euo pipefail

DRY_RUN=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    -h|--help)
      sed -n '2,30p' "$0"; exit 0 ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

log()  { printf '%s\n' "$*"; }
err()  { printf 'error: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# --- Locate the Zen places.sqlite (newest match wins) ----------------------
find_zen() {
  if [ -n "${ZEN_PLACES:-}" ]; then
    printf '%s\n' "$ZEN_PLACES"; return
  fi
  local f
  # Flatpak install and native install layouts.
  f=$(ls -t \
        "$HOME"/.var/app/app.zen_browser.zen/.zen/*/places.sqlite \
        "$HOME"/.zen/*/places.sqlite \
        2>/dev/null | head -n1 || true)
  printf '%s\n' "$f"
}

# --- Locate the Helium Bookmarks file --------------------------------------
find_helium() {
  if [ -n "${HELIUM_BOOKMARKS:-}" ]; then
    printf '%s\n' "$HELIUM_BOOKMARKS"; return
  fi
  local c
  for c in \
      "$HOME/.config/net.imput.helium/Default/Bookmarks" \
      "$HOME/.config/helium/Default/Bookmarks"; do
    [ -f "$c" ] && { printf '%s\n' "$c"; return; }
  done
}

ZEN=$(find_zen)
HEL=$(find_helium)

[ -n "$ZEN" ] && [ -f "$ZEN" ] || die "could not find Zen places.sqlite (set ZEN_PLACES=...)"
[ -n "$HEL" ] && [ -f "$HEL" ] || die "could not find Helium Bookmarks file (set HELIUM_BOOKMARKS=...)"

command -v python3 >/dev/null || die "python3 is required but not installed"

log "Zen source : $ZEN"
log "Helium dest: $HEL"

# --- Refuse to run while Helium is open (it would clobber our write) --------
# (A dry run writes nothing, so the check is only enforced for real syncs.)
if [ "$DRY_RUN" -eq 0 ] && pgrep -fi 'helium' 2>/dev/null | grep -vqw "$$"; then
  if [ "$FORCE" -eq 1 ]; then
    err "Helium appears to be running -- continuing because --force was given."
    err "Whatever Helium writes when it closes may overwrite these changes."
  else
    die "Helium appears to be running. Close it first, then re-run (or pass --force)."
  fi
fi

# --- Back up the current Helium bookmarks ----------------------------------
if [ "$DRY_RUN" -eq 0 ]; then
  BACKUP="${HEL}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$HEL" "$BACKUP"
  log "Backup     : $BACKUP"
fi

# --- Build the new Helium bookmark tree from Zen ----------------------------
python3 - "$ZEN" "$HEL" "$DRY_RUN" <<'PY'
import sys, os, json, sqlite3, uuid, hashlib, tempfile

zen_path, hel_path, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

# Firefox stores timestamps as microseconds since 1970-01-01.
# Chromium stores microseconds since 1601-01-01. Difference in microseconds:
EPOCH_DELTA = 11644473600000000

def to_chrome_time(ff_micros):
    if not ff_micros:
        return "0"
    return str(int(ff_micros) + EPOCH_DELTA)

# Read Zen's bookmark DB read-only & lock-free, even if Zen is running.
uri = f"file:{zen_path}?immutable=1"
con = sqlite3.connect(uri, uri=True)
con.row_factory = sqlite3.Row

# id -> url
places = {row["id"]: row["url"] for row in con.execute("SELECT id, url FROM moz_places")}

# parent -> ordered list of child rows
children = {}
for row in con.execute(
        "SELECT id, parent, type, title, fk, dateAdded, lastModified "
        "FROM moz_bookmarks ORDER BY parent, position"):
    children.setdefault(row["parent"], []).append(row)
con.close()

_counter = [3]  # node ids 1-3 are reserved for the three root folders
def next_id():
    _counter[0] += 1
    return str(_counter[0])

stats = {"folders": 0, "urls": 0}

def build(zen_id):
    """Return a list of Chromium child nodes for the given Zen folder id."""
    out = []
    for row in children.get(zen_id, []):
        t = row["type"]
        if t == 1:  # URL bookmark
            url = places.get(row["fk"])
            if not url or url.startswith("place:"):
                continue  # skip internal/smart-folder queries
            out.append({
                "type": "url",
                "id": next_id(),
                "guid": str(uuid.uuid4()),
                "name": row["title"] or "",
                "url": url,
                "date_added": to_chrome_time(row["dateAdded"]),
                "date_last_used": "0",
            })
            stats["urls"] += 1
        elif t == 2:  # folder
            node = {
                "type": "folder",
                "id": next_id(),
                "guid": str(uuid.uuid4()),
                "name": row["title"] or "",
                "date_added": to_chrome_time(row["dateAdded"]),
                "date_modified": to_chrome_time(row["lastModified"] or row["dateAdded"]),
                "date_last_used": "0",
                "children": build(row["id"]),
            }
            out.append(node)
            stats["folders"] += 1
        # type 3 (separator) and anything else is skipped.
    return out

# Zen root ids: 2=menu, 3=toolbar, 5=unfiled, 6=mobile
def root(node_id, guid, name, children_nodes):
    return {
        "type": "folder",
        "id": str(node_id),
        "guid": guid,
        "name": name,
        "date_added": "0",
        "date_modified": "0",
        "date_last_used": "0",
        "children": children_nodes,
    }

# Standard Chromium permanent-folder GUIDs (must be these exact values).
roots = {
    "bookmark_bar": root(1, "0bc5d13f-2cba-5d74-951f-3f233fe6c908",
                         "Bookmarks bar", build(3)),
    "other":        root(2, "82b081ec-3dd3-529c-8475-ab6c344590dd",
                         "Other bookmarks", build(2) + build(5)),
    "synced":       root(3, "4cf2e351-0e85-532b-bb37-df045d8f8d0f",
                         "Mobile bookmarks", build(6)),
}

# --- Compute Chromium's bookmark checksum so Helium loads it cleanly --------
md5 = hashlib.md5()
def _walk_checksum(n):
    md5.update(n["id"].encode("utf-8"))
    md5.update(n["name"].encode("utf-16-le"))
    if n["type"] == "url":
        md5.update(b"url")
        md5.update(n["url"].encode("utf-8"))
    else:
        md5.update(b"folder")
        for c in n["children"]:
            _walk_checksum(c)
for k in ("bookmark_bar", "other", "synced"):
    _walk_checksum(roots[k])

doc = {"checksum": md5.hexdigest(), "roots": roots, "version": 1}

print(f"Zen bookmarks found: {stats['urls']} URLs in {stats['folders']} folders")

if dry:
    print("Dry run -- Helium Bookmarks file was NOT modified.")
    sys.exit(0)

# Write atomically, preserving Helium's 0600 permissions.
d = os.path.dirname(hel_path)
fd, tmp = tempfile.mkstemp(dir=d, prefix=".Bookmarks.new.")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=3)
    os.chmod(tmp, 0o600)
    os.replace(tmp, hel_path)
except BaseException:
    try: os.unlink(tmp)
    except OSError: pass
    raise

# Helium keeps its own "Bookmarks.bak"; remove the stale one so it doesn't get
# restored over our update on a crash/recovery.
stale = hel_path + ".bak"
if os.path.exists(stale):
    try: os.unlink(stale)
    except OSError: pass

print("Helium bookmarks updated.")
PY

if [ "$DRY_RUN" -eq 0 ]; then
  log "Done. Start Helium to see the updated bookmarks."
fi

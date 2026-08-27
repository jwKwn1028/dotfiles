#!/usr/bin/env bash
#
# update-helium.sh — automatically update the Helium browser AppImage.
#
# Checks imputnet/helium-linux's latest release and, if it is newer than the
# installed AppImage, downloads it, swaps it in, and repoints helium.desktop.
#
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="imputnet/helium-linux"
ARCH="x86_64"
# Desktop files to keep in sync (local copy + the one installed in the app menu).
DESKTOP_FILES=(
    "$APP_DIR/helium.desktop"
    "$HOME/.local/share/applications/helium.desktop"
)

log() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

for cmd in curl flock mktemp python3 sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || { err "missing required command: $cmd"; exit 1; }
done

lock_wait=${HELIUM_UPDATE_LOCK_WAIT_SECONDS:-10}
case "$lock_wait" in
    ''|*[!0-9]*) err "HELIUM_UPDATE_LOCK_WAIT_SECONDS must be a nonnegative integer"; exit 2 ;;
esac
exec 9>"$APP_DIR/.update-helium.lock"
if ! flock -w "$lock_wait" 9; then
    err "another Helium update is already running"
    exit 1
fi

tmp_path=
cleanup() {
    if [[ -n "$tmp_path" && -e "$tmp_path" ]]; then
        rm -f -- "$tmp_path"
    fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Re-assert preferences updates tend to reset: Helium re-pins the zen-mode top
# chrome (the URL panel), undoing "hidden by default, reveal on hover". Skipped
# while Helium runs, since it rewrites Preferences on exit.
enforce_helium_prefs() {
    local pref="$HOME/.config/net.imput.helium/Default/Preferences"
    [[ -f "$pref" ]] || return 0
    command -v python3 >/dev/null 2>&1 || { log "python3 not found; skipping Helium preference enforcement"; return 0; }
    if pgrep -f 'helium-.*\.AppImage|\.mount_[Hh]elium' >/dev/null 2>&1; then
        log "Helium is running; skipping preference enforcement (applies next launch)"
        return 0
    fi
    local result
    if ! result="$(python3 - "$pref" <<'PY'
import json, os, stat, sys, tempfile
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        prefs = json.load(fh)
except (OSError, ValueError):
    print("error"); sys.exit(0)
browser = prefs.setdefault("helium", {}).setdefault("browser", {})
if browser.get("zen_mode_top_chrome_pinned") is False:
    print("ok"); sys.exit(0)
browser["zen_mode_top_chrome_pinned"] = False
mode = stat.S_IMODE(os.stat(path).st_mode)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".Preferences.new.")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(prefs, fh, separators=(",", ":"))
        fh.flush()
        os.fsync(fh.fileno())
    os.chmod(tmp, mode)
    os.replace(tmp, path)
    directory_fd = os.open(os.path.dirname(path) or ".", os.O_DIRECTORY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
except BaseException:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
print("fixed")
PY
)"; then
        log "warning: could not enforce Helium preferences"
        return 0
    fi
    case "$result" in
        fixed) log "Re-asserted Helium pref: zen_mode_top_chrome_pinned=false" ;;
        ok)    log "Helium pref already correct: zen_mode_top_chrome_pinned=false" ;;
        *)     log "warning: could not enforce Helium preferences" ;;
    esac
}

# --- Find the currently installed AppImage and its version -------------------
current_appimage="$(ls -1 "$APP_DIR"/helium-*-"$ARCH".AppImage 2>/dev/null | sort -V | tail -n1 || true)"
if [[ -n "$current_appimage" ]]; then
    current_version="$(basename "$current_appimage" | sed -E "s/^helium-(.*)-$ARCH\.AppImage$/\1/")"
else
    current_version="none"
fi
log "Installed version: $current_version"

# --- Query GitHub for the latest release tag --------------------------------
api_url="https://api.github.com/repos/$REPO/releases/latest"
auth=()
[[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")

api_response="$(curl -fsSL "${auth[@]}" "$api_url")"
if ! release_info="$(python3 - "$ARCH" 3<<<"$api_response" <<'PY'
import json, os, re, sys

arch = sys.argv[1]
data = json.load(os.fdopen(3))
tag = data.get("tag_name")
if not isinstance(tag, str) or not re.fullmatch(r"[0-9A-Za-z._+-]+", tag):
    raise SystemExit("release has an invalid tag_name")
name = f"helium-{tag}-{arch}.AppImage"
asset = next((item for item in data.get("assets", []) if item.get("name") == name), None)
if asset is None:
    raise SystemExit(f"release is missing {name}")
url = asset.get("browser_download_url")
digest = asset.get("digest")
if not isinstance(url, str) or not url.startswith("https://github.com/"):
    raise SystemExit("release asset has an invalid download URL")
if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-fA-F]{64}", digest):
    raise SystemExit("release asset is missing a SHA-256 digest")
print(tag)
print(url)
print(digest.removeprefix("sha256:").lower())
PY
)"; then
    err "could not resolve a verified $ARCH AppImage from the GitHub release"
    exit 1
fi
mapfile -t release_fields <<<"$release_info"
latest_version=${release_fields[0]:-}
url=${release_fields[1]:-}
expected_sha256=${release_fields[2]:-}
log "Latest version:    $latest_version"

# --- Compare versions -------------------------------------------------------
if [[ "$current_version" == "$latest_version" ]]; then
    log "Already up to date. Nothing to do."
    exit 0
fi

# If the "newest" of the two equals the installed one, the installed is newer/equal.
if [[ "$current_version" != "none" ]]; then
    newest="$(printf '%s\n%s\n' "$current_version" "$latest_version" | sort -V | tail -n1)"
    if [[ "$newest" == "$current_version" ]]; then
        log "Installed version is newer than or equal to the latest release. Nothing to do."
        exit 0
    fi
fi

# --- Download the new AppImage ----------------------------------------------
new_name="helium-$latest_version-$ARCH.AppImage"
new_path="$APP_DIR/$new_name"
tmp_path="$(mktemp "$APP_DIR/.${new_name}.part.XXXXXX")"

log "Downloading $new_name ..."
curl -fL --progress-bar -o "$tmp_path" "$url"
actual_sha256=$(sha256sum -- "$tmp_path")
actual_sha256=${actual_sha256%%[[:space:]]*}
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    err "SHA-256 mismatch for $new_name"
    exit 1
fi
log "Verified SHA-256: $actual_sha256"
chmod 0755 "$tmp_path"
mv -f "$tmp_path" "$new_path"
tmp_path=
log "Saved to $new_path"

# --- Update helium.desktop files --------------------------------------------
# Match any previous version (handles files that were out of sync).
for desktop in "${DESKTOP_FILES[@]}"; do
    [[ -f "$desktop" ]] || continue
    sed -i \
        -e "s|helium-[^/]*-$ARCH\.AppImage|$new_name|g" \
        -e "s|^X-AppImage-Version=.*|X-AppImage-Version=$latest_version|" \
        "$desktop"
    log "Updated $desktop"
done
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# --- Remove the old AppImage ------------------------------------------------
if [[ -n "$current_appimage" && "$current_appimage" != "$new_path" ]]; then
    rm -f "$current_appimage"
    log "Removed old AppImage: $(basename "$current_appimage")"
fi

# --- Re-assert preferences the update may have reset ------------------------
enforce_helium_prefs

log "Helium updated: $current_version -> $latest_version"

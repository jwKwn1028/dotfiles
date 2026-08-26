#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(dirname "$(readlink -f "$0")")"
SOURCE_ROOT="$(readlink -f "$TEST_DIR/../../..")"
UPDATER="$SOURCE_ROOT/Applications/executable_update-helium.sh"
[ -r "$UPDATER" ] || UPDATER="$HOME/Applications/update-helium.sh"

TEST_TMP="$(mktemp -d)"
TEST_HOME="$TEST_TMP/home"
APP_DIR="$TEST_HOME/Applications"
MOCK_BIN="$TEST_TMP/bin"
CURL_LOG="$TEST_TMP/curl-calls"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$APP_DIR" "$TEST_HOME/.local/share/applications" \
    "$TEST_HOME/.config/net.imput.helium/Default" "$MOCK_BIN"
cp -p -- "$UPDATER" "$APP_DIR/update-helium.sh"
chmod +x "$APP_DIR/update-helium.sh"

cat >"$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$HELIUM_TEST_CURL_LOG"
out=
url=
while (( $# )); do
    case $1 in
        -o) out=$2; shift 2 ;;
        -H) shift 2 ;;
        -*) shift ;;
        *) url=$1; shift ;;
    esac
done
if [[ $url == *'/releases/latest' ]]; then
    printf '{"tag_name":"%s","assets":[{"name":"helium-%s-x86_64.AppImage","browser_download_url":"https://github.com/test/helium-%s-x86_64.AppImage","digest":"sha256:%s"}]}\n' \
        "$HELIUM_TEST_VERSION" "$HELIUM_TEST_VERSION" \
        "$HELIUM_TEST_VERSION" "$HELIUM_TEST_DIGEST"
else
    printf '%s' "$HELIUM_TEST_PAYLOAD" >"$out"
fi
EOF
cat >"$MOCK_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat >"$MOCK_BIN/update-desktop-database" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN/curl" "$MOCK_BIN/pgrep" "$MOCK_BIN/update-desktop-database"

printf '%s' old >"$APP_DIR/helium-0.1.0-x86_64.AppImage"
chmod 0755 "$APP_DIR/helium-0.1.0-x86_64.AppImage"
for desktop in "$APP_DIR/helium.desktop" "$TEST_HOME/.local/share/applications/helium.desktop"; do
    printf 'Exec=%s/helium-0.1.0-x86_64.AppImage %%U\nX-AppImage-Version=0.1.0\n' \
        "$APP_DIR" >"$desktop"
done
printf '%s\n' '{"helium":{"browser":{"zen_mode_top_chrome_pinned":true}}}' \
    >"$TEST_HOME/.config/net.imput.helium/Default/Preferences"
chmod 0600 "$TEST_HOME/.config/net.imput.helium/Default/Preferences"

payload='verified-appimage-payload'
digest="$(printf '%s' "$payload" | sha256sum)"
digest=${digest%%[[:space:]]*}

env -u GITHUB_TOKEN \
    HOME="$TEST_HOME" PATH="$MOCK_BIN:/usr/bin:/bin" \
    HELIUM_TEST_CURL_LOG="$CURL_LOG" \
    HELIUM_TEST_VERSION=0.2.0 HELIUM_TEST_PAYLOAD="$payload" \
    HELIUM_TEST_DIGEST="$digest" \
    bash "$APP_DIR/update-helium.sh" >"$TEST_TMP/update-out"

[ "$(cat "$APP_DIR/helium-0.2.0-x86_64.AppImage")" = "$payload" ] || {
    printf 'FAIL: verified AppImage was not installed\n' >&2
    exit 1
}
[ ! -e "$APP_DIR/helium-0.1.0-x86_64.AppImage" ] || {
    printf 'FAIL: old AppImage survived a successful update\n' >&2
    exit 1
}
grep -Fq 'helium-0.2.0-x86_64.AppImage' "$APP_DIR/helium.desktop" || {
    printf 'FAIL: desktop file was not updated\n' >&2
    exit 1
}
python3 - "$TEST_HOME/.config/net.imput.helium/Default/Preferences" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    prefs = json.load(fh)
if prefs["helium"]["browser"]["zen_mode_top_chrome_pinned"] is not False:
    raise SystemExit("preference was not enforced")
PY
[ "$(stat -c %a "$TEST_HOME/.config/net.imput.helium/Default/Preferences")" = 600 ] || {
    printf 'FAIL: atomic preference rewrite changed file permissions\n' >&2
    exit 1
}
grep -Fq 'Verified SHA-256' "$TEST_TMP/update-out" || {
    printf 'FAIL: updater did not report digest verification\n' >&2
    exit 1
}

bad_digest=$(printf '0%.0s' {1..64})
status=0
env -u GITHUB_TOKEN \
    HOME="$TEST_HOME" PATH="$MOCK_BIN:/usr/bin:/bin" \
    HELIUM_TEST_CURL_LOG="$CURL_LOG" \
    HELIUM_TEST_VERSION=0.3.0 HELIUM_TEST_PAYLOAD=tampered \
    HELIUM_TEST_DIGEST="$bad_digest" \
    bash "$APP_DIR/update-helium.sh" >"$TEST_TMP/bad-out" 2>"$TEST_TMP/bad-err" || status=$?
[ "$status" -ne 0 ] || {
    printf 'FAIL: mismatched AppImage digest was accepted\n' >&2
    exit 1
}
[ -e "$APP_DIR/helium-0.2.0-x86_64.AppImage" ] && \
    [ ! -e "$APP_DIR/helium-0.3.0-x86_64.AppImage" ] || {
    printf 'FAIL: digest failure disturbed the installed AppImage\n' >&2
    exit 1
}
[ -z "$(find "$APP_DIR" -maxdepth 1 -name '*.part.*' -print -quit)" ] || {
    printf 'FAIL: failed update left a partial download behind\n' >&2
    exit 1
}

exec 8>"$APP_DIR/.update-helium.lock"
flock -n 8
status=0
env -u GITHUB_TOKEN \
    HOME="$TEST_HOME" PATH="$MOCK_BIN:/usr/bin:/bin" \
    HELIUM_TEST_CURL_LOG="$CURL_LOG" \
    HELIUM_TEST_VERSION=0.3.0 HELIUM_TEST_PAYLOAD="$payload" \
    HELIUM_TEST_DIGEST="$digest" HELIUM_UPDATE_LOCK_WAIT_SECONDS=0 \
    bash "$APP_DIR/update-helium.sh" >/dev/null 2>"$TEST_TMP/lock-err" || status=$?
exec 8>&-
[ "$status" -ne 0 ] && grep -Fq 'another Helium update' "$TEST_TMP/lock-err" || {
    printf 'FAIL: updater lock did not reject a concurrent run\n' >&2
    exit 1
}

printf 'PASS: Helium updates are locked, verified, and atomic\n'

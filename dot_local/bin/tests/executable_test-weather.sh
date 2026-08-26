#!/usr/bin/env bash
set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
WEATHER="$ROOT/weather"
[ -r "$WEATHER" ] || WEATHER="$ROOT/executable_weather"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
CALL_LOG="$TEST_TMP/curl-calls"
JQ_LOG="$TEST_TMP/jq-calls"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$WEATHER_TEST_CURL_LOG"
status=${WEATHER_TEST_CURL_STATUS:-0}
(( status == 0 )) || exit "$status"
case "$*" in
    *format=j1*) printf '%s\n' '{"weather":[]}' ;;
    *) printf '%s\n' 'compact weather' ;;
esac
EOF

cat >"$MOCK_BIN/jq" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$WEATHER_TEST_JQ_LOG"
cat >/dev/null
printf '%s\n' 'rendered forecast'
EOF
chmod +x "$MOCK_BIN/curl" "$MOCK_BIN/jq"

status=0
env PATH="$MOCK_BIN:/usr/bin:/bin" \
    WEATHER_TEST_CURL_LOG="$CALL_LOG" \
    WEATHER_TEST_JQ_LOG="$JQ_LOG" \
    WEATHER_TEST_CURL_STATUS=7 \
    /bin/sh "$WEATHER" --today >"$TEST_TMP/out" 2>"$TEST_TMP/err" || status=$?
[ "$status" -eq 7 ] || {
    printf 'FAIL: weather hid curl exit 7 as exit %s\n' "$status" >&2
    exit 1
}
[ ! -e "$JQ_LOG" ] || {
    printf 'FAIL: jq ran after the weather download failed\n' >&2
    exit 1
}

: >"$CALL_LOG"
result="$(env PATH="$MOCK_BIN:/usr/bin:/bin" \
    WEATHER_TEST_CURL_LOG="$CALL_LOG" \
    WEATHER_TEST_JQ_LOG="$JQ_LOG" \
    /bin/sh "$WEATHER" --today)"
[ "$result" = 'rendered forecast' ] || {
    printf 'FAIL: successful forecast was not rendered: %s\n' "$result" >&2
    exit 1
}
grep -Fq -- '--connect-timeout 5' "$CALL_LOG" || {
    printf 'FAIL: weather curl call lacks a connection timeout\n' >&2
    exit 1
}
grep -Fq -- '--max-time 20' "$CALL_LOG" || {
    printf 'FAIL: weather curl call lacks a total timeout\n' >&2
    exit 1
}

status=0
env PATH="$MOCK_BIN:/usr/bin:/bin" \
    WEATHER_TEST_CURL_LOG="$CALL_LOG" \
    WEATHER_CONNECT_TIMEOUT=never \
    /bin/sh "$WEATHER" --today >/dev/null 2>&1 || status=$?
[ "$status" -eq 2 ] || {
    printf 'FAIL: invalid timeout exited %s instead of 2\n' "$status" >&2
    exit 1
}

printf 'PASS: weather propagates network failures and bounds requests\n'

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
RESNAP="$ROOT/resnap.sh"
[ -r "$RESNAP" ] || RESNAP="$ROOT/executable_resnap.sh"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
CALL_LOG="$TEST_TMP/calls"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$MOCK_BIN" "$TEST_TMP/i3"
cp -p -- "$RESNAP" "$TEST_TMP/i3/resnap.sh"

cat >"$TEST_TMP/i3/_snap-common.sh" <<'EOF'
snap_log() { :; }
EOF
cat >"$TEST_TMP/i3/tile-snap.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RESNAP_TEST_CALL_LOG"
EOF
cat >"$MOCK_BIN/i3-msg" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    '-t get_tree') cat "$RESNAP_TEST_TREE" ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$TEST_TMP/i3/resnap.sh" "$TEST_TMP/i3/tile-snap.sh" "$MOCK_BIN/i3-msg"

cat >"$TEST_TMP/tree.json" <<'EOF'
{
  "nodes": [
    {"id": 42, "window": 100, "marks": ["_snap_ul", "_snap_left", "_snap_full"]},
    {"id": 43, "window": 101, "marks": ["_snap_dr", "_snap_right"]},
    {"id": 44, "window": 102, "marks": ["_snap_unknown"]}
  ]
}
EOF

env PATH="$MOCK_BIN:/usr/bin:/bin" \
    RESNAP_TEST_TREE="$TEST_TMP/tree.json" \
    RESNAP_TEST_CALL_LOG="$CALL_LOG" \
    bash "$TEST_TMP/i3/resnap.sh"

grep -Fqx 'full 42' "$CALL_LOG" || {
    printf 'FAIL: resnap did not choose full over smaller stale marks\n' >&2
    exit 1
}
grep -Fqx 'right 43' "$CALL_LOG" || {
    printf 'FAIL: resnap did not choose a half over a quadrant\n' >&2
    exit 1
}
[ "$(wc -l <"$CALL_LOG")" -eq 2 ] || {
    printf 'FAIL: resnap accepted an invalid snap mark\n' >&2
    exit 1
}

printf 'PASS: resnap chooses the largest valid region mark\n'

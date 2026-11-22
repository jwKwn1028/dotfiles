#!/usr/bin/env bash
# Tests dot_config/zed/modify_private_settings.json.tmpl.

set -euo pipefail

SOURCE_ROOT="$(readlink -f "$(dirname "$(readlink -f "$0")")/../../..")"
TEMPLATE="dot_config/zed/modify_private_settings.json.tmpl"
[ -r "$SOURCE_ROOT/$TEMPLATE" ] || SOURCE_ROOT="$(chezmoi source-path 2>/dev/null || true)"
if [ ! -r "$SOURCE_ROOT/$TEMPLATE" ]; then
    echo "SKIP: the chezmoi source directory is unavailable from the applied tree"
    exit 0
fi

TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT
SUBJECT="$TEST_TMP/modify"
chezmoi --source "$SOURCE_ROOT" execute-template <"$SOURCE_ROOT/$TEMPLATE" >"$SUBJECT"
chmod +x "$SUBJECT"
IN="$TEST_TMP/in"
OUT="$TEST_TMP/out"
ERR="$TEST_TMP/err"

fail() {
    echo "FAIL: $1" >&2
    [ -s "$ERR" ] && sed 's/^/      stderr: /' "$ERR" >&2
    exit 1
}

run() {
    RC=0
    "$SUBJECT" <"$IN" >"$OUT" 2>"$ERR" || RC=$?
}

# `expr` is evaluated with the parsed output bound to d.
jchk() {
    python3 - "$OUT" "$1" <<'PY' || fail "$2"
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if eval(sys.argv[2], {"d": d}) else 1)
PY
}

: >"$IN"
run
[ "$RC" = 0 ] || fail "empty input exited $RC"
jchk 'd["helix_mode"] is True and d["base_keymap"] == "VSCode"' \
    'empty input did not produce the managed settings'

cat >"$IN" <<'JSONC'
// Zed writes JSONC.
{
  "helix_mode": false, /* drifted */
  "ssh_connections": [{"host": "example-host", "args": [],},],
  "context_servers": {"demo": {"command": "demo-mcp", "args": ["//kept", ",}"]}},
}
JSONC
run
[ "$RC" = 0 ] || fail "JSONC input exited $RC"
jchk 'd["helix_mode"] is True' 'a drifted managed key was not restored'
jchk 'd["ssh_connections"] == [{"host": "example-host", "args": []}]' 'SSH connections were dropped'
jchk 'd["context_servers"]["demo"]["args"] == ["//kept", ",}"]' 'context servers were altered'

cp -- "$OUT" "$IN"
run
cmp -s "$IN" "$OUT" || fail 'matching settings were rewritten'

for bad in '{"helix_mode": ' '[]' 'null' $'{"a": "\xff"}'; do
    printf '%s' "$bad" >"$IN"
    run
    [ "$RC" = 0 ] || fail "invalid settings ($bad) exited $RC instead of 0"
    cmp -s "$IN" "$OUT" || fail "invalid settings ($bad) were not passed through unchanged"
    grep -q 'leaving them unchanged' "$ERR" || fail "invalid settings ($bad) were left without saying why"
done

echo 'PASS: Zed settings merge sets managed keys, keeps Zed-owned keys, passes bad input through'

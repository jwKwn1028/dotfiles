#!/usr/bin/env bash

# Covers private_dot_claude/modify_private_settings.json, the chezmoi modify_
# script that merges the managed Claude settings into the live file. The file it
# rewrites is owned by an installer as well, so the invariant under test is that
# unmanaged keys survive untouched -- see AGENTS.md, "Agent tooling this repo
# does not manage".

set -euo pipefail

TEST_DIR="$(dirname "$(readlink -f "$0")")"
SOURCE_ROOT="$(readlink -f "$TEST_DIR/../../..")"
MERGE="$SOURCE_ROOT/private_dot_claude/modify_private_settings.json"
[ -r "$MERGE" ] ||
    MERGE="$(chezmoi source-path 2>/dev/null || true)/private_dot_claude/modify_private_settings.json"
if [ ! -r "$MERGE" ]; then
    echo "SKIP: the chezmoi source directory is unavailable from the applied tree"
    exit 0
fi

TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT
# chezmoi runs a modify_ script from a temp copy it makes executable, so the
# shebang is what selects the interpreter. Exercise it the same way.
SUBJECT="$TEST_TMP/modify"
cp -p -- "$MERGE" "$SUBJECT"
chmod +x "$SUBJECT"

IN="$TEST_TMP/in"
OUT="$TEST_TMP/out"
ERR="$TEST_TMP/err"
RC=0

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
sys.exit(0 if eval(" ".join(sys.argv[2].split()), {"d": d}) else 1)
PY
}

# The managed set, duplicated on purpose: changing what the script pins should
# take a deliberate edit here too.
managed_ok='d["model"] == "opus[1m]"
    and d["env"]["ENABLE_TOOL_SEARCH"] == "auto:50"
    and d["permissions"]["defaultMode"] == "manual"
    and d["disableRemoteControl"] is True
    and d["effortLevel"] == "xhigh"
    and d["tui"] == "fullscreen"'

# --- a missing or empty file becomes the managed set -------------------------
: >"$IN"
run
[ "$RC" = 0 ] || fail "empty input exited $RC"
jchk "$managed_ok" 'empty input did not produce the managed settings'
[ "$(tail -c1 "$OUT" | od -An -c | tr -d ' \n')" = '\n' ] ||
    fail 'the rewritten file does not end in a newline'

printf '   \n  \n' >"$IN"
run
[ "$RC" = 0 ] || fail "whitespace-only input exited $RC"
jchk "$managed_ok" 'whitespace-only input did not produce the managed settings'

# --- unreadable input is refused, never overwritten --------------------------
for bad in '{"model": ' 'not json at all' '{"a": 1,}'; do
    printf '%s' "$bad" >"$IN"
    run
    [ "$RC" = 1 ] || fail "invalid JSON exited $RC instead of 1"
    [ -s "$OUT" ] && fail 'invalid JSON still produced output, clobbering the file'
    grep -q 'refusing to overwrite' "$ERR" ||
        fail 'invalid JSON was refused without saying why'
done

for bad in '[]' '"a string"' '3' 'null' 'true'; do
    printf '%s' "$bad" >"$IN"
    run
    [ "$RC" = 1 ] || fail "non-object JSON ($bad) exited $RC instead of 1"
    [ -s "$OUT" ] && fail "non-object JSON ($bad) still produced output"
    grep -q 'not a JSON object' "$ERR" ||
        fail "non-object JSON ($bad) was refused without saying why"
    grep -q 'Traceback' "$ERR" &&
        fail "non-object JSON ($bad) crashed instead of refusing cleanly"
done

# --- installer-owned keys survive -------------------------------------------
cat >"$IN" <<'EOF'
{
  "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": []}]},
  "statusLine": {"type": "command", "command": "/opt/installer/statusline"},
  "mcpServers": {"thing": {"command": "thing-server"}},
  "env": {"INSTALLER_VAR": "keep me", "ENABLE_TOOL_SEARCH": "stale"},
  "permissions": {"allow": ["Read(*)"], "defaultMode": "acceptEdits"},
  "theme": "dark",
  "model": "some-other-model"
}
EOF
run
[ "$RC" = 0 ] || fail "a populated settings file exited $RC"
jchk "$managed_ok" 'the managed keys were not applied over stale values'
jchk 'd["hooks"]["PreToolUse"][0]["matcher"] == "Bash"' 'installer hooks were dropped'
jchk 'd["statusLine"]["command"] == "/opt/installer/statusline"' \
    'the installer statusLine was dropped'
jchk 'd["mcpServers"]["thing"]["command"] == "thing-server"' \
    'installer mcpServers were dropped'
jchk 'd["env"]["INSTALLER_VAR"] == "keep me"' 'an unmanaged env key was dropped'
jchk 'd["permissions"]["allow"] == ["Read(*)"]' \
    'an unmanaged permissions key was dropped'
jchk 'd["theme"] == "dark"' 'an unrelated top-level key was dropped'

# --- a wrongly typed env/permissions block is rebuilt, not fatal -------------
for shape in '"env": "a string"' '"env": []' '"env": null'; do
    printf '{%s, "theme": "dark"}\n' "$shape" >"$IN"
    run
    [ "$RC" = 0 ] || fail "env as $shape exited $RC"
    jchk "$managed_ok" "env as $shape did not yield the managed settings"
    jchk 'd["theme"] == "dark"' "env as $shape lost an unrelated key"
done

for shape in '"permissions": "a string"' '"permissions": 7'; do
    printf '{%s, "theme": "dark"}\n' "$shape" >"$IN"
    run
    [ "$RC" = 0 ] || fail "permissions as $shape exited $RC"
    jchk "$managed_ok" "permissions as $shape did not yield the managed settings"
    jchk 'd["theme"] == "dark"' "permissions as $shape lost an unrelated key"
done

# --- an already-correct file is passed through byte for byte -----------------
# chezmoi diffs the output, so a formatting-only rewrite would show as drift on
# every apply.
cat >"$IN" <<'EOF'
{
    "model": "opus[1m]",
    "env": {"ENABLE_TOOL_SEARCH": "auto:50"},
    "permissions": {"defaultMode": "manual"},
    "disableRemoteControl": true,
    "effortLevel": "xhigh",
    "tui": "fullscreen",
    "keepMyFormatting":    "yes"
}
EOF
run
[ "$RC" = 0 ] || fail "an already-correct file exited $RC"
cmp -s "$IN" "$OUT" ||
    fail 'an already-correct file was reformatted instead of passed through'

# --- every managed key is load-bearing for that passthrough -----------------
# Flip one key at a time; each must break the match and force a rewrite.
while IFS='|' read -r label mutation; do
    [ -n "$label" ] || continue
    python3 - "$mutation" >"$IN" <<'PY'
import json, sys
d = {
    "model": "opus[1m]",
    "env": {"ENABLE_TOOL_SEARCH": "auto:50"},
    "permissions": {"defaultMode": "manual"},
    "disableRemoteControl": True,
    "effortLevel": "xhigh",
    "tui": "fullscreen",
}
exec(sys.argv[1], {"d": d})
json.dump(d, sys.stdout, indent=4)
PY
    cp -- "$IN" "$TEST_TMP/before"
    run
    [ "$RC" = 0 ] || fail "a settings file with $label exited $RC"
    cmp -s "$TEST_TMP/before" "$OUT" &&
        fail "$label was passed through instead of corrected"
    jchk "$managed_ok" "$label was not corrected"
done <<'EOF'
a wrong model|d["model"] = "sonnet"
a wrong ENABLE_TOOL_SEARCH|d["env"]["ENABLE_TOOL_SEARCH"] = "off"
a missing ENABLE_TOOL_SEARCH|del d["env"]["ENABLE_TOOL_SEARCH"]
a wrong defaultMode|d["permissions"]["defaultMode"] = "plan"
a wrong disableRemoteControl|d["disableRemoteControl"] = False
a truthy non-true disableRemoteControl|d["disableRemoteControl"] = 1
a wrong effortLevel|d["effortLevel"] = "high"
a wrong tui|d["tui"] = "windowed"
a missing model|del d["model"]
EOF

# --- the rewrite is a fixed point -------------------------------------------
printf '{"theme": "dark"}\n' >"$IN"
run
[ "$RC" = 0 ] || fail "the first pass exited $RC"
cp -- "$OUT" "$IN"
run
[ "$RC" = 0 ] || fail "the second pass exited $RC"
cmp -s "$IN" "$OUT" || fail 'a rewritten file is not a fixed point'

# --- non-ASCII survives the round trip --------------------------------------
printf '{"note": "\xed\x95\x9c\xea\xb5\xad\xec\x96\xb4"}\n' >"$IN"
run
[ "$RC" = 0 ] || fail "non-ASCII input exited $RC"
jchk 'd["note"] == "한국어"' 'non-ASCII content was mangled'
grep -q $'\xed\x95\x9c' "$OUT" || fail 'non-ASCII was escaped instead of kept literal'

echo 'PASS: Claude settings merge pins the managed keys and keeps the rest'

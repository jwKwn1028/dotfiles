#!/usr/bin/env bash

# Covers private_dot_codex/modify_private_config.toml, the chezmoi modify_ script
# that pins `model` and `model_reasoning_effort` in the live Codex config. Codex
# and its installer own everything else in that file -- MCP servers, hooks,
# per-project trust -- so the invariant under test is that only the two top-level
# keys move. See AGENTS.md, "Agent tooling this repo does not manage".
#
# The regression this guards: the top-level region was once addressed as
# `1,/^\[/`, which GNU sed resolves by testing the end pattern from line 2. On a
# config whose first line is a section header that range swallowed the whole
# first table, so a `model` key belonging to that table was rewritten in place
# and no top-level key was set at all.

set -euo pipefail

TEST_DIR="$(dirname "$(readlink -f "$0")")"
SOURCE_ROOT="$(readlink -f "$TEST_DIR/../../..")"
MERGE="$SOURCE_ROOT/private_dot_codex/modify_private_config.toml"
[ -r "$MERGE" ] ||
    MERGE="$(chezmoi source-path 2>/dev/null || true)/private_dot_codex/modify_private_config.toml"
if [ ! -r "$MERGE" ]; then
    echo "SKIP: the chezmoi source directory is unavailable from the applied tree"
    exit 0
fi

TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT
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
    [ -s "$OUT" ] && sed 's/^/      output: /' "$OUT" >&2
    exit 1
}

run() {
    RC=0
    "$SUBJECT" <"$IN" >"$OUT" 2>"$ERR" || RC=$?
    [ "$RC" = 0 ] || fail "the script exited $RC"
}

# `expr` is evaluated with the parsed output bound to d.
tchk() {
    python3 - "$OUT" "$1" <<'PY' || fail "$2"
import sys, tomllib
with open(sys.argv[1], "rb") as fh:
    d = tomllib.load(fh)
sys.exit(0 if eval(" ".join(sys.argv[2].split()), {"d": d}) else 1)
PY
}

count_top() {
    sed -n "0,/^\[/p" "$OUT" | grep -Ec "^$1[[:space:]]*=" || true
}

managed_ok='d["model"] == "gpt-6-astra" and d["model_reasoning_effort"] == "xhigh"'

# --- an empty config becomes the two managed keys ----------------------------
: >"$IN"
run
tchk "$managed_ok" 'an empty config did not gain the managed keys'

# --- existing top-level values are replaced, not duplicated ------------------
cat >"$IN" <<'EOF'
model = "gpt-old"
model_reasoning_effort = "low"
personality = "pragmatic"

[features]
web_search = true
EOF
run
tchk "$managed_ok" 'stale top-level values were not replaced'
tchk 'd["personality"] == "pragmatic"' 'an unmanaged top-level key was dropped'
tchk 'd["features"]["web_search"] is True' 'an installer-owned table was dropped'
for key in model model_reasoning_effort; do
    [ "$(count_top "$key")" = 1 ] ||
        fail "$key appears $(count_top "$key") times in the top-level region"
done

# --- the regression: a config that opens with a section ----------------------
# Both managed names live in that first table, so whichever the script writes
# first cannot shorten the range and mask the other.
cat >"$IN" <<'EOF'
[features]
model = "table-owned"
model_reasoning_effort = "table-owned"

[mcp_servers.thing]
command = "thing-server"
EOF
run
tchk "$managed_ok" 'the managed keys were not set at the top level'
tchk 'd["features"]["model"] == "table-owned"' \
    'a table-owned model was clobbered by the top-level pin'
tchk 'd["features"]["model_reasoning_effort"] == "table-owned"' \
    'a table-owned model_reasoning_effort was clobbered'
tchk 'd["mcp_servers"]["thing"]["command"] == "thing-server"' \
    'an installer-owned MCP server was dropped'

# Each key on its own, since the bug only showed when nothing else had already
# pushed a non-header line to line 1.
for key in model model_reasoning_effort; do
    printf '[features]\n%s = "table-owned"\n' "$key" >"$IN"
    run
    tchk "$managed_ok" "opening with a table holding only $key lost the managed keys"
    tchk "d[\"features\"][\"$key\"] == \"table-owned\"" \
        "a table-owned $key was clobbered when it was the only key"
done

# --- installer-owned content passes through untouched ------------------------
cat >"$IN" <<'EOF'
model = "gpt-old"

[features]
web_search = true

[mcp_servers.alpha]
command = "alpha"
args = ["--flag"]

[projects."/some/path"]
trust_level = "trusted"

[[hooks.pre]]
run = "echo hi"
EOF
run
python3 - "$IN" "$OUT" <<'PY' || fail 'installer-owned tables did not survive verbatim'
import sys, tomllib
before = tomllib.load(open(sys.argv[1], "rb"))
after = tomllib.load(open(sys.argv[2], "rb"))
for key in ("features", "mcp_servers", "projects", "hooks"):
    if before[key] != after[key]:
        print(f"{key}: {before[key]!r} -> {after[key]!r}", file=sys.stderr)
        sys.exit(1)
PY

# --- running twice changes nothing ------------------------------------------
cp -- "$OUT" "$IN"
cp -- "$OUT" "$TEST_TMP/first"
run
cmp -s "$TEST_TMP/first" "$OUT" || fail 'a second pass changed the config again'

# --- spacing variants are recognised as the same key ------------------------
while IFS= read -r variant; do
    [ -n "$variant" ] || continue
    printf '%s\npersonality = "pragmatic"\n' "$variant" >"$IN"
    run
    tchk "$managed_ok" "the spacing variant [$variant] was not replaced"
    [ "$(count_top model)" = 1 ] ||
        fail "the spacing variant [$variant] left model duplicated"
done <<'EOF'
model="gpt-old"
model = "gpt-old"
model	=	"gpt-old"
model    =    "gpt-old"
EOF

# --- a longer key that merely starts with a managed name is left alone -------
cat >"$IN" <<'EOF'
model_reasoning_summary = "detailed"
modelx = "untouched"
EOF
run
tchk "$managed_ok" 'the managed keys were not added alongside similar names'
tchk 'd["model_reasoning_summary"] == "detailed"' \
    'a key sharing a managed prefix was overwritten'
tchk 'd["modelx"] == "untouched"' 'a key sharing a managed prefix was overwritten'

# --- a commented-out or indented key is not mistaken for the real one -------
cat >"$IN" <<'EOF'
#model = "commented"

[features]
  model = "indented"
EOF
run
tchk "$managed_ok" 'a commented or indented key suppressed the managed pin'
tchk 'd["features"]["model"] == "indented"' 'an indented table key was clobbered'
grep -q '^#model = "commented"' "$OUT" || fail 'the commented line was rewritten'

# --- a config with no trailing newline is not corrupted ---------------------
printf 'personality = "pragmatic"' >"$IN"
run
tchk "$managed_ok" 'a config without a trailing newline lost the managed keys'
tchk 'd["personality"] == "pragmatic"' \
    'a config without a trailing newline lost an unmanaged key'

echo 'PASS: Codex config merge pins two top-level keys and leaves tables alone'

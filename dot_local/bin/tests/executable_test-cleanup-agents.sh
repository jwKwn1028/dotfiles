#!/usr/bin/env bash
# Black-box safety tests for ~/.cleanup-agents.sh.
#
# Every case gets a disposable HOME. Interactive cases run under script(1), so
# the production code reads real answers from /dev/tty without a test-only
# switch or any possibility of touching the caller's Claude/Codex state.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/../../.." && pwd)"
if [[ -f "$ROOT/executable_dot_cleanup-agents.sh" ]]; then
  CLEANUP="$ROOT/executable_dot_cleanup-agents.sh"
elif [[ -f "$ROOT/.cleanup-agents.sh" ]]; then
  CLEANUP="$ROOT/.cleanup-agents.sh"
else
  printf 'FAIL: cleanup-agents script not found under %s\n' "$ROOT" >&2
  exit 1
fi

TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT

pass_count=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  pass_count=$((pass_count + 1))
  printf 'ok %d - %s\n' "$pass_count" "$1"
}

assert_exists() {
  [[ -e "$1" ]] || fail "expected to exist: $1"
}

assert_absent() {
  [[ ! -e "$1" ]] || fail "expected to be absent: $1"
}

assert_contains() {
  local file="$1" text="$2"
  grep -Fq -- "$text" "$file" || {
    sed -n '1,240p' "$file" >&2
    fail "expected output to contain: $text"
  }
}

assert_same() {
  local expected="$1" actual="$2"
  cmp -s -- "$expected" "$actual" || {
    printf '%s\n' "--- expected: $expected" >&2
    sed -n '1,120p' "$expected" >&2
    printf '%s\n' "--- actual: $actual" >&2
    sed -n '1,120p' "$actual" >&2
    fail "files differ: $expected $actual"
  }
}

new_home() {
  local name="$1"
  local home="$TEST_TMP/$name/home"
  mkdir -p -- "$home"
  printf '%s\n' "$home"
}

write_codex_chat() {
  local home="$1" sid="$2"
  local transcript="$home/.codex/sessions/2026/08/rollout-$sid.jsonl"
  mkdir -p -- "${transcript%/*}"
  printf '%s\n' \
    'this malformed JSONL line must be ignored' \
    "{\"timestamp\":\"2026-08-21T00:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"session_id\":\"$sid\",\"cwd\":\"/tmp/fixture\"}}" \
    '{"timestamp":"2026-08-21T00:01:00Z","type":"event_msg","payload":{"type":"user_message","message":"fixture request"}}' \
    >"$transcript"
  printf '%s\n' "$transcript"
}

write_claude_chat() {
  local home="$1" sid="$2"
  local transcript="$home/.claude/projects/fixture/$sid.jsonl"
  mkdir -p -- "${transcript%/*}"
  printf '%s\n' \
    'this malformed JSONL line must be ignored' \
    '{"timestamp":"2026-08-21T00:00:00Z","type":"user","message":{"content":"fixture request"}}' \
    '{"timestamp":"2026-08-21T00:01:00Z","type":"assistant","message":{"content":"fixture response"}}' \
    >"$transcript"
  printf '%s\n' "$transcript"
}

run_interactive() {
  local home="$1" output="$2" replies="$3" command
  command -v script >/dev/null 2>&1 || fail 'script(1) is required for interactive cleanup tests'
  printf -v command 'env HOME=%q bash %q --apply' "$home" "$CLEANUP"
  printf '%s' "$replies" | script -qefc "$command" /dev/null >"$output"
}

test_dry_run_preserves_everything() {
  local home output codex_sid claude_sid codex_chat claude_chat
  home="$(new_home dry-run)"
  output="$TEST_TMP/dry-run/output"
  codex_sid='11111111-1111-1111-1111-111111111111'
  claude_sid='22222222-2222-2222-2222-222222222222'
  codex_chat="$(write_codex_chat "$home" "$codex_sid")"
  claude_chat="$(write_claude_chat "$home" "$claude_sid")"

  mkdir -p -- "$home/.codex/memories" "$home/.claude/projects/fixture/memory"
  printf '%s\n' '{"session_id":"'$codex_sid'"}' >"$home/.codex/history.jsonl"
  printf '%s\n' '{"sessionId":"'$claude_sid'"}' >"$home/.claude/history.jsonl"
  printf 'protected\n' >"$home/.codex/config.toml"
  printf 'remove me\n' >"$home/.codex/cache.tmp"
  printf 'memory\n' >"$home/.codex/memories/memory.md"
  printf 'memory\n' >"$home/.claude/projects/fixture/memory/memory.md"
  : >"$home/.codex/state_5.sqlite"
  : >"$home/.codex/memories_1.sqlite"

  HOME="$home" bash "$CLEANUP" >"$output" 2>&1

  assert_exists "$codex_chat"
  assert_exists "$claude_chat"
  assert_exists "$home/.codex/history.jsonl"
  assert_exists "$home/.claude/history.jsonl"
  assert_exists "$home/.codex/state_5.sqlite"
  assert_exists "$home/.codex/memories_1.sqlite"
  assert_exists "$home/.codex/memories/memory.md"
  assert_exists "$home/.claude/projects/fixture/memory/memory.md"
  assert_exists "$home/.codex/cache.tmp"
  assert_exists "$home/.codex/config.toml"
  assert_contains "$output" "Would remove: $home/.codex/cache.tmp"
  assert_contains "$output" 'No files were removed.'
  pass 'dry run previews changes and preserves all fixture state'
}

test_codex_keep_prunes_history() {
  local home output sid transcript expected
  home="$(new_home codex-keep)"
  output="$TEST_TMP/codex-keep/output"
  expected="$TEST_TMP/codex-keep/expected-history"
  sid='33333333-3333-3333-3333-333333333333'
  transcript="$(write_codex_chat "$home" "$sid")"

  printf '%s\n' \
    "{\"session_id\":\"$sid\",\"text\":\"keep\"}" \
    'this malformed history line must be dropped' \
    '{"session_id":"stale","text":"drop"}' \
    >"$home/.codex/history.jsonl"
  printf '%s\n' "{\"session_id\":\"$sid\",\"text\":\"keep\"}" >"$expected"
  printf 'protected\n' >"$home/.codex/config.toml"
  : >"$home/.codex/state_5.sqlite"
  : >"$home/.codex/logs_1.sqlite"

  run_interactive "$home" "$output" $'n\n'

  assert_exists "$transcript"
  assert_same "$expected" "$home/.codex/history.jsonl"
  assert_exists "$home/.codex/state_5.sqlite"
  assert_exists "$home/.codex/logs_1.sqlite"
  assert_exists "$home/.codex/config.toml"
  assert_contains "$output" 'Kept chat transcript:'
  assert_contains "$output" 'Pruned history.jsonl to 1 kept entry.'
  pass 'Codex keep decision preserves the chat and drops malformed/stale history rows'
}

test_codex_delete_removes_chat_state() {
  local home output sid transcript
  home="$(new_home codex-delete)"
  output="$TEST_TMP/codex-delete/output"
  sid='44444444-4444-4444-4444-444444444444'
  transcript="$(write_codex_chat "$home" "$sid")"

  printf '%s\n' "{\"session_id\":\"$sid\"}" >"$home/.codex/history.jsonl"
  printf 'protected\n' >"$home/.codex/config.toml"
  : >"$home/.codex/state_5.sqlite"
  : >"$home/.codex/state_5.sqlite-wal"
  : >"$home/.codex/state_5.sqlite-shm"
  : >"$home/.codex/logs_1.sqlite"
  : >"$home/.codex/logs_1.sqlite-journal"

  run_interactive "$home" "$output" $'y\ny\n'

  assert_absent "$transcript"
  assert_absent "$home/.codex/history.jsonl"
  assert_absent "$home/.codex/state_5.sqlite"
  assert_absent "$home/.codex/state_5.sqlite-wal"
  assert_absent "$home/.codex/state_5.sqlite-shm"
  assert_absent "$home/.codex/logs_1.sqlite"
  assert_absent "$home/.codex/logs_1.sqlite-journal"
  assert_exists "$home/.codex/config.toml"
  assert_contains "$output" 'Deleted chat transcript:'
  assert_contains "$output" "Removed: $home/.codex/state_5.sqlite"
  pass 'Codex delete decisions remove the transcript, history, DBs, and sidecars'
}

test_claude_keep_prunes_history() {
  local home output sid transcript expected
  home="$(new_home claude-keep)"
  output="$TEST_TMP/claude-keep/output"
  expected="$TEST_TMP/claude-keep/expected-history"
  sid='55555555-5555-5555-5555-555555555555'
  transcript="$(write_claude_chat "$home" "$sid")"

  printf '%s\n' \
    "{\"sessionId\":\"$sid\",\"display\":\"keep\"}" \
    'this malformed history line must be dropped' \
    '{"sessionId":"stale","display":"drop"}' \
    >"$home/.claude/history.jsonl"
  printf '%s\n' "{\"sessionId\":\"$sid\",\"display\":\"keep\"}" >"$expected"
  printf 'protected\n' >"$home/.claude/settings.json"

  run_interactive "$home" "$output" $'n\n'

  assert_exists "$transcript"
  assert_same "$expected" "$home/.claude/history.jsonl"
  assert_exists "$home/.claude/settings.json"
  assert_contains "$output" 'Kept chat transcript:'
  assert_contains "$output" 'Pruned Claude history.jsonl to 1 kept entry.'
  pass 'Claude keep decision preserves the chat and drops malformed/stale history rows'
}

test_claude_delete_removes_chat_state() {
  local home output sid transcript
  home="$(new_home claude-delete)"
  output="$TEST_TMP/claude-delete/output"
  sid='66666666-6666-6666-6666-666666666666'
  transcript="$(write_claude_chat "$home" "$sid")"

  printf '%s\n' "{\"sessionId\":\"$sid\"}" >"$home/.claude/history.jsonl"
  printf 'protected\n' >"$home/.claude/settings.json"

  run_interactive "$home" "$output" $'y\ny\n'

  assert_absent "$transcript"
  assert_absent "$home/.claude/history.jsonl"
  assert_absent "$home/.claude/projects"
  assert_exists "$home/.claude/settings.json"
  assert_contains "$output" 'Deleted chat transcript:'
  assert_contains "$output" "Removed: $home/.claude/history.jsonl"
  pass 'Claude delete decisions remove the transcript and orphaned history'
}

test_absent_codex_databases_are_a_noop() {
  local home output
  home="$(new_home absent-databases)"
  output="$TEST_TMP/absent-databases/output"
  mkdir -p -- "$home/.codex"
  printf 'protected\n' >"$home/.codex/config.toml"

  HOME="$home" bash "$CLEANUP" --apply >"$output" 2>&1

  assert_exists "$home/.codex/config.toml"
  assert_contains "$output" 'No Codex chat transcripts found.'
  assert_contains "$output" 'No Codex memory stored (nothing to erase).'
  assert_contains "$output" 'Cleanup complete.'
  pass 'absent Codex databases and stores are harmless'
}

test_dry_run_preserves_everything
test_codex_keep_prunes_history
test_codex_delete_removes_chat_state
test_claude_keep_prunes_history
test_claude_delete_removes_chat_state
test_absent_codex_databases_are_a_noop

printf 'PASS: cleanup-agents safety fixtures (%d cases)\n' "$pass_count"

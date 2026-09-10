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
  # Without this the diagnostic below dies on its own sed before it can report.
  [[ -e "$actual" ]] || fail "expected to exist: $actual"
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
  local home="$1" output="$2" replies="$3"
  shift 3
  local command extra=""
  command -v script >/dev/null 2>&1 || fail 'script(1) is required for interactive cleanup tests'
  (( $# )) && printf -v extra ' %q' "$@"
  printf -v command 'env HOME=%q bash %q --apply%s' "$home" "$CLEANUP" "$extra"
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

test_claude_hooks_survive_apply() {
  local home output
  home="$(new_home claude-hooks)"
  output="$TEST_TMP/claude-hooks/output"
  mkdir -p -- "$home/.claude/hooks/nested"
  printf 'hook\n' >"$home/.claude/hooks/session-start.sh"
  printf 'hook\n' >"$home/.claude/hooks/nested/deep.sh"
  printf 'remove me\n' >"$home/.claude/cache.tmp"

  HOME="$home" bash "$CLEANUP" --apply >"$output" 2>&1

  assert_exists "$home/.claude/hooks/session-start.sh"
  assert_exists "$home/.claude/hooks/nested/deep.sh"
  assert_absent "$home/.claude/cache.tmp"
  assert_contains "$output" "Keep: $home/.claude/hooks"
  pass 'Claude hooks directory survives --apply'
}

# The per-chat prompt is pointless if the sweep afterwards takes the state that
# belongs to a chat you just kept.
test_kept_chat_keeps_its_session_state() {
  local home output kept dropped
  home="$(new_home kept-session-state)"
  output="$TEST_TMP/kept-session-state/output"
  kept='77777777-7777-7777-7777-777777777777'
  dropped='88888888-8888-8888-8888-888888888888'
  write_claude_chat "$home" "$kept" >/dev/null
  write_claude_chat "$home" "$dropped" >/dev/null

  local sid
  for sid in "$kept" "$dropped"; do
    mkdir -p -- "$home/.claude/projects/fixture/$sid/tool-results" \
                "$home/.claude/file-history/$sid" \
                "$home/.claude/session-env/$sid"
    printf 'artifact\n' >"$home/.claude/projects/fixture/$sid/tool-results/out.txt"
    printf 'edit\n' >"$home/.claude/file-history/$sid/1.json"
    printf 'env\n' >"$home/.claude/session-env/$sid/env"
  done
  printf 'junk\n' >"$home/.claude/projects/fixture/stats.json"
  printf 'protected\n' >"$home/.claude/settings.json"

  # Transcripts are visited in sorted order: keep 7…, delete 8….
  run_interactive "$home" "$output" $'n\ny\n'

  assert_exists "$home/.claude/projects/fixture/$kept/tool-results/out.txt"
  assert_exists "$home/.claude/file-history/$kept/1.json"
  assert_exists "$home/.claude/session-env/$kept/env"
  assert_absent "$home/.claude/projects/fixture/$dropped/tool-results/out.txt"
  assert_absent "$home/.claude/file-history/$dropped"
  assert_absent "$home/.claude/session-env/$dropped"
  assert_absent "$home/.claude/projects/fixture/stats.json"
  pass 'a kept chat keeps its tool-results, file-history and session-env'
}

test_memory_index_survives_the_sweep() {
  local home output sid
  home="$(new_home memory-index)"
  output="$TEST_TMP/memory-index/output"
  sid='99999999-9999-9999-9999-999999999999'
  write_claude_chat "$home" "$sid" >/dev/null
  mkdir -p -- "$home/.claude/projects/fixture/memory"
  printf -- '- [note](memory/note.md)\n' >"$home/.claude/projects/fixture/MEMORY.md"
  printf 'a note\n' >"$home/.claude/projects/fixture/memory/note.md"
  printf 'protected\n' >"$home/.claude/settings.json"

  run_interactive "$home" "$output" $'n\nn\n'

  assert_exists "$home/.claude/projects/fixture/MEMORY.md"
  assert_exists "$home/.claude/projects/fixture/memory/note.md"
  assert_contains "$output" 'Memory indexes: 1 MEMORY.md at project roots'
  pass 'a project-root MEMORY.md follows the memory prompt, not the sweep'
}

test_memory_erase_takes_the_index() {
  local home output sid
  home="$(new_home memory-erase)"
  output="$TEST_TMP/memory-erase/output"
  sid='99999999-aaaa-aaaa-aaaa-999999999999'
  write_claude_chat "$home" "$sid" >/dev/null
  mkdir -p -- "$home/.claude/projects/fixture/memory"
  printf -- '- [note](memory/note.md)\n' >"$home/.claude/projects/fixture/MEMORY.md"
  printf 'a note\n' >"$home/.claude/projects/fixture/memory/note.md"
  printf 'protected\n' >"$home/.claude/settings.json"

  run_interactive "$home" "$output" $'n\ny\n'

  assert_absent "$home/.claude/projects/fixture/MEMORY.md"
  assert_absent "$home/.claude/projects/fixture/memory"
  pass 'erasing Claude memory takes the index with the store'
}

test_codex_session_index_follows_chats() {
  local home output sid transcript expected
  home="$(new_home codex-index)"
  output="$TEST_TMP/codex-index/output"
  expected="$TEST_TMP/codex-index/expected-index"
  sid='cccccccc-3333-3333-3333-333333333333'
  transcript="$(write_codex_chat "$home" "$sid")"

  printf '%s\n' "{\"session_id\":\"$sid\"}" >"$home/.codex/history.jsonl"
  printf '%s\n' \
    "{\"id\":\"$sid\",\"thread_name\":\"keep\"}" \
    'this malformed index line must be dropped' \
    '{"id":"stale","thread_name":"drop"}' \
    >"$home/.codex/session_index.jsonl"
  printf '%s\n' "{\"id\":\"$sid\",\"thread_name\":\"keep\"}" >"$expected"
  printf 'protected\n' >"$home/.codex/config.toml"
  : >"$home/.codex/thread_history_1.sqlite"
  : >"$home/.codex/queue_1.sqlite"

  run_interactive "$home" "$output" $'n\n'

  assert_exists "$transcript"
  assert_same "$expected" "$home/.codex/session_index.jsonl"
  assert_exists "$home/.codex/thread_history_1.sqlite"
  assert_exists "$home/.codex/queue_1.sqlite"
  assert_contains "$output" 'Pruned session_index.jsonl to 1 kept entry.'
  pass 'Codex session_index.jsonl and thread/queue DBs follow the chat decisions'
}

# A schema bump leaves the older generation on disk; codex_bucket hides it from
# the blanket sweep, so only these functions can ever remove it.
test_codex_removes_every_db_generation() {
  local home output sid transcript
  home="$(new_home codex-generations)"
  output="$TEST_TMP/codex-generations/output"
  sid='dddddddd-4444-4444-4444-444444444444'
  transcript="$(write_codex_chat "$home" "$sid")"

  printf '%s\n' "{\"session_id\":\"$sid\"}" >"$home/.codex/history.jsonl"
  printf 'protected\n' >"$home/.codex/config.toml"
  : >"$home/.codex/state_5.sqlite"
  : >"$home/.codex/state_6.sqlite"
  : >"$home/.codex/logs_1.sqlite"
  : >"$home/.codex/memories_1.sqlite"
  : >"$home/.codex/memories_2.sqlite"

  run_interactive "$home" "$output" $'y\ny\ny\n'

  assert_absent "$transcript"
  assert_absent "$home/.codex/state_5.sqlite"
  assert_absent "$home/.codex/state_6.sqlite"
  assert_absent "$home/.codex/logs_1.sqlite"
  assert_absent "$home/.codex/memories_1.sqlite"
  assert_absent "$home/.codex/memories_2.sqlite"
  assert_exists "$home/.codex/config.toml"
  pass 'every schema generation of a Codex DB is removed, not just the first'
}

# These are gitignored per-project agents and settings; nothing here restores
# them, so they must not go without an explicit flag and an explicit yes.
test_project_local_agents_need_the_flag() {
  local home output
  home="$(new_home project-local)"
  output="$TEST_TMP/project-local/output"
  mkdir -p -- "$home/.claude" "$home/src/proj/.claude/agents" "$home/Documents/other/.codex"
  printf 'protected\n' >"$home/.claude/settings.json"
  printf 'agent\n' >"$home/src/proj/.claude/agents/reviewer.md"

  HOME="$home" bash "$CLEANUP" --apply >"$output" 2>&1

  assert_exists "$home/src/proj/.claude/agents/reviewer.md"
  assert_exists "$home/Documents/other/.codex"
  assert_contains "$output" 'Skipped project-local .claude/.codex directories'
  pass 'project-local agent directories are untouched without --include-projects'
}

test_include_projects_prompts_per_path() {
  local home output
  home="$(new_home include-projects)"
  output="$TEST_TMP/include-projects/output"
  mkdir -p -- "$home/.claude" "$home/aaa-drop/.codex" "$home/zzz-keep/.claude/agents"
  printf 'protected\n' >"$home/.claude/settings.json"
  printf 'agent\n' >"$home/zzz-keep/.claude/agents/reviewer.md"

  # Paths are offered in sorted order: delete aaa-drop, keep zzz-keep.
  run_interactive "$home" "$output" $'y\nn\n' --include-projects

  assert_absent "$home/aaa-drop/.codex"
  assert_exists "$home/zzz-keep/.claude/agents/reviewer.md"
  assert_exists "$home/.claude/settings.json"
  assert_contains "$output" 'Project-local agent path:'
  pass '--include-projects offers each path and honours the answer'
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

# ---- Filters -----------------------------------------------------------------

assert_not_contains() {
  local file="$1" text="$2"
  ! grep -Fq -- "$text" "$file" || {
    sed -n '1,240p' "$file" >&2
    fail "expected output not to contain: $text"
  }
}

filler() {
  local pad="${1:-0}"
  (( pad )) || return 0
  printf "%${pad}s" '' | tr ' ' x
}

# Claude chat started in <cwd>, last active at <ts>, padded by <pad> bytes.
write_claude_chat_in() {
  local home="$1" sid="$2" cwd="$3" ts="$4" pad="${5:-0}"
  local transcript="$home/.claude/projects/${cwd//[^A-Za-z0-9]/-}/$sid.jsonl"
  mkdir -p -- "${transcript%/*}"
  printf '%s\n' \
    "{\"timestamp\":\"2026-01-01T00:00:00Z\",\"type\":\"user\",\"cwd\":\"$cwd\",\"message\":{\"content\":\"request in $cwd $(filler "$pad")\"}}" \
    "{\"timestamp\":\"$ts\",\"type\":\"assistant\",\"cwd\":\"$cwd\",\"message\":{\"content\":\"fixture response\"}}" \
    >"$transcript"
  printf '%s\n' "$transcript"
}

write_codex_chat_in() {
  local home="$1" sid="$2" cwd="$3" ts="$4" pad="${5:-0}"
  local transcript="$home/.codex/sessions/2026/01/01/rollout-2026-01-01T00-00-00-$sid.jsonl"
  mkdir -p -- "${transcript%/*}"
  printf '%s\n' \
    "{\"timestamp\":\"2026-01-01T00:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"session_id\":\"$sid\",\"cwd\":\"$cwd\"}}" \
    "{\"timestamp\":\"$ts\",\"type\":\"event_msg\",\"payload\":{\"type\":\"user_message\",\"message\":\"request in $cwd $(filler "$pad")\"}}" \
    >"$transcript"
  printf '%s\n' "$transcript"
}

test_filter_dry_run_lists_only_matches() {
  local home output small big
  home="$(new_home filter-dry-run)"
  output="$TEST_TMP/filter-dry-run/output"
  small="$(write_claude_chat_in "$home" a1111111-1111-1111-1111-111111111111 /work/small 2026-08-01T00:00:00Z)"
  big="$(write_claude_chat_in "$home" a2222222-2222-2222-2222-222222222222 /work/big 2026-08-01T00:00:00Z 4096)"
  write_codex_chat_in "$home" a3333333-3333-3333-3333-333333333333 /work/codex-small 2026-08-01T00:00:00Z >/dev/null
  printf 'remove me\n' >"$home/.claude/cache.tmp"

  HOME="$home" bash "$CLEANUP" --smaller-than 2K >"$output" 2>&1

  assert_exists "$small"
  assert_exists "$big"
  assert_exists "$home/.claude/cache.tmp"
  assert_contains "$output" '/work/small'
  assert_contains "$output" '/work/codex-small'
  assert_not_contains "$output" '/work/big'
  assert_not_contains "$output" 'Would remove:'
  assert_contains "$output" '--apply would ask once'
  assert_contains "$output" 'No files were removed.'
  pass 'a filtered dry run lists only the matches and skips the general sweep'
}

test_filter_apply_takes_matching_chats_with_their_state() {
  local home output small big csmall cbig sid
  local s=b1111111-1111-1111-1111-111111111111 b=b2222222-2222-2222-2222-222222222222
  local cs=b3333333-3333-3333-3333-333333333333 cb=b4444444-4444-4444-4444-444444444444
  home="$(new_home filter-apply)"
  output="$TEST_TMP/filter-apply/output"
  small="$(write_claude_chat_in "$home" "$s" /work/p 2026-08-01T00:00:00Z)"
  big="$(write_claude_chat_in "$home" "$b" /work/p 2026-08-01T00:00:00Z 4096)"
  csmall="$(write_codex_chat_in "$home" "$cs" /work/p 2026-08-01T00:00:00Z)"
  cbig="$(write_codex_chat_in "$home" "$cb" /work/p 2026-08-01T00:00:00Z 4096)"
  for sid in "$s" "$b"; do
    mkdir -p -- "$home/.claude/projects/-work-p/$sid/tool-results" \
                "$home/.claude/file-history/$sid" "$home/.claude/session-env/$sid"
    printf 'x\n' >"$home/.claude/projects/-work-p/$sid/tool-results/out.txt"
    printf 'x\n' >"$home/.claude/file-history/$sid/1.json"
    printf 'x\n' >"$home/.claude/session-env/$sid/env"
  done
  printf '%s\n' "{\"sessionId\":\"$s\",\"timestamp\":1785542400000}" 'malformed line stays' \
    "{\"sessionId\":\"$b\",\"timestamp\":1785542400000}" >"$home/.claude/history.jsonl"
  printf '%s\n' 'malformed line stays' "{\"sessionId\":\"$b\",\"timestamp\":1785542400000}" \
    >"$TEST_TMP/filter-apply/claude-history"
  printf '%s\n' "{\"session_id\":\"$cs\",\"ts\":1785542400}" "{\"session_id\":\"$cb\",\"ts\":1785542400}" \
    >"$home/.codex/history.jsonl"
  printf '%s\n' "{\"session_id\":\"$cb\",\"ts\":1785542400}" >"$TEST_TMP/filter-apply/codex-history"
  printf '%s\n' "{\"id\":\"$cs\",\"updated_at\":\"2026-08-01T00:00:00.000000000Z\"}" \
    "{\"id\":\"$cb\",\"updated_at\":\"2026-08-01T00:00:00.000000000Z\"}" >"$home/.codex/session_index.jsonl"
  printf '%s\n' "{\"id\":\"$cb\",\"updated_at\":\"2026-08-01T00:00:00.000000000Z\"}" \
    >"$TEST_TMP/filter-apply/codex-index"
  mkdir -p -- "$home/.claude/projects/-work-p/memory"
  printf 'a note\n' >"$home/.claude/projects/-work-p/memory/note.md"
  printf 'protected\n' >"$home/.claude/settings.json"
  printf 'remove me\n' >"$home/.claude/cache.tmp"
  : >"$home/.codex/state_5.sqlite"

  # Claude chats: yes; Claude memory: no; Codex chats: yes.
  run_interactive "$home" "$output" $'y\nn\ny\n' --smaller-than 2K

  assert_absent "$small"
  assert_absent "$home/.claude/projects/-work-p/$s"
  assert_absent "$home/.claude/file-history/$s"
  assert_absent "$home/.claude/session-env/$s"
  assert_exists "$big"
  assert_exists "$home/.claude/projects/-work-p/$b/tool-results/out.txt"
  assert_exists "$home/.claude/file-history/$b/1.json"
  assert_exists "$home/.claude/session-env/$b/env"
  assert_same "$TEST_TMP/filter-apply/claude-history" "$home/.claude/history.jsonl"
  assert_exists "$home/.claude/projects/-work-p/memory/note.md"
  assert_absent "$csmall"
  assert_exists "$cbig"
  assert_same "$TEST_TMP/filter-apply/codex-history" "$home/.codex/history.jsonl"
  assert_same "$TEST_TMP/filter-apply/codex-index" "$home/.codex/session_index.jsonl"
  assert_exists "$home/.claude/settings.json"
  assert_exists "$home/.claude/cache.tmp"
  assert_exists "$home/.codex/state_5.sqlite"
  pass '--smaller-than deletes small chats with their state and history lines, nothing else'
}

test_filter_ended_before_takes_old_orphan_history() {
  local home output old new
  local o=c1111111-1111-1111-1111-111111111111 n=c2222222-2222-2222-2222-222222222222
  home="$(new_home filter-date)"
  output="$TEST_TMP/filter-date/output"
  old="$(write_claude_chat_in "$home" "$o" /work/p 2026-06-01T00:00:00Z)"
  new="$(write_claude_chat_in "$home" "$n" /work/p 2026-08-01T00:00:00Z)"
  # Transcript-less lines: 2026-05-01 goes, 2026-08-15 stays.
  printf '%s\n' \
    "{\"sessionId\":\"$o\",\"timestamp\":1780272000000}" \
    "{\"sessionId\":\"$n\",\"timestamp\":1785542400000}" \
    '{"sessionId":"c3333333-3333-3333-3333-333333333333","timestamp":1777593600000}' \
    '{"sessionId":"c4444444-4444-4444-4444-444444444444","timestamp":1786752000000}' \
    >"$home/.claude/history.jsonl"
  printf '%s\n' \
    "{\"sessionId\":\"$n\",\"timestamp\":1785542400000}" \
    '{"sessionId":"c4444444-4444-4444-4444-444444444444","timestamp":1786752000000}' \
    >"$TEST_TMP/filter-date/expected"

  run_interactive "$home" "$output" $'y\n' --ended-before 2026-07-01

  assert_absent "$old"
  assert_exists "$new"
  assert_same "$TEST_TMP/filter-date/expected" "$home/.claude/history.jsonl"
  assert_contains "$output" '1 history/index line whose chat is already gone'
  pass '--ended-before takes old chats and old orphaned history lines only'
}

test_filter_path_takes_the_tree_not_its_siblings() {
  local home output a sub ab ca cab
  home="$(new_home filter-path)"
  output="$TEST_TMP/filter-path/output"
  a="$(write_claude_chat_in "$home" d1111111-1111-1111-1111-111111111111 /work/a 2026-08-01T00:00:00Z)"
  sub="$(write_claude_chat_in "$home" d2222222-2222-2222-2222-222222222222 /work/a/sub 2026-08-01T00:00:00Z)"
  ab="$(write_claude_chat_in "$home" d3333333-3333-3333-3333-333333333333 /work/ab 2026-08-01T00:00:00Z)"
  ca="$(write_codex_chat_in "$home" d4444444-4444-4444-4444-444444444444 /work/a 2026-08-01T00:00:00Z)"
  cab="$(write_codex_chat_in "$home" d5555555-5555-5555-5555-555555555555 /work/ab 2026-08-01T00:00:00Z)"
  mkdir -p -- "$home/.claude/projects/-work-a/memory" "$home/.claude/projects/-work-ab/memory" \
              "$home/.claude/projects/-work-a-old/memory" "$home/.codex/memories"
  printf 'note\n' >"$home/.claude/projects/-work-a/memory/note.md"
  printf 'note\n' >"$home/.claude/projects/-work-ab/memory/note.md"
  # No transcript left: only history says -work-a-old is /work/a/old.
  printf 'note\n' >"$home/.claude/projects/-work-a-old/memory/note.md"
  printf '%s\n' '{"sessionId":"d6666666-6666-6666-6666-666666666666","project":"/work/a/old"}' \
    >"$home/.claude/history.jsonl"
  printf 'shared\n' >"$home/.codex/memories/m.md"

  # Claude chats: yes; Claude memory: yes; Codex chats: yes.
  run_interactive "$home" "$output" $'y\ny\ny\n' --path /work/a

  assert_absent "$a"
  assert_absent "$sub"
  assert_exists "$ab"
  assert_absent "$home/.claude/projects/-work-a"
  assert_absent "$home/.claude/projects/-work-a-old"
  assert_exists "$home/.claude/projects/-work-ab/memory/note.md"
  assert_absent "$ca"
  assert_exists "$cab"
  assert_exists "$home/.codex/memories/m.md"
  assert_contains "$output" 'Shared by every project, so --path never selects it.'
  pass '--path takes the directory tree and its memory, never a same-prefix sibling'
}

test_filter_decline_keeps_everything() {
  local home output claude codex
  home="$(new_home filter-decline)"
  output="$TEST_TMP/filter-decline/output"
  claude="$(write_claude_chat_in "$home" e1111111-1111-1111-1111-111111111111 /work/p 2026-08-01T00:00:00Z)"
  codex="$(write_codex_chat_in "$home" e2222222-2222-2222-2222-222222222222 /work/p 2026-08-01T00:00:00Z)"

  run_interactive "$home" "$output" $'n\nn\n' --smaller-than 1G

  assert_exists "$claude"
  assert_exists "$codex"
  assert_contains "$output" 'Kept them.'
  pass 'declining a filtered section keeps every match'
}

test_filter_codex_memory_store_by_date() {
  local home output
  home="$(new_home filter-codex-memory)"
  output="$TEST_TMP/filter-codex-memory/output"
  mkdir -p -- "$home/.codex/memories"
  printf 'memory\n' >"$home/.codex/memories/m.md"
  : >"$home/.codex/memories_1.sqlite"
  : >"$home/.codex/memories_1.sqlite-wal"
  : >"$home/.codex/goals_1.sqlite"
  printf 'protected\n' >"$home/.codex/config.toml"

  run_interactive "$home" "$output" $'y\n' --ended-before 2999-01-01

  assert_absent "$home/.codex/memories"
  assert_absent "$home/.codex/memories_1.sqlite"
  assert_absent "$home/.codex/memories_1.sqlite-wal"
  assert_absent "$home/.codex/goals_1.sqlite"
  assert_exists "$home/.codex/config.toml"
  assert_contains "$output" 'No Codex chats match the filters.'
  pass 'a filter selects the Codex memory store as one unit, sidecars included'
}

test_filters_combine_as_and() {
  local home output small_old small_new big_old
  home="$(new_home filter-and)"
  output="$TEST_TMP/filter-and/output"
  small_old="$(write_claude_chat_in "$home" f1111111-1111-1111-1111-111111111111 /work/p 2026-06-01T00:00:00Z)"
  small_new="$(write_claude_chat_in "$home" f2222222-2222-2222-2222-222222222222 /work/p 2026-08-01T00:00:00Z)"
  big_old="$(write_claude_chat_in "$home" f3333333-3333-3333-3333-333333333333 /work/p 2026-06-01T00:00:00Z 4096)"

  run_interactive "$home" "$output" $'y\n' --smaller-than 2K --ended-before=2026-07-01

  assert_absent "$small_old"
  assert_exists "$small_new"
  assert_exists "$big_old"
  pass 'filters combine: only chats matching every filter go'
}

test_filter_rejects_bad_values() {
  local home output chat args status
  home="$(new_home filter-bad)"
  output="$TEST_TMP/filter-bad/output"
  chat="$(write_claude_chat_in "$home" 99999999-0000-0000-0000-000000000000 /work/p 2026-08-01T00:00:00Z)"

  for args in '--smaller-than lots' '--smaller-than 0' '--ended-before 2026-13-45' '--path=' \
              '--path /a --path /b' '--path /a --include-projects' '--smaller-than'; do
    status=0
    # shellcheck disable=SC2086  # split on purpose
    HOME="$home" bash "$CLEANUP" --apply $args >"$output" 2>&1 </dev/null || status=$?
    (( status == 2 )) || fail "expected exit 2 for: $args (got $status)"
  done
  assert_exists "$chat"
  pass 'bad filter values exit 2 before touching anything'
}

test_dry_run_preserves_everything
test_codex_keep_prunes_history
test_codex_delete_removes_chat_state
test_claude_keep_prunes_history
test_claude_delete_removes_chat_state
test_claude_hooks_survive_apply
test_kept_chat_keeps_its_session_state
test_memory_index_survives_the_sweep
test_memory_erase_takes_the_index
test_codex_session_index_follows_chats
test_codex_removes_every_db_generation
test_project_local_agents_need_the_flag
test_include_projects_prompts_per_path
test_absent_codex_databases_are_a_noop
test_filter_dry_run_lists_only_matches
test_filter_apply_takes_matching_chats_with_their_state
test_filter_ended_before_takes_old_orphan_history
test_filter_path_takes_the_tree_not_its_siblings
test_filter_decline_keeps_everything
test_filter_codex_memory_store_by_date
test_filters_combine_as_and
test_filter_rejects_bad_values

printf 'PASS: cleanup-agents safety fixtures (%d cases)\n' "$pass_count"

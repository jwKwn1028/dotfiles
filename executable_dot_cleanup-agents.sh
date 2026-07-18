#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="${HOME:?}"
CODEX_DIR="$HOME_DIR/.codex"
CLAUDE_DIR="$HOME_DIR/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"

DRY_RUN=1

# Claude transcript path -> "keep" | "delete".
declare -A CHAT_DECISION=()
# Codex thread id -> "keep" | "delete"; same idea for Codex session transcripts.
declare -A CODEX_CHAT_DECISION=()

usage() {
  cat <<'USAGE'
Usage:
  ./.cleanup-agents.sh          Show what would be removed
  ./.cleanup-agents.sh --apply  Actually remove the files/directories

This preserves:
  ~/.codex/auth.json
  ~/.codex/config.toml
  ~/.codex/statusline.toml
  ~/.codex/rules/
  ~/.codex/skills/
  ~/.codex/plugins/
  ~/.claude/.credentials.json
  ~/.claude/settings.json
  ~/.claude/settings.local.json
  ~/.claude/statusline-command.sh
  ~/.claude/CLAUDE.md
  ~/.claude/agents/
  ~/.claude/commands/
  ~/.claude/skills/
  ~/.claude/plugins/
  ~/.claude/backups/
  ~/.claude.json

Claude and Codex chat/memory get the same careful workflow: every transcript is
previewed and, with --apply, offered for deletion individually (default "no").
Each tool's complete memory store is then previewed and only erased after a
separate confirmation (also default "no").

Claude chats are ~/.claude/projects/**/*.jsonl and Claude memory is everything
under ~/.claude/projects/*/memory/. Codex chats are
~/.codex/sessions/**/*.jsonl. Codex's chat index/logs (history.jsonl and
state_*/logs_* DBs) follow the chat choices, while Codex memory includes
~/.codex/memories/, generated summaries in memories_*.sqlite, and goals in
goals_*.sqlite.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --apply)
      DRY_RUN=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

is_protected() {
  local path="$1"

  case "$path" in
    "$CODEX_DIR"|"$CLAUDE_DIR"|"$HOME_DIR/.claude.json")
      return 0
      ;;
    "$CODEX_DIR/auth.json"|"$CODEX_DIR/config.toml"|"$CODEX_DIR/statusline.toml")
      return 0
      ;;
    "$CODEX_DIR/rules"|"$CODEX_DIR/rules/"*)
      return 0
      ;;
    "$CODEX_DIR/skills"|"$CODEX_DIR/skills/"*)
      return 0
      ;;
    "$CODEX_DIR/plugins"|"$CODEX_DIR/plugins/"*)
      return 0
      ;;
    "$CLAUDE_DIR/.credentials.json"|"$CLAUDE_DIR/settings.json"|"$CLAUDE_DIR/settings.local.json"|"$CLAUDE_DIR/statusline-command.sh"|"$CLAUDE_DIR/CLAUDE.md")
      return 0
      ;;
    "$CLAUDE_DIR/backups"|"$CLAUDE_DIR/backups/"*)
      return 0
      ;;
    "$CLAUDE_DIR/agents"|"$CLAUDE_DIR/agents/"*)
      return 0
      ;;
    "$CLAUDE_DIR/commands"|"$CLAUDE_DIR/commands/"*)
      return 0
      ;;
    "$CLAUDE_DIR/skills"|"$CLAUDE_DIR/skills/"*)
      return 0
      ;;
    "$CLAUDE_DIR/plugins"|"$CLAUDE_DIR/plugins/"*)
      return 0
      ;;
  esac

  return 1
}

# Classify a top-level ~/.codex child as belonging to the interactively handled
# "chat" or "memory" bucket, or "" for everything else. Buckets are owned by the
# Codex functions below, so clean_directory_contents leaves them alone. Matching
# is by prefix so a schema-version bump (state_5 -> state_6, ...) still lands in
# the right bucket.
codex_bucket() {
  case "$(basename "$1")" in
    sessions|history.jsonl)
      printf 'chat' ;;
    state_*.sqlite|state_*.sqlite-*|logs_*.sqlite|logs_*.sqlite-*)
      printf 'chat' ;;
    memories)
      printf 'memory' ;;
    memories_*.sqlite|memories_*.sqlite-*|goals_*.sqlite|goals_*.sqlite-*)
      printf 'memory' ;;
    *)
      printf '' ;;
  esac
}

remove_path() {
  local path="$1"

  [[ -e "$path" || -L "$path" ]] || return 0

  if is_protected "$path"; then
    printf 'Keep: %s\n' "$path"
    return 0
  fi

  if (( DRY_RUN )); then
    printf 'Would remove: %s\n' "$path"
  else
    rm -rf -- "$path"
    printf 'Removed: %s\n' "$path"
  fi
}

clean_directory_contents() {
  local dir="$1"

  [[ -d "$dir" ]] || return 0

  while IFS= read -r -d '' child; do
    # The Claude chat/memory functions own the projects tree and chat history.
    [[ "$child" == "$PROJECTS_DIR" ]] && continue
    [[ "$dir" == "$CLAUDE_DIR" && "$child" == "$CLAUDE_DIR/history.jsonl" ]] && continue
    # The Codex chat/memory buckets are owned by the Codex functions below.
    if [[ "$dir" == "$CODEX_DIR" && -n "$(codex_bucket "$child")" ]]; then
      continue
    fi
    remove_path "$child"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0)
}

clean_other_marker_paths() {
  local child

  while IFS= read -r -d '' child; do
    case "$child" in
      "$CODEX_DIR"|"$CLAUDE_DIR")
        continue
        ;;
    esac

    while IFS= read -r -d '' path; do
      remove_path "$path"
    done < <(find "$child" \( -name '.codex*' -o -name '.claude*' \) -print0)
  done < <(find "$HOME_DIR" -mindepth 1 -maxdepth 1 -print0)
}

# ---- Interactive chat + memory handling (Claude) ----------------------------
# clean_directory_contents skips "$PROJECTS_DIR", so these functions are the
# sole authority over it. As on the Codex side, every transcript is previewed
# and offered for deletion, and the complete memory store gets its own preview
# and confirmation.

# Print "name<TAB>description<TAB>type<TAB>originSessionId" for a memory file,
# always four tab-separated fields even when the frontmatter lacks some keys.
read_memory_meta() {
  local out
  out="$(python3 - "$1" 2>/dev/null <<'PY'
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except OSError:
    print("\t\t\t"); raise SystemExit
m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.S)
fm = m.group(1) if m else ""
def grab(key):
    mm = re.search(r"(?m)^\s*%s:\s*(.+?)\s*$" % re.escape(key), fm)
    v = mm.group(1).strip() if mm else ""
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1]
    return v
print("\t".join((grab("name"), grab("description"), grab("type"), grab("originSessionId"))))
PY
)" || out=""
  [[ -n "$out" ]] || out=$'\t\t\t'
  printf '%s\n' "$out"
}

# Print a short, human-readable summary ("slight verbose") of a chat transcript.
chat_preview() {
  if ! python3 - "$1" 2>/dev/null <<'PY'
import datetime, json, os, sys
path = sys.argv[1]
title = ""
first_user = None
users = asst = 0
ts_first = ts_last = None

def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                return block.get("text", "")
    return ""

with open(path, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        ts = rec.get("timestamp")
        if ts:
            ts_first = ts_first or ts
            ts_last = ts
        kind = rec.get("type")
        if kind == "ai-title" and rec.get("aiTitle"):
            title = rec["aiTitle"]
        elif kind == "user":
            users += 1
            if first_user is None:
                body = text_of(rec.get("message", {}).get("content"))
                if body and not body.lstrip().startswith("<"):
                    first_user = body
        elif kind == "assistant":
            asst += 1

def when(ts):
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts or "?"

def span():
    try:
        a = datetime.datetime.fromisoformat(ts_first.replace("Z", "+00:00"))
        b = datetime.datetime.fromisoformat(ts_last.replace("Z", "+00:00"))
        secs = int((b - a).total_seconds())
    except Exception:
        return "?"
    if secs < 60:
        return "%ds" % secs
    if secs < 3600:
        return "%dm" % (secs // 60)
    return "%dh%dm" % (secs // 3600, (secs % 3600) // 60)

def human(n):
    size = float(n)
    for unit in ("B", "K", "M", "G"):
        if size < 1024:
            return ("%d%s" % (size, unit)) if unit == "B" else ("%.1f%s" % (size, unit))
        size /= 1024
    return "%.1fT" % size

print("    Title:    %s" % (title or "(untitled)"))
if ts_first:
    print("    When:     %s → %s  (~%s)" % (when(ts_first), when(ts_last), span()))
print("    Messages: %d from you / %d from Claude" % (users, asst))
if first_user:
    opened = " ".join(first_user.split())
    if len(opened) > 100:
        opened = opened[:99] + "…"
    print("    Opened:   “%s”" % opened)
print("    Size:     %s" % human(os.path.getsize(path)))
PY
  then
    printf '    (transcript preview unavailable)\n'
  fi
}

# Preview a Claude transcript and record whether to delete it.
decide_chat() {
  local sid="$1" jsonl="$2" reply=""

  if (( DRY_RUN )); then
    printf '\nWould review chat transcript (%s):\n' "${sid:0:8}"
  else
    printf '\nReviewing chat transcript (%s):\n' "${sid:0:8}"
  fi
  chat_preview "$jsonl"

  if (( DRY_RUN )); then
    printf '    -> --apply would ask whether to delete this chat (kept in dry run).\n'
    CHAT_DECISION["$jsonl"]="keep"
    return 0
  fi

  if [[ -r /dev/tty ]]; then
    printf '    Delete this chat transcript? [y/N] '
    read -r reply < /dev/tty || reply=""
  else
    printf '    (no terminal available; keeping chat by default)\n'
  fi

  case "$reply" in
    y|Y|yes|YES|Yes)
      rm -f -- "$jsonl"
      CHAT_DECISION["$jsonl"]="delete"
      printf '    Deleted chat transcript: %s\n' "$jsonl"
      ;;
    *)
      CHAT_DECISION["$jsonl"]="keep"
      printf '    Kept chat transcript: %s\n' "$jsonl"
      ;;
  esac
}

# Preview every Claude transcript and decide each one.
process_claude_chats() {
  local found=0 jsonl sid

  while IFS= read -r -d '' jsonl; do
    found=1
    sid="$(basename "$jsonl" .jsonl)"
    decide_chat "$sid" "$jsonl"
  done < <(find "$PROJECTS_DIR" -type f -name '*.jsonl' -print0 2>/dev/null | sort -z)

  (( found )) || printf 'No Claude chat transcripts found.\n'
}

# Reconcile Claude's history index with the per-chat decisions, matching the
# Codex history behavior: prune it when chats remain, or offer to remove it
# after every chat has been deleted.
finalize_claude_chat_side() {
  local any_kept=0 jsonl sid reply=""
  local kept=()

  if (( ${#CHAT_DECISION[@]} )); then
    for jsonl in "${!CHAT_DECISION[@]}"; do
      if [[ "${CHAT_DECISION[$jsonl]}" == "keep" ]]; then
        any_kept=1
        sid="$(basename "$jsonl" .jsonl)"
        kept+=("$sid")
      fi
    done
  fi

  local hist="$CLAUDE_DIR/history.jsonl"
  if (( any_kept )); then
    [[ -f "$hist" ]] || return 0
    if (( DRY_RUN )); then
      printf '\nWould prune Claude history.jsonl to the kept chats.\n'
      return 0
    fi

    local n
    n="$(python3 - "$hist" "${kept[@]}" <<'PY'
import json, os, sys
path = sys.argv[1]
kept = set(sys.argv[2:])
out = []
try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            s = line.strip()
            if not s:
                continue
            try:
                rec = json.loads(s)
            except ValueError:
                continue
            if rec.get("sessionId") in kept:
                out.append(s)
except OSError:
    print(0)
    raise SystemExit
if out:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
else:
    try:
        os.remove(path)
    except OSError:
        pass
print(len(out))
PY
)" || n="?"
    printf '\nPruned Claude history.jsonl to %s kept entr%s.\n' \
      "$n" "$([[ "$n" == 1 ]] && printf y || printf ies)"
    return 0
  fi

  [[ -f "$hist" ]] || return 0
  if (( DRY_RUN )); then
    printf '\nNo Claude chats kept; --apply would ask to remove the orphaned chat history:\n'
    printf '  %s\n' "${hist##*/}"
    printf '  -> kept in dry run.\n'
    return 0
  fi

  printf '\nNo Claude chats kept. Orphaned chat history remains:\n'
  printf '  %s\n' "${hist##*/}"
  if [[ -r /dev/tty ]]; then
    printf '  Remove this orphaned chat history? [y/N] '
    read -r reply < /dev/tty || reply=""
  else
    printf '  (no terminal available; keeping chat history by default)\n'
  fi

  case "$reply" in
    y|Y|yes|YES|Yes)
      rm -f -- "$hist"
      printf '  Removed: %s\n' "$hist"
      ;;
    *)
      printf '  Kept orphaned chat history.\n'
      ;;
  esac
}

# Remove project files that are neither chat transcripts nor memory. The chat
# and memory passes above own their respective stores.
sweep_claude_projects_remainder() {
  [[ -d "$PROJECTS_DIR" ]] || return 0

  local path
  while IFS= read -r -d '' path; do
    if (( DRY_RUN )); then
      printf 'Would remove project-state file: %s\n' "$path"
    else
      rm -f -- "$path"
      printf 'Removed project-state file: %s\n' "$path"
    fi
  done < <(find "$PROJECTS_DIR" -type f ! -name '*.jsonl' ! -path '*/memory/*' -print0 2>/dev/null)

  if (( ! DRY_RUN )); then
    # Prune now-empty project directories bottom-up. Kept chats or memory keep
    # their containing directories in place.
    find "$PROJECTS_DIR" -depth -type d -empty -delete 2>/dev/null || true
  fi
}

# Preview the complete Claude memory store and, with --apply, erase it only
# after a separate yes.
process_claude_memory() {
  if [[ ! -d "$PROJECTS_DIR" ]]; then
    printf 'No Claude memory stored (nothing to erase).\n'
    return 0
  fi

  local memdirs=0 pfiles=0 memfile name desc typ origin reply="" memdir
  memdirs="$(find "$PROJECTS_DIR" -type d -name memory -prune -print 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$memdirs" -eq 0 ]]; then
    printf 'No Claude memory stored (nothing to erase).\n'
    return 0
  fi

  pfiles="$(find "$PROJECTS_DIR" -type f -path '*/memory/*' 2>/dev/null | wc -l | tr -d ' ')"
  printf 'Claude memory store:\n'
  printf '  Persistent store: %s file%s under ~/.claude/projects/*/memory/\n' \
    "$pfiles" "$([[ "$pfiles" == 1 ]] && printf '' || printf s)"

  if [[ "$pfiles" -gt 0 ]]; then
    printf '  Sample memories:\n'
    local shown=0
    while IFS= read -r -d '' memfile; do
      IFS=$'\t' read -r name desc typ origin < <(read_memory_meta "$memfile")
      printf '    - %s' "${name:-$(basename "$memfile")}"
      [[ -n "$typ" ]] && printf ' (%s)' "$typ"
      [[ -n "$desc" ]] && printf ': %s' "${desc:0:90}"
      [[ -n "$origin" ]] && printf ' [chat %s]' "${origin:0:8}"
      printf '\n'
      (( ++shown >= 5 )) && break
    done < <(find "$PROJECTS_DIR" -type f -path '*/memory/*' -print0 2>/dev/null | sort -z)
  else
    printf '  (memory is empty; only store directories are present)\n'
  fi

  if (( DRY_RUN )); then
    printf '  -> --apply would ask whether to erase the Claude memory store (kept in dry run).\n'
    return 0
  fi

  if [[ -r /dev/tty ]]; then
    printf '  Erase the Claude memory store above? [y/N] '
    read -r reply < /dev/tty || reply=""
  else
    printf '  (no terminal available; keeping memory by default)\n'
  fi

  case "$reply" in
    y|Y|yes|YES|Yes)
      while IFS= read -r -d '' memdir; do
        rm -rf -- "$memdir"
        printf '  Removed: %s\n' "$memdir"
      done < <(find "$PROJECTS_DIR" -type d -name memory -prune -print0 2>/dev/null)
      ;;
    *)
      printf '  Kept the Claude memory store.\n'
      ;;
  esac
}

# ---- Interactive chat + memory handling (Codex) -----------------------------
# clean_directory_contents skips the Codex chat/memory buckets (see
# codex_bucket), so these functions are the sole authority over them. They give
# Codex the same courtesy as Claude: every session transcript is previewed and
# offered for deletion (default keep), the chat index/logs follow those choices,
# and the memory store is previewed and only erased after an explicit yes.

# True when a string is a plausible session/thread id (safe to splice into SQL).
codex_id_safe() {
  [[ "$1" =~ ^[0-9a-fA-F-]+$ ]]
}

# Echo the session id for a rollout transcript (from session_meta, else the
# UUID in the filename), or nothing.
codex_session_id() {
  python3 - "$1" 2>/dev/null <<'PY' || true
import json, os, re, sys
path = sys.argv[1]
sid = ""
try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("type") == "session_meta":
                sid = (rec.get("payload", {}) or {}).get("session_id") or ""
                break
except OSError:
    pass
if not sid:
    m = re.search(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", os.path.basename(path))
    sid = m.group(0) if m else ""
print(sid)
PY
}

# Print a short, human-readable summary of a Codex rollout transcript.
codex_chat_preview() {
  if ! python3 - "$1" 2>/dev/null <<'PY'
import datetime, json, os, sys
path = sys.argv[1]
first_user = None
users = asst = 0
ts_first = ts_last = None
cwd = ""

with open(path, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        ts = rec.get("timestamp")
        if ts:
            ts_first = ts_first or ts
            ts_last = ts
        kind = rec.get("type")
        payload = rec.get("payload", {}) or {}
        if kind == "session_meta":
            cwd = payload.get("cwd", "") or cwd
        elif kind == "event_msg":
            ptype = payload.get("type")
            if ptype == "user_message":
                users += 1
                msg = payload.get("message") or ""
                if first_user is None and msg.strip() and not msg.lstrip().startswith(("<", "#")):
                    first_user = msg
            elif ptype == "agent_message":
                asst += 1

def when(ts):
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts or "?"

def span():
    try:
        a = datetime.datetime.fromisoformat(ts_first.replace("Z", "+00:00"))
        b = datetime.datetime.fromisoformat(ts_last.replace("Z", "+00:00"))
        secs = int((b - a).total_seconds())
    except Exception:
        return "?"
    if secs < 60:
        return "%ds" % secs
    if secs < 3600:
        return "%dm" % (secs // 60)
    return "%dh%dm" % (secs // 3600, (secs % 3600) // 60)

def human(n):
    size = float(n)
    for unit in ("B", "K", "M", "G"):
        if size < 1024:
            return ("%d%s" % (size, unit)) if unit == "B" else ("%.1f%s" % (size, unit))
        size /= 1024
    return "%.1fT" % size

opened = ""
if first_user:
    opened = " ".join(first_user.split())
    if len(opened) > 100:
        opened = opened[:99] + "…"
print("    Title:    %s" % (opened or "(untitled)"))
if ts_first:
    print("    When:     %s → %s  (~%s)" % (when(ts_first), when(ts_last), span()))
print("    Messages: %d from you / %d from Codex" % (users, asst))
if cwd:
    print("    Where:    %s" % cwd)
if opened:
    print("    Opened:   “%s”" % opened)
print("    Size:     %s" % human(os.path.getsize(path)))
PY
  then
    printf '    (transcript preview unavailable)\n'
  fi
}

# Echo the base path of the first Codex bucket DB matching a prefix (e.g.
# "memories_", "state_"), skipping -shm/-wal sidecars; nothing if none exist.
codex_db_for() {
  local prefix="$1" f
  for f in "$CODEX_DIR/$prefix"*.sqlite; do
    [[ -f "$f" ]] || continue
    printf '%s' "$f"
    return 0
  done
}

# Remove a sqlite DB together with its -wal/-shm/-journal sidecars.
codex_remove_db() {
  local base="$1" f
  for f in "$base" "$base"-wal "$base"-shm "$base"-journal; do
    [[ -e "$f" ]] || continue
    if (( DRY_RUN )); then
      printf 'Would remove: %s\n' "$f"
    else
      rm -f -- "$f"
      printf 'Removed: %s\n' "$f"
    fi
  done
}

# Print the memory summary Codex derived from a thread, if any (read-only).
codex_linked_memory_line() {
  local sid="$1" db summary
  command -v sqlite3 >/dev/null 2>&1 || return 0
  codex_id_safe "$sid" || return 0
  db="$(codex_db_for memories_)"
  [[ -n "$db" ]] || return 0
  summary="$(sqlite3 "$db" "SELECT COALESCE(rollout_summary, raw_memory) FROM stage1_outputs WHERE thread_id='$sid' LIMIT 1;" 2>/dev/null | tr '\n' ' ')" || return 0
  summary="$(printf '%s' "$summary" | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//')"
  [[ -n "$summary" ]] || return 0
  printf '    Memory:   Codex derived a summary from this chat — “%s%s”\n' \
    "${summary:0:100}" "$([[ ${#summary} -gt 100 ]] && printf '…')"
}

# Preview a Codex session transcript and record whether to delete it.
decide_codex_chat() {
  local sid="$1" jsonl="$2" reply=""

  if (( DRY_RUN )); then
    printf '\nWould review chat transcript (%s):\n' "${sid:0:8}"
  else
    printf '\nReviewing chat transcript (%s):\n' "${sid:0:8}"
  fi
  codex_chat_preview "$jsonl"
  codex_linked_memory_line "$sid"

  if (( DRY_RUN )); then
    printf '    -> --apply would ask whether to delete this chat (kept in dry run).\n'
    CODEX_CHAT_DECISION[$sid]="keep"
    return 0
  fi

  if [[ -r /dev/tty ]]; then
    printf '    Delete this chat transcript? [y/N] '
    read -r reply < /dev/tty || reply=""
  else
    printf '    (no terminal available; keeping chat by default)\n'
  fi

  case "$reply" in
    y|Y|yes|YES|Yes)
      rm -f -- "$jsonl"
      CODEX_CHAT_DECISION[$sid]="delete"
      printf '    Deleted chat transcript: %s\n' "$jsonl"
      ;;
    *)
      CODEX_CHAT_DECISION[$sid]="keep"
      printf '    Kept chat transcript: %s\n' "$jsonl"
      ;;
  esac
}

# Preview every Codex session transcript and decide each one.
process_codex_chats() {
  local sessions="$CODEX_DIR/sessions" found=0 jsonl sid

  if [[ -d "$sessions" ]]; then
    while IFS= read -r -d '' jsonl; do
      found=1
      sid="$(codex_session_id "$jsonl")"
      [[ -n "$sid" ]] || sid="$(basename "$jsonl" .jsonl)"
      decide_codex_chat "$sid" "$jsonl"
    done < <(find "$sessions" -type f -name '*.jsonl' -print0 2>/dev/null | sort -z)

    if (( ! DRY_RUN )); then
      find "$sessions" -depth -mindepth 1 -type d -empty -delete 2>/dev/null || true
      rmdir "$sessions" 2>/dev/null || true
    fi
  fi

  (( found )) || printf 'No Codex chat transcripts found.\n'
}

# Reconcile the chat index/logs (history.jsonl, state_*/logs_* DBs) with the
# per-chat decisions: keep them while any chat is kept (pruning history to the
# kept ids), otherwise offer to remove the now-orphaned chat state.
finalize_codex_chat_side() {
  local any_kept=0 sid
  local kept=()
  if (( ${#CODEX_CHAT_DECISION[@]} )); then
    for sid in "${!CODEX_CHAT_DECISION[@]}"; do
      if [[ "${CODEX_CHAT_DECISION[$sid]}" == "keep" ]]; then
        any_kept=1
        kept+=("$sid")
      fi
    done
  fi

  local hist="$CODEX_DIR/history.jsonl"
  local -a chat_dbs=()
  local db
  db="$(codex_db_for state_)" && [[ -n "$db" ]] && chat_dbs+=("$db")
  db="$(codex_db_for logs_)" && [[ -n "$db" ]] && chat_dbs+=("$db")

  if (( any_kept )); then
    if [[ -f "$hist" ]]; then
      if (( DRY_RUN )); then
        printf '\nWould prune history.jsonl to the kept chats.\n'
      else
        local n
        n="$(python3 - "$hist" "${kept[@]}" <<'PY'
import json, os, sys
path = sys.argv[1]
kept = set(sys.argv[2:])
out = []
try:
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            s = line.strip()
            if not s:
                continue
            try:
                rec = json.loads(s)
            except ValueError:
                continue
            if rec.get("session_id") in kept:
                out.append(s)
except OSError:
    print(0)
    raise SystemExit
if out:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
else:
    try:
        os.remove(path)
    except OSError:
        pass
print(len(out))
PY
)" || n="?"
        printf '\nPruned history.jsonl to %s kept entr%s.\n' "$n" "$([[ "$n" == 1 ]] && printf y || printf ies)"
      fi
    fi
    if (( ${#chat_dbs[@]} )); then
      printf 'Kept chat index/logs (still referenced by kept chats): %s\n' "${chat_dbs[*]##*/}"
    fi
    return 0
  fi

  # No chats kept: history.jsonl + the index/log DBs are now orphaned state.
  local -a orphans=()
  [[ -f "$hist" ]] && orphans+=("$hist")
  local base
  for base in "${chat_dbs[@]:-}"; do
    [[ -n "$base" ]] && orphans+=("$base")
  done
  (( ${#orphans[@]} )) || return 0

  local reply=""
  if (( DRY_RUN )); then
    printf '\nNo Codex chats kept; --apply would ask to remove the orphaned chat state:\n'
    printf '  %s\n' "${orphans[@]##*/}"
    printf '  -> kept in dry run.\n'
    return 0
  fi

  printf '\nNo Codex chats kept. Orphaned chat state remains:\n'
  printf '  %s\n' "${orphans[@]##*/}"
  if [[ -r /dev/tty ]]; then
    printf '  Remove this orphaned chat index/logs? [y/N] '
    read -r reply < /dev/tty || reply=""
  else
    printf '  (no terminal available; keeping chat state by default)\n'
  fi

  case "$reply" in
    y|Y|yes|YES|Yes)
      [[ -f "$hist" ]] && { rm -f -- "$hist"; printf '  Removed: %s\n' "$hist"; }
      for base in "${chat_dbs[@]:-}"; do
        [[ -n "$base" ]] && codex_remove_db "$base"
      done
      ;;
    *)
      printf '  Kept orphaned chat state.\n'
      ;;
  esac
}

# Preview the Codex memory store and, with --apply, only erase after a yes.
process_codex_memory() {
  [[ -d "$CODEX_DIR" ]] || return 0

  local memdir="$CODEX_DIR/memories"
  local pfiles=0 mrows=0 grows=0 mdb gdb
  mdb="$(codex_db_for memories_)" || mdb=""
  gdb="$(codex_db_for goals_)" || gdb=""

  if [[ -d "$memdir" ]]; then
    pfiles="$(find "$memdir" -type f -not -path '*/.git/*' 2>/dev/null | wc -l | tr -d ' ')"
  fi
  if command -v sqlite3 >/dev/null 2>&1; then
    [[ -n "$mdb" ]] && mrows="$(sqlite3 "$mdb" 'SELECT COUNT(*) FROM stage1_outputs;' 2>/dev/null || printf 0)"
    [[ -n "$gdb" ]] && grows="$(sqlite3 "$gdb" 'SELECT COUNT(*) FROM thread_goals;' 2>/dev/null || printf 0)"
  fi
  [[ "$mrows" =~ ^[0-9]+$ ]] || mrows=0
  [[ "$grows" =~ ^[0-9]+$ ]] || grows=0

  # Nothing that counts as memory exists at all.
  if [[ ! -d "$memdir" && -z "$mdb" && -z "$gdb" ]]; then
    printf 'No Codex memory stored (nothing to erase).\n'
    return 0
  fi

  printf 'Codex memory store:\n'
  printf '  Persistent store: %s file%s under ~/.codex/memories/\n' \
    "$pfiles" "$([[ "$pfiles" == 1 ]] && printf '' || printf s)"
  printf '  Generated summaries: %s\n' "$mrows"
  printf '  Recorded goals: %s\n' "$grows"

  if command -v sqlite3 >/dev/null 2>&1 && [[ -n "$mdb" && "$mrows" -gt 0 ]]; then
    printf '  Sample summaries:\n'
    sqlite3 -separator $'\t' "$mdb" \
      "SELECT substr(thread_id,1,8), substr(replace(replace(COALESCE(rollout_summary,raw_memory),char(10),' '),char(13),' '),1,90) FROM stage1_outputs LIMIT 5;" 2>/dev/null \
      | while IFS=$'\t' read -r tid summary; do
          printf '    - %s: %s…\n' "$tid" "$summary"
        done
  fi

  if [[ "$pfiles" -eq 0 && "$mrows" -eq 0 && "$grows" -eq 0 ]]; then
    printf '  (memory is empty; only regenerable store/db scaffolding is present)\n'
  fi

  local reply=""
  if (( DRY_RUN )); then
    printf '  -> --apply would ask whether to erase the Codex memory store (kept in dry run).\n'
    return 0
  fi

  if [[ -r /dev/tty ]]; then
    printf '  Erase the Codex memory store above? [y/N] '
    read -r reply < /dev/tty || reply=""
  else
    printf '  (no terminal available; keeping memory by default)\n'
  fi

  case "$reply" in
    y|Y|yes|YES|Yes)
      if [[ -d "$memdir" ]]; then
        rm -rf -- "$memdir"
        printf '  Removed: %s\n' "$memdir"
      fi
      [[ -n "$mdb" ]] && codex_remove_db "$mdb"
      [[ -n "$gdb" ]] && codex_remove_db "$gdb"
      ;;
    *)
      printf '  Kept the Codex memory store.\n'
      ;;
  esac
}

if (( DRY_RUN )); then
  printf 'Dry run. Re-run with --apply to delete.\n\n'
else
  printf 'Deleting Claude/Codex cleanup targets.\n\n'
fi

if [[ -d "$CLAUDE_DIR" ]]; then
  printf '== Claude chat transcripts ==\n'
  process_claude_chats
  finalize_claude_chat_side
  printf '\n== Claude memory ==\n'
  process_claude_memory
  sweep_claude_projects_remainder
  printf '\n'
fi

if [[ -d "$CODEX_DIR" ]]; then
  printf '== Codex chat transcripts ==\n'
  process_codex_chats
  finalize_codex_chat_side
  printf '\n== Codex memory ==\n'
  process_codex_memory
  printf '\n'
fi

clean_directory_contents "$CODEX_DIR"
clean_directory_contents "$CLAUDE_DIR"
clean_other_marker_paths

if (( DRY_RUN )); then
  printf '\nNo files were removed.\n'
else
  printf '\nCleanup complete.\n'
fi

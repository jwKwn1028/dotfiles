#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="${HOME:?}"
CODEX_DIR="$HOME_DIR/.codex"
CLAUDE_DIR="$HOME_DIR/.claude"
PROJECTS_DIR="$CLAUDE_DIR/projects"

DRY_RUN=1

# session id -> "keep" | "delete", so a chat linked by several memory files is
# previewed and decided only once.
declare -A CHAT_DECISION=()

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
  ~/.codex/memories/
  ~/.claude/.credentials.json
  ~/.claude/settings.json
  ~/.claude/settings.local.json
  ~/.claude/statusline-command.sh
  ~/.claude/CLAUDE.md
  ~/.claude/agents/
  ~/.claude/commands/
  ~/.claude/skills/
  ~/.claude/plugins/
  ~/.claude.json

When a memory file (.../projects/*/memory/*.md) is erased, its originating chat
transcript is previewed first. With --apply you are asked whether to delete that
chat too; the default answer is "no", which keeps the transcript. Chat
transcripts with no linked memory file are removed as before.
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
    "$CODEX_DIR/memories"|"$CODEX_DIR/memories/"*)
      return 0
      ;;
    "$CLAUDE_DIR/.credentials.json"|"$CLAUDE_DIR/settings.json"|"$CLAUDE_DIR/settings.local.json"|"$CLAUDE_DIR/statusline-command.sh"|"$CLAUDE_DIR/CLAUDE.md")
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
    # process_memory_files/sweep_projects_remainder own the projects tree.
    [[ "$child" == "$PROJECTS_DIR" ]] && continue
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

# ---- Interactive memory + linked-chat handling ------------------------------
# clean_directory_contents skips "$PROJECTS_DIR", so these two functions are the
# sole authority over it: every memory file is erased, its linked chat is
# previewed and (with --apply) offered for deletion, and any transcript with no
# memory file is removed as before.

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

# Echo the transcript path for a session id, or nothing if it cannot be found.
find_transcript() {
  local sid="$1" proj="$2" candidate
  candidate="$proj/$sid.jsonl"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  while IFS= read -r -d '' candidate; do
    printf '%s' "$candidate"
    return 0
  done < <(find "$PROJECTS_DIR" -maxdepth 2 -name "$sid.jsonl" -print0 2>/dev/null)
}

# Preview a linked chat and record (once per session) whether to delete it.
decide_chat() {
  local sid="$1" jsonl="$2" reply=""

  if [[ -n "${CHAT_DECISION[$sid]:-}" ]]; then
    printf '  Linked chat %s already handled (%s).\n' "${sid:0:8}" "${CHAT_DECISION[$sid]}"
    return 0
  fi

  printf '  Linked chat transcript (%s):\n' "${sid:0:8}"
  chat_preview "$jsonl"

  if (( DRY_RUN )); then
    printf '    -> --apply would ask whether to delete this chat (kept in dry run).\n'
    CHAT_DECISION[$sid]="keep"
    return 0
  fi

  if [[ -r /dev/tty ]]; then
    printf '    Delete this chat transcript too? [y/N] '
    read -r reply < /dev/tty || reply=""
  else
    printf '    (no terminal available; keeping chat by default)\n'
  fi

  case "$reply" in
    y|Y|yes|YES|Yes)
      rm -f -- "$jsonl"
      CHAT_DECISION[$sid]="delete"
      printf '    Deleted chat transcript: %s\n' "$jsonl"
      ;;
    *)
      CHAT_DECISION[$sid]="keep"
      printf '    Kept chat transcript: %s\n' "$jsonl"
      ;;
  esac
}

# Erase every memory file, previewing/prompting for each one's linked chat.
process_memory_files() {
  [[ -d "$PROJECTS_DIR" ]] || return 0

  local memfile proj name desc typ origin jsonl
  while IFS= read -r -d '' memfile; do
    proj="$(dirname "$(dirname "$memfile")")"
    IFS=$'\t' read -r name desc typ origin < <(read_memory_meta "$memfile")

    if (( DRY_RUN )); then
      printf '\nWould erase memory file: %s\n' "$memfile"
    else
      printf '\nErasing memory file: %s\n' "$memfile"
    fi
    [[ -n "$name" ]] && printf '  Name:  %s (%s)\n' "$name" "${typ:-memory}"
    [[ -n "$desc" ]] && printf '  About: %s\n' "$desc"

    if [[ -n "$origin" ]]; then
      jsonl="$(find_transcript "$origin" "$proj")"
      if [[ -n "$jsonl" ]]; then
        decide_chat "$origin" "$jsonl"
      else
        printf '  Linked chat %s: transcript not found (already gone).\n' "${origin:0:8}"
      fi
    else
      printf '  (no linked chat recorded)\n'
    fi

    (( DRY_RUN )) || rm -f -- "$memfile"
  done < <(find "$PROJECTS_DIR" -type f -path '*/memory/*.md' -print0 2>/dev/null | sort -z)
}

# Remove whatever is left under "$PROJECTS_DIR" except chats kept above.
sweep_projects_remainder() {
  [[ -d "$PROJECTS_DIR" ]] || return 0

  local path base label
  while IFS= read -r -d '' path; do
    label='file'
    if [[ "$path" == *.jsonl ]]; then
      base="$(basename "$path" .jsonl)"
      if [[ "${CHAT_DECISION[$base]:-}" == "keep" ]]; then
        printf 'Keeping linked chat: %s\n' "$path"
        continue
      fi
      label='chat (no linked memory)'
    fi
    if (( DRY_RUN )); then
      printf 'Would remove %s: %s\n' "$label" "$path"
    else
      rm -f -- "$path"
      printf 'Removed %s: %s\n' "$label" "$path"
    fi
  done < <(find "$PROJECTS_DIR" -type f -not -path '*/memory/*' -print0 2>/dev/null)

  if (( ! DRY_RUN )); then
    # Prune now-empty project directories bottom-up; this removes
    # "$PROJECTS_DIR" itself only when no chats were kept.
    find "$PROJECTS_DIR" -depth -type d -empty -delete 2>/dev/null || true
  fi
}

if (( DRY_RUN )); then
  printf 'Dry run. Re-run with --apply to delete.\n\n'
else
  printf 'Deleting Claude/Codex cleanup targets.\n\n'
fi

if [[ -d "$PROJECTS_DIR" ]]; then
  printf '== Memory files and linked chat history ==\n'
  process_memory_files
  sweep_projects_remainder
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

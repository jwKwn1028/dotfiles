#!/usr/bin/env bash
# Claude Code statusLine: mirrors the Starship [directory] segment plus a
# remaining-context indicator. Git info is intentionally omitted.
#
# Managed by the statusline-setup agent -- ask it to make changes rather than
# hand-editing.

input=$(cat)

CWD=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$CWD" ] && CWD="$PWD"
REMAINING=$(printf '%s' "$input" | jq -r '.context_window.remaining_percentage // empty')
MODEL=$(printf '%s' "$input" | jq -r '.model.display_name // empty')

# ---- Tokyo Night palette (matches [palettes.tokyo_night] in starship.toml) ----
BLUE=$(printf '\033[38;2;122;162;247m')
RED=$(printf '\033[38;2;247;118;142m')
YELLOW=$(printf '\033[38;2;224;175;104m')
GREEN=$(printf '\033[38;2;158;206;106m')
GRAY=$(printf '\033[38;2;86;95;137m')
RESET=$(printf '\033[0m')
BOLD=$(printf '\033[1m')

# ---------------------------------------------------------------------------
# [directory]  style = "bold blue", truncation_length = 3, truncation_symbol = "…/"
# ---------------------------------------------------------------------------
dir="$CWD"
case "$dir" in
  "$HOME") dir="~" ;;
  "$HOME"/*) dir="~${dir#"$HOME"}" ;;
esac

IFS='/' read -r -a parts <<< "$dir"
clean=()
for p in "${parts[@]}"; do
  [ -n "$p" ] && clean+=("$p")
done
n=${#clean[@]}
if [ "$n" -gt 3 ]; then
  start=$((n - 3))
  disp="…/"
  for ((i = start; i < n; i++)); do
    disp="${disp}${clean[$i]}"
    [ "$i" -lt $((n - 1)) ] && disp="${disp}/"
  done
else
  disp="$dir"
fi
DIR_SEGMENT="${BOLD}${BLUE}${disp}${RESET}"

# ---------------------------------------------------------------------------
# Remaining context (context_window.remaining_percentage), ramping green ->
# yellow -> red. Omitted until the session's first API response exists.
# ---------------------------------------------------------------------------
CONTEXT_SEGMENT=""
if [ -n "$REMAINING" ]; then
  remaining_int=$(printf '%.0f' "$REMAINING")
  if [ "$remaining_int" -ge 50 ]; then
    ctx_color="$GREEN"
  elif [ "$remaining_int" -ge 20 ]; then
    ctx_color="$YELLOW"
  else
    ctx_color="$RED"
  fi
  CONTEXT_SEGMENT=" ${GRAY}·${RESET} ${ctx_color}${remaining_int}% context left${RESET}"
fi

# ---------------------------------------------------------------------------
# Model name (model.display_name) — dimmed, Tokyo Night comment-gray, appended
# last, e.g. "(Claude Opus 4.5)".
# ---------------------------------------------------------------------------
MODEL_SEGMENT=""
[ -n "$MODEL" ] && MODEL_SEGMENT=" ${GRAY}(${MODEL})${RESET}"

printf '%s%s%s\n' "$DIR_SEGMENT" "$CONTEXT_SEGMENT" "$MODEL_SEGMENT"

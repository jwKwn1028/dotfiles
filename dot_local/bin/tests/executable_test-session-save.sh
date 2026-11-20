#!/usr/bin/env bash
# session-save runs the tmux and guarded i3 saves together, and both always run.
set -euo pipefail

SCRIPT="$(dirname "$(dirname "$(readlink -f "$0")")")/executable_session-save"
[ -r "$SCRIPT" ] || SCRIPT="$HOME/.local/bin/session-save"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
bin="$TEST_TMP/bin"
mkdir -p "$bin"
cat >"$bin/tmux-resurrect-autosave" <<'EOF'
#!/bin/bash
sleep 0.6; printf 'tmux\n' >>"$SAVE_LOG"; exit "${TMUX_STATUS:-0}"
EOF
cat >"$bin/i3-save" <<'EOF'
#!/bin/bash
sleep 0.6; printf 'i3 %s live=%s\n' "$*" "${ZEN_LIVE_URL_CAPTURE-}" >>"$SAVE_LOG"
EOF
printf '#!/bin/bash\nexit 0\n' >"$bin/notify-send"
chmod +x "$bin"/*

for tmux_status in 0 1; do
    : >"$TEST_TMP/log"
    start=$(date +%s%N)
    env PATH="$bin:/usr/bin:/bin" SAVE_LOG="$TEST_TMP/log" I3_RESURRECT_SAVE="$bin/i3-save" \
        TMUX_STATUS="$tmux_status" sh "$SCRIPT"
    elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
    [ "$(sort "$TEST_TMP/log")" = "$(printf 'i3 save --auto live=0\ntmux')" ] || {
        printf 'FAIL: expected both saves (tmux status %s), got:\n' "$tmux_status" >&2
        cat "$TEST_TMP/log" >&2
        exit 1
    }
    [ "$elapsed" -lt 1100 ] || { printf 'FAIL: saves ran one after the other (%s ms)\n' "$elapsed" >&2; exit 1; }
done

printf 'PASS: tmux and i3 saves run together\n'

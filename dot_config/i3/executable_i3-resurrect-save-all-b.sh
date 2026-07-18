#!/usr/bin/env bash
set -euo pipefail

export I3_RESURRECT_STATE_DIR="${I3_RESURRECT_STATE_DIR:-$HOME/.config/i3/resurrect-b}"
export I3_RESURRECT_META_DIR="${I3_RESURRECT_META_DIR:-$HOME/.config/i3/resurrect-meta-b}"

exec "$HOME/.config/i3/i3-resurrect-save-all.sh" "$@"

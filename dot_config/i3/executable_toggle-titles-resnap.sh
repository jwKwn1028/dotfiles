#!/usr/bin/env bash
# Toggle title bars, then re-fit snapped windows to the new border geometry.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

snap_log "toggle-titles-resnap"
"$DIR/toggle-titles.sh"
"$DIR/resnap.sh"

#!/usr/bin/env bash
set -eu
DIR="$(dirname "$(readlink -f "$0")")"
HELPER="$DIR/workspace-groups.py"
[ -r "$HELPER" ] || HELPER="$DIR/executable_workspace-groups.py"
exec /usr/bin/python3 "$HELPER" desktop

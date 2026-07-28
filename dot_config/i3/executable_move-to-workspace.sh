#!/usr/bin/env bash

set -u

workspace="${1:-}"

case "$workspace" in
    1|2|3|4|5|6|7|8|9|10)
        ;;
    *)
        exit 2
        ;;
esac

i3-msg "move container to workspace number $workspace; workspace number $workspace" >/dev/null

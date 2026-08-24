#!/usr/bin/env bash
# Confirm a poweroff or reboot. A timeout always cancels: walking away from a
# confirmation dialog must never turn a stray click into a delayed power action.

set -u

ACTION="${1:-poweroff}"
TIMEOUT_SECONDS="${2:-30}"

case "$ACTION" in
    poweroff)
        TITLE="Shut Down?"
        PROMPT="Shut down this machine?"
        CONFIRM_LABEL="Shut Down"
        ;;
    reboot)
        TITLE="Restart?"
        PROMPT="Restart this machine?"
        CONFIRM_LABEL="Restart"
        ;;
    *)
        printf 'usage: %s [poweroff|reboot] [timeout-seconds]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

case "$TIMEOUT_SECONDS" in
    ''|*[!0-9]*|0)
        printf 'timeout must be a positive integer\n' >&2
        exit 2
        ;;
esac

MESSAGE="$PROMPT

If you do nothing, this prompt will close in ${TIMEOUT_SECONDS} seconds and the action will be cancelled."

perform_action() {
    systemctl "$ACTION"
}

prompt_with_zenity() {
    zenity --question \
        --title="$TITLE" \
        --text="$MESSAGE" \
        --ok-label="$CONFIRM_LABEL" \
        --cancel-label="Cancel" \
        --timeout="$TIMEOUT_SECONDS" \
        --no-wrap

    [ "$?" -eq 0 ] && perform_action
    return 0
}

prompt_with_rofi() {
    choice="$(
        printf '%s\nCancel\n' "$CONFIRM_LABEL" |
            timeout "$TIMEOUT_SECONDS" rofi -dmenu -i -p "$TITLE"
    )"
    status="$?"

    if [ "$status" -eq 0 ] && [ "$choice" = "$CONFIRM_LABEL" ]; then
        perform_action
    fi
    return 0
}

prompt_with_xmessage() {
    timeout "$TIMEOUT_SECONDS" xmessage \
        -center \
        -buttons "$CONFIRM_LABEL:0,Cancel:1" \
        -default "Cancel" \
        "$MESSAGE"

    [ "$?" -eq 0 ] && perform_action
    return 0
}

if command -v zenity >/dev/null 2>&1; then
    prompt_with_zenity
elif command -v rofi >/dev/null 2>&1; then
    prompt_with_rofi
elif command -v xmessage >/dev/null 2>&1; then
    prompt_with_xmessage
else
    notify-send -u critical "Power action cancelled" "No confirmation dialog tool was found." 2>/dev/null || true
    exit 1
fi

#!/usr/bin/env bash
set -u

TIMEOUT_SECONDS="${1:-30}"
TITLE="Shut Down?"
MESSAGE="Shut down this machine?

If you do nothing, shutdown will start in ${TIMEOUT_SECONDS} seconds."

poweroff_now() {
    systemctl poweroff
}

prompt_with_zenity() {
    zenity --question \
        --title="$TITLE" \
        --text="$MESSAGE" \
        --ok-label="Yes" \
        --cancel-label="Cancel" \
        --timeout="$TIMEOUT_SECONDS" \
        --no-wrap

    case "$?" in
        0|5)
            poweroff_now
            ;;
    esac
}

prompt_with_rofi() {
    choice="$(
        printf 'Yes\nCancel\n' |
            timeout "$TIMEOUT_SECONDS" rofi -dmenu -i -p "Shutdown in ${TIMEOUT_SECONDS}s?"
    )"
    status="$?"

    case "$status:$choice" in
        0:Yes|124:*|137:*)
            poweroff_now
            ;;
    esac
}

prompt_with_xmessage() {
    timeout "$TIMEOUT_SECONDS" xmessage \
        -center \
        -buttons "Yes:0,Cancel:1" \
        -default "Cancel" \
        "$MESSAGE"

    case "$?" in
        0|124|137)
            poweroff_now
            ;;
    esac
}

if command -v zenity >/dev/null 2>&1; then
    prompt_with_zenity
elif command -v rofi >/dev/null 2>&1; then
    prompt_with_rofi
elif command -v xmessage >/dev/null 2>&1; then
    prompt_with_xmessage
else
    notify-send -u critical "Shutdown cancelled" "No confirmation dialog tool was found." 2>/dev/null || true
    exit 1
fi

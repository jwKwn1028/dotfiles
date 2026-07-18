#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${I3_RESURRECT_STATE_DIR:-$HOME/.config/i3/resurrect}"
META_DIR="${I3_RESURRECT_META_DIR:-$HOME/.config/i3/resurrect-meta}"
SWALLOW="${I3_RESURRECT_SWALLOW:-class,instance,title}"
WORKSPACES_FILE="$META_DIR/workspaces.txt"
FOCUSED_FILE="$META_DIR/focused-workspace.txt"
ZATHURA_PAGES_FILE="$META_DIR/zathura-pages.json"
ZEN_PAGES_FILE="$META_DIR/zen-pages.json"
ZEN_URL_STATE_HELPER="$HOME/.config/i3/zen-url-state.py"
HELIUM_DESKTOP_FILE="${HELIUM_DESKTOP_FILE:-$HOME/.local/share/applications/helium.desktop}"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "i3-resurrect" "$1"
    fi
}

find_i3_resurrect() {
    if [ -n "${I3_RESURRECT:-}" ]; then
        printf '%s\n' "$I3_RESURRECT"
    elif command -v i3-resurrect >/dev/null 2>&1; then
        command -v i3-resurrect
    elif [ -x "$HOME/.local/bin/i3-resurrect" ]; then
        printf '%s\n' "$HOME/.local/bin/i3-resurrect"
    else
        printf 'i3-resurrect not found\n' >&2
        exit 127
    fi
}

workspace_file_id() {
    printf '%s' "$1" | tr -d '/\\:*"<>|'
}

ensure_zen_browser_programs() {
    local workspace="$1"
    local workspace_id
    local layout_file
    local programs_file
    local zen_windows
    local zen_programs
    local tmp

    workspace_id="$(workspace_file_id "$workspace")"
    layout_file="$STATE_DIR/workspace_${workspace_id}_layout.json"
    programs_file="$STATE_DIR/workspace_${workspace_id}_programs.json"

    [ -s "$layout_file" ] || return 0
    [ -s "$programs_file" ] || return 0

    zen_windows="$(
        jq '[.. | objects | select(.swallows? | type == "array") |
            .swallows[]? | select((.class // "") == "^zen$")] | length' "$layout_file"
    )"
    [ "$zen_windows" -gt 0 ] || return 0

    zen_programs="$(
        jq '[.[] | select((.command | if type == "array" then join(" ") else . end) |
            contains("app.zen_browser.zen"))] | length' "$programs_file"
    )"
    if [ "$zen_programs" -ge "$zen_windows" ]; then
        return 0
    fi

    tmp="$programs_file.tmp"
    jq --arg wd "$HOME" --argjson missing "$((zen_windows - zen_programs))" '
        . + [range(0; $missing) |
            {"command": ["flatpak", "run", "app.zen_browser.zen"], "working_directory": $wd}]
    ' "$programs_file" > "$tmp"
    mv "$tmp" "$programs_file"
}

# Print the Helium launch command as a JSON array, e.g.
# ["/home/me/Applications/helium-0.13.1.1-x86_64.AppImage"]. Helium is shipped
# as a versioned AppImage, so resolve the path from the .desktop Exec line
# (falling back to the newest AppImage under ~/Applications) instead of
# hardcoding a version that breaks on upgrade.
helium_launch_command() {
    local exec_line=""
    local cand=""

    if [ -r "$HELIUM_DESKTOP_FILE" ]; then
        exec_line="$(awk -F= '/^Exec=/{sub(/^Exec=/, ""); print; exit}' "$HELIUM_DESKTOP_FILE")"
    fi
    # Drop desktop-entry field codes (%U %f ...) and trailing whitespace.
    exec_line="$(printf '%s' "$exec_line" | sed -E 's/[[:space:]]*%[A-Za-z]//g; s/[[:space:]]+$//')"

    if [ -z "$exec_line" ]; then
        cand="$(ls -1t "$HOME"/Applications/helium*.AppImage 2>/dev/null | head -n 1)"
        exec_line="$cand"
    fi

    [ -n "$exec_line" ] || return 1
    printf '%s' "$exec_line" | jq -R 'split(" ") | map(select(length > 0))'
}

ensure_helium_browser_programs() {
    local workspace="$1"
    local workspace_id
    local layout_file
    local programs_file
    local helium_windows
    local helium_cmd
    local tmp

    workspace_id="$(workspace_file_id "$workspace")"
    layout_file="$STATE_DIR/workspace_${workspace_id}_layout.json"
    programs_file="$STATE_DIR/workspace_${workspace_id}_programs.json"

    [ -s "$layout_file" ] || return 0
    [ -s "$programs_file" ] || return 0

    helium_windows="$(
        jq '[.. | objects | select(.swallows? | type == "array") |
            .swallows[]? | select((.class // "") | test("helium"; "i"))] | length' "$layout_file"
    )"
    [ "$helium_windows" -gt 0 ] || return 0

    helium_cmd="$(helium_launch_command)" || return 0
    [ -n "$helium_cmd" ] || return 0

    # i3-resurrect captures whatever the running AppImage exposed in
    # /proc/<pid>/cmdline (often an ephemeral /tmp/.mount_helium*/... path that
    # won't exist after a reboot). Replace any Helium-ish entry with the clean,
    # reusable launch command, one per Helium window in the layout.
    tmp="$programs_file.tmp"
    jq --argjson count "$helium_windows" --argjson cmd "$helium_cmd" --arg wd "$HOME" '
        def is_helium_command($c):
            (($c | type) == "array") and
            (($c | map(select(type == "string")) | join(" ")) | test("helium"; "i"));
        (map(select(is_helium_command(.command // []) | not))) +
        [range(0; $count) | {"command": $cmd, "working_directory": $wd}]
    ' "$programs_file" > "$tmp"
    mv "$tmp" "$programs_file"
}

capture_zathura_page_state() {
    if ! command -v busctl >/dev/null 2>&1 || ! command -v xprop >/dev/null 2>&1; then
        printf '[]\n'
        return 0
    fi

    local tree
    tree="$(i3-msg -t get_tree 2>/dev/null)" || {
        printf '[]\n'
        return 0
    }

    {
        printf '%s\n' "$tree" | jq -r '
            [.. | objects | select(.type? == "workspace") |
                .name as $workspace |
                .. | objects |
                select(
                    (.window? // null) != null and
                    ((.window_properties.instance? // "") == "org.pwmt.zathura" or
                     (.window_properties.class? // "") == "Zathura")
                ) |
                [$workspace, .window] | @tsv
            ] | .[]
        ' | while IFS=$'\t' read -r workspace window_id; do
            local pid filename page_zero page_one

            [ -n "$workspace" ] || continue
            [ -n "$window_id" ] || continue

            pid="$(
                xprop -id "$window_id" _NET_WM_PID 2>/dev/null |
                    awk -F'= ' '/_NET_WM_PID/ {print $2; exit}'
            )"
            [[ "$pid" =~ ^[0-9]+$ ]] || continue

            filename="$(
                busctl --user --json=short get-property \
                    "org.pwmt.zathura.PID-$pid" \
                    /org/pwmt/zathura \
                    org.pwmt.zathura \
                    filename 2>/dev/null |
                    jq -r '.data // empty'
            )"
            [ -n "$filename" ] || continue

            page_zero="$(
                busctl --user --json=short get-property \
                    "org.pwmt.zathura.PID-$pid" \
                    /org/pwmt/zathura \
                    org.pwmt.zathura \
                    pagenumber 2>/dev/null |
                    jq -r '.data // empty'
            )"
            [[ "$page_zero" =~ ^[0-9]+$ ]] || continue

            page_one=$((page_zero + 1))
            jq -cn \
                --arg workspace "$workspace" \
                --arg window_id "$window_id" \
                --arg pid "$pid" \
                --arg filename "$filename" \
                --argjson page "$page_one" \
                '{workspace: $workspace, window_id: $window_id, pid: $pid, filename: $filename, page: $page}'
        done
    } | jq -s '.'
}

capture_zen_page_state() {
    if ! command -v python3 >/dev/null 2>&1 || [ ! -r "$ZEN_URL_STATE_HELPER" ]; then
        printf '[]\n'
        return 0
    fi

    local tree
    tree="$(i3-msg -t get_tree 2>/dev/null)" || {
        printf '[]\n'
        return 0
    }

    ZEN_PROFILE_ROOTS="${ZEN_PROFILE_ROOTS:-$HOME/.var/app/app.zen_browser.zen/.zen:$HOME/.zen}" \
        python3 "$ZEN_URL_STATE_HELPER" <<< "$tree" || printf '[]\n'
}

remember_zen_pages_for_workspace() {
    local workspace="$1"
    local workspace_id
    local programs_file
    local tmp

    workspace_id="$(workspace_file_id "$workspace")"
    programs_file="$STATE_DIR/workspace_${workspace_id}_programs.json"

    [ -s "$programs_file" ] || return 0
    [ -s "$ZEN_PAGES_FILE" ] || return 0

    tmp="$programs_file.tmp"
    jq --arg workspace "$workspace" --slurpfile zen_pages "$ZEN_PAGES_FILE" '
        def is_zen_command($cmd):
            (($cmd | type) == "array") and
            (
                ($cmd | index("app.zen_browser.zen")) != null or
                (
                    $cmd |
                    map(select(type == "string") | split("/") | last) |
                    any(. == "zen" or . == "zen-browser")
                )
            );

        def is_url_arg($arg):
            (($arg | type) == "string") and
            ($arg | test("^[A-Za-z][A-Za-z0-9+.-]*:"));

        def strip_zen_url_args($cmd):
            if ($cmd | length) == 0 then
                []
            elif $cmd[0] == "--new-window" then
                strip_zen_url_args($cmd[1:])
            elif is_url_arg($cmd[0]) then
                strip_zen_url_args($cmd[1:])
            else
                [$cmd[0]] + strip_zen_url_args($cmd[1:])
            end;

        def command_with_zen_url($cmd; $url):
            (strip_zen_url_args($cmd)) + ["--new-window", $url];

        ($zen_pages[0] // []) as $states |
        . as $programs |
        [
            range(0; length) as $i |
            .[$i] as $entry |
            ($entry.command // []) as $cmd |
            if is_zen_command($cmd) then
                ([
                    range(0; $i) |
                    $programs[.] |
                    select(is_zen_command(.command // []))
                ] | length) as $occurrence |
                ([
                    $states[] |
                    select(.workspace == $workspace and ((.browser // "zen") == "zen"))
                ]) as $matches |
                ($matches[$occurrence] // $matches[0] // null) as $state |
                if $state == null or (($state.url // "") == "") then
                    $entry
                else
                    $entry | .command = command_with_zen_url($cmd; $state.url)
                end
            else
                $entry
            end
        ]
    ' "$programs_file" > "$tmp"
    mv "$tmp" "$programs_file"
}

remember_helium_pages_for_workspace() {
    local workspace="$1"
    local workspace_id
    local programs_file
    local tmp

    workspace_id="$(workspace_file_id "$workspace")"
    programs_file="$STATE_DIR/workspace_${workspace_id}_programs.json"

    [ -s "$programs_file" ] || return 0
    [ -s "$ZEN_PAGES_FILE" ] || return 0

    tmp="$programs_file.tmp"
    jq --arg workspace "$workspace" --slurpfile zen_pages "$ZEN_PAGES_FILE" '
        def is_helium_command($cmd):
            (($cmd | type) == "array") and
            (($cmd | map(select(type == "string")) | join(" ")) | test("helium"; "i"));

        def is_url_arg($arg):
            (($arg | type) == "string") and
            ($arg | test("^[A-Za-z][A-Za-z0-9+.-]*:"));

        def strip_helium_url_args($cmd):
            if ($cmd | length) == 0 then
                []
            elif $cmd[0] == "--new-window" then
                strip_helium_url_args($cmd[1:])
            elif is_url_arg($cmd[0]) then
                strip_helium_url_args($cmd[1:])
            else
                [$cmd[0]] + strip_helium_url_args($cmd[1:])
            end;

        def command_with_helium_url($cmd; $url):
            (strip_helium_url_args($cmd)) + ["--new-window", $url];

        ($zen_pages[0] // []) as $states |
        . as $programs |
        [
            range(0; length) as $i |
            .[$i] as $entry |
            ($entry.command // []) as $cmd |
            if is_helium_command($cmd) then
                ([
                    range(0; $i) |
                    $programs[.] |
                    select(is_helium_command(.command // []))
                ] | length) as $occurrence |
                ([
                    $states[] |
                    select(.workspace == $workspace and ((.browser // "") == "helium"))
                ]) as $matches |
                ($matches[$occurrence] // $matches[0] // null) as $state |
                if $state == null or (($state.url // "") == "") then
                    $entry
                else
                    $entry | .command = command_with_helium_url($cmd; $state.url)
                end
            else
                $entry
            end
        ]
    ' "$programs_file" > "$tmp"
    mv "$tmp" "$programs_file"
}

remember_zathura_pages_for_workspace() {
    local workspace="$1"
    local workspace_id
    local programs_file
    local tmp

    workspace_id="$(workspace_file_id "$workspace")"
    programs_file="$STATE_DIR/workspace_${workspace_id}_programs.json"

    [ -s "$programs_file" ] || return 0
    [ -s "$ZATHURA_PAGES_FILE" ] || return 0

    tmp="$programs_file.tmp"
    jq --arg workspace "$workspace" --slurpfile zathura_pages "$ZATHURA_PAGES_FILE" '
        def is_zathura_command($cmd):
            (($cmd | type) == "array") and
            (($cmd | length) > 0) and
            ((($cmd[0] // "") | split("/") | last) == "zathura");

        def strip_zathura_page_args($cmd):
            if ($cmd | length) == 0 then
                []
            elif ($cmd[0] == "-P" or $cmd[0] == "--page") then
                strip_zathura_page_args($cmd[2:])
            elif (($cmd[0] | type) == "string" and ($cmd[0] | startswith("--page="))) then
                strip_zathura_page_args($cmd[1:])
            else
                [$cmd[0]] + strip_zathura_page_args($cmd[1:])
            end;

        def zathura_filename($cmd):
            (strip_zathura_page_args($cmd)[1:] |
                map(select((type == "string") and (startswith("-") | not))) |
                last // null);

        def command_with_zathura_page($cmd; $page):
            (strip_zathura_page_args($cmd)) as $clean |
            [$clean[0], "--page=\($page)"] + ($clean[1:] // []);

        ($zathura_pages[0] // []) as $states |
        . as $programs |
        [
            range(0; length) as $i |
            .[$i] as $entry |
            ($entry.command // []) as $cmd |
            if is_zathura_command($cmd) then
                (zathura_filename($cmd)) as $filename |
                if $filename == null then
                    $entry
                else
                    ([
                        range(0; $i) |
                        $programs[.] |
                        select(is_zathura_command(.command // [])) |
                        select(zathura_filename(.command) == $filename)
                    ] | length) as $occurrence |
                    ([
                        $states[] |
                        select(.workspace == $workspace and .filename == $filename)
                    ]) as $matches |
                    ($matches[$occurrence] // $matches[0] // null) as $state |
                    if $state == null then
                        $entry
                    else
                        $entry | .command = command_with_zathura_page($cmd; $state.page)
                    end
                end
            else
                $entry
            end
        ]
    ' "$programs_file" > "$tmp"
    mv "$tmp" "$programs_file"
}

normalize_layout_after_save() {
    local workspace="$1"
    local workspace_id
    local layout_file
    local tmp

    workspace_id="$(workspace_file_id "$workspace")"
    layout_file="$STATE_DIR/workspace_${workspace_id}_layout.json"

    [ -s "$layout_file" ] || return 0

    tmp="$layout_file.tmp"
    jq '
        walk(
            if type == "object" and ((.swallows? // null) | type == "array") then
                .swallows |= map(
                    if ((.class // "") | test("ghostty|zen|helium"; "i")) then
                        del(.title)
                    else
                        .
                    end
                )
            else
                .
            end
        )
    ' "$layout_file" > "$tmp"
    mv "$tmp" "$layout_file"
}

if [ "${1:-}" = "--check" ]; then
    command -v i3-msg >/dev/null
    command -v jq >/dev/null
    find_i3_resurrect >/dev/null
    exit 0
fi

I3_RESURRECT="$(find_i3_resurrect)"
mkdir -p "$STATE_DIR" "$META_DIR"

capture_zathura_page_state > "$ZATHURA_PAGES_FILE.tmp"
mv "$ZATHURA_PAGES_FILE.tmp" "$ZATHURA_PAGES_FILE"
capture_zen_page_state > "$ZEN_PAGES_FILE.tmp"
mv "$ZEN_PAGES_FILE.tmp" "$ZEN_PAGES_FILE"

workspaces_json="$(i3-msg -t get_workspaces)"
printf '%s\n' "$workspaces_json" | jq -r 'sort_by(.num)[] | .name' > "$WORKSPACES_FILE.tmp"
printf '%s\n' "$workspaces_json" | jq -r '.[] | select(.focused) | .name' > "$FOCUSED_FILE.tmp"

mv "$WORKSPACES_FILE.tmp" "$WORKSPACES_FILE"
mv "$FOCUSED_FILE.tmp" "$FOCUSED_FILE"

saved=0
while IFS= read -r workspace; do
    [ -n "$workspace" ] || continue
    "$I3_RESURRECT" save -w "$workspace" -d "$STATE_DIR" --swallow="$SWALLOW"
    normalize_layout_after_save "$workspace"
    ensure_zen_browser_programs "$workspace"
    ensure_helium_browser_programs "$workspace"
    remember_zen_pages_for_workspace "$workspace"
    remember_helium_pages_for_workspace "$workspace"
    remember_zathura_pages_for_workspace "$workspace"
    saved=$((saved + 1))
done < "$WORKSPACES_FILE"

notify "Saved $saved workspace(s)."

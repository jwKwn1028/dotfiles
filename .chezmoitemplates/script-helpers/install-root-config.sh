# shellcheck shell=sh
changed=0
temporary=
trap 'rm -f "${temporary:-}"' EXIT HUP INT TERM

install_config() {
    target=$1
    shift
    temporary=$(mktemp)
    cat >"$temporary"

    metadata=$(stat -c '%u:%g:%a' "$target" 2>/dev/null || true)
    if ! cmp -s "$temporary" "$target" || [ "$metadata" != "0:0:644" ]; then
        echo "==> Installing $target (sudo may prompt for your password)"
        sudo install "$@" -o root -g root -m 0644 "$temporary" "$target"
        # shellcheck disable=SC2034
        changed=1
    fi

    rm -f "$temporary"
    temporary=
}

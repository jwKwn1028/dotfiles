#!/usr/bin/env bash
set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
BACKUP="$ROOT/restic-backup"
[ -r "$BACKUP" ] || BACKUP="$ROOT/executable_restic-backup"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
TEST_HOME="$TEST_TMP/home"
MOUNT="$TEST_TMP/mount"
RESTIC_LOG="$TEST_TMP/restic-calls"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$MOCK_BIN" "$TEST_HOME/.config/restic" "$MOUNT/home-repo" "$MOUNT/system-repo"
: >"$MOUNT/home-repo/config"
: >"$TEST_HOME/.config/restic/password"

cat >"$TEST_HOME/.config/restic/config.sh" <<EOF
RESTIC_BACKUP_MOUNT='$MOUNT'
RESTIC_REPOSITORY='$MOUNT/home-repo'
RESTIC_SYSTEM_REPOSITORY='$MOUNT/system-repo'
RESTIC_PASSWORD_FILE='$TEST_HOME/.config/restic/password'
RESTIC_SYSTEM_PATHS=()
EOF

cat >"$MOCK_BIN/restic" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RESTIC_TEST_LOG"
EOF
cat >"$MOCK_BIN/mountpoint" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$MOCK_BIN/stat" <<'EOF'
#!/usr/bin/env bash
last=
for arg in "$@"; do last=$arg; done
case "$last" in
    /) printf '%s\n' 100 ;;
    "$RESTIC_TEST_MOUNT")
        if [ "${RESTIC_TEST_SAME_DEVICE:-0}" = 1 ]; then
            printf '%s\n' 100
        else
            printf '%s\n' 200
        fi
        ;;
    *) exec /usr/bin/stat "$@" ;;
esac
EOF
chmod +x "$MOCK_BIN/restic" "$MOCK_BIN/mountpoint" "$MOCK_BIN/stat"

status=0
env HOME="$TEST_HOME" PATH="$MOCK_BIN:/usr/bin:/bin" \
    RESTIC_TEST_LOG="$RESTIC_LOG" RESTIC_TEST_MOUNT="$MOUNT" \
    RESTIC_TEST_SAME_DEVICE=1 \
    bash "$BACKUP" snapshots >"$TEST_TMP/out" 2>"$TEST_TMP/err" || status=$?
[ "$status" -ne 0 ] || {
    printf 'FAIL: a root-filesystem mountpoint was accepted\n' >&2
    exit 1
}
grep -Fq 'mountpoint on the root filesystem' "$TEST_TMP/err" || {
    printf 'FAIL: same-device refusal was not explained\n' >&2
    exit 1
}
[ ! -s "$RESTIC_LOG" ] || {
    printf 'FAIL: restic ran before same-device validation failed\n' >&2
    exit 1
}

env HOME="$TEST_HOME" PATH="$MOCK_BIN:/usr/bin:/bin" \
    RESTIC_TEST_LOG="$RESTIC_LOG" RESTIC_TEST_MOUNT="$MOUNT" \
    RESTIC_TEST_SAME_DEVICE=0 \
    bash "$BACKUP" snapshots >/dev/null
grep -Fq 'snapshots --host' "$RESTIC_LOG" || {
    printf 'FAIL: distinct-device repository did not reach restic snapshots\n' >&2
    exit 1
}

printf 'PASS: restic rejects mountpoints backed by the root filesystem\n'

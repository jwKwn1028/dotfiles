# shellcheck shell=bash
select_mozilla_profile() {
    local profile_root=$1 profile_file=$2 candidate
    while IFS= read -r candidate; do
        case "$candidate" in
            "" | "." | ".." | /* | ../* | */../* | */..)
                continue
                ;;
        esac
        if [[ -d "$profile_root/$candidate" ]]; then
            printf '%s\n' "$profile_root/$candidate"
            return 0
        fi
    done < <(
        awk '
            /^\[/ {
                section = $0
                sub(/\r$/, "", section)

                if (section ~ /^\[Install[^]]*\]$/) {
                    mode = "install"
                    next
                }
                if (section ~ /^\[Profile[0-9]+\]$/) {
                    mode = "profile"
                    profile_count++
                    next
                }

                mode = ""
                next
            }

            mode == "install" && /^Default=/ {
                value = $0
                sub(/^Default=/, "", value)
                sub(/\r$/, "", value)
                install_paths[++install_count] = value
                next
            }

            mode == "profile" && /^Path=/ {
                value = $0
                sub(/^Path=/, "", value)
                sub(/\r$/, "", value)
                profile_paths[profile_count] = value
                next
            }

            mode == "profile" && /^Default=1\r?$/ {
                profile_defaults[profile_count] = 1
            }

            END {
                for (i = 1; i <= install_count; i++) {
                    print install_paths[i]
                }
                for (i = 1; i <= profile_count; i++) {
                    if (profile_defaults[i]) {
                        print profile_paths[i]
                    }
                }
                for (i = 1; i <= profile_count; i++) {
                    if (!profile_defaults[i]) {
                        print profile_paths[i]
                    }
                }
            }
        ' "$profile_file"
    )
    return 0
}

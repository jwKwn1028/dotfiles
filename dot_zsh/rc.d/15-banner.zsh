# --------------------------------------------------------
# Startup Banner (Random, Centered, Bold, Green)
# --------------------------------------------------------
# Anonymous function keeps the scratch variables out of the session
# (the old top-level version leaked messages/size/index/... globals).
if (( SHLVL <= 2 )); then
  () {
    local -a messages=(
      "Welcome Back"
      "Hello World"
      "What's the Plan?"
      "Have a Nice Day"
      "Ready to Focus"
      "One at a Time"
    )

    local size=${#messages[@]}
    local index=$(( RANDOM % size + 1 ))
    local banner_text="${messages[$index]}"

    # Format: YYYY-MM-DD HH:MM:SS
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')

    # We need separate padding for the banner and the time
    local padding_banner=$(( (${COLUMNS:-80} - ${#banner_text}) / 2 ))
    local indent_banner=$(printf "%*s" $padding_banner)

    local padding_time=$(( (${COLUMNS:-80} - ${#current_time}) / 2 ))
    local indent_time=$(printf "%*s" $padding_time)

    print -P ""
    print -P "%B%F{#86BE43}${indent_banner}${banner_text}%f%b"
    print -P "%F{245}${indent_time}${current_time}%f"
    print -P ""
  }
fi

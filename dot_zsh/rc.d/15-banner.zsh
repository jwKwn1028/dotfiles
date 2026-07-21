# --------------------------------------------------------
# Startup Banner (Centered and Bold)
# --------------------------------------------------------
# Optional configuration (set these before this file is sourced, or edit the
# defaults below):
#   ZSH_BANNER_SPECIAL_MESSAGES=("Message one" "Message two")
#   ZSH_BANNER_SPECIAL_COLORS=("#FFAF00")
#   ZSH_BANNER_SPECIAL_CHANCE=1/8191  # ratio, or an integer percentage (e.g. 5)

if (( ! ${+ZSH_BANNER_SPECIAL_MESSAGES} )); then
  typeset -ga ZSH_BANNER_SPECIAL_MESSAGES=(
    "Wir müssen wissen, dass wir es wissen werden."
    "Longtemps, je me suis couché de bonne heure."
    "It is not down on any map; true places never are."
    "La verdad adelgaza y no quiebra, y siempre anda sobre la mentira como el aceite sobre el agua."
    "이지러는 졌으나 보름을 갓 지난 달은 부드러운 빛을 흐뭇이 흘리고 있다."
    "Music is the Silence Between the Notes"
  )
fi

# Colors correspond to the messages above; a shorter color list is cycled.
if (( ! ${+ZSH_BANNER_SPECIAL_COLORS} )); then
  typeset -ga ZSH_BANNER_SPECIAL_COLORS=(
    "#FFAF00"
  )
fi

if (( ! ${+ZSH_BANNER_SPECIAL_CHANCE} )); then
  typeset -g ZSH_BANNER_SPECIAL_CHANCE=1/8191
fi

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

    # Format: YYYY-MM-DD HH:MM:SS
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local month_day="${current_time[6,10]}"
    local banner_text banner_color="#86BE43"

    # Accept either odds such as 1/8191 or a backward-compatible integer
    # percentage such as 5. Invalid values fall back to 1/8191.
    local special_chance=$ZSH_BANNER_SPECIAL_CHANCE
    local special_numerator special_denominator
    if [[ $special_chance == <->/<-> ]]; then
      special_numerator=${special_chance%%/*}
      special_denominator=${special_chance#*/}
    elif [[ $special_chance == <-> ]]; then
      special_numerator=$special_chance
      special_denominator=100
    else
      special_numerator=1
      special_denominator=8191
    fi

    special_numerator=$(( 10#$special_numerator ))
    special_denominator=$(( 10#$special_denominator ))
    if (( special_denominator == 0 )); then
      special_numerator=1
      special_denominator=1234
    elif (( special_numerator > special_denominator )); then
      special_numerator=$special_denominator
    fi

    # Combine two RANDOM values so ratios can use denominators above 32768.
    local special_roll=$(( (RANDOM * 32768 + RANDOM) % special_denominator ))

    if [[ $month_day == "10-28" ]]; then
      # The birthday message always wins over normal and rare messages.
      banner_text="Happy Birthday!"
    elif (( ${#ZSH_BANNER_SPECIAL_MESSAGES[@]} > 0 &&
             special_roll < special_numerator )); then
      local special_index=$(( RANDOM % ${#ZSH_BANNER_SPECIAL_MESSAGES[@]} + 1 ))
      banner_text="${ZSH_BANNER_SPECIAL_MESSAGES[$special_index]}"

      if (( ${#ZSH_BANNER_SPECIAL_COLORS[@]} > 0 )); then
        local color_index=$(( (special_index - 1) % ${#ZSH_BANNER_SPECIAL_COLORS[@]} + 1 ))
        banner_color="${ZSH_BANNER_SPECIAL_COLORS[$color_index]}"
      else
        banner_color="#FFAF00"
      fi
    else
      local index=$(( RANDOM % ${#messages[@]} + 1 ))
      banner_text="${messages[$index]}"
    fi

    # We need separate padding for the banner and the time
    local padding_banner=$(( (${COLUMNS:-80} - ${#banner_text}) / 2 ))
    (( padding_banner < 0 )) && padding_banner=0
    local indent_banner=$(printf "%*s" $padding_banner)

    local padding_time=$(( (${COLUMNS:-80} - ${#current_time}) / 2 ))
    (( padding_time < 0 )) && padding_time=0
    local indent_time=$(printf "%*s" $padding_time)

    print -P ""
    print -nP "%B%F{$banner_color}"
    print -nr -- "${indent_banner}${banner_text}"
    print -P "%f%b"
    print -P "%F{245}${indent_time}${current_time}%f"
    print -P ""
  }
fi

# --------------------------------------------------------
# Startup Banner (Centered and Bold)
# --------------------------------------------------------
# Optional configuration (set these before this file is sourced, or edit the
# defaults below):
#   ZSH_BANNER_SPECIAL_MESSAGES=("Message one" "Message two")
#   ZSH_BANNER_SPECIAL_COLORS=("#FFAF00")
#   ZSH_BANNER_SPECIAL_CHANCE=1/100  # ratio, or an integer percentage (e.g. 5)

if (( ! ${+ZSH_BANNER_SPECIAL_MESSAGES} )); then
  typeset -ga ZSH_BANNER_SPECIAL_MESSAGES=(
    "Wir müssen wissen, dass wir es wissen werden"
    "Longtemps, je me suis couché de bonne heure"
    "It is not down on any map; true places never are"
    "산허리는 온통 메밀밭이어서 피기 시작한 꽃이 소금을 뿌린 듯이 흐뭇한 달빛에 숨이 막힐 지경이다"
    "Music is the Silence Between the Notes"
    "Creía en infinitas series de tiempos, en una red creciente y vertiginosa de tiempos divergentes convergentes y paralelos"
    "Live the Questions Now"
    "행복은 하찮은 것에 있다"
    "All those moments will be lost in time, like tears in rain"
    "The Matrix is Everywhere"
    )
fi

# Colors correspond to the messages above; a shorter color list is cycled.
if (( ! ${+ZSH_BANNER_SPECIAL_COLORS} )); then
  typeset -ga ZSH_BANNER_SPECIAL_COLORS=(
    "#FFAF00"
  )
fi

if (( ! ${+ZSH_BANNER_SPECIAL_CHANCE} )); then
  typeset -g ZSH_BANNER_SPECIAL_CHANCE=1/100
fi

# Render the banner through the first live prompt instead of writing fixed
# leading spaces into the scrollback. ZLE re-expands prompts after a terminal
# resize, so the padding follows the current value of COLUMNS while that first
# command line is active.
_zsh_banner_prompt() {
  emulate -L zsh
  (( ${ZSH_BANNER_ACTIVE:-0} )) || return 0

  local banner_text=$ZSH_BANNER_TEXT
  local current_time=$ZSH_BANNER_TIME
  local tasklist=$ZSH_BANNER_TASKLIST
  local -i banner_width padding_banner padding_time

  # Measure terminal cells rather than Unicode code points so wide and
  # combining characters are centered correctly.
  banner_width=${(m)#banner_text}
  (( padding_banner = (${COLUMNS:-80} - banner_width) / 2 ))
  (( padding_banner < 0 )) && padding_banner=0
  local indent_banner=$(printf "%*s" "$padding_banner")

  (( padding_time = (${COLUMNS:-80} - ${#current_time}) / 2 ))
  (( padding_time < 0 )) && padding_time=0
  local indent_time=$(printf "%*s" "$padding_time")

  # The returned text is expanded as part of PROMPT, so literal percent signs
  # in user-configured messages or task descriptions must be doubled.
  banner_text=${banner_text//\%/%%}
  current_time=${current_time//\%/%%}
  tasklist=${tasklist//\%/%%}

  print -nr -- $'\n'
  print -nr -- "%B%F{${ZSH_BANNER_COLOR}}${indent_banner}${banner_text}%f%b"$'\n'
  print -nr -- "%F{245}${indent_time}${current_time}%f"$'\n\n'
  [[ -n $tasklist ]] && print -nr -- "${tasklist}"$'\n\n'

  # Command substitution strips trailing newlines. This zero-width prompt
  # escape preserves the blank line before Starship without adding a cell.
  print -nr -- '%f%b'
}

_zsh_banner_finish() {
  emulate -L zsh

  typeset -gi ZSH_BANNER_ACTIVE=0
  typeset -gi ZSH_BANNER_INSTALLED=0
  local banner_prefix='$(_zsh_banner_prompt)'
  [[ $PROMPT == ${banner_prefix}* ]] && PROMPT=${PROMPT#$banner_prefix}

  autoload -Uz add-zsh-hook
  add-zsh-hook -d preexec _zsh_banner_finish
}

_zsh_banner_install() {
  emulate -L zsh
  (( ${ZSH_BANNER_ACTIVE:-0} && ! ${ZSH_BANNER_INSTALLED:-0} )) || return 0

  PROMPT='$(_zsh_banner_prompt)'"${PROMPT}"
  typeset -gi ZSH_BANNER_INSTALLED=1

  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _zsh_banner_finish
}

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
    local current_date="${current_time[1,10]}"
    local current_hour=$(( 10#${current_time[12,13]} ))
    local month_day="${current_time[6,10]}"
    local banner_text banner_color="#86BE43"

    # Show today's task list on the first top-level terminal opened between
    # 06:00 and 08:59. The state file records the day it was last shown, so an
    # earlier terminal does not consume the day's slot.
    local banner_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
    local tasklist_date_file="$banner_state_dir/banner-terminal-date"
    local last_tasklist_date show_tasklist=0

    if (( current_hour >= 6 && current_hour < 9 )) && (( $+commands[task] )); then
      [[ -r $tasklist_date_file ]] &&
        IFS= read -r last_tasklist_date < "$tasklist_date_file"
      [[ $last_tasklist_date != $current_date ]] && show_tasklist=1
    fi

    # Accept either odds such as 1/100 or a backward-compatible integer
    # percentage such as 5. Invalid values fall back to 1/100.
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
      special_denominator=100
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

    typeset -g ZSH_BANNER_TEXT=$banner_text
    typeset -g ZSH_BANNER_COLOR=$banner_color
    typeset -g ZSH_BANNER_TIME=$current_time
    typeset -g ZSH_BANNER_TASKLIST=
    typeset -gi ZSH_BANNER_ACTIVE=1

    if (( show_tasklist )); then
      if [[ -d $banner_state_dir ]] || mkdir -p -- "$banner_state_dir" 2>/dev/null; then
        { print -r -- "$current_date" >! "$tasklist_date_file" } 2>/dev/null
      fi
      # Raw ANSI color bytes confuse ZLE's prompt-width accounting.
      ZSH_BANNER_TASKLIST=$(command task rc.verbose=nothing rc.color=off list)
    fi
  }
fi

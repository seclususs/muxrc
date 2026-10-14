#####################
# AI Assistant Module
#####################

typeset -g _ai_env="$HOME/.gemini_ai_env"
typeset -g _ai_cooldown="$HOME/.cache/gemini_cooldown"
typeset -g _ai_default_model="gemini-3.5-flash-lite"
typeset -g _gemini_env="$_ai_env"
typeset -g _gemini_cooldown="$_ai_cooldown"
typeset -g _AI_LAST_CMD=""
typeset -g _AI_LAST_STATUS=0
typeset -g _AI_SKIP_STATUS_RECORD=0
typeset -g _AI_SPINNER_PID=""
typeset -g _AI_PHASE_FILE=""
typeset -gU precmd_functions preexec_functions

zmodload zsh/datetime 2> /dev/null

####################
# Environment loader
####################
_ai_load() {
  if [[ -f "$_ai_env" ]]; then
    source "$_ai_env"
    if [[ -n "${GEMINI_API_KEY-}" ]]; then
      GEMINI_API_KEY="${GEMINI_API_KEY#"${GEMINI_API_KEY%%[![:space:]]*}"}"
      GEMINI_API_KEY="${GEMINI_API_KEY%"${GEMINI_API_KEY##*[![:space:]]}"}"
    fi
    if [[ -n "${GEMINI_MODEL-}" ]]; then
      GEMINI_MODEL="${GEMINI_MODEL#"${GEMINI_MODEL%%[![:space:]]*}"}"
      GEMINI_MODEL="${GEMINI_MODEL%"${GEMINI_MODEL##*[![:space:]]}"}"
    fi
  fi
}

_gemini_load() {
  _ai_load
}

#################
# Key mask helper
#################
_ai_mask_key() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    print "not configured"
    return 0
  fi
  if ((${#raw} > 10)); then
    print -r -- "${raw[1,6]}...${raw[-4,-1]}"
  else
    print "configured"
  fi
}

###################
# Key verify helper
###################
_ai_verify_key() {
  local test_key="$1"
  if ! command -v curl > /dev/null 2>&1 || ! command -v jq > /dev/null 2>&1; then
    print -u2 "curl or jq not installed. run: pkg install curl jq"
    return 1
  fi

  local resp
  resp=$(curl -s --max-time 8 -H "x-goog-api-key: $test_key" \
    "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1" 2> /dev/null)

  if [[ -z "$resp" ]]; then
    return 2
  fi

  local err_msg
  err_msg=$(jq -r '.error.message // empty' <<< "$resp" 2> /dev/null)
  if [[ -n "$err_msg" ]]; then
    print -u2 "gemini api error: $err_msg"
    return 1
  fi

  if jq -e '.models // empty' <<< "$resp" > /dev/null 2>&1; then
    return 0
  fi

  return 1
}

####################
# Central gate check
####################
_ai_gate_check() {
  local silent="${1:-0}"
  _ai_load

  local active="${AI_ENABLED:-${AI_AUTOCORRECT_ENABLED:-0}}"
  if [[ "$active" != "1" ]]; then
    if ((silent == 0)); then
      print -u2 "ai is disabled. run: ai-toggle"
    fi
    return 1
  fi

  if [[ -z "${GEMINI_API_KEY-}" ]]; then
    if ((silent == 0)); then
      print -u2 "gemini api key not found. set GEMINI_API_KEY in ~/.gemini_ai_env"
    fi
    return 1
  fi

  if ! command -v curl > /dev/null 2>&1 || ! command -v jq > /dev/null 2>&1; then
    if ((silent == 0)); then
      print -u2 "curl or jq not installed. run: pkg install curl jq"
    fi
    return 1
  fi

  return 0
}

#######################
# Cooldown rate limiter
#######################
_ai_check_cooldown() {
  local cooldown_sec="${1:-3}"
  mkdir -p "${_ai_cooldown:h}" 2> /dev/null

  local now="${EPOCHSECONDS:-0}"
  if ((now == 0)); then
    now=$(date +%s)
  fi

  local last=0
  [[ -f "$_ai_cooldown" ]] && last=$(< "$_ai_cooldown" 2> /dev/null)
  [[ "$last" =~ ^[0-9]+$ ]] || last=0

  if ((now - last < cooldown_sec)); then
    return 1
  fi

  print "$now" > "$_ai_cooldown" 2> /dev/null
  return 0
}

##################
# AI master toggle
##################
ai-toggle() {
  mkdir -p "${_ai_env:h}" 2> /dev/null
  touch "$_ai_env" 2> /dev/null
  _ai_load

  local current="${AI_ENABLED:-${AI_AUTOCORRECT_ENABLED:-0}}"
  local target=1
  local msg="gemini ai assistant: on"

  if [[ "$current" == "1" ]]; then
    target=0
    msg="gemini ai assistant: off"
  fi

  local key
  for key in AI_ENABLED AI_AUTOCORRECT_ENABLED; do
    if grep -q "^[[:space:]]*${key}=" "$_ai_env" 2> /dev/null; then
      sed -i "s/^[[:space:]]*${key}=.*/${key}=${target}/" "$_ai_env"
    else
      print "${key}=${target}" >> "$_ai_env"
    fi
  done

  export AI_ENABLED="$target"
  export AI_AUTOCORRECT_ENABLED="$target"
  print -u2 -- "$msg"
}

###################
# AI model switcher
###################
ai-model() {
  _ai_load

  if [[ $# -eq 0 ]]; then
    local current="${GEMINI_MODEL:-$_ai_default_model}"
    print -u2 "current gemini model: $current"
    print -u2 "usage: ai-model <model-name>"
    return 0
  fi

  local target="$1"
  mkdir -p "${_ai_env:h}" 2> /dev/null
  touch "$_ai_env" 2> /dev/null

  if grep -q "^[[:space:]]*GEMINI_MODEL=" "$_ai_env" 2> /dev/null; then
    sed -i "s/^[[:space:]]*GEMINI_MODEL=.*/GEMINI_MODEL=\"${target}\"/" "$_ai_env"
  else
    print "GEMINI_MODEL=\"${target}\"" >> "$_ai_env"
  fi

  export GEMINI_MODEL="$target"
  print -u2 "gemini model: $target"
}

################
# AI key manager
################
ai-key() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    print -u2 "usage: ai-key [-c|--check]"
    return 0
  fi

  _ai_load

  if [[ "$1" == "-c" || "$1" == "--check" ]]; then
    print -u2 "current gemini api key: $(_ai_mask_key "${GEMINI_API_KEY-}")"
    if [[ -z "${GEMINI_API_KEY-}" ]]; then
      return 1
    fi
    if _ai_verify_key "$GEMINI_API_KEY"; then
      print -u2 "gemini api key: valid"
      return 0
    else
      print -u2 "gemini api key: invalid"
      return 1
    fi
  fi

  if [[ $# -gt 0 ]]; then
    print -u2 "do not pass api key as an argument (leaks to shell history)"
    print -u2 "usage: ai-key [-c|--check]"
    return 1
  fi

  print -u2 "current gemini api key: $(_ai_mask_key "${GEMINI_API_KEY-}")"

  local new_key
  if ! read -rs "new_key?enter gemini api key: "; then
    print -u2 ""
    return 1
  fi
  print -u2 ""

  new_key="${new_key#"${new_key%%[![:space:]]*}"}"
  new_key="${new_key%"${new_key##*[![:space:]]}"}"
  new_key="${new_key#[\'\"]}"
  new_key="${new_key%[\'\"]}"

  if [[ -z "$new_key" ]]; then
    print -u2 "api key cannot be empty"
    return 1
  fi

  local verify_status=0
  _ai_verify_key "$new_key" || verify_status=$?

  if ((verify_status == 1)); then
    return 1
  elif ((verify_status == 2)); then
    if ! read -q "?network verification failed. save anyway? [y/N] "; then
      print -u2 ""
      return 1
    fi
    print -u2 ""
  fi

  mkdir -p "${_ai_env:h}" 2> /dev/null
  touch "$_ai_env" 2> /dev/null

  local escaped_key="${new_key//\\/\\\\}"
  escaped_key="${escaped_key//\//\\/}"
  escaped_key="${escaped_key//&/\\&}"

  if grep -q "^[[:space:]]*GEMINI_API_KEY=" "$_ai_env" 2> /dev/null; then
    sed -i "s|^[[:space:]]*GEMINI_API_KEY=.*|GEMINI_API_KEY=\"${escaped_key}\"|" "$_ai_env"
  else
    print "GEMINI_API_KEY=\"${escaped_key}\"" >> "$_ai_env"
  fi

  chmod 600 "$_ai_env" 2> /dev/null
  export GEMINI_API_KEY="$new_key"
  print -u2 "gemini api key: updated ($(_ai_mask_key "$GEMINI_API_KEY"))"

  unset new_key escaped_key
}

##################
# Spinner feedback
##################
_ai_start_phased_spinner() {
  local initial_phase="${1:-searching}"
  [[ ! -t 2 ]] && return 0

  _ai_stop_phased_spinner

  _AI_PHASE_FILE="$HOME/.cache/ai_phase_$$"
  mkdir -p "${_AI_PHASE_FILE:h}" 2> /dev/null
  print "$initial_phase" > "$_AI_PHASE_FILE" 2> /dev/null

  setopt local_options no_monitor no_notify

  (
    local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local curr_phase=""
    local new_phase=""
    local phase_start=$SECONDS
    local i=1
    while [[ -f "$_AI_PHASE_FILE" ]]; do
      new_phase=$(< "$_AI_PHASE_FILE" 2> /dev/null)
      if [[ -n "$new_phase" && "$new_phase" != "$curr_phase" ]]; then
        curr_phase="$new_phase"
        phase_start=$SECONDS
      fi
      local elapsed=$((SECONDS - phase_start))
      printf "\r\033[2K\033[34m%s\033[0m (%ds) %s" "$curr_phase" "$elapsed" "${frames[i]}" >&2
      ((i = (i % 10) + 1))
      sleep 0.1
    done
  ) > /dev/null &
  _AI_SPINNER_PID=$!
}

_ai_set_phase() {
  local phase="$1"
  [[ -n "$_AI_PHASE_FILE" && -f "$_AI_PHASE_FILE" ]] && print "$phase" > "$_AI_PHASE_FILE" 2> /dev/null
}

_ai_stop_phased_spinner() {
  if [[ -n "$_AI_PHASE_FILE" ]]; then
    rm -f "$_AI_PHASE_FILE" 2> /dev/null
    _AI_PHASE_FILE=""
  fi
  rm -f "$HOME/.cache/ai_phase_$$" 2> /dev/null
  if [[ -n "$_AI_SPINNER_PID" ]]; then
    kill -9 "$_AI_SPINNER_PID" 2> /dev/null
    wait "$_AI_SPINNER_PID" 2> /dev/null
    _AI_SPINNER_PID=""
  fi
  if [[ -t 2 ]]; then
    printf "\r\033[2K" >&2
  fi
}

######################
# Terminal state hooks
######################
_ai_preexec_hook() {
  local cmd="$1"
  local trimmed="${cmd#"${cmd%%[![:space:]]*}"}"
  local base_cmd="${trimmed%% *}"

  case "$base_cmd" in
    cmd-do | cmd-fix | cmd-ask | ai-toggle | ai-model | ai-key | '\?\?' | '??')
      _AI_SKIP_STATUS_RECORD=1
      return 0
      ;;
    *)
      _AI_SKIP_STATUS_RECORD=0
      _AI_LAST_CMD="$trimmed"
      ;;
  esac
}

_ai_precmd_hook() {
  local last_ret=$?
  _ai_stop_phased_spinner

  if ((_AI_SKIP_STATUS_RECORD == 1)); then
    _AI_SKIP_STATUS_RECORD=0
    return 0
  fi

  _AI_LAST_STATUS=$last_ret
}

preexec_functions+=(_ai_preexec_hook)
precmd_functions+=(_ai_precmd_hook)

######################
# Terminal UI renderer
######################
_ai_render() {
  local text="$1"

  if [[ -z "$text" ]]; then
    return 0
  fi

  if [[ "${AI_RENDER_STYLE:-markdown}" == "raw" ]]; then
    print -r -- "$text"
    return 0
  fi

  local term_cols="${AI_RENDER_WIDTH:-0}"
  if ((term_cols <= 0)); then
    term_cols="${COLUMNS:-$(tput cols 2> /dev/null || echo 80)}"
  fi
  ((term_cols < 30)) && term_cols=80

  local compact_flag="${AI_RENDER_COMPACT:-0}"
  local card_flag="${AI_RENDER_CARD:-1}"
  local term_lines="${LINES:-$(tput lines 2> /dev/null || echo 24)}"

  local formatted
  formatted=$(awk -v width="$term_cols" -v compact_mode="$compact_flag" -v card_mode="$card_flag" '
    function strip_ansi(str,   tmp) {
      tmp = str
      gsub(/\033\[[0-9;]*[a-zA-Z]/, "", tmp)
      return length(tmp)
    }

    function format_inline(s,   out, idx, in_bold, in_italic, in_code, c) {
      out = ""
      in_bold = 0
      in_italic = 0
      in_code = 0
      idx = 1
      while (idx <= length(s)) {
        c = substr(s, idx, 1)
        if (c == "*" && substr(s, idx, 2) == "**") {
          if (in_bold == 0) {
            out = out "\033[1;37m"
            in_bold = 1
          } else {
            out = out "\033[0m"
            in_bold = 0
          }
          idx += 2
          continue
        }
        if (c == "*") {
          if (in_italic == 0) {
            out = out "\033[3m"
            in_italic = 1
          } else {
            out = out "\033[0m"
            in_italic = 0
          }
          idx += 1
          continue
        }
        if (c == "`") {
          if (in_code == 0) {
            out = out "\033[36m"
            in_code = 1
          } else {
            out = out "\033[0m"
            in_code = 0
          }
          idx += 1
          continue
        }
        out = out c
        idx += 1
      }
      if (in_bold || in_italic || in_code) out = out "\033[0m"
      return out
    }

    function color_urls(w) {
      if (w ~ /^https?:\/\//) {
        return "\033[4;36m" w "\033[0m"
      }
      return w
    }

    function print_card_line(content) {
      if (use_card) {
        if (length(content) == 0) {
          print border_color "│\033[0m"
        } else {
          print border_color "│\033[0m " content
        }
      } else {
        print content
      }
    }

    function print_wrapped(text, prefix1, prefix2, max_w,   words, n, i, line, word, line_len, w_len) {
      text = format_inline(text)
      n = split(text, words, /[ \t]+/)
      if (n == 0) {
        if (length(prefix1) > 0) print_card_line(prefix1)
        return
      }

      words[1] = color_urls(words[1])
      line = prefix1 words[1]
      line_len = strip_ansi(line)

      for (i = 2; i <= n; i++) {
        word = words[i]
        if (word == "") continue
        word = color_urls(word)
        w_len = strip_ansi(word)
        if (line_len + 1 + w_len > max_w) {
          print_card_line(line)
          line = prefix2 word
          line_len = strip_ansi(line)
        } else {
          line = line " " word
          line_len += 1 + w_len
        }
      }
      if (length(line) > 0) {
        print_card_line(line)
      }
    }

    function print_wrapped_cmd(cmd, max_w,   tokens, n, i, line, tok, line_len, tok_len, prefix1, prefix2) {
      n = split(cmd, tokens, /[ \t]+/)
      if (n == 0) return

      prefix1 = "   \033[1;32m$\033[0m \033[1m"
      prefix2 = "       \033[1m"

      line = prefix1 tokens[1]
      line_len = strip_ansi(line)

      for (i = 2; i <= n; i++) {
        tok = tokens[i]
        if (tok == "") continue
        tok_len = strip_ansi(tok)
        if (line_len + 1 + tok_len + 2 > max_w) {
          print_card_line(line " \\" "\033[0m")
          line = prefix2 tok
          line_len = strip_ansi(line)
        } else {
          line = line " " tok
          line_len += 1 + tok_len
        }
      }
      if (length(line) > 0) {
        print_card_line(line "\033[0m")
      }
    }

    BEGIN {
      cols = (width > 0 ? width : 60)
      compact = (compact_mode > 0 ? 1 : 0)
      use_card = (card_mode != "0" ? 1 : 0)

      border_color = "\033[2;37m"
      bar_len = cols - 4
      if (bar_len < 10) bar_len = 10

      card_top = border_color "┌"
      card_bot = border_color "└"
      for (b = 1; b <= bar_len; b++) {
        card_top = card_top "─"
        card_bot = card_bot "─"
      }
      card_top = card_top "\033[0m"
      card_bot = card_bot "\033[0m"

      max_w = (use_card ? cols - 6 : cols - 2)
      if (max_w < 20) max_w = 20

      in_code = 0
      prev_line_empty = 0
      is_first = 1
      prev_was_cmd = 0
      prev_bullet_colon = 0

      if (use_card) {
        print card_top
        print border_color "│\033[0m"
      }
    }

    /^```/ {
      if (in_code == 0) {
        in_code = 1
        print_card_line("   \033[32m")
        prev_line_empty = 0
      } else {
        in_code = 0
        print_card_line("\033[0m")
        prev_line_empty = 1
      }
      is_first = 0
      prev_was_cmd = 0
      prev_bullet_colon = 0
      next
    }

    in_code == 1 {
      print_card_line("   " $0)
      prev_line_empty = 0
      prev_was_cmd = 0
      prev_bullet_colon = 0
      next
    }

    /^(#{2,3} |# [A-Z0-9])/ {
      sub(/^#{1,3} /, "")
      h = format_inline($0)
      if (!is_first && prev_line_empty == 0) print_card_line("")
      print_card_line("\033[1;36m" h "\033[0m")
      is_first = 0
      prev_line_empty = 0
      prev_was_cmd = 0
      prev_bullet_colon = 0
      next
    }

    /^---SOURCES---/ {
      if (!is_first && prev_line_empty == 0) print_card_line("")
      print_card_line(" \033[2;37m─── sources ───\033[0m")
      is_first = 0
      prev_line_empty = 0
      prev_was_cmd = 0
      prev_bullet_colon = 0
      next
    }

    /^[ \t]*(-|\*|•|[0-9]+\.) / {
      body = $0
      prefix1 = ""
      prefix2 = ""

      if (match(body, /^[ \t]*[0-9]+\. /)) {
        m = substr(body, RSTART, RLENGTH)
        sub(/^[ \t]*/, "", m)
        prefix1 = " \033[33m" m "\033[0m"
        prefix2 = sprintf("%*s", length(m) + 1, "")
        sub(/^[ \t]*[0-9]+\. /, "", body)
      } else {
        prefix1 = " \033[33m•\033[0m "
        prefix2 = "   "
        sub(/^[ \t]*(-|\*|•) /, "", body)
      }

      if (!is_first && compact == 0 && prev_line_empty == 0) {
        print_card_line("")
      }
      is_first = 0
      prev_line_empty = 0
      prev_was_cmd = 0

      if (body ~ /:[ \t]*$/) {
        prev_bullet_colon = 1
      } else {
        prev_bullet_colon = 0
      }

      print_wrapped(body, prefix1, prefix2, max_w)
      next
    }

    # Filter out bare language lines like "bash", "sh", "zsh"
    prev_bullet_colon == 1 && /^[ \t]*(bash|sh|zsh)[ \t]*$/ {
      next
    }

    /^[ \t]*(\$|(source|pkg|apt|git|tar|du|find|grep|cat|echo|log_[a-z]+|start_[a-z]+|stop_[a-z]+|clear_[a-z]+|mkdir|rm|chmod|chown|ss|netstat|ping|curl|wget)\b)/ || (prev_bullet_colon == 1 && $0 ~ /^[ \t]*[a-zA-Z0-9_\-\.\/]+/) {
      cmd = $0
      sub(/^[ \t]*\$?[ \t]*/, "", cmd)
      cmd = format_inline(cmd)
      print_wrapped_cmd(cmd, max_w)
      is_first = 0
      prev_line_empty = 0
      prev_was_cmd = 1
      prev_bullet_colon = 1
      next
    }

    /^[ \t]*# / {
      cmt = $0
      sub(/^[ \t]*# /, "", cmt)
      cmt = format_inline(cmt)
      print_card_line("   \033[2;3m# " cmt "\033[0m")
      is_first = 0
      prev_line_empty = 0
      prev_was_cmd = 1
      next
    }

    /^[ \t]*$/ {
      if (!is_first && prev_line_empty == 0) {
        print_card_line("")
        prev_line_empty = 1
      }
      prev_was_cmd = 0
      prev_bullet_colon = 0
      next
    }

    {
      is_first = 0
      prev_line_empty = 0
      prev_was_cmd = 0
      prev_bullet_colon = 0
      print_wrapped($0, "", "", max_w)
    }

    END {
      if (in_code == 1) {
        print_card_line("\033[0m")
      }
      if (use_card) {
        print border_color "│\033[0m"
        print card_bot
      }
    }
  ' <<< "$text")

  local line_count
  line_count=$(wc -l <<< "$formatted")

  if ((line_count > term_lines)) && [[ -t 1 && "${AI_RENDER_PAGER:-0}" == "1" ]] && command -v less > /dev/null 2>&1; then
    print -r -- "$formatted" | less -R -F -X
  else
    print -r -- "$formatted"
  fi
}

###################
# Gemini API client
###################
_ai_query_api() {
  setopt local_options no_xtrace
  local prompt_text="$1"
  local enable_search="${2:-0}"
  local silent="${3:-0}"
  local model="${GEMINI_MODEL:-$_ai_default_model}"
  local timeout=35
  ((silent == 1)) && timeout=6
  ((enable_search == 1)) && timeout=45

  local payload
  if ((enable_search == 1)); then
    payload=$(jq -n \
      --arg p "$prompt_text" \
      '{
        contents: [{parts: [{text: $p}]}],
        tools: [{"google_search":{}}]
      }')
  else
    payload=$(jq -n \
      --arg p "$prompt_text" \
      '{
        contents: [{parts: [{text: $p}]}]
      }')
  fi

  if ((silent == 0)); then
    if ((enable_search == 1)); then
      _ai_start_phased_spinner "searching"
    else
      _ai_start_phased_spinner "thinking"
    fi
  fi
  trap '_ai_stop_phased_spinner; trap - INT; return 130' INT

  local raw_stream=""
  local first_chunk=0
  local line

  while IFS= read -r line; do
    if ((first_chunk == 0)) && [[ "$line" == data:* ]]; then
      first_chunk=1
      ((silent == 0)) && _ai_set_phase "thinking"
    fi
    raw_stream+="$line"$'\n'
  done < <(curl -N -s \
    --max-time "$timeout" \
    --connect-timeout 4 \
    -H "x-goog-api-key: $GEMINI_API_KEY" \
    -H "Content-Type: application/json" \
    -X POST "https://generativelanguage.googleapis.com/v1beta/models/${model}:streamGenerateContent?alt=sse" \
    -d "$payload" 2> /dev/null)

  ((silent == 0)) && _ai_set_phase "formatting"

  local json_stream
  json_stream=$(grep '^data: ' <<< "$raw_stream" 2> /dev/null | sed 's/^data: //' | grep -v '^\[DONE\]$')

  local err_msg
  err_msg=$(jq -r '.error.message // empty' <<< "$raw_stream" 2> /dev/null)
  if [[ -z "$err_msg" && -n "$json_stream" ]]; then
    err_msg=$(jq -s -r 'map(.error.message // empty) | first // empty' <<< "$json_stream" 2> /dev/null)
  fi

  if [[ -n "$err_msg" ]]; then
    _ai_stop_phased_spinner
    trap - INT
    if ((enable_search == 1)) && [[ "$err_msg" == *"quota"* || "$err_msg" == *"rate"* || "$err_msg" == *"RESOURCE_EXHAUSTED"* ]]; then
      _ai_query_api "$prompt_text" 0 "$silent"
      return $?
    fi
    ((silent == 0)) && print -u2 "gemini api error: $err_msg"
    return 1
  fi

  if [[ -z "$json_stream" ]]; then
    _ai_stop_phased_spinner
    trap - INT
    ((silent == 0)) && print -u2 "network timeout or empty response from api"
    return 1
  fi

  local parsed_output
  parsed_output=$(jq -s -r '
    ([.[].candidates[0]?.content?.parts[]? | select(.thought != true) | .text // empty] | join("")) +
    (
      [.[].candidates[0]?.groundingMetadata?.groundingChunks[]? | select(.web != null and .web.uri != null) | "- " + (.web.title // "Source") + ": " + .web.uri] | unique |
      if length > 0 then "\n---SOURCES---\n" + join("\n") else "" end
    )
  ' <<< "$json_stream" 2> /dev/null)

  _ai_stop_phased_spinner
  trap - INT

  if [[ -z "$parsed_output" ]]; then
    ((silent == 0)) && print -u2 "empty parsed content from api stream"
    return 1
  fi

  print -r -- "$parsed_output"
}

####################
# Auto-correct query
####################
_gemini_query() {
  local failed="$1"
  local mode="${2:-error}"

  [[ "${AI_AUTOCORRECT_ENABLED:-0}" != "1" ]] && return 0
  _ai_gate_check 1 || return 0
  _ai_check_cooldown 3 || return 0

  local prompt_text
  if [[ "$mode" == "not_found" ]]; then
    prompt_text="Environment: Termux Android Zsh.
Failed: Command '$failed' not found.
Task: If '$failed' is an obvious typo of a common CLI tool (e.g. 'gti' -> 'git', 'pyhton' -> 'python', 'sl' -> 'ls'), output ONLY the corrected command preserving all arguments.
If the command is unknown, uninstalled, or not an obvious typo, output ONLY 'IGNORE'.
Rules: Single-line plain text only. No markdown, no quotes, no explanation."
  else
    prompt_text="Environment: Termux Android Zsh.
Failed: Command '$failed' returned error.
Task: If failure is an obvious syntax typo or flag typo (e.g. 'git cmomit', 'grep -nr'), output ONLY the corrected single-line command.
If it is a runtime failure, valid syntax, permission error, or logic error, output ONLY 'IGNORE'.
Rules: Single-line plain text only. No markdown, no quotes, no explanation."
  fi

  local raw_sugg
  raw_sugg=$(_ai_query_api "$prompt_text" 0 1)
  [[ -z "$raw_sugg" ]] && return 0

  local suggestion
  suggestion=$(grep -v '^```' <<< "$raw_sugg" | grep -v '^[[:space:]]*$' | head -n 1 | sed -e 's/^`//' -e 's/`$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^\$[[:space:]]*//')

  local upper_sugg="${(U)suggestion}"
  if [[ -n "$suggestion" && "$suggestion" != "$failed" && "$upper_sugg" != IGNORE* ]]; then
    print -r -- "$suggestion"
  fi
}

###################
# Command not found
###################
if ! (($+functions[_cnf_original])) && (($+functions[command_not_found_handler])); then
  functions -c command_not_found_handler _cnf_original
fi

command_not_found_handler() {
  local cmd="$1"
  local suggestion=""

  if [[ -o interactive && -t 0 && "${AI_AUTOCORRECT_ENABLED:-0}" == "1" ]]; then
    suggestion=$(_gemini_query "$*" "not_found")
  fi

  if [[ -n "$suggestion" ]]; then
    print -u2 "zsh: command not found: $cmd"
    print -u2 "correct: $suggestion"
    if read -q "?run it? [y/N] "; then
      print -u2 ""
      _AI_SKIP_STATUS_RECORD=0
      _AI_LAST_CMD="$suggestion"
      eval "$suggestion"
      return $?
    fi
    print -u2 ""
    return 127
  fi

  if (($+functions[_cnf_original])); then
    _cnf_original "$@"
  else
    print -u2 "zsh: command not found: $cmd"
    return 127
  fi
}

######################
# Postcmd auto-correct
######################
_ai_postcmd_check() {
  local ret=$?
  ((ret == 0 || ret == 127 || ret >= 128)) && return
  [[ -o interactive ]] || return
  [[ ! -t 0 ]] && return
  [[ "${AI_AUTOCORRECT_ENABLED:-0}" != "1" ]] && return

  local lastcmd="$(fc -ln -1)"
  [[ -z "$lastcmd" ]] && return

  local trimmed="${lastcmd#"${lastcmd%%[![:space:]]*}"}"
  local base_cmd="${trimmed%% *}"
  case "$base_cmd" in
    cmd-do | cmd-fix | cmd-ask | ai-toggle | ai-model | ai-key | '\?\?' | '??') return ;;
  esac

  local suggestion=$(_gemini_query "$lastcmd")
  [[ -z "$suggestion" ]] && return

  print -u2 "correct: $suggestion"
  if read -q "?run it? [y/N] "; then
    print -u2 ""
    _AI_SKIP_STATUS_RECORD=0
    _AI_LAST_CMD="$suggestion"
    eval "$suggestion"
  else
    print -u2 ""
  fi
}
precmd_functions+=(_ai_postcmd_check)

###################
# Intent to command
###################
cmd-do() {
  if [[ $# -eq 0 ]]; then
    print -u2 "usage: cmd-do <intent description>"
    return 1
  fi

  _ai_gate_check 0 || return 1
  _ai_check_cooldown 2 || return 0

  local intent="$*"
  local dir="$PWD"

  local local_files
  local_files=$(ls -1pa 2> /dev/null | grep -vE '^(\.|\.\.|\.git/|\.env.*|\.pem|\.key|.*id_rsa.*)$' | head -n 20 | tr '\n' ', ')

  local prompt_text="Context: Termux/Android Zsh. Dir: $dir
Files: ${local_files:-none}
muxrc tools (use ONLY when capability and arguments match):
- video-compress <file>: compress single video to HEVC in-place (ffmpeg crf 18)
- clean-meta <dir>: strip EXIF/GPS metadata from media directory (saves to ~/muxrc-out/stripped)
- spoof-meta <preset> <file>: inject camera EXIF tags into image (preset: iphone-nyc)
- date-sync <file_or_dir>: sync file internal dates with filesystem modify date
- rename-by-date <dir> <prefix>: rename media in dir to prefix_YYYYMMDD_HHMMSS
- clean-dupes <dir>: scan directory and delete duplicate files by sha256 hash
- shred-file <file>: securely wipe and overwrite single file (shred 3x)
- media-crypt <file>: encrypt file with AES-256 (prompts password, saves to vault)
- media-decrypt <file.enc> [out]: decrypt AES-256 encrypted file (prompts password)
- stego-vault: interactive wizard to hide/extract secret in image (no args)
- trash <file...>: move file(s) safely to trash bin instead of rm
- untrash: interactive fzf restore from trash (no args)
- notify-task <cmd...>: run long command and send Android notification/vibration
- net-info: show local Wi-Fi IP and SSH connection string (no args)
- net-sweep: scan local Wi-Fi subnet hosts and MAC addresses (no args)
- clip-pick: fuzzy-search and restore clipboard history (no args)
- ex <archive>: extract any archive format (.zip, .tar.*, .7z, .rar)
- tor-start / tor-stop / tor-check: manage background Tor proxy daemon (no args)
- tor-run <cmd...>: run command routed through Tor proxy
- su / sudo <cmd...>: run command with root privileges
- ai-toggle: toggle Gemini AI assistant and auto-correct on/off (no args)
- ai-model [name]: view or switch active Gemini model (preset: gemini-3.5-flash-lite, gemini-2.5-flash)
Request: $intent
Rules:
1. Decision: If intent matches a muxrc tool, output that tool with exact arguments. Otherwise, output standard Termux/Linux command (pkg, git, curl, find, etc.). Never force muxrc tools.
2. Target: Use real filename from Files if matching. NEVER output placeholders like '<file>' or '[file]'.
3. Termux specifics: Use 'pkg' for packages, not 'apt'. No systemd/systemctl.
4. Output: Reply ONLY the single-line shell command. No markdown, no quotes, no explanation."

  local raw_cmd
  raw_cmd=$(_ai_query_api "$prompt_text" 0)

  if [[ -z "$raw_cmd" ]]; then
    return 1
  fi

  local sanitized_cmd
  sanitized_cmd=$(grep -v '^```' <<< "$raw_cmd" | grep -v '^[[:space:]]*$' | head -n 1 | sed -e 's/^`//' -e 's/`$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^\$[[:space:]]*//')

  if [[ -n "$sanitized_cmd" ]]; then
    print -u2 "command: $sanitized_cmd"
    if read -q "?run it? [y/N] "; then
      print -u2 ""
      _AI_SKIP_STATUS_RECORD=0
      _AI_LAST_CMD="$sanitized_cmd"
      eval "$sanitized_cmd"
      return $?
    else
      print -u2 ""
      return 0
    fi
  fi
}

#####################
# Runtime error fixer
#####################
cmd-fix() {
  _ai_gate_check 0 || return 1

  local user_hint="${*:-}"
  local piped_hint=""
  if [[ ! -t 0 ]]; then
    piped_hint=$(cat 2> /dev/null | head -c 16384)
  fi

  if [[ -z "$_AI_LAST_CMD" && -z "$piped_hint" ]]; then
    print -u2 "no recorded previous command to diagnose"
    return 0
  fi

  if [[ -z "$piped_hint" ]]; then
    if ((_AI_LAST_STATUS == 0)); then
      print -u2 "last command succeeded (exit code 0), nothing to fix"
      return 0
    fi

    if ((_AI_LAST_STATUS == 130)); then
      print -u2 "last command was cancelled by user (SIGINT)"
      return 0
    fi
  fi

  _ai_check_cooldown 2 || return 0

  local failed_cmd="${_AI_LAST_CMD:-piped input}"
  local exit_code="$_AI_LAST_STATUS"
  local dir="$PWD"

  local local_files
  local_files=$(ls -1pa 2> /dev/null | grep -vE '^(\.|\.\.|\.git/|\.env.*|\.pem|\.key|.*id_rsa.*)$' | head -n 20 | tr '\n' ', ')

  local hint_line=""
  if [[ -n "$user_hint" && -n "$piped_hint" ]]; then
    hint_line="Error hint: $user_hint"$'\n'"Piped error output:"$'\n'"$piped_hint"
  elif [[ -n "$piped_hint" ]]; then
    hint_line="Piped error output:"$'\n'"$piped_hint"
  elif [[ -n "$user_hint" ]]; then
    hint_line="Error hint: $user_hint"
  fi

  local prompt_text="Context: Termux/Android Zsh. Dir: $dir
Files: ${local_files:-none}
Failed: '$failed_cmd' (exit code $exit_code)
${hint_line}
Rules:
1. Diagnosis: Factual cause from command, exit code, and hint. If uncertain without logs, state most probable cause.
2. Safety: Suggest safe fix using 'pkg' if missing tool. NEVER suggest destructive flags (--force, -f, rm) unless hint explicitly requires it.
Format:
CAUSE: <1-sentence factual cause>
FIX: <single-line shell command using 'pkg' if package is needed>"

  local response
  response=$(_ai_query_api "$prompt_text" 0)

  if [[ -z "$response" ]]; then
    return 1
  fi

  local cause=""
  local fix_cmd=""
  local line

  while IFS= read -r line; do
    case "$line" in
      [Cc][Aa][Uu][Ss][Ee]:*)
        cause="${line#*:}"
        cause="${cause#"${cause%%[![:space:]]*}"}"
        ;;
      [Ff][Ii][Xx]:*)
        fix_cmd="${line#*:}"
        fix_cmd="${fix_cmd#"${fix_cmd%%[![:space:]]*}"}"
        ;;
    esac
  done <<< "$response"

  if [[ -n "$cause" ]]; then
    print -u2 "cause: $cause"
  fi

  if [[ -n "$fix_cmd" ]]; then
    local sanitized_fix
    sanitized_fix=$(grep -v '^```' <<< "$fix_cmd" | grep -v '^[[:space:]]*$' | head -n 1 | sed -e 's/^`//' -e 's/`$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^\$[[:space:]]*//')
    if [[ -n "$sanitized_fix" ]]; then
      print -u2 "correct: $sanitized_fix"
      if read -q "?run it? [y/N] "; then
        print -u2 ""
        _AI_SKIP_STATUS_RECORD=0
        _AI_LAST_CMD="$sanitized_fix"
        eval "$sanitized_fix"
        return $?
      else
        print -u2 ""
        return 0
      fi
    fi
  fi
}

alias '??'='cmd-fix'

#####################
# Context file reader
#####################
_ai_read_file_content() {
  local target="$1"
  local max_bytes="${2:-65536}"

  [[ ! -f "$target" || ! -r "$target" || ! -s "$target" ]] && return 1

  case "$target" in
    */.git/* | *.git* | */.ssh/* | *.netrc* | *history* | */secrets/*)
      return 1
      ;;
  esac

  case "${target:t}" in
    *.env* | *.pem | *.key | *id_rsa* | *id_ed25519* | *credentials* | *token* | .netrc | *secret*)
      return 1
      ;;
  esac

  if ! grep -q -I . "$target" 2> /dev/null; then
    return 1
  fi

  local size=0
  size=$(wc -c < "$target" 2> /dev/null | tr -d ' ')
  [[ "$size" =~ ^[0-9]+$ ]] || return 1

  if ((size > max_bytes)); then
    local head_content tail_content
    head_content=$(head -n 50 "$target" 2> /dev/null | awk '{if (length($0) > 500) $0 = substr($0, 1, 500) "... [truncated]"; printf "%4d: %s\n", NR, $0}')
    local total_lines=0
    total_lines=$(wc -l < "$target" 2> /dev/null | tr -d ' ')
    if ((total_lines > 50)); then
      local offset=$((total_lines - 50))
      tail_content=$(tail -n 50 "$target" 2> /dev/null | awk -v offset="$offset" '{if (length($0) > 500) $0 = substr($0, 1, 500) "... [truncated]"; printf "%4d: %s\n", offset + NR, $0}')
      print -r -- "File: $target (truncated: ${size} bytes, ${total_lines} lines)"$'\n'"--- HEAD (lines 1-50) ---"$'\n'"${head_content}"$'\n'"... [middle content skipped for context efficiency] ..."$'\n'"--- TAIL (last 50 lines) ---"$'\n'"${tail_content}"$'\n'"--- END ---"
    else
      print -r -- "File: $target (truncated: ${size} bytes, ${total_lines} lines)"$'\n'"--- CONTENT (first 50 lines) ---"$'\n'"${head_content}"$'\n'"--- END ---"
    fi
    return 0
  fi

  local full_content
  full_content=$(awk '{if (length($0) > 500) $0 = substr($0, 1, 500) "... [truncated]"; printf "%4d: %s\n", NR, $0}' "$target" 2> /dev/null)
  print -r -- "File: $target (full content, ${size} bytes):"$'\n'"---"$'\n'"${full_content}"$'\n'"---"
  return 0
}

######################
# Project Q&A & Search
######################
cmd-ask() {
  local query="$*"
  local piped_input=""

  if [[ ! -t 0 ]]; then
    piped_input=$(cat 2> /dev/null | head -c 65536)
  fi

  if [[ -z "$query" && -z "$piped_input" ]]; then
    print -u2 "usage: cmd-ask <question or task> (or: pipe text into cmd-ask)"
    return 1
  fi

  _ai_gate_check 0 || return 1
  _ai_check_cooldown 2 || return 0

  local dir="$PWD"

  local project_files=""
  project_files=$(find . -mindepth 1 -maxdepth 2 \
    -not -path '*/.*' \
    -not -path '*node_modules*' \
    -not -path '*build*' \
    -not -path '*dist*' \
    -not -path '*venv*' \
    -not -path '*cache*' \
    -not -name '*.env*' \
    -not -name '*.pem*' \
    -not -name '*.key*' \
    -not -name '*id_rsa*' \
    2> /dev/null | head -n 25 | tr '\n' ', ')

  local git_info=""
  if command -v git > /dev/null 2>&1 && git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    local branch
    branch=$(git branch --show-current 2> /dev/null)
    local git_status
    git_status=$(git status -s 2> /dev/null | head -n 8 | tr '\n' '; ')
    git_info="Git branch: ${branch:-detached}; Modified: ${git_status:-clean}"
  fi

  local attached_context=""
  if [[ -n "$piped_input" ]]; then
    attached_context+="Piped STDIN input:"$'\n'"---"$'\n'"${piped_input}"$'\n'"---"$'\n\n'
  fi

  if [[ -n "$query" ]]; then
    local -a mentioned_files=()
    local word
    for word in ${(z)query}; do
      local clean_word="${word#[\'\"]}"
      clean_word="${clean_word%[\'\"]}"
      clean_word="${clean_word%[,:.\?!]}"
      clean_word="${clean_word%[\'\"]}"
      if [[ -n "$clean_word" && -f "$clean_word" && -r "$clean_word" ]]; then
        if ((${#mentioned_files} < 3 && ${mentioned_files[(Ie)$clean_word]} == 0)); then
          mentioned_files+=("$clean_word")
          local file_ctx
          file_ctx=$(_ai_read_file_content "$clean_word")
          if [[ -n "$file_ctx" ]]; then
            attached_context+="${file_ctx}"$'\n\n'
          fi
        fi
      fi
    done
  fi

  local prompt_text="Context: Termux/Android Zsh. Dir: $dir. ${git_info}
Files: ${project_files:-none}
${attached_context}Question: ${query:-Analyze or explain the attached input}
Rules:
1. Compatibility: Answers MUST work in Termux (Android). Use 'pkg' (not apt-get), no systemd/systemctl.
2. Tone: Actionable, factual, strictly concise. Flat bullets (-), commands formatted with '$ ...'. Break long commands with backslash (\).
3. Output: No markdown tables, no conversational filler or greetings."

  local enable_search=1
  [[ -n "$attached_context" ]] && enable_search=0

  local response
  response=$(_ai_query_api "$prompt_text" "$enable_search")

  if [[ -z "$response" ]]; then
    return 1
  fi

  _ai_render "$response"
}

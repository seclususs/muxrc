#!/data/data/com.termux/files/usr/bin/bash

###########
# Formatter
###########

#######################################
# Truncates string to fit Termux bounds
#######################################
format_truncate() {
  local text="${1:-}"
  local max_len="${2:-60}"

  if [[ ! "${max_len}" =~ ^[0-9]+$ ]] || [[ "${max_len}" -le 0 ]]; then
    max_len=60
  fi

  if [[ ${#text} -gt ${max_len} ]]; then
    echo "${text:0:${max_len}}..."
  else
    echo "${text}"
  fi
}

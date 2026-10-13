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

#################################
# Formats bytes to human readable
#################################
format_bytes() {
  local bytes="${1:-0}"

  if [[ ! "${bytes}" =~ ^[0-9]+$ ]]; then
    echo "0 B"
    return 0
  fi

  if command -v numfmt > /dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "${bytes}" 2> /dev/null || echo "${bytes} B"
  elif command -v awk > /dev/null 2>&1; then
    awk -v b="${bytes}" 'BEGIN {
      if (b < 1024) printf "%d B\n", b;
      else if (b < 1048576) printf "%.2f KiB\n", b / 1024;
      else if (b < 1073741824) printf "%.2f MiB\n", b / 1048576;
      else printf "%.2f GiB\n", b / 1073741824;
    }'
  else
    echo "${bytes} B"
  fi
}

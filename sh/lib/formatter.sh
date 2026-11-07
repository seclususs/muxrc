#!/data/data/com.termux/files/usr/bin/sh

###########
# Formatter
###########

#######################################
# Truncates string to fit Termux bounds
#######################################
format_truncate() {
  local text="${1:-}"
  local max_len="${2:-60}"

  case "${max_len}" in
    '' | *[!0-9]*) max_len=60 ;;
    *)
      if [ "${max_len}" -le 0 ]; then
        max_len=60
      fi
      ;;
  esac

  if [ "${#text}" -gt "${max_len}" ]; then
    printf '%s...\n' "$(printf '%s' "${text}" | cut -c 1-"${max_len}")"
  else
    printf '%s\n' "${text}"
  fi
}

#################################
# Formats bytes to human readable
#################################
format_bytes() {
  local bytes="${1:-0}"

  case "${bytes}" in
    '' | *[!0-9]*)
      printf '0 B\n'
      return 0
      ;;
  esac

  if command -v numfmt > /dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "${bytes}" 2> /dev/null || printf '%s B\n' "${bytes}"
  elif command -v awk > /dev/null 2>&1; then
    awk -v b="${bytes}" 'BEGIN {
      if (b < 1024) printf "%d B\n", b;
      else if (b < 1048576) printf "%.2f KiB\n", b / 1024;
      else if (b < 1073741824) printf "%.2f MiB\n", b / 1048576;
      else printf "%.2f GiB\n", b / 1073741824;
    }'
  else
    printf '%s B\n' "${bytes}"
  fi
}

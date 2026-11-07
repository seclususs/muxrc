#!/data/data/com.termux/files/usr/bin/sh

#########
# loggers
#########
log_info() { printf '%b[*]%b %s\n' "${C_BLUE:-}" "${C_RESET:-}" "$*" >&2; }
log_success() { printf '%b[+]%b %s\n' "${C_GREEN:-}" "${C_RESET:-}" "$*" >&2; }
log_warn() { printf '%b[-]%b %s\n' "${C_YELLOW:-}" "${C_RESET:-}" "$*" >&2; }
log_error() { printf '%b[!]%b %s\n' "${C_RED:-}" "${C_RESET:-}" "$*" >&2; }
log_prompt() { printf '%b[?]%b %s' "${C_CYAN:-}" "${C_RESET:-}" "$*" >&2; }

##################
# progress display
##################
log_progress() {
  local current="${1:-0}"
  local total="${2:-1}"
  local msg="${3:-processing}"
  local percent=0

  if [ "${total}" -gt 0 ]; then
    percent=$((current * 100 / total))
  fi

  printf "\r\033[K%b[*]%b %s... %d%% (%d/%d)" "${C_BLUE:-}" "${C_RESET:-}" "${msg}" "${percent}" "${current}" "${total}" >&2
}

clear_progress() {
  printf '\r\033[K' >&2
}

#########
# spinner
#########
SPINNER_PID=""

cleanup_spinner() {
  if [ -n "${SPINNER_PID:-}" ] && kill -0 "${SPINNER_PID}" 2> /dev/null; then
    kill -9 "${SPINNER_PID}" 2> /dev/null || true
  fi
  SPINNER_PID=""
  printf '\r\033[K' >&2
}

start_spinner() {
  local msg="${1:-}"
  local monitor_state=0
  case "$-" in
    *m*) monitor_state=1 ;;
  esac
  set +m

  (
    set -- "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"
    while :; do
      for frame in "$@"; do
        printf "\r%b[*]%b %s... %s" "${C_BLUE:-}" "${C_RESET:-}" "${msg}" "${frame}" >&2
        sleep 0.08
      done
    done
  ) &
  SPINNER_PID=$!

  # shellcheck disable=SC3044
  disown %% 2> /dev/null || disown "${SPINNER_PID}" 2> /dev/null || true

  if [ "${monitor_state}" -eq 1 ]; then set -m; fi
}

stop_spinner() {
  local spin_status="${1:-info}"
  local msg="${2:-}"
  local monitor_state=0
  case "$-" in
    *m*) monitor_state=1 ;;
  esac
  set +m

  if [ -n "${SPINNER_PID:-}" ] && kill -0 "${SPINNER_PID}" 2> /dev/null; then
    kill "${SPINNER_PID}" > /dev/null 2>&1
    wait "${SPINNER_PID}" 2> /dev/null || true
  fi
  SPINNER_PID=""

  if [ "${monitor_state}" -eq 1 ]; then set -m; fi
  printf '\r\033[K' >&2
  case "${spin_status}" in
    success) log_success "${msg}" ;;
    error | fail) log_error "${msg}" ;;
    warn) log_warn "${msg}" ;;
    *) log_info "${msg}" ;;
  esac
}

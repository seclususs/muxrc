#!/data/data/com.termux/files/usr/bin/bash

#########
# loggers
#########
log_info() { echo -e "${C_BLUE:-}[*]${C_RESET:-} $*" >&2; }
log_success() { echo -e "${C_GREEN:-}[+]${C_RESET:-} $*" >&2; }
log_warn() { echo -e "${C_YELLOW:-}[-]${C_RESET:-} $*" >&2; }
log_error() { echo -e "${C_RED:-}[!]${C_RESET:-} $*" >&2; }
log_prompt() { echo -ne "${C_CYAN:-}[?]${C_RESET:-} $*" >&2; }

##################
# progress display
##################
log_progress() {
  local current="${1:-0}"
  local total="${2:-1}"
  local msg="${3:-processing}"
  local percent=0

  if ((total > 0)); then
    percent=$((current * 100 / total))
  fi

  printf "\r\033[K${C_BLUE:-}[*]${C_RESET:-} %s... %d%% (%d/%d)" "${msg}" "${percent}" "${current}" "${total}" >&2
}

clear_progress() {
  echo -ne "\r\033[K" >&2
}

#########
# spinner
#########
SPINNER_PID=""

cleanup_spinner() {
  if [[ -n "${SPINNER_PID:-}" ]] && kill -0 "${SPINNER_PID}" 2> /dev/null; then
    kill -9 "${SPINNER_PID}" 2> /dev/null || true
  fi
  SPINNER_PID=""
  echo -ne "\r\033[K" >&2
}

start_spinner() {
  local msg="${1:-}"
  local -a frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local monitor_state=0
  [[ $- == *m* ]] && monitor_state=1
  set +m

  (
    while true; do
      for frame in "${frames[@]}"; do
        echo -ne "\r${C_BLUE:-}[*]${C_RESET:-} ${msg}... ${frame}" >&2
        sleep 0.08
      done
    done
  ) &
  SPINNER_PID=$!

  disown %% 2> /dev/null || disown "${SPINNER_PID}" 2> /dev/null || true

  if [[ ${monitor_state} -eq 1 ]]; then set -m; fi
}

stop_spinner() {
  local spin_status="${1:-info}"
  local msg="${2:-}"
  local monitor_state=0
  [[ $- == *m* ]] && monitor_state=1
  set +m

  if [[ -n "${SPINNER_PID:-}" ]] && kill -0 "${SPINNER_PID}" 2> /dev/null; then
    kill "${SPINNER_PID}" > /dev/null 2>&1
    wait "${SPINNER_PID}" 2> /dev/null || true
  fi
  SPINNER_PID=""

  if [[ ${monitor_state} -eq 1 ]]; then set -m; fi
  echo -ne "\r\033[K" >&2
  if [[ "${spin_status}" == "success" ]]; then
    log_success "${msg}"
  elif [[ "${spin_status}" == "error" ]]; then
    log_error "${msg}"
  else
    log_info "${msg}"
  fi
}

#!/data/data/com.termux/files/usr/bin/bash

#################
# Tor OpSec Setup
#################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd tor shred
}

start_tor() {
  local opsec_dir="${1:-}"
  local torrc="${2:-}"
  local tor_data="${3:-}"
  local pid_file="${4:-}"

  if [[ -z "${opsec_dir}" || -z "${torrc}" || -z "${tor_data}" || -z "${pid_file}" ]]; then
    log_error "missing tor configuration parameters."
    return 1
  fi

  local tpid=""

  mkdir -p "${tor_data}"

  log_info "generating config..."
  cat << EOF > "${torrc}"
SocksPort 127.0.0.1:9050
DNSPort 127.0.0.1:5353
DataDirectory ${tor_data}
PidFile ${pid_file}
EOF

  log_info "spawning tor..."
  tor -f "${torrc}" > "${opsec_dir}/tor.log" 2>&1 &

  trap 'cleanup_spinner' EXIT
  start_spinner "waiting for tor"
  sleep 2

  if [[ -f "${pid_file}" ]]; then
    tpid=$(cat "${pid_file}")
    stop_spinner "success" "tor spawned (pid: ${tpid}). proxy: 127.0.0.1:9050"
    trap - EXIT
    return 0
  else
    stop_spinner "error" "failed to spawn tor. check log"
    trap - EXIT
    return 1
  fi
}

terminate_tor_process() {
  local tpid="${1:-}"

  if [[ -z "${tpid}" ]]; then
    return 1
  fi

  local i

  if ! kill -0 "${tpid}" 2> /dev/null; then
    log_warn "tor ${tpid} no longer running."
    return 0
  fi

  trap 'cleanup_spinner' EXIT
  start_spinner "terminating tor (pid: ${tpid})"
  kill -INT "${tpid}"

  for i in {1..10}; do
    if ! kill -0 "${tpid}" 2> /dev/null; then
      break
    fi
    sleep 1
  done

  if kill -0 "${tpid}" 2> /dev/null; then
    stop_spinner "error" "force killing tor..."
    kill -9 "${tpid}"
  else
    stop_spinner "success" "tor terminated."
  fi
  trap - EXIT
  return 0
}

shred_tor_state() {
  local opsec_dir="${1:-}"
  local torrc="${2:-}"
  local tor_data="${3:-}"
  local pid_file="${4:-}"

  if [[ -z "${opsec_dir}" || -z "${torrc}" || -z "${tor_data}" || -z "${pid_file}" ]]; then
    return 1
  fi

  trap 'cleanup_spinner' EXIT
  start_spinner "shredding state"

  [[ -f "${torrc}" ]] && shred -u "${torrc}" 2> /dev/null || true
  [[ -f "${pid_file}" ]] && shred -u "${pid_file}" 2> /dev/null || true
  [[ -f "${opsec_dir}/tor.log" ]] && shred -u "${opsec_dir}/tor.log" 2> /dev/null || true

  if [[ -d "${tor_data}" ]]; then
    find "${tor_data}" -type f -exec shred -u {} \; 2> /dev/null || true
    rm -rf "${tor_data}"
  fi

  stop_spinner "success" "tor stopped and shredded."
  trap - EXIT
}

stop_tor() {
  local opsec_dir="${1:-}"
  local torrc="${2:-}"
  local tor_data="${3:-}"
  local pid_file="${4:-}"

  if [[ -z "${opsec_dir}" || -z "${torrc}" || -z "${tor_data}" || -z "${pid_file}" ]]; then
    return 1
  fi

  local tpid=""

  if [[ ! -f "${pid_file}" ]]; then
    log_warn "pid file not found in ${opsec_dir}."
    log_warn "assume tor is stopped."
    return 0
  fi

  tpid=$(cat "${pid_file}")
  terminate_tor_process "${tpid}"
  shred_tor_state "${opsec_dir}" "${torrc}" "${tor_data}" "${pid_file}"
}

main() {
  local action="${1:-start}"
  local opsec_dir="${HOME}/.muxrc/run"
  local torrc="${opsec_dir}/torrc"
  local tor_data="${opsec_dir}/tor_data"
  local pid_file="${opsec_dir}/tor.pid"

  check_dependencies || exit 1

  if [[ "${action}" == "start" ]]; then
    start_tor "${opsec_dir}" "${torrc}" "${tor_data}" "${pid_file}" || exit 1
  elif [[ "${action}" == "stop" ]]; then
    stop_tor "${opsec_dir}" "${torrc}" "${tor_data}" "${pid_file}"
  else
    log_error "usage: $(basename "$0") {start|stop}"
    exit 1
  fi
}

main "$@"

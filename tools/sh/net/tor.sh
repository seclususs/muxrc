#!/data/data/com.termux/files/usr/bin/bash

#################
# Tor OpSec Setup
#################
set -euo pipefail

_script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
source "${_script_dir}/../../../lib/init.sh"
if [[ -f "${_script_dir}/../../../lib/shredder.sh" ]]; then
  source "${_script_dir}/../../../lib/shredder.sh"
fi

check_dependencies() {
  require_cmd tor
}

ensure_proxychains_config() {
  local cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/muxrc"
  local opsec_dir="${1:-${cache_dir}/run}"
  local run_pconf="${opsec_dir}/proxychains.conf"
  local user_pconf_dir="${HOME}/.proxychains"
  local user_pconf="${user_pconf_dir}/proxychains.conf"

  mkdir -p "${opsec_dir}"
  cat << 'EOF' > "${run_pconf}"
strict_chain
proxy_dns
quiet_mode
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000

[ProxyList]
socks5 127.0.0.1 9050
EOF
  chmod 600 "${run_pconf}"

  if [[ ! -s "${user_pconf}" ]]; then
    mkdir -p "${user_pconf_dir}"
    cp "${run_pconf}" "${user_pconf}"
    chmod 600 "${user_pconf}"
  fi
}

start_tor() {
  local opsec_dir="${1:-}"
  local torrc="${2:-}"
  local tor_data="${3:-}"
  local pid_file="${4:-}"

  if [[ -z "${opsec_dir}" || -z "${torrc}" || -z "${tor_data}" || -z "${pid_file}" ]]; then
    log_error "missing tor config params"
    return 1
  fi

  local existing_pid=""
  existing_pid=$(pgrep -x tor 2> /dev/null | head -n 1 || true)
  if [[ -n "${existing_pid}" ]]; then
    if [[ -f "${pid_file}" ]] && [[ "$(< "${pid_file}")" == "${existing_pid}" ]]; then
      log_warn "tor already running (pid: ${existing_pid})"
      return 0
    else
      log_error "external tor detected (pid: ${existing_pid}), stop it first"
      return 1
    fi
  fi

  local tpid=""
  local i=0

  mkdir -p "${tor_data}"
  chmod 700 "${tor_data}"
  rm -f "${pid_file}"

  ensure_proxychains_config "${opsec_dir}"

  log_info "generating torrc..."
  cat << EOF > "${torrc}"
SocksPort 127.0.0.1:9050 IsolateDestAddr IsolateDestPort
DNSPort 127.0.0.1:5353
ClientOnly 1
PublishServerDescriptor 0
SafeLogging 1
WarnUnsafeSocks 1
TestSocks 1
Log notice file /dev/null
DataDirectory ${tor_data}
PidFile ${pid_file}
EOF

  if ! tor --verify-config -f "${torrc}" > /dev/null 2>&1; then
    log_error "torrc syntax error"
    return 1
  fi

  log_info "spawning tor..."
  tor -f "${torrc}" > "${opsec_dir}/tor.log" 2>&1 &

  trap 'cleanup_spinner' EXIT
  start_spinner "waiting for tor"

  for ((i = 0; i < 50; i++)); do
    if [[ -f "${pid_file}" ]]; then
      tpid=$(cat "${pid_file}" 2> /dev/null || true)
      if [[ -n "${tpid}" ]] && kill -0 "${tpid}" 2> /dev/null; then
        stop_spinner "success" "tor spawned (pid: ${tpid}) at 127.0.0.1:9050"
        trap - EXIT
        return 0
      fi
    fi
    sleep 0.1
  done

  stop_spinner "error" "failed to spawn tor"
  trap - EXIT
  return 1
}

terminate_tor_process() {
  local tpid="${1:-}"

  if [[ -z "${tpid}" || ! "${tpid}" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  local i=0

  if ! kill -0 "${tpid}" 2> /dev/null; then
    log_warn "tor ${tpid} not running"
    return 0
  fi

  trap 'cleanup_spinner' EXIT
  start_spinner "stopping tor (pid: ${tpid})"
  kill -INT "${tpid}"

  for ((i = 0; i < 30; i++)); do
    if ! kill -0 "${tpid}" 2> /dev/null; then
      break
    fi
    sleep 0.1
  done

  if kill -0 "${tpid}" 2> /dev/null; then
    kill -9 "${tpid}" 2> /dev/null || true
  fi

  stop_spinner "success" "tor terminated"
  trap - EXIT
  return 0
}

shred_tor_state() {
  local opsec_dir="${1:-}"
  local torrc="${2:-}"
  local tor_data="${3:-}"
  local pid_file="${4:-}"

  trap 'cleanup_spinner' EXIT
  start_spinner "shredding tor state"

  [[ -f "${torrc}" ]] && shred_file "${torrc}" 1
  [[ -f "${pid_file}" ]] && shred_file "${pid_file}" 1
  [[ -f "${opsec_dir}/tor.log" ]] && shred_file "${opsec_dir}/tor.log" 1
  [[ -f "${opsec_dir}/proxychains.conf" ]] && shred_file "${opsec_dir}/proxychains.conf" 1

  if [[ -d "${tor_data}" ]]; then
    find "${tor_data}" -type f -exec shred -u {} \; 2> /dev/null || true
    rm -rf "${tor_data}"
  fi

  stop_spinner "success" "tor state shredded"
  trap - EXIT
}

stop_tor() {
  local opsec_dir="${1:-}"
  local torrc="${2:-}"
  local tor_data="${3:-}"
  local pid_file="${4:-}"

  local tpid=""

  if [[ ! -f "${pid_file}" ]]; then
    log_warn "tor pid file not found"
    shred_tor_state "${opsec_dir}" "${torrc}" "${tor_data}" "${pid_file}"
    return 0
  fi

  tpid=$(tr -d ' \n' < "${pid_file}" 2> /dev/null || true)
  if [[ -n "${tpid}" && "${tpid}" =~ ^[0-9]+$ ]]; then
    terminate_tor_process "${tpid}" || true
  fi
  shred_tor_state "${opsec_dir}" "${torrc}" "${tor_data}" "${pid_file}"
}

run_tor_command() {
  local opsec_dir="${1:-}"
  local torrc="${2:-}"
  local tor_data="${3:-}"
  local pid_file="${4:-}"
  shift 4

  if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "usage: net tor run <command> [args...]"
    return 0
  fi

  require_cmd proxychains4 || return 1

  local is_running=0
  if [[ -f "${pid_file}" ]]; then
    local tpid
    tpid=$(cat "${pid_file}" 2> /dev/null || true)
    if [[ -n "${tpid}" ]] && kill -0 "${tpid}" 2> /dev/null; then
      is_running=1
    fi
  fi

  if [[ ${is_running} -eq 0 ]]; then
    log_info "spawning tor session..."
    start_tor "${opsec_dir}" "${torrc}" "${tor_data}" "${pid_file}" || return 1
  fi

  local run_pconf="${opsec_dir}/proxychains.conf"
  if [[ -f "${run_pconf}" ]]; then
    proxychains4 -f "${run_pconf}" -q "$@"
  else
    proxychains4 -q "$@"
  fi
}

check_tor_connection() {
  local pid_file="${1:-}"

  require_cmd curl jq || return 1

  local is_running=0
  if [[ -f "${pid_file}" ]]; then
    local tpid
    tpid=$(cat "${pid_file}" 2> /dev/null || true)
    if [[ -n "${tpid}" ]] && kill -0 "${tpid}" 2> /dev/null; then
      is_running=1
    fi
  fi

  if [[ ${is_running} -eq 0 ]]; then
    log_warn "tor is not running (start via: net tor start)"
    return 1
  fi

  trap 'cleanup_spinner' EXIT
  start_spinner "checking tor routing"

  local response
  response=$(curl -s --max-time 15 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip 2> /dev/null || true)

  if [[ -z "${response}" ]]; then
    stop_spinner "error" "failed to reach tor check service"
    trap - EXIT
    return 1
  fi

  local is_tor exit_ip
  is_tor=$(echo "${response}" | jq -r '.IsTor // empty' 2> /dev/null)
  exit_ip=$(echo "${response}" | jq -r '.IP // empty' 2> /dev/null)

  if [[ "${is_tor}" == "true" ]]; then
    stop_spinner "success" "tor verified (exit ip: ${exit_ip})"
  else
    stop_spinner "warn" "not routed through tor (ip: ${exit_ip})"
  fi
  trap - EXIT
}

usage() {
  echo "usage: net tor <action> [args]"
  echo ""
  echo "actions:"
  echo "  start              spawn isolated tor daemon"
  echo "  stop               terminate tor & shred state"
  echo "  run <cmd> [args]   run command via proxychains"
  echo "  check              verify routing & exit ip"
}

main() {
  local action="${1:-start}"
  if [[ "${action}" == "-h" || "${action}" == "--help" ]]; then
    usage
    exit 0
  fi

  local cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/muxrc"
  local opsec_dir="${cache_dir}/run"
  local torrc="${opsec_dir}/torrc"
  local tor_data="${opsec_dir}/tor_data"
  local pid_file="${opsec_dir}/tor.pid"

  check_dependencies || exit 1

  case "${action}" in
    start)
      start_tor "${opsec_dir}" "${torrc}" "${tor_data}" "${pid_file}" || exit 1
      ;;
    stop)
      stop_tor "${opsec_dir}" "${torrc}" "${tor_data}" "${pid_file}"
      ;;
    run)
      shift
      run_tor_command "${opsec_dir}" "${torrc}" "${tor_data}" "${pid_file}" "$@"
      ;;
    check)
      check_tor_connection "${pid_file}"
      ;;
    *)
      log_error "unknown action: ${action} (see -h)"
      usage
      exit 1
      ;;
  esac
}

main "$@"

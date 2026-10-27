#!/data/data/com.termux/files/usr/bin/bash

#######################
# Network Identity Tool
#######################
set -euo pipefail

source "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")/../../lib/init.sh"

check_dependencies() {
  require_cmd ip awk
}

check_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "root access required. run via sudo: sudo net-identity"
    return 1
  fi
  return 0
}

detect_interface() {
  local iface="${1:-}"

  if [[ -n "${iface}" ]]; then
    if [[ ! -d "/sys/class/net/${iface}" ]] && ! ip link show "${iface}" > /dev/null 2>&1; then
      log_error "interface '${iface}' not found."
      return 1
    fi
    printf "%s\n" "${iface}"
    return 0
  fi

  local detected=""
  local dev_path
  for dev_path in /sys/class/net/wlan*; do
    if [[ -d "${dev_path}" ]]; then
      detected="${dev_path##*/}"
      break
    fi
  done

  if [[ -z "${detected}" ]]; then
    detected=$(ip -o link show 2> /dev/null | awk -F': ' '{print $2}' | grep -E '^wlan' | head -n 1 || true)
  fi

  if [[ -z "${detected}" ]]; then
    detected="wlan0"
  fi

  if [[ ! -d "/sys/class/net/${detected}" ]] && ! ip link show "${detected}" > /dev/null 2>&1; then
    log_error "no active wireless interface detected."
    return 1
  fi

  printf "%s\n" "${detected}"
  return 0
}

get_current_mac() {
  local iface="${1}"
  local cur_mac=""

  if [[ -f "/sys/class/net/${iface}/address" ]]; then
    cur_mac=$(tr -d ' \n' < "/sys/class/net/${iface}/address" 2> /dev/null || true)
  fi

  if [[ -z "${cur_mac}" ]]; then
    cur_mac=$(ip -o link show "${iface}" 2> /dev/null | awk '{for(i=1;i<=NF;i++) if($i=="link/ether") print $(i+1)}' || true)
  fi

  printf "%s\n" "${cur_mac,,}"
}

get_hostname() {
  local h=""
  if command -v getprop > /dev/null 2>&1; then
    h=$(getprop net.hostname 2> /dev/null || true)
  fi

  if [[ -z "${h}" || "${h}" == "null" ]] && command -v settings > /dev/null 2>&1; then
    h=$(settings get global device_name 2> /dev/null || true)
  fi

  if [[ -z "${h}" || "${h}" == "null" ]] && [[ -f /proc/sys/kernel/hostname ]]; then
    h=$(tr -d ' \n' < /proc/sys/kernel/hostname 2> /dev/null || true)
  fi

  if [[ -z "${h}" || "${h}" == "null" ]]; then
    h="localhost"
  fi

  printf "%s\n" "${h}"
}

generate_hostname() {
  local -a prefixes=("android" "pixel" "galaxy" "device")
  local rand_idx=$((RANDOM % ${#prefixes[@]}))
  local prefix="${prefixes[rand_idx]}"

  local suffix=""
  if command -v openssl > /dev/null 2>&1; then
    suffix=$(openssl rand -hex 4 2> /dev/null || true)
  fi

  if [[ -z "${suffix}" || ${#suffix} -ne 8 ]]; then
    suffix=$(od -An -N4 -tx1 /dev/urandom 2> /dev/null | tr -d ' \n' || true)
  fi

  if [[ -z "${suffix}" || ${#suffix} -ne 8 ]]; then
    suffix=$(printf "%04x%04x" "$((RANDOM % 65536))" "$((RANDOM % 65536))")
  fi

  printf "%s-%s\n" "${prefix}" "${suffix}"
}

save_original_hostname() {
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local orig_file="${state_dir}/hostname_orig"

  if [[ -f "${orig_file}" ]]; then
    return 0
  fi

  local cur_host
  cur_host=$(get_hostname)

  if [[ -n "${cur_host}" && "${cur_host}" != "localhost" ]]; then
    mkdir -p "${state_dir}"
    printf "%s\n" "${cur_host}" > "${orig_file}"
    chmod 600 "${orig_file}"
    log_info "saved factory hostname: ${cur_host}"
  fi
}

apply_hostname() {
  local new_host="${1}"

  save_original_hostname

  if command -v setprop > /dev/null 2>&1; then
    setprop net.hostname "${new_host}" > /dev/null 2>&1 || true
  fi

  if command -v settings > /dev/null 2>&1; then
    settings put global device_name "${new_host}" > /dev/null 2>&1 || true
  fi

  # Modern Android kernel hostname proc entry
  if [[ -w /proc/sys/kernel/hostname ]]; then
    printf "%s\n" "${new_host}" > /proc/sys/kernel/hostname 2> /dev/null || true
  fi

  log_info "updated hostname: ${new_host}"
}

get_ipv6_status() {
  local iface="${1}"
  local all_status="0"
  local iface_status="0"

  if [[ -f /proc/sys/net/ipv6/conf/all/disable_ipv6 ]]; then
    all_status=$(tr -d ' \n' < /proc/sys/net/ipv6/conf/all/disable_ipv6 2> /dev/null || echo "0")
  fi

  if [[ -f "/proc/sys/net/ipv6/conf/${iface}/disable_ipv6" ]]; then
    iface_status=$(tr -d ' \n' < "/proc/sys/net/ipv6/conf/${iface}/disable_ipv6" 2> /dev/null || echo "0")
  fi

  if [[ "${all_status}" == "1" || "${iface_status}" == "1" ]]; then
    printf "%s\n" "disabled (protected)"
  else
    printf "%s\n" "enabled (unprotected)"
  fi
}

set_ipv6_state() {
  local state="${1}"
  local iface="${2}"

  if [[ -w /proc/sys/net/ipv6/conf/all/disable_ipv6 ]]; then
    printf "%s\n" "${state}" > /proc/sys/net/ipv6/conf/all/disable_ipv6 2> /dev/null || true
  fi

  if [[ -w /proc/sys/net/ipv6/conf/default/disable_ipv6 ]]; then
    printf "%s\n" "${state}" > /proc/sys/net/ipv6/conf/default/disable_ipv6 2> /dev/null || true
  fi

  if [[ -w "/proc/sys/net/ipv6/conf/${iface}/disable_ipv6" ]]; then
    printf "%s\n" "${state}" > "/proc/sys/net/ipv6/conf/${iface}/disable_ipv6" 2> /dev/null || true
  fi

  if [[ "${state}" == "1" ]]; then
    log_info "ipv6 disabled (mitigating slaac and ipv6 dns leaks)"
  else
    log_info "ipv6 restored to enabled state"
  fi
}

set_wifi_framework_state() {
  local state="${1}"

  # Android 10+ uses cmd wifi; older Android uses svc wifi
  if command -v cmd > /dev/null 2>&1; then
    cmd wifi set-wifi-enabled "${state}" > /dev/null 2>&1 || true
  elif command -v svc > /dev/null 2>&1; then
    svc wifi "${state}" > /dev/null 2>&1 || true
  fi
}

flush_network_caches() {
  local iface="${1}"

  log_info "flushing neighbor and resolver caches..."
  if command -v ip > /dev/null 2>&1; then
    ip neigh flush all > /dev/null 2>&1 || true
  fi

  # Android low-level netd resolver flushes
  if command -v ndc > /dev/null 2>&1; then
    ndc resolver clearnetdns "${iface}" > /dev/null 2>&1 || true
    ndc resolver flushdefaultif > /dev/null 2>&1 || true
  fi
}

signal_tor() {
  local tor_pid
  tor_pid=$(pgrep -x tor 2> /dev/null | head -n 1 || true)

  if [[ -n "${tor_pid}" ]]; then
    log_info "sending sighup to tor (pid: ${tor_pid}) for fresh circuit..."
    kill -HUP "${tor_pid}" 2> /dev/null || true
    log_success "tor circuit reset signaled."
  fi
}

rotate_identity() {
  local iface="${1}"
  local custom_host="${2:-}"
  local keep_mac="${3:-false}"
  local keep_ipv6="${4:-false}"

  log_info "initiating network identity rotation on ${iface}..."

  # Hostname
  local target_host="${custom_host}"
  if [[ -z "${target_host}" ]]; then
    target_host=$(generate_hostname)
  fi
  apply_hostname "${target_host}"

  # IPv6 protection
  if [[ "${keep_ipv6}" != "true" ]]; then
    set_ipv6_state "1" "${iface}"
  fi

  # MAC address rotation
  local script_dir
  script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
  if [[ "${keep_mac}" != "true" ]]; then
    if [[ -f "${script_dir}/mac-spoof.sh" ]]; then
      log_info "rotating mac address..."
      bash "${script_dir}/mac-spoof.sh" random "${iface}"
    else
      log_warn "mac-spoof.sh not found in ${script_dir}, skipping mac rotation."
    fi
  else
    log_info "keeping existing mac address, resetting connection..."
    set_wifi_framework_state "disabled"
    sleep 0.5
    set_wifi_framework_state "enabled"
  fi

  # Flush caches
  flush_network_caches "${iface}"

  # Signal Tor if running
  signal_tor

  log_success "network identity rotation complete on ${iface}."
  show_status "${iface}"
}

reset_identity() {
  local iface="${1}"
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local orig_file="${state_dir}/hostname_orig"

  log_info "restoring factory network identity on ${iface}..."

  # Restore MAC
  local script_dir
  script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
  if [[ -f "${script_dir}/mac-spoof.sh" ]]; then
    bash "${script_dir}/mac-spoof.sh" reset "${iface}"
  fi

  # Restore Hostname
  if [[ -f "${orig_file}" ]]; then
    local orig_host
    orig_host=$(tr -d ' \n' < "${orig_file}" 2> /dev/null || true)
    if [[ -n "${orig_host}" ]]; then
      if command -v setprop > /dev/null 2>&1; then
        setprop net.hostname "${orig_host}" > /dev/null 2>&1 || true
      fi
      if command -v settings > /dev/null 2>&1; then
        settings put global device_name "${orig_host}" > /dev/null 2>&1 || true
      fi
      if [[ -w /proc/sys/kernel/hostname ]]; then
        printf "%s\n" "${orig_host}" > /proc/sys/kernel/hostname 2> /dev/null || true
      fi
      log_info "restored original hostname: ${orig_host}"
    fi
    rm -f "${orig_file}"
  fi

  # Restore IPv6
  set_ipv6_state "0" "${iface}"

  # Flush caches
  flush_network_caches "${iface}"

  # Signal Tor
  signal_tor

  log_success "network identity restored to factory defaults."
  show_status "${iface}"
}

show_status() {
  local iface="${1}"
  local mac_addr
  mac_addr=$(get_current_mac "${iface}")
  local host_name
  host_name=$(get_hostname)
  local ipv6_stat
  ipv6_stat=$(get_ipv6_status "${iface}")

  local tor_stat="stopped"
  local tor_pid
  tor_pid=$(pgrep -x tor 2> /dev/null | head -n 1 || true)
  if [[ -n "${tor_pid}" ]]; then
    tor_stat="running (pid: ${tor_pid})"
  fi

  printf "\n"
  printf "network identity: %s\n" "${iface}"
  printf "  mac address : %s\n" "${mac_addr:-unknown}"
  printf "  hostname    : %s\n" "${host_name}"
  printf "  ipv6 state  : %s\n" "${ipv6_stat}"
  printf "  tor daemon  : %s\n" "${tor_stat}"
  printf "\n"
}

usage() {
  echo "usage:"
  echo "  $(basename "$0") <command> [options] [interface]"
  echo ""
  echo "commands:"
  echo "  show [iface]"
  echo "      show current network identity and opsec state"
  echo ""
  echo "  rotate [options] [iface]"
  echo "      rotate mac, hostname, disable ipv6, flush caches"
  echo ""
  echo "  reset [iface]"
  echo "      restore factory mac, original hostname, re-enable ipv6"
  echo ""
  echo "  ipv6 {enable|disable|status} [iface]"
  echo "      toggle ipv6 leak protection explicitly"
  echo ""
  echo "rotate options:"
  echo "  --hostname <name>"
  echo "      set custom hostname instead of random"
  echo ""
  echo "  --keep-mac"
  echo "      rotate identity without changing mac"
  echo ""
  echo "  --keep-ipv6"
  echo "      keep current ipv6 state without disabling"
}

main() {
  local action="${1:-show}"
  if [[ "${action}" == "-h" || "${action}" == "--help" || "${action}" == "help" ]]; then
    usage
    exit 0
  fi

  check_dependencies || exit 1
  shift || true

  case "${action}" in
    show | status)
      local iface
      iface=$(detect_interface "${1:-}") || exit 1
      show_status "${iface}"
      ;;
    rotate)
      check_root || exit 1
      local custom_host=""
      local keep_mac="false"
      local keep_ipv6="false"
      local iface_arg=""

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --hostname)
            shift
            if [[ $# -eq 0 ]]; then
              log_error "--hostname requires an argument."
              exit 1
            fi
            custom_host="$1"
            ;;
          --keep-mac)
            keep_mac="true"
            ;;
          --keep-ipv6)
            keep_ipv6="true"
            ;;
          -*)
            log_error "unknown option: $1"
            usage
            exit 1
            ;;
          *)
            iface_arg="$1"
            ;;
        esac
        shift
      done

      local iface
      iface=$(detect_interface "${iface_arg}") || exit 1
      rotate_identity "${iface}" "${custom_host}" "${keep_mac}" "${keep_ipv6}"
      ;;
    reset)
      check_root || exit 1
      local iface
      iface=$(detect_interface "${1:-}") || exit 1
      reset_identity "${iface}"
      ;;
    ipv6)
      check_root || exit 1
      local sub="${1:-status}"
      shift || true
      local iface
      iface=$(detect_interface "${1:-}") || exit 1
      case "${sub}" in
        enable)
          set_ipv6_state "0" "${iface}"
          ;;
        disable)
          set_ipv6_state "1" "${iface}"
          ;;
        status)
          log_info "ipv6 status on ${iface}: $(get_ipv6_status "${iface}")"
          ;;
        *)
          log_error "usage: $(basename "$0") ipv6 {enable|disable|status} [interface]"
          exit 1
          ;;
      esac
      ;;
    -h | --help | help)
      usage
      ;;
    *)
      log_error "unknown command: ${action}"
      usage
      exit 1
      ;;
  esac
}

main "$@"

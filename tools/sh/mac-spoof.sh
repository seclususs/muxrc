#!/data/data/com.termux/files/usr/bin/bash

######################
# Wi-Fi MAC Spoof Tool
######################
set -euo pipefail

source "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")/../../lib/init.sh"

check_dependencies() {
  require_cmd ip awk
}

check_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "root access required. run via sudo: sudo mac-spoof"
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

generate_laa_mac() {
  local -a valid_laa=(2 6 a e)
  local rand_idx=$((RANDOM % 4))
  local n2="${valid_laa[rand_idx]}"
  local n1
  n1=$(printf "%x" "$((RANDOM % 16))")
  local b0="${n1}${n2}"

  local tail_hex=""
  if command -v openssl > /dev/null 2>&1; then
    tail_hex=$(openssl rand -hex 5 2> /dev/null || true)
  fi

  if [[ -z "${tail_hex}" || ${#tail_hex} -ne 10 ]]; then
    tail_hex=$(od -An -N5 -tx1 /dev/urandom 2> /dev/null | tr -d ' \n' || true)
  fi

  if [[ -z "${tail_hex}" || ${#tail_hex} -ne 10 ]]; then
    tail_hex=$(printf "%02x%02x%02x%02x%02x" "$((RANDOM % 256))" "$((RANDOM % 256))" "$((RANDOM % 256))" "$((RANDOM % 256))" "$((RANDOM % 256))")
  fi

  printf "%s:%s:%s:%s:%s:%s\n" \
    "${b0}" \
    "${tail_hex:0:2}" \
    "${tail_hex:2:2}" \
    "${tail_hex:4:2}" \
    "${tail_hex:6:2}" \
    "${tail_hex:8:2}"
}

validate_mac() {
  local mac="${1:-}"
  local mac_regex='^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'

  if [[ ! "${mac}" =~ ${mac_regex} ]]; then
    log_error "invalid mac address format: ${mac}"
    return 1
  fi

  local lower_mac="${mac,,}"
  if [[ "${lower_mac}" == "00:00:00:00:00:00" || "${lower_mac}" == "ff:ff:ff:ff:ff:ff" ]]; then
    log_error "reserved broadcast/null mac cannot be used: ${mac}"
    return 1
  fi

  local first_byte="${mac%%:*}"
  local second_nibble="${first_byte:1:1}"
  if [[ "${second_nibble}" =~ [13579bdfBDF] ]]; then
    log_error "multicast mac address not allowed: ${mac}"
    return 1
  fi

  return 0
}

save_original_mac() {
  local iface="${1}"
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local orig_file="${state_dir}/mac_orig_${iface}"

  if [[ -f "${orig_file}" ]]; then
    return 0
  fi

  local cur_mac
  cur_mac=$(get_current_mac "${iface}")

  if [[ -n "${cur_mac}" ]]; then
    mkdir -p "${state_dir}"
    printf "%s\n" "${cur_mac}" > "${orig_file}"
    chmod 600 "${orig_file}"
    log_info "saved factory mac for ${iface}: ${cur_mac}"
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

apply_mac() {
  local iface="${1}"
  local new_mac="${2}"
  local cur_mac

  cur_mac=$(get_current_mac "${iface}")
  if [[ "${cur_mac}" == "${new_mac,,}" ]]; then
    log_warn "interface ${iface} already has address ${cur_mac}."
    return 0
  fi

  save_original_mac "${iface}"

  trap 'cleanup_spinner' EXIT
  start_spinner "changing mac on ${iface}"

  set_wifi_framework_state "disabled"
  sleep 0.5

  ip link set dev "${iface}" down > /dev/null 2>&1 || true
  sleep 0.2

  local set_ok=0
  if ip link set dev "${iface}" address "${new_mac}" > /dev/null 2>&1; then
    set_ok=1
  elif command -v busybox > /dev/null 2>&1 && busybox ifconfig "${iface}" hw ether "${new_mac}" > /dev/null 2>&1; then
    set_ok=1
  elif command -v ifconfig > /dev/null 2>&1 && ifconfig "${iface}" hw ether "${new_mac}" > /dev/null 2>&1; then
    set_ok=1
  fi

  ip link set dev "${iface}" up > /dev/null 2>&1 || true
  set_wifi_framework_state "enabled"

  local verified_mac
  verified_mac=$(get_current_mac "${iface}")

  if [[ ${set_ok} -eq 1 && "${verified_mac}" == "${new_mac,,}" ]]; then
    stop_spinner "success" "mac changed on ${iface}: ${verified_mac}"
    trap - EXIT
    return 0
  else
    stop_spinner "error" "mac update refused by driver. active: ${verified_mac}"
    trap - EXIT
    return 1
  fi
}

show_status() {
  local iface="${1}"
  local cur_mac
  cur_mac=$(get_current_mac "${iface}")

  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local orig_file="${state_dir}/mac_orig_${iface}"
  local orig_mac="unknown"
  [[ -f "${orig_file}" ]] && orig_mac=$(tr -d ' \n' < "${orig_file}")

  local link_state="UNKNOWN"
  if [[ -f "/sys/class/net/${iface}/operstate" ]]; then
    link_state=$(tr -d ' \n' < "/sys/class/net/${iface}/operstate")
  fi

  local addr_type="Burned-in / Universal (BIA)"
  local first_byte="${cur_mac%%:*}"
  local second_nibble="${first_byte:1:1}"
  if [[ "${second_nibble}" =~ [26ae] ]]; then
    addr_type="Locally Administered / Spoofed (LAA)"
  fi

  printf "%-14s : %s\n" "interface" "${iface}"
  printf "%-14s : %s\n" "state" "${link_state^^}"
  printf "%-14s : %s\n" "active mac" "${cur_mac}"
  printf "%-14s : %s\n" "type" "${addr_type}"
  printf "%-14s : %s\n" "factory mac" "${orig_mac}"
}

reset_mac() {
  local iface="${1}"
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local orig_file="${state_dir}/mac_orig_${iface}"

  if [[ ! -f "${orig_file}" ]]; then
    log_error "no factory mac backup found for ${iface} in ${state_dir}."
    return 1
  fi

  local orig_mac
  orig_mac=$(tr -d ' \n' < "${orig_file}")
  validate_mac "${orig_mac}" || return 1

  log_info "restoring factory mac ${orig_mac} on ${iface}..."
  apply_mac "${iface}" "${orig_mac}"
}

usage() {
  echo "usage: $(basename "$0") {show|random|set <mac>|reset} [interface]"
  echo ""
  echo "commands:"
  echo "  show [iface]       show current mac, state, and address type"
  echo "  random [iface]     generate and apply a valid ieee 802 laa unicast mac"
  echo "  set <mac> [iface]  apply a custom mac address"
  echo "  reset [iface]      restore saved factory mac address"
}

main() {
  check_dependencies || exit 1

  local action="${1:-show}"
  shift || true

  case "${action}" in
    show)
      local iface
      iface=$(detect_interface "${1:-}") || exit 1
      show_status "${iface}"
      ;;
    random)
      check_root || exit 1
      local iface
      iface=$(detect_interface "${1:-}") || exit 1
      local target_mac
      target_mac=$(generate_laa_mac)
      apply_mac "${iface}" "${target_mac}"
      ;;
    set)
      check_root || exit 1
      local target_mac="${1:-}"
      if [[ -z "${target_mac}" ]]; then
        log_error "usage: $(basename "$0") set <mac_address> [interface]"
        exit 1
      fi
      shift
      validate_mac "${target_mac}" || exit 1
      local iface
      iface=$(detect_interface "${1:-}") || exit 1
      apply_mac "${iface}" "${target_mac}"
      ;;
    reset)
      check_root || exit 1
      local iface
      iface=$(detect_interface "${1:-}") || exit 1
      reset_mac "${iface}"
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

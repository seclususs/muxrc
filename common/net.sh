#!/data/data/com.termux/files/usr/bin/bash

###################
# Network utilities
###################

##################################
# Detect active wireless interface
##################################
detect_interface() {
  local iface="${1:-}"

  if [[ -n "${iface}" ]]; then
    if [[ ! -d "/sys/class/net/${iface}" ]] && ! ip link show "${iface}" > /dev/null 2>&1; then
      log_error "interface '${iface}' not found"
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
    log_error "no active wireless interface detected"
    return 1
  fi

  printf "%s\n" "${detected}"
  return 0
}

###################################
# Read current MAC address in lower
###################################
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

################################
# Toggle Android Wi-Fi framework
################################
set_wifi_framework_state() {
  local state="${1}"

  # Android 10+ uses cmd wifi; older Android uses svc wifi
  if command -v cmd > /dev/null 2>&1; then
    cmd wifi set-wifi-enabled "${state}" > /dev/null 2>&1 || true
  elif command -v svc > /dev/null 2>&1; then
    local svc_state="${state}"
    case "${state}" in
      enable | enabled) svc_state="enable" ;;
      disable | disabled) svc_state="disable" ;;
    esac
    svc wifi "${svc_state}" > /dev/null 2>&1 || true
  fi
}

###############################
# Flush neighbor and DNS caches
###############################
flush_network_caches() {
  local iface="${1}"

  log_info "flushing network caches..."
  if command -v ip > /dev/null 2>&1; then
    ip neigh flush all > /dev/null 2>&1 || true
  fi

  if command -v ndc > /dev/null 2>&1; then
    ndc resolver clearnetdns "${iface}" > /dev/null 2>&1 || true
    ndc resolver flushdefaultif > /dev/null 2>&1 || true
  fi
}

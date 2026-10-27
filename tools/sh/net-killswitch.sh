#!/data/data/com.termux/files/usr/bin/bash

#########################
# Network Killswitch Tool
#########################
set -euo pipefail

source "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")/../../lib/init.sh"

readonly CHAIN_NAME="MUXRC_KILLSWITCH"

get_iptables_bin() {
  if command -v iptables > /dev/null 2>&1; then
    command -v iptables
  elif [[ -x /system/bin/iptables ]]; then
    printf "%s\n" "/system/bin/iptables"
  fi
}

get_ip6tables_bin() {
  if command -v ip6tables > /dev/null 2>&1; then
    command -v ip6tables
  elif [[ -x /system/bin/ip6tables ]]; then
    printf "%s\n" "/system/bin/ip6tables"
  fi
}

check_dependencies() {
  local ipt
  ipt=$(get_iptables_bin)
  if [[ -z "${ipt}" ]]; then
    log_error "missing required command: iptables (install root-repo and iptables)"
    return 1
  fi
  return 0
}

check_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "root access required. run via sudo: sudo net-killswitch"
    return 1
  fi
  return 0
}

is_killswitch_active() {
  local ipt
  ipt=$(get_iptables_bin)
  if [[ -z "${ipt}" ]]; then
    return 1
  fi
  "${ipt}" -C OUTPUT -j "${CHAIN_NAME}" 2> /dev/null
}

add_state_rule() {
  local ipt="${1}"
  local chain="${2}"

  if "${ipt}" -A "${chain}" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2> /dev/null; then
    return 0
  fi

  if "${ipt}" -A "${chain}" -m state --state ESTABLISHED,RELATED -j ACCEPT 2> /dev/null; then
    return 0
  fi

  # Fallback when conntrack module is missing in stripped kernel
  log_warn "conntrack/state module unavailable in kernel, continuing without state rule."
  return 0
}

get_tor_uid() {
  local tor_pid
  tor_pid=$(pgrep -x tor 2> /dev/null | head -n 1 || true)

  if [[ -z "${tor_pid}" ]]; then
    return 1
  fi

  local tor_uid=""
  if [[ -r "/proc/${tor_pid}/status" ]]; then
    tor_uid=$(awk '/^Uid:/ {print $2}' "/proc/${tor_pid}/status" 2> /dev/null || true)
  fi

  if [[ -z "${tor_uid}" ]] && command -v stat > /dev/null 2>&1; then
    tor_uid=$(stat -c '%u' "/proc/${tor_pid}" 2> /dev/null || true)
  fi

  if [[ -z "${tor_uid}" ]]; then
    tor_uid=$(id -u 2> /dev/null || true)
  fi

  printf "%s\n" "${tor_uid}"
}

disable_killswitch_rules() {
  local ipt
  ipt=$(get_iptables_bin)
  local ip6
  ip6=$(get_ip6tables_bin)

  if [[ -n "${ipt}" ]]; then
    # Safely detach all jump hooks from OUTPUT
    while "${ipt}" -C OUTPUT -j "${CHAIN_NAME}" 2> /dev/null; do
      "${ipt}" -D OUTPUT -j "${CHAIN_NAME}" 2> /dev/null || break
    done
    "${ipt}" -F "${CHAIN_NAME}" 2> /dev/null || true
    "${ipt}" -X "${CHAIN_NAME}" 2> /dev/null || true
  fi

  if [[ -n "${ip6}" ]]; then
    while "${ip6}" -C OUTPUT -j "${CHAIN_NAME}" 2> /dev/null; do
      "${ip6}" -D OUTPUT -j "${CHAIN_NAME}" 2> /dev/null || break
    done
    "${ip6}" -F "${CHAIN_NAME}" 2> /dev/null || true
    "${ip6}" -X "${CHAIN_NAME}" 2> /dev/null || true
  fi

  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  rm -f "${state_dir}/killswitch_mode"
}

enable_killswitch() {
  local mode="${1:-block}"
  local allow_ssh="${2:-true}"
  local ssh_port="${3:-8022}"

  local ipt
  ipt=$(get_iptables_bin)
  local ip6
  ip6=$(get_ip6tables_bin)

  disable_killswitch_rules > /dev/null 2>&1 || true

  log_info "configuring killswitch in mode: ${mode}..."

  # Setup custom isolated chain
  "${ipt}" -N "${CHAIN_NAME}" 2> /dev/null || true
  "${ipt}" -F "${CHAIN_NAME}" 2> /dev/null || true

  # Loopback traffic
  "${ipt}" -A "${CHAIN_NAME}" -o lo -j ACCEPT

  # Established / related sockets
  add_state_rule "${ipt}" "${CHAIN_NAME}"

  # Exempt local SSH port to prevent terminal lockout
  if [[ "${allow_ssh}" == "true" && -n "${ssh_port}" ]]; then
    "${ipt}" -A "${CHAIN_NAME}" -p tcp --sport "${ssh_port}" -j ACCEPT 2> /dev/null || true
    "${ipt}" -A "${CHAIN_NAME}" -p tcp --dport "${ssh_port}" -j ACCEPT 2> /dev/null || true
    log_info "exempted ssh port ${ssh_port}"
  fi

  # Mode-specific egress filters
  case "${mode}" in
    tor)
      local tor_uid
      tor_uid=$(get_tor_uid) || true
      if [[ -z "${tor_uid}" ]]; then
        log_error "tor daemon is not running. start tor via 'tor-start' before enabling tor killswitch."
        disable_killswitch_rules > /dev/null 2>&1 || true
        return 1
      fi

      log_info "permitting tor egress (uid: ${tor_uid})..."
      "${ipt}" -A "${CHAIN_NAME}" -m owner --uid-owner "${tor_uid}" -j ACCEPT

      # Permit local loopback access to Tor ports
      "${ipt}" -A "${CHAIN_NAME}" -d 127.0.0.1 -p tcp --dport 9050 -j ACCEPT 2> /dev/null || true
      "${ipt}" -A "${CHAIN_NAME}" -d 127.0.0.1 -p udp --dport 5353 -j ACCEPT 2> /dev/null || true

      # Drop all non-Tor egress
      "${ipt}" -A "${CHAIN_NAME}" -j DROP
      ;;
    lan)
      log_info "permitting local rfc1918 subnets..."
      "${ipt}" -A "${CHAIN_NAME}" -d 10.0.0.0/8 -j ACCEPT
      "${ipt}" -A "${CHAIN_NAME}" -d 172.16.0.0/12 -j ACCEPT
      "${ipt}" -A "${CHAIN_NAME}" -d 192.168.0.0/16 -j ACCEPT
      "${ipt}" -A "${CHAIN_NAME}" -d 224.0.0.0/4 -j ACCEPT 2> /dev/null || true
      "${ipt}" -A "${CHAIN_NAME}" -j DROP
      ;;
    block | *)
      log_info "blocking all outbound wan traffic..."
      "${ipt}" -A "${CHAIN_NAME}" -j DROP
      ;;
  esac

  # Attach hook to top of OUTPUT chain
  "${ipt}" -I OUTPUT 1 -j "${CHAIN_NAME}"

  # Mirror drop policy on IPv6
  if [[ -n "${ip6}" ]]; then
    "${ip6}" -N "${CHAIN_NAME}" 2> /dev/null || true
    "${ip6}" -F "${CHAIN_NAME}" 2> /dev/null || true
    "${ip6}" -A "${CHAIN_NAME}" -o lo -j ACCEPT
    add_state_rule "${ip6}" "${CHAIN_NAME}"
    if [[ "${allow_ssh}" == "true" && -n "${ssh_port}" ]]; then
      "${ip6}" -A "${CHAIN_NAME}" -p tcp --sport "${ssh_port}" -j ACCEPT 2> /dev/null || true
      "${ip6}" -A "${CHAIN_NAME}" -p tcp --dport "${ssh_port}" -j ACCEPT 2> /dev/null || true
    fi
    "${ip6}" -A "${CHAIN_NAME}" -j DROP
    "${ip6}" -I OUTPUT 1 -j "${CHAIN_NAME}"
  fi

  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  mkdir -p "${state_dir}"
  printf "%s\n" "${mode}" > "${state_dir}/killswitch_mode"

  log_success "killswitch active (mode: ${mode})."
}

show_status() {
  local ipt
  ipt=$(get_iptables_bin)
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local mode="unknown"

  if [[ -f "${state_dir}/killswitch_mode" ]]; then
    mode=$(tr -d ' \n' < "${state_dir}/killswitch_mode" 2> /dev/null || echo "unknown")
  fi

  if is_killswitch_active; then
    printf "\n"
    printf "killswitch status: active\n"
    printf "  active mode : %s\n" "${mode}"
    printf "  firewall    : iptables (chain: %s)\n" "${CHAIN_NAME}"
    printf "\n"
    printf "packet drop statistics:\n"
    if [[ -n "${ipt}" ]]; then
      "${ipt}" -L "${CHAIN_NAME}" -v -n 2> /dev/null | awk '
        NR==1,NR==2 { print "  " $0 }
        /DROP/      { print "  " $0 }
      ' || true
    fi
    printf "\n"
  else
    printf "\n"
    printf "killswitch status: inactive\n"
    printf "  network traffic is operating normally (fail-open).\n"
    printf "\n"
  fi
}

toggle_killswitch() {
  if is_killswitch_active; then
    log_info "killswitch is currently active. disabling..."
    disable_killswitch_rules
    log_success "killswitch disabled."
  else
    log_info "killswitch is currently inactive. enabling (mode: block)..."
    enable_killswitch "block" "true" "8022"
  fi
}

usage() {
  echo "usage:"
  echo "  $(basename "$0") <command> [options]"
  echo ""
  echo "commands:"
  echo "  on [block|tor|lan]"
  echo "      enable killswitch (default: block)"
  echo ""
  echo "  off"
  echo "      disable killswitch and restore traffic"
  echo ""
  echo "  status"
  echo "      display active killswitch rules & counters"
  echo ""
  echo "  toggle"
  echo "      switch between active killswitch and off"
  echo ""
  echo "modes:"
  echo "  block"
  echo "      drop all outbound traffic except loopback & ssh"
  echo ""
  echo "  tor"
  echo "      allow only tor process egress and drop leaks"
  echo ""
  echo "  lan"
  echo "      allow local rfc1918 traffic and block wan"
  echo ""
  echo "options:"
  echo "  --no-ssh"
  echo "      do not exempt termux sshd port 8022"
  echo ""
  echo "  --ssh-port <port>"
  echo "      custom ssh port to keep open (default: 8022)"
}

main() {
  local action="${1:-status}"
  if [[ "${action}" == "-h" || "${action}" == "--help" || "${action}" == "help" ]]; then
    usage
    exit 0
  fi

  check_dependencies || exit 1
  shift || true

  case "${action}" in
    on)
      check_root || exit 1
      local mode="block"
      local allow_ssh="true"
      local ssh_port="8022"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          block | tor | lan)
            mode="$1"
            ;;
          --no-ssh)
            allow_ssh="false"
            ;;
          --ssh-port)
            shift
            if [[ $# -eq 0 ]]; then
              log_error "--ssh-port requires a port argument."
              exit 1
            fi
            ssh_port="$1"
            ;;
          -*)
            log_error "unknown option: $1"
            usage
            exit 1
            ;;
          *)
            log_error "unexpected argument: $1"
            usage
            exit 1
            ;;
        esac
        shift
      done

      enable_killswitch "${mode}" "${allow_ssh}" "${ssh_port}"
      ;;
    off | disable | reset)
      check_root || exit 1
      log_info "disabling killswitch..."
      disable_killswitch_rules
      log_success "killswitch disabled. normal routing restored."
      ;;
    status)
      show_status
      ;;
    toggle)
      check_root || exit 1
      toggle_killswitch
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

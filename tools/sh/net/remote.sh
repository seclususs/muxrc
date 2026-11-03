#!/data/data/com.termux/files/usr/bin/bash

################################
# Remote SSH & Multiplexer Tools
################################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../../lib/init.sh"

check_dependencies() {
  require_cmd sshd ssh-keygen awk grep
}

usage() {
  echo "usage: net remote <command> [args]"
  echo "secure ssh remote and persistent session management."
  echo ""
  echo "commands:"
  echo "  status               display sshd, wakelock, ip, and tmux status"
  echo "  setup                harden sshd config and configure permissions"
  echo "  pair [key|file]      register client public key into authorized_keys"
  echo "  sessions [subcmd]    manage tmux sessions (list, attach, kill)"
  echo "  start                start ssh daemon and acquire wake lock"
  echo "  stop                 stop ssh daemon and release wake lock"
}

get_sshd_port() {
  local config_file="${PREFIX:-/data/data/com.termux/files/usr}/etc/ssh/sshd_config"
  local port="8022"

  if [[ -f "${config_file}" ]]; then
    local configured_port
    configured_port=$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2; exit}' "${config_file}")
    if [[ -n "${configured_port}" ]]; then
      port="${configured_port}"
    fi
  fi

  printf "%s\n" "${port}"
}

status_remote() {
  log_info "remote service status"

  local port
  port=$(get_sshd_port)

  # SSH daemon status
  if pgrep -x sshd > /dev/null 2>&1; then
    local sshd_pid
    sshd_pid=$(pgrep -x sshd | head -n 1)
    log_success "sshd: active (pid ${sshd_pid}, listening on port ${port})"
  else
    log_warn "sshd: inactive (start with: net remote start)"
  fi

  # Wake lock status
  if pgrep -f "termux-wake-lock" > /dev/null 2>&1; then
    log_success "wake-lock: held (cpu sleep prevented)"
  elif [[ -f "/sys/power/wake_lock" ]] && grep -qi "termux" "/sys/power/wake_lock" 2> /dev/null; then
    log_success "wake-lock: active in kernel"
  else
    log_info "wake-lock: standard (acquire with: wakelock or net remote start)"
  fi

  # Network IP addresses
  local wifi_iface=""
  wifi_iface=$(detect_interface 2> /dev/null || true)
  local lan_ip=""

  if [[ -n "${wifi_iface}" ]]; then
    lan_ip=$(ip -4 -o addr show "${wifi_iface}" 2> /dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1 || true)
  fi

  if [[ -n "${lan_ip}" ]]; then
    log_info "lan ip (${wifi_iface}): ${lan_ip} -> ssh -p ${port} $(whoami)@${lan_ip}"
  else
    log_warn "lan ip: no wireless connection detected"
  fi

  # VPN / Mesh network addresses (Tailscale, WireGuard, Tun)
  local vpn_lines=""
  vpn_lines=$(ip -4 -o addr show 2> /dev/null | awk '$2 ~ /^(tailscale|tun|wg)/ {print $2 " " $4}' | cut -d/ -f1 || true)
  if [[ -n "${vpn_lines}" ]]; then
    while read -r vpn_iface vpn_addr; do
      if [[ -n "${vpn_iface}" && -n "${vpn_addr}" ]]; then
        log_info "vpn ip (${vpn_iface}): ${vpn_addr} -> ssh -p ${port} $(whoami)@${vpn_addr}"
      fi
    done <<< "${vpn_lines}"
  fi

  # Android 12+ Phantom Process Killer check
  local sdk_ver=""
  sdk_ver=$(getprop ro.build.version.sdk 2> /dev/null || true)
  if [[ -n "${sdk_ver}" ]] && ((sdk_ver >= 31)); then
    log_info "android ${sdk_ver}+: verify phantom process killer is disabled if running many panes"
  fi

  # Tmux sessions status
  if command -v tmux > /dev/null 2>&1; then
    if tmux list-sessions > /dev/null 2>&1; then
      echo ""
      log_info "active tmux sessions:"
      tmux list-sessions -F "  * #{session_name}: #{session_windows} window(s) (created #{session_created_string}) #{?session_attached,(attached),(detached)}" >&2
    else
      log_info "tmux: server running, no active sessions"
    fi
  else
    log_warn "tmux: not installed (pkg install tmux)"
  fi
}

set_config_value() {
  local file="${1}"
  local key="${2}"
  local value="${3}"

  if grep -qE "^[#[:space:]]*${key}[[:space:]]+" "${file}"; then
    sed -i "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "${file}"
  else
    echo "${key} ${value}" >> "${file}"
  fi
}

setup_remote() {
  log_info "hardening sshd configuration..."

  local ssh_dir="${PREFIX:-/data/data/com.termux/files/usr}/etc/ssh"
  local config_file="${ssh_dir}/sshd_config"

  if [[ ! -d "${ssh_dir}" ]]; then
    mkdir -p "${ssh_dir}"
  fi

  if [[ ! -f "${config_file}" ]]; then
    touch "${config_file}"
  fi

  # Apply hardened settings
  set_config_value "${config_file}" "Port" "8022"
  set_config_value "${config_file}" "PasswordAuthentication" "no"
  set_config_value "${config_file}" "PubkeyAuthentication" "yes"
  set_config_value "${config_file}" "PermitEmptyPasswords" "no"
  set_config_value "${config_file}" "ClientAliveInterval" "30"
  set_config_value "${config_file}" "ClientAliveCountMax" "3"

  log_success "sshd_config updated (port 8022, pubkey-only, keepalive active)."

  # Setup ~/.ssh directory with strict permissions
  local user_ssh="${HOME}/.ssh"
  local auth_keys="${user_ssh}/authorized_keys"

  mkdir -p "${user_ssh}"
  chmod 700 "${user_ssh}"

  if [[ ! -f "${auth_keys}" ]]; then
    touch "${auth_keys}"
  fi
  chmod 600 "${auth_keys}"

  log_success "ssh directory permissions secured (700 ~/.ssh, 600 authorized_keys)."
}

pair_client_key() {
  local target_key="${1:-}"
  local user_ssh="${HOME}/.ssh"
  local auth_keys="${user_ssh}/authorized_keys"

  if [[ -z "${target_key}" ]]; then
    log_prompt "paste client public key: "
    read -r target_key
    echo ""
  elif [[ -f "${target_key}" ]]; then
    target_key=$(< "${target_key}")
  fi

  # Trim leading/trailing whitespace
  target_key=$(echo "${target_key}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  if [[ -z "${target_key}" ]]; then
    log_error "empty public key provided."
    return 1
  fi

  # Validate OpenSSH key signature format
  local key_regex='^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]]+.*)?$'
  if [[ ! "${target_key}" =~ ${key_regex} ]]; then
    log_error "invalid openssh public key format."
    return 1
  fi

  mkdir -p "${user_ssh}"
  chmod 700 "${user_ssh}"
  touch "${auth_keys}"
  chmod 600 "${auth_keys}"

  # Extract key token without comment to prevent duplicates
  local key_token
  key_token=$(echo "${target_key}" | awk '{print $1 " " $2}')

  if grep -qF "${key_token}" "${auth_keys}" 2> /dev/null; then
    log_warn "public key is already present in authorized_keys."
    return 0
  fi

  echo "${target_key}" >> "${auth_keys}"
  log_success "public key successfully added to ${auth_keys}."

  local port
  port=$(get_sshd_port)
  local wifi_iface=""
  wifi_iface=$(detect_interface 2> /dev/null || true)
  local lan_ip="<device-ip>"
  if [[ -n "${wifi_iface}" ]]; then
    lan_ip=$(ip -4 -o addr show "${wifi_iface}" 2> /dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1 || true)
  fi

  log_info "you can now connect from client:"
  log_info "  ssh -p ${port} $(whoami)@${lan_ip:-<device-ip>}"
}

manage_sessions() {
  if ! command -v tmux > /dev/null 2>&1; then
    log_error "tmux is not installed (pkg install tmux)"
    return 1
  fi

  local action="${1:-list}"

  case "${action}" in
    list | ls)
      if tmux list-sessions > /dev/null 2>&1; then
        tmux list-sessions
      else
        log_info "no active tmux sessions."
      fi
      ;;
    attach | a)
      local session_name="${2:-main}"
      log_info "attaching to session '${session_name}'..."
      exec tmux new-session -A -s "${session_name}"
      ;;
    kill | k)
      local session_name="${2:-}"
      if [[ -z "${session_name}" ]]; then
        log_error "usage: net remote sessions kill <session-name>"
        return 1
      fi
      if tmux has-session -t "${session_name}" 2> /dev/null; then
        tmux kill-session -t "${session_name}"
        log_success "session '${session_name}' terminated."
      else
        log_error "session '${session_name}' not found."
        return 1
      fi
      ;;
    kill-all)
      tmux kill-server 2> /dev/null || true
      log_success "all tmux sessions terminated."
      ;;
    *)
      log_error "unknown session action: ${action} (use: list, attach, kill, kill-all)"
      return 1
      ;;
  esac
}

start_remote() {
  log_info "starting remote services..."

  if command -v termux-wake-lock > /dev/null 2>&1; then
    termux-wake-lock 2> /dev/null || true
    log_success "wake-lock acquired."
  fi

  if ! pgrep -x sshd > /dev/null 2>&1; then
    sshd
    log_success "sshd started."
  else
    log_info "sshd is already running."
  fi

  status_remote
}

stop_remote() {
  log_info "stopping remote services..."

  if pgrep -x sshd > /dev/null 2>&1; then
    pkill sshd 2> /dev/null || true
    log_success "sshd stopped."
  else
    log_info "sshd was not running."
  fi

  if command -v termux-wake-unlock > /dev/null 2>&1; then
    termux-wake-unlock 2> /dev/null || true
    log_success "wake-lock released."
  fi
}

main() {
  check_dependencies

  local cmd="${1:-status}"

  case "${cmd}" in
    -h | --help)
      usage
      return 0
      ;;
    status)
      status_remote
      ;;
    setup)
      setup_remote
      ;;
    pair)
      shift
      pair_client_key "${1:-}"
      ;;
    sessions)
      shift
      manage_sessions "${@}"
      ;;
    start)
      start_remote
      ;;
    stop)
      stop_remote
      ;;
    *)
      log_error "unknown command: ${cmd} (see: net remote -h)"
      return 1
      ;;
  esac
}

main "${@}"

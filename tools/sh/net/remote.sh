#!/data/data/com.termux/files/usr/bin/bash

################################
# Remote SSH & Multiplexer Tools
################################
set -euo pipefail

source "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")/../../../lib/init.sh"

check_dependencies() {
  require_cmd sshd ssh-keygen awk grep
}

usage() {
  echo "usage: net remote <command> [args]"
  echo ""
  echo "commands:"
  echo "  status               display status"
  echo "  setup                sshd config"
  echo "  pair [key|file]      register public key"
  echo "  config               open sshd cfg in editor"
  echo "  sessions [subcmd]    manage tmux sessions"
  echo "  start                start ssh daemon"
  echo "  stop                 stop ssh daemon"
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

_run_ip() {
  local ip_bin="ip"
  if ! command -v ip > /dev/null 2>&1; then
    if [[ -x "/system/bin/ip" ]]; then
      ip_bin="/system/bin/ip"
    else
      return 1
    fi
  fi

  local out=""
  out=$("${ip_bin}" "${@}" 2> /dev/null || true)
  if [[ -n "${out}" ]]; then
    printf "%s\n" "${out}"
    return 0
  fi

  if [[ "${EUID:-$(id -u)}" -ne 0 ]] && command -v su > /dev/null 2>&1; then
    local su_ip="/system/bin/ip"
    [[ -x "${su_ip}" ]] || su_ip="ip"
    out=$(su -c "${su_ip} $*" 2> /dev/null || true)
    if [[ -n "${out}" ]]; then
      printf "%s\n" "${out}"
      return 0
    fi
  fi

  return 1
}

get_device_ip() {
  local ip_addr=""

  ip_addr=$(_run_ip -4 route get 1.1.1.1 2> /dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}' || true)

  if [[ -z "${ip_addr}" ]]; then
    local iface
    iface=$(detect_interface 2> /dev/null || true)
    if [[ -n "${iface}" ]]; then
      ip_addr=$(_run_ip -4 -o addr show "${iface}" 2> /dev/null | awk '{print $4; exit}' | cut -d/ -f1 || true)
    fi
  fi

  if [[ -z "${ip_addr}" ]]; then
    ip_addr=$(_run_ip -4 -o addr show scope global 2> /dev/null | awk '$2 !~ /^(dummy|lo|tun|tailscale|wg)/ {print $4; exit}' | cut -d/ -f1 || true)
  fi

  if [[ -z "${ip_addr}" ]]; then
    ip_addr=$(getprop dhcp.wlan0.ipaddress 2> /dev/null || true)
  fi

  printf "%s\n" "${ip_addr}"
}

status_remote() {
  log_info "remote service status"

  local port
  port=$(get_sshd_port)
  local current_user="${USER:-$(whoami)}"

  if pgrep -x sshd > /dev/null 2>&1; then
    local sshd_pid
    sshd_pid=$(pgrep -x sshd | head -n 1)
    log_success "sshd: active (pid ${sshd_pid}, port ${port})"
  else
    log_warn "sshd: inactive"
  fi

  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  if [[ -f "${state_dir}/wakelock" ]]; then
    log_success "wake-lock: held"
  elif pgrep -u "${EUID:-$(id -u)}" -x termux-wake-lock > /dev/null 2>&1; then
    log_success "wake-lock: held"
  else
    log_info "wake-lock: standard"
  fi

  local lan_ip
  lan_ip=$(get_device_ip)
  if [[ -n "${lan_ip}" ]]; then
    log_info "ip: ${lan_ip} -> ssh -p ${port} ${current_user}@${lan_ip}"
  fi

  local vpn_lines=""
  vpn_lines=$(_run_ip -4 -o addr show 2> /dev/null | awk '$2 ~ /^(tailscale|tun|wg)/ {print $2 " " $4}' | cut -d/ -f1 || true)
  if [[ -n "${vpn_lines}" ]]; then
    while read -r vpn_iface vpn_addr; do
      if [[ -n "${vpn_iface}" && -n "${vpn_addr}" ]]; then
        log_info "vpn (${vpn_iface}): ${vpn_addr} -> ssh -p ${port} ${current_user}@${vpn_addr}"
      fi
    done <<< "${vpn_lines}"
  fi

  if [[ -z "${lan_ip}" && -z "${vpn_lines}" ]]; then
    log_warn "ip: no network connection"
  fi

  if command -v tmux > /dev/null 2>&1; then
    if tmux list-sessions > /dev/null 2>&1; then
      echo ""
      log_info "active tmux sessions:"
      tmux list-sessions -F "  * #{session_name}: #{session_windows} win #{?session_attached,(attached),(detached)}" >&2
    fi
  fi
}

set_config_value() {
  local file="${1}"
  local key="${2}"
  local value="${3}"

  if grep -qE "^[[:space:]]*${key}[[:space:]]+" "${file}"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]].*|${key} ${value}|" "${file}"
  elif grep -qE "^[[:space:]]*#[[:space:]]*${key}[[:space:]]+" "${file}"; then
    sed -i -E "0,/^[[:space:]]*#[[:space:]]*${key}[[:space:]].*/s|^[[:space:]]*#[[:space:]]*${key}[[:space:]].*|${key} ${value}|" "${file}"
  else
    printf "%s %s\n" "${key}" "${value}" >> "${file}"
  fi
}

setup_remote() {
  local ssh_dir="${PREFIX:-/data/data/com.termux/files/usr}/etc/ssh"
  local config_file="${ssh_dir}/sshd_config"

  if [[ ! -d "${ssh_dir}" ]]; then
    mkdir -p "${ssh_dir}"
  fi

  if [[ ! -f "${config_file}" ]]; then
    touch "${config_file}"
  fi

  set_config_value "${config_file}" "Port" "8022"
  set_config_value "${config_file}" "PasswordAuthentication" "no"
  set_config_value "${config_file}" "PubkeyAuthentication" "yes"
  set_config_value "${config_file}" "KbdInteractiveAuthentication" "no"
  set_config_value "${config_file}" "PermitEmptyPasswords" "no"
  set_config_value "${config_file}" "PermitRootLogin" "no"
  set_config_value "${config_file}" "MaxAuthTries" "3"
  set_config_value "${config_file}" "LoginGraceTime" "30"
  set_config_value "${config_file}" "X11Forwarding" "no"
  set_config_value "${config_file}" "AllowAgentForwarding" "no"
  set_config_value "${config_file}" "ClientAliveInterval" "30"
  set_config_value "${config_file}" "ClientAliveCountMax" "3"

  if ! compgen -G "${ssh_dir}/ssh_host_*_key" > /dev/null 2>&1; then
    ssh-keygen -A > /dev/null 2>&1 || true
  fi

  local user_ssh="${HOME}/.ssh"
  local auth_keys="${user_ssh}/authorized_keys"

  mkdir -p "${user_ssh}"
  chmod 700 "${user_ssh}"

  if [[ ! -f "${auth_keys}" ]]; then
    touch "${auth_keys}"
  fi
  chmod 600 "${auth_keys}"

  log_success "sshd configured"
}

pair_client_key() {
  local target_key="${*:-}"
  local user_ssh="${HOME}/.ssh"
  local auth_keys="${user_ssh}/authorized_keys"
  local key_regex='^(ssh-[a-z0-9-]+|ecdsa-[a-z0-9-]+|sk-[a-z0-9@.-]+)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]]+.*)?$'

  if [[ -z "${target_key}" ]] && command -v termux-clipboard-get > /dev/null 2>&1; then
    local clip_content
    clip_content=$(termux-clipboard-get 2> /dev/null | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' || true)
    if [[ -n "${clip_content}" && "${clip_content}" =~ ${key_regex} ]]; then
      log_prompt "use clipboard key? [y/N]: "
      local use_clip=""
      read -r use_clip || true
      if [[ "${use_clip}" =~ ^[Yy]$ ]]; then
        target_key="${clip_content}"
      fi
    fi
  fi

  if [[ -z "${target_key}" ]]; then
    log_prompt "paste public key: "
    read -r target_key
    echo ""
  elif [[ -f "${target_key}" ]]; then
    target_key=$(< "${target_key}")
  fi

  target_key=$(printf "%s\n" "${target_key}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^[[:space:]]*$' || true)

  if [[ -z "${target_key}" ]]; then
    log_error "empty public key."
    return 1
  fi

  local line_count
  line_count=$(printf "%s\n" "${target_key}" | wc -l)
  if [[ "${line_count}" -ne 1 || ! "${target_key}" =~ ${key_regex} ]] || ! ssh-keygen -l -f - <<< "${target_key}" > /dev/null 2>&1; then
    log_error "invalid openssh public key format."
    return 1
  fi

  mkdir -p "${user_ssh}"
  chmod 700 "${user_ssh}"
  printf "%s\n" "${target_key}" > "${auth_keys}"
  chmod 600 "${auth_keys}"
  log_success "key registered to ~/.ssh/authorized_keys"

  local port
  port=$(get_sshd_port)
  local current_user="${USER:-$(whoami)}"
  local lan_ip
  lan_ip=$(get_device_ip)

  if [[ -n "${lan_ip}" ]]; then
    log_info "connect: ssh -p ${port} ${current_user}@${lan_ip}"
  fi

  local vpn_ip
  vpn_ip=$(_run_ip -4 -o addr show 2> /dev/null | awk '$2 ~ /^(tailscale|tun|wg)/ {print $4}' | cut -d/ -f1 | head -n 1 || true)
  if [[ -n "${vpn_ip}" && "${vpn_ip}" != "${lan_ip}" ]]; then
    log_info "connect: ssh -p ${port} ${current_user}@${vpn_ip}"
  fi
}

edit_ssh_config() {
  local config_file="${PREFIX:-/data/data/com.termux/files/usr}/etc/ssh/sshd_config"
  local editor="${EDITOR:-nano}"

  if ! command -v "${editor}" > /dev/null 2>&1; then
    if command -v nano > /dev/null 2>&1; then
      editor="nano"
    elif command -v vi > /dev/null 2>&1; then
      editor="vi"
    else
      log_error "no editor found."
      return 1
    fi
  fi

  if [[ ! -f "${config_file}" ]]; then
    setup_remote
  fi

  "${editor}" "${config_file}"

  if command -v sshd > /dev/null 2>&1; then
    if ! sshd -t > /dev/null 2>&1; then
      log_warn "sshd_config syntax error"
    fi
  fi
}

sessions_usage() {
  echo "usage: net remote sessions <command> [args]"
  echo ""
  echo "commands:"
  echo "  list, ls             list active tmux sessions"
  echo "  attach, a [name]     attach to session (default: main)"
  echo "  kill, k <name>       terminate specific session"
  echo "  kill-all             terminate all tmux sessions"
}

manage_sessions() {
  local action="${1:-list}"

  if [[ "${action}" == "-h" || "${action}" == "--help" || "${action}" == "help" ]]; then
    sessions_usage
    return 0
  fi

  require_cmd tmux || return 1

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
      log_info "attaching to '${session_name}'..."
      if [[ -n "${TMUX:-}" ]]; then
        if ! tmux has-session -t "${session_name}" 2> /dev/null; then
          tmux new-session -d -s "${session_name}"
        fi
        tmux switch-client -t "${session_name}"
      else
        exec tmux new-session -A -s "${session_name}"
      fi
      ;;
    kill | k)
      local session_name="${2:-}"
      if [[ -z "${session_name}" ]]; then
        log_error "usage: net remote sessions kill <name>"
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
      log_error "unknown command: ${action} (see: net remote sessions -h)"
      return 1
      ;;
  esac
}

start_remote() {
  log_info "starting remote services..."

  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  mkdir -p "${state_dir}"

  if command -v termux-wake-lock > /dev/null 2>&1; then
    termux-wake-lock 2> /dev/null || true
    touch "${state_dir}/wakelock"
    log_success "wake-lock acquired."
  fi

  if ! pgrep -x sshd > /dev/null 2>&1; then
    local ssh_dir="${PREFIX:-/data/data/com.termux/files/usr}/etc/ssh"
    if ! compgen -G "${ssh_dir}/ssh_host_*_key" > /dev/null 2>&1; then
      ssh-keygen -A > /dev/null 2>&1 || true
    fi

    if sshd; then
      log_success "sshd started."
    else
      log_error "sshd failed to start."
      return 1
    fi
  else
    log_info "sshd already running."
  fi

  status_remote
}

stop_remote() {
  log_info "stopping remote services..."

  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"

  if pgrep -x sshd > /dev/null 2>&1; then
    pkill sshd 2> /dev/null || true
    log_success "sshd stopped."
  else
    log_info "sshd not running."
  fi

  if command -v termux-wake-unlock > /dev/null 2>&1; then
    termux-wake-unlock 2> /dev/null || true
    rm -f "${state_dir}/wakelock"
    log_success "wake-lock released."
  fi
}

main() {
  local cmd="${1:-status}"

  if [[ "${cmd}" == "-h" || "${cmd}" == "--help" ]]; then
    usage
    exit 0
  fi

  check_dependencies || exit 1

  case "${cmd}" in
    status)
      status_remote
      ;;
    setup)
      setup_remote
      ;;
    pair)
      shift
      pair_client_key "${*:-}"
      ;;
    config)
      edit_ssh_config
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
      exit 1
      ;;
  esac
}

main "${@}"

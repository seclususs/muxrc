#!/data/data/com.termux/files/usr/bin/bash

################################
# Remote SSH & Multiplexer Tools
################################
set -euo pipefail

source "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")/init.sh"

SSH_DIR="${PREFIX:-/data/data/com.termux/files/usr}/etc/ssh"
SSH_CONFIG="${SSH_DIR}/sshd_config"

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
  echo "  2fa [on|off]         toggle key+password 2fa"
  echo "  history              display login history"
  echo "  config               open sshd cfg in editor"
  echo "  start                start ssh daemon"
  echo "  stop                 stop ssh daemon"
  echo "  reload               reload ssh daemon"
}

get_sshd_port() {
  local config_file="${SSH_CONFIG}"
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

run_ip_cmd() {
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

  if [[ "${EUID:-$(id -u)}" -ne 0 ]] && command -v su > /dev/null 2>&1 && su -c true 2> /dev/null; then
    local su_ip="/system/bin/ip"
    [[ -x "${su_ip}" ]] || su_ip="ip"
    local safe_args
    safe_args=$(printf '%q ' "$@")
    out=$(su -c "${su_ip} ${safe_args}" 2> /dev/null || true)
    if [[ -n "${out}" ]]; then
      printf "%s\n" "${out}"
      return 0
    fi
  fi

  return 1
}

get_device_ip() {
  local ip_addr=""

  local route_out
  route_out=$(run_ip_cmd -4 route get 1.1.1.1 2> /dev/null || true)
  if [[ -n "${route_out}" ]]; then
    local r_dev
    r_dev=$(awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}' <<< "${route_out}")
    if ! [[ "${r_dev}" =~ ^(dummy|lo|tun|tailscale|wg) ]]; then
      ip_addr=$(awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}' <<< "${route_out}")
    fi
  fi

  if [[ -z "${ip_addr}" ]]; then
    local iface
    iface=$(detect_interface 2> /dev/null || true)
    if [[ -n "${iface}" ]]; then
      ip_addr=$(run_ip_cmd -4 -o addr show "${iface}" 2> /dev/null | awk '{print $4; exit}' | cut -d/ -f1 || true)
    fi
  fi

  if [[ -z "${ip_addr}" ]]; then
    ip_addr=$(run_ip_cmd -4 -o addr show scope global 2> /dev/null | awk '$2 !~ /^(dummy|lo|tun|tailscale|wg)/ {print $4; exit}' | cut -d/ -f1 || true)
  fi

  if [[ -z "${ip_addr}" ]] && command -v ifconfig > /dev/null 2>&1; then
    local iface
    iface=$(detect_interface 2> /dev/null || echo "wlan0")
    ip_addr=$(ifconfig "${iface}" 2> /dev/null | awk '/^[[:space:]]*inet / {sub(/^addr:/, "", $2); print $2; exit}' || true)
  fi

  if [[ -z "${ip_addr}" ]]; then
    ip_addr=$(getprop dhcp.wlan0.ipaddress 2> /dev/null || true)
  fi

  printf "%s\n" "${ip_addr}"
}

get_active_clients() {
  local port="${1:-8022}"
  local my_uid="${EUID:-$(id -u)}"
  local total_count=0
  local unique_ips=()

  _add_unique_ip() {
    local ip="${1}"
    [[ -z "${ip}" ]] && return 0
    case " ${unique_ips[*]:-} " in
      *" ${ip} "*) ;;
      *) unique_ips+=("${ip}") ;;
    esac
  }

  local ss_bin=""
  if command -v ss > /dev/null 2>&1; then
    ss_bin="ss"
  elif [[ -x "${PREFIX:-/data/data/com.termux/files/usr}/bin/ss" ]]; then
    ss_bin="${PREFIX:-/data/data/com.termux/files/usr}/bin/ss"
  fi

  local ss_out=""
  if [[ -n "${ss_bin}" ]]; then
    ss_out=$("${ss_bin}" -tn state established "( sport = :${port} )" 2> /dev/null || true)
  fi

  if [[ -z "${ss_out}" && "${my_uid}" -ne 0 ]] && command -v su > /dev/null 2>&1; then
    local su_ss="ss"
    [[ -x "${PREFIX:-/data/data/com.termux/files/usr}/bin/ss" ]] && su_ss="${PREFIX:-/data/data/com.termux/files/usr}/bin/ss"
    ss_out=$(su -c "${su_ss} -tn state established '( sport = :${port} )'" 2> /dev/null || true)
  fi

  if [[ -n "${ss_out}" ]]; then
    while read -r raw_peer; do
      [[ -z "${raw_peer}" ]] && continue
      ((total_count++))
      local peer_ip
      peer_ip=$(printf "%s\n" "${raw_peer}" | sed -E 's/:[0-9]+$//; s/^\[::ffff://; s/^\[//; s/\]$//')
      _add_unique_ip "${peer_ip}"
    done < <(printf "%s\n" "${ss_out}" | awk 'NR>1 {print $NF}' || true)
  fi

  if [[ "${total_count}" -eq 0 ]]; then
    local sshd_pid
    sshd_pid=$(pgrep -u "${my_uid}" -x sshd 2> /dev/null | head -n 1 || true)
    if [[ -n "${sshd_pid}" ]]; then
      local child_pids
      child_pids=$(pgrep -u "${my_uid}" -P "${sshd_pid}" 2> /dev/null || true)
      if [[ -n "${child_pids}" ]]; then
        for cpid in ${child_pids}; do
          ((total_count++))
          local pids_to_check="${cpid}"
          local grand_pids
          grand_pids=$(pgrep -u "${my_uid}" -P "${cpid}" 2> /dev/null || true)
          if [[ -n "${grand_pids}" ]]; then
            pids_to_check="${pids_to_check} ${grand_pids}"
          fi

          local found_ip=""
          for p in ${pids_to_check}; do
            if [[ -r "/proc/${p}/environ" ]]; then
              local env_ip
              env_ip=$(tr '\0' '\n' < "/proc/${p}/environ" 2> /dev/null | awk -F'[ =]' '$1=="SSH_CLIENT"{print $2; exit}' || true)
              if [[ -n "${env_ip}" ]]; then
                found_ip="${env_ip}"
                break
              fi
            fi
          done
          _add_unique_ip "${found_ip}"
        done
      fi
    fi
  fi

  if [[ -n "${SSH_CLIENT:-}" ]]; then
    local cur_ip="${SSH_CLIENT%% *}"
    if [[ -n "${cur_ip}" ]]; then
      _add_unique_ip "${cur_ip}"
      if [[ "${total_count}" -eq 0 ]]; then
        total_count=1
      fi
    fi
  fi

  if [[ "${total_count}" -gt 0 ]]; then
    local joined=""
    for ip in "${unique_ips[@]}"; do
      if [[ -z "${joined}" ]]; then
        joined="${ip}"
      else
        joined="${joined}, ${ip}"
      fi
    done
    if [[ -n "${joined}" ]]; then
      printf "%s active (%s)\n" "${total_count}" "${joined}"
    else
      printf "%s active\n" "${total_count}"
    fi
  else
    printf "none\n"
  fi
}

status_remote() {
  local port
  port=$(get_sshd_port)
  local current_user="${USER:-$(whoami)}"

  if ! pgrep -x sshd > /dev/null 2>&1; then
    log_warn "sshd: inactive"
    return 0
  fi

  log_success "sshd: active (port ${port})"

  local clients
  clients=$(get_active_clients "${port}")
  if [[ "${clients}" != "none" ]]; then
    log_info "clients: ${clients}"
  fi

  local auth_status
  auth_status=$(get_2fa_status)
  if [[ "${auth_status}" == "enabled" ]]; then
    log_info "auth: key + password (2fa)"
  else
    log_info "auth: key only"
  fi

  local lan_ip
  lan_ip=$(get_device_ip)

  local vpn_ips=()
  local vpn_lines=""
  vpn_lines=$(run_ip_cmd -4 -o addr show 2> /dev/null | awk '$2 ~ /^(tailscale|tun|wg)/ {print $2 " " $4}' | cut -d/ -f1 || true)
  if [[ -z "${vpn_lines}" ]] && command -v ifconfig > /dev/null 2>&1; then
    vpn_lines=$(ifconfig 2> /dev/null | awk '
      /^[a-zA-Z0-9_.-]+:/ { iface = $1; sub(/:$/, "", iface) }
      /^[[:space:]]*inet / {
        ip = $2; sub(/^addr:/, "", ip)
        if (ip != "127.0.0.1" && iface ~ /^(tailscale|tun|wg)/) print iface " " ip
      }
    ' || true)
  fi
  if [[ -n "${vpn_lines}" ]]; then
    while read -r vpn_iface vpn_addr; do
      if [[ -n "${vpn_iface}" && -n "${vpn_addr}" ]]; then
        vpn_ips+=("${vpn_addr}")
      fi
    done <<< "${vpn_lines}"
  fi

  local connect_cmds=()
  for vip in "${vpn_ips[@]}"; do
    connect_cmds+=("ssh -p ${port} ${current_user}@${vip}")
  done
  if [[ -n "${lan_ip}" ]]; then
    local lan_cmd="ssh -p ${port} ${current_user}@${lan_ip}"
    case " ${connect_cmds[*]:-} " in
      *" ${lan_cmd} "*) ;;
      *) connect_cmds+=("${lan_cmd}") ;;
    esac
  fi

  if [[ ${#connect_cmds[@]} -gt 0 ]]; then
    echo ""
    log_info "connect:"
    for cmd in "${connect_cmds[@]}"; do
      echo "  ${cmd}"
    done
  elif [[ -z "${lan_ip}" && ${#vpn_ips[@]} -eq 0 ]]; then
    log_warn "ip: no network connection"
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

remove_config_key() {
  local file="${1}"
  local key="${2}"

  if [[ -f "${file}" ]]; then
    sed -i -E "/^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+/d" "${file}"
  fi
}

has_user_password() {
  local shadow_file="${PREFIX:-/data/data/com.termux/files/usr}/etc/shadow"
  [[ -f "${shadow_file}" ]] || return 1

  local current_user="${USER:-$(whoami)}"
  local hash=""
  hash=$(awk -F: -v u="${current_user}" '$1 == u {print $2; exit}' "${shadow_file}" 2> /dev/null || true)
  if [[ -z "${hash}" ]]; then
    hash=$(awk -F: 'NR==1 {print $2; exit}' "${shadow_file}" 2> /dev/null || true)
  fi

  if [[ -z "${hash}" || "${hash}" == "*" || "${hash}" == "!" ]]; then
    return 1
  fi
  return 0
}

get_2fa_status() {
  local config_file="${SSH_CONFIG}"
  if [[ -f "${config_file}" ]] && grep -qE "^[[:space:]]*AuthenticationMethods[[:space:]]+.*password" "${config_file}"; then
    printf "enabled\n"
  else
    printf "disabled\n"
  fi
}

toggle_2fa() {
  local action="${1:-status}"
  local config_file="${SSH_CONFIG}"

  if [[ ! -f "${config_file}" ]]; then
    setup_remote
  fi

  case "${action}" in
    on | enable)
      if ! has_user_password; then
        log_error "no password set"
        log_info "run 'passwd' first"
        return 1
      fi

      set_config_value "${config_file}" "PasswordAuthentication" "yes"
      set_config_value "${config_file}" "PubkeyAuthentication" "yes"
      set_config_value "${config_file}" "AuthenticationMethods" "publickey,password"

      log_success "2fa: enabled (key + password)"
      if pgrep -x sshd > /dev/null 2>&1; then
        reload_remote
      fi
      ;;
    off | disable)
      set_config_value "${config_file}" "PasswordAuthentication" "no"
      set_config_value "${config_file}" "PubkeyAuthentication" "yes"
      remove_config_key "${config_file}" "AuthenticationMethods"

      log_success "2fa: disabled (key only)"
      if pgrep -x sshd > /dev/null 2>&1; then
        reload_remote
      fi
      ;;
    status)
      local st
      st=$(get_2fa_status)
      if [[ "${st}" == "enabled" ]]; then
        log_info "2fa: enabled (key + password)"
      else
        log_info "2fa: disabled (key only)"
      fi
      ;;
    *)
      log_error "usage: net remote 2fa [on|off]"
      return 1
      ;;
  esac
}

setup_remote() {
  local ssh_dir="${SSH_DIR}"
  local config_file="${SSH_CONFIG}"

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
  remove_config_key "${config_file}" "AuthenticationMethods"

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
    log_error "empty public key"
    return 1
  fi

  local line_count
  line_count=$(printf "%s\n" "${target_key}" | wc -l)
  if [[ "${line_count}" -ne 1 || ! "${target_key}" =~ ${key_regex} ]] || ! ssh-keygen -l -f - <<< "${target_key}" > /dev/null 2>&1; then
    log_error "invalid openssh public key format"
    return 1
  fi

  mkdir -p "${user_ssh}"
  chmod 700 "${user_ssh}"
  if ! grep -qxF "${target_key}" "${auth_keys}" 2> /dev/null; then
    printf "%s\n" "${target_key}" >> "${auth_keys}"
  fi
  chmod 600 "${auth_keys}"
  log_success "key registered to auth_keys"

  local port
  port=$(get_sshd_port)
  local current_user="${USER:-$(whoami)}"
  local lan_ip
  lan_ip=$(get_device_ip)

  if [[ -n "${lan_ip}" ]]; then
    local target="${current_user}@${lan_ip}"
    log_info "ssh: ${target}:${port}"
  fi

  local vpn_ip
  vpn_ip=$(run_ip_cmd -4 -o addr show 2> /dev/null | awk '$2 ~ /^(tailscale|tun|wg)/ {print $4}' | cut -d/ -f1 | head -n 1 || true)
  if [[ -n "${vpn_ip}" && "${vpn_ip}" != "${lan_ip}" ]]; then
    local vpn_target="${current_user}@${vpn_ip}"
    log_info "ssh vpn: ${vpn_target}:${port}"
  fi
}

edit_ssh_config() {
  local config_file="${SSH_CONFIG}"
  local editor="${EDITOR:-nano}"

  if ! command -v "${editor}" > /dev/null 2>&1; then
    if command -v nano > /dev/null 2>&1; then
      editor="nano"
    elif command -v vi > /dev/null 2>&1; then
      editor="vi"
    else
      log_error "no editor found"
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

trim_str() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "${var}"
}

record_history_entry() {
  local entry_type="${1}"
  local client_ip="${2}"
  local auth_mode="${3}"
  local entry_time="${4:-}"

  [[ "${entry_type}" == "REJECT" ]] || return 0

  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local log_file="${state_dir}/ssh_history.log"
  mkdir -p "${state_dir}" 2> /dev/null

  if [[ -z "${entry_time}" ]]; then
    entry_time=$(date +'%Y-%m-%d %H:%M:%S' 2> /dev/null || date)
  fi

  entry_time=$(trim_str "${entry_time}")
  entry_type=$(trim_str "${entry_type}")
  client_ip=$(trim_str "${client_ip}")
  auth_mode=$(trim_str "${auth_mode}")

  local last_line
  last_line=$(tail -n 1 "${log_file}" 2> /dev/null || true)
  if [[ -n "${last_line}" ]]; then
    local l_time l_type l_ip l_mode
    IFS='|' read -r l_time l_type l_ip l_mode <<< "${last_line}"
    l_time=$(trim_str "${l_time}")
    l_type=$(trim_str "${l_type}")
    l_ip=$(trim_str "${l_ip}")
    l_mode=$(trim_str "${l_mode}")

    if [[ "${l_type}" == "${entry_type}" && "${l_ip}" == "${client_ip}" && "${l_mode}" == "${auth_mode}" ]]; then
      local t_cur t_prev
      t_cur=$(date -d "${entry_time}" +%s 2> /dev/null || true)
      t_prev=$(date -d "${l_time}" +%s 2> /dev/null || true)
      if [[ -n "${t_cur}" && -n "${t_prev}" ]]; then
        local delta=$((t_cur - t_prev))
        if ((delta >= 0 && delta < 5)); then
          return 0
        fi
      elif [[ "${l_time}" == "${entry_time}" ]]; then
        return 0
      fi
    fi
  fi

  printf "%s | %s | %s | %s\n" "${entry_time}" "${entry_type}" "${client_ip}" "${auth_mode}" >> "${log_file}"

  local max_lines=100
  local total_lines
  total_lines=$(wc -l < "${log_file}" 2> /dev/null || echo 0)
  if ((total_lines > max_lines)); then
    local tmp_log
    tmp_log=$(mktemp "${log_file}.XXXXXX" 2> /dev/null || mktemp)
    if tail -n "${max_lines}" "${log_file}" > "${tmp_log}" 2> /dev/null && mv -f "${tmp_log}" "${log_file}" 2> /dev/null; then
      :
    else
      rm -f "${tmp_log}" 2> /dev/null
    fi
  fi
}

send_security_alert() {
  local client_ip="${1}"
  local reason="${2:-auth_failed}"

  if command -v termux-notification > /dev/null 2>&1; then
    termux-notification --id "muxrc_ssh_security" \
      --title "SSH Security Alert" \
      --content "Rejected ${client_ip} (${reason})" \
      --priority high 2> /dev/null || true
  fi
}

parse_sshd_line() {
  local line="${1}"
  local notify="${2:-0}"
  local type="" ip="" mode="" entry_time=""

  if [[ "${line}" =~ ^([0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
    local cur_year
    cur_year=$(date +'%Y' 2> /dev/null || echo "2026")
    entry_time="${cur_year}-${BASH_REMATCH[1]}"
  else
    entry_time=$(date +'%Y-%m-%d %H:%M:%S' 2> /dev/null || date)
  fi

  if [[ "${line}" =~ Failed[[:space:]]+password[[:space:]]+for[[:space:]]+(invalid[[:space:]]+user[[:space:]]+)?([^[:space:]]+)[[:space:]]+from[[:space:]]+([^[:space:]]+) ]]; then
    type="REJECT"
    ip="${BASH_REMATCH[3]}"
    mode="password"
  elif [[ "${line}" =~ Failed[[:space:]]+publickey[[:space:]]+for[[:space:]]+(invalid[[:space:]]+user[[:space:]]+)?([^[:space:]]+)[[:space:]]+from[[:space:]]+([^[:space:]]+) ]]; then
    type="REJECT"
    ip="${BASH_REMATCH[3]}"
    mode="key"
  elif [[ "${line}" =~ Too[[:space:]]+many[[:space:]]+authentication[[:space:]]+failures ]]; then
    type="REJECT"
    mode="auth_failed"
    if [[ "${line}" =~ from[[:space:]]+([^[:space:]]+) ]]; then
      ip="${BASH_REMATCH[1]}"
    elif [[ "${line}" =~ user[[:space:]]+[^[:space:]]+[[:space:]]+([0-9a-fA-F.:]+)[[:space:]]+port ]]; then
      ip="${BASH_REMATCH[1]}"
    fi
  fi

  if [[ -n "${type}" && -n "${ip}" ]]; then
    if [[ "${ip}" =~ ^\[([0-9a-fA-F:]+)\](:[0-9]+)?$ ]]; then
      ip="${BASH_REMATCH[1]}"
    elif [[ "${ip}" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(:[0-9]+)?$ ]]; then
      ip="${BASH_REMATCH[1]}"
    fi
    record_history_entry "${type}" "${ip}" "${mode}" "${entry_time}"
    if [[ "${notify}" -eq 1 ]]; then
      send_security_alert "${ip}" "${mode}"
    fi
  fi
}

sync_sshd_log() {
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local sshd_log="${state_dir}/sshd.log"
  local pos_file="${state_dir}/sshd_log.pos"

  if [[ -s "${sshd_log}" ]]; then
    local start_line=0
    [[ -f "${pos_file}" ]] && start_line=$(< "${pos_file}")
    [[ "${start_line}" =~ ^[0-9]+$ ]] || start_line=0

    local total_lines=0
    total_lines=$(wc -l < "${sshd_log}" 2> /dev/null || echo 0)

    if ((total_lines > start_line)); then
      local new_lines
      new_lines=$(awk -v start="${start_line}" 'NR > start' "${sshd_log}")
      while read -r raw_line; do
        [[ -z "${raw_line}" ]] && continue
        parse_sshd_line "${raw_line}" 0
      done <<< "${new_lines}"
      echo "${total_lines}" > "${pos_file}"
    elif ((total_lines < start_line)); then
      echo 0 > "${pos_file}"
    fi
  elif command -v logcat > /dev/null 2>&1; then
    local logcat_out
    logcat_out=$(logcat -d -s 'sshd:*' 2> /dev/null | grep -E 'Failed (password|publickey)|Too many authentication failures' || true)
    if [[ -n "${logcat_out}" ]]; then
      while read -r raw_line; do
        [[ -z "${raw_line}" ]] && continue
        parse_sshd_line "${raw_line}" 0
      done <<< "${logcat_out}"
    fi
  fi
}

start_monitor() {
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  mkdir -p "${state_dir}"
  local pid_file="${state_dir}/sshd_monitor.pid"

  if [[ -f "${pid_file}" ]]; then
    local old_pid
    old_pid=$(< "${pid_file}")
    if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2> /dev/null; then
      return 0
    fi
  fi

  local sshd_log="${state_dir}/sshd.log"
  local pos_file="${state_dir}/sshd_log.pos"
  touch "${sshd_log}"

  (
    trap 'pkill -P $$ 2> /dev/null || true; exit 0' TERM INT EXIT
    exec < /dev/null
    exec >> "${state_dir}/monitor.err" 2>&1

    tail -n 0 -F "${sshd_log}" 2> /dev/null | while read -r raw_line; do
      [[ -z "${raw_line}" ]] && continue
      parse_sshd_line "${raw_line}" 1
      wc -l < "${sshd_log}" 2> /dev/null > "${pos_file}" || true
    done
  ) &
  local mon_pid=$!
  echo "${mon_pid}" > "${pid_file}"
  disown "${mon_pid}" 2> /dev/null || true
}

stop_monitor() {
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local pid_file="${state_dir}/sshd_monitor.pid"

  if [[ -f "${pid_file}" ]]; then
    local mon_pid
    mon_pid=$(< "${pid_file}")
    if [[ -n "${mon_pid}" ]]; then
      pkill -P "${mon_pid}" 2> /dev/null || true
      kill "${mon_pid}" 2> /dev/null || true
    fi
    rm -f "${pid_file}" 2> /dev/null
  fi
}

start_remote() {
  if pgrep -x sshd > /dev/null 2>&1; then
    status_remote
    return 0
  fi

  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  mkdir -p "${state_dir}"

  if command -v termux-wake-lock > /dev/null 2>&1; then
    termux-wake-lock 2> /dev/null || true
    touch "${state_dir}/wakelock"
  fi

  local ssh_dir="${SSH_DIR}"
  if [[ ! -f "${SSH_CONFIG}" ]]; then
    setup_remote
  fi

  if ! compgen -G "${ssh_dir}/ssh_host_*_key" > /dev/null 2>&1; then
    trap 'cleanup_spinner' EXIT
    start_spinner "generating ssh host keys"
    ssh-keygen -A > /dev/null 2>&1 || true
    stop_spinner "success" "ssh host keys generated"
    trap - EXIT
  fi

  local sshd_log="${state_dir}/sshd.log"
  touch "${sshd_log}"

  if ! sshd -E "${sshd_log}"; then
    log_error "sshd failed to start"
    return 1
  fi

  start_monitor
  status_remote
}

stop_remote() {
  confirm_ssh_hazard "this will terminate your ssh session" || return 1

  stop_monitor

  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local my_uid="${EUID:-$(id -u)}"
  local sv_dir="${PREFIX:-/data/data/com.termux/files/usr}/var/service/sshd"

  if command -v sv > /dev/null 2>&1 && [[ -d "${sv_dir}" ]]; then
    sv down "${sv_dir}" > /dev/null 2>&1 || true
  fi

  if pgrep -u "${my_uid}" sshd > /dev/null 2>&1; then
    pkill -u "${my_uid}" sshd 2> /dev/null || true

    local i
    for ((i = 0; i < 20; i++)); do
      if ! pgrep -u "${my_uid}" sshd > /dev/null 2>&1; then
        break
      fi
      sleep 0.1
    done

    if pgrep -u "${my_uid}" sshd > /dev/null 2>&1; then
      pkill -9 -u "${my_uid}" sshd 2> /dev/null || true
    fi

    log_success "sshd stopped"
  else
    log_warn "sshd: inactive"
  fi

  if [[ -f "${state_dir}/wakelock" ]]; then
    if command -v termux-wake-unlock > /dev/null 2>&1; then
      termux-wake-unlock 2> /dev/null || true
    fi
    rm -f "${state_dir}/wakelock"
  fi
}

reload_remote() {
  local my_uid="${EUID:-$(id -u)}"
  if pgrep -u "${my_uid}" -x sshd > /dev/null 2>&1; then
    pkill -HUP -u "${my_uid}" -x sshd 2> /dev/null || true
    start_monitor
    log_success "sshd reloaded"
  else
    log_warn "sshd: inactive"
  fi
}

history_remote() {
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"
  local log_file="${state_dir}/ssh_history.log"

  sync_sshd_log

  if [[ ! -s "${log_file}" ]]; then
    log_warn "no reject history"
    return 0
  fi

  log_info "ssh reject history:"
  tail -n 10 "${log_file}"
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
    2fa)
      shift
      toggle_2fa "${1:-status}"
      ;;
    history)
      history_remote
      ;;
    config)
      edit_ssh_config
      ;;
    start)
      start_remote
      ;;
    stop)
      stop_remote
      ;;
    reload)
      reload_remote
      ;;
    *)
      log_error "unknown command: ${cmd}"
      exit 1
      ;;
  esac
}

main "${@}"

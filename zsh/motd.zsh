###########################
# Message of the Day Banner
###########################
() {
  if [[ -o interactive && "$EUID" -ne 0 ]]; then
    local android_ver=""
    local device=""
    local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/muxrc/device_info"

    if [[ -s "$cache_file" ]]; then
      {
        read -r device
        read -r android_ver
      } < "$cache_file" 2> /dev/null
    fi

    if [[ -z "$device" || -z "$android_ver" ]]; then
      android_ver=$(getprop ro.build.version.release 2> /dev/null)
      device=$(getprop ro.product.model 2> /dev/null)
      if [[ -n "$device" || -n "$android_ver" ]]; then
        mkdir -p "${cache_file:h}" 2> /dev/null
        printf "%s\n%s\n" "${device:-unknown device}" "${android_ver:-?}" > "$cache_file" 2> /dev/null
      fi
    fi

    local ssh_cfg="${PREFIX:-/data/data/com.termux/files/usr}/etc/ssh/sshd_config"
    local tfa_status="off"
    local tfa_color="yellow"
    if [[ -f "$ssh_cfg" ]] && grep -qE '^[[:space:]]*AuthenticationMethods[[:space:]]+.*password' "$ssh_cfg" 2> /dev/null; then
      tfa_status="on"
      tfa_color="green"
    fi

    local storage_free
    storage_free=$(df -h "$HOME" 2> /dev/null | awk 'NR==2 {print $4" free"}')

    local net_ips="offline"
    if (( $+functions[_net_active_ips] )); then
      net_ips=$(_net_active_ips)
    fi

    print -P "%F{39}%n@termux%f - ${device:-unknown device} · Android ${android_ver:-?}"
    print -P "Storage: ${storage_free:-?} · 2FA: %F{${tfa_color}}${tfa_status}%f"
    print -P "IP: ${net_ips}"
  fi
}

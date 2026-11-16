############################
# Network diagnostic helpers
############################

ping() {
  local -a args=("$@")
  if [[ ! " ${args[*]} " =~ [[:space:]]-c[[:space:]] ]]; then
    args=(-c 4 "${args[@]}")
  fi

  if command ping "${args[@]}"; then
    return 0
  fi

  local code=$?
  if [[ -x /system/bin/ping ]] && /system/bin/ping "${args[@]}"; then
    return 0
  fi

  return $code
}

net-info() {
  command -v termux-wifi-connectioninfo > /dev/null 2>&1 || {
    echo "net-info: needs termux-api"
    return 1
  }
  command -v jq > /dev/null 2>&1 || {
    echo "net-info: needs jq"
    return 1
  }
  local ip=$(termux-wifi-connectioninfo | jq -r '.ip // empty')
  [[ -z "$ip" || "$ip" == null || "$ip" == "0.0.0.0" ]] && {
    echo "net-info: no wifi ip"
    return 1
  }
  local cmd="ssh ${USER:-$(whoami)}@${ip} -p 8022"
  echo "$cmd"
  command -v termux-toast > /dev/null 2>&1 && termux-toast "$cmd" || true
}

_ip_format_ifconfig() {
  local brief=0
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "-br" || "$arg" == "-brief" ]]; then
      brief=1
      break
    fi
  done

  ifconfig 2> /dev/null | awk -v brief="$brief" '
    /^[a-zA-Z0-9_.-]+:/ {
      iface = $1
      sub(/:$/, "", iface)
      flags = $2
      state = (flags ~ /RUNNING/) ? "UP" : "DOWN"
      mtu = $4
      idx++
      found_inet = 0
    }
    /^[[:space:]]*inet / {
      ip = $2
      netmask = $4
      brd = $6

      prefix = 24
      if (netmask == "255.0.0.0") prefix = 8
      else if (netmask == "255.255.255.255") prefix = 32
      else if (netmask == "255.255.0.0") prefix = 16

      found_inet = 1
      if (brief == 1) {
        printf "%-16s %-10s %s/%d\n", iface, state, ip, prefix
      } else {
        printf "%d: %s: <%s> mtu %s state %s\n", idx, iface, flags, mtu, state
        if (brd != "") {
          printf "    inet %s/%d brd %s scope global %s\n", ip, prefix, brd, iface
        } else {
          printf "    inet %s/%d scope global %s\n", ip, prefix, iface
        }
      }
    }
    /^[[:space:]]*unspec / && found_inet == 0 && brief == 0 {
      printf "%d: %s: <%s> mtu %s state %s\n", idx, iface, flags, mtu, state
    }
  '
}

ip() {
  local tmp_err
  tmp_err=$(mktemp "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/ip.err.XXXXXX" 2> /dev/null || mktemp)

  if command ip "$@" 2> "$tmp_err"; then
    rm -f "$tmp_err" 2> /dev/null
    return 0
  fi

  local rc=$?
  local err_msg
  err_msg=$(< "$tmp_err" 2> /dev/null)
  rm -f "$tmp_err" 2> /dev/null

  if [[ "$err_msg" == *"Cannot bind netlink socket: Permission denied"* ]]; then
    local is_addr_query=0
    local arg
    for arg in "$@"; do
      case "$arg" in
        a | addr | address | l | link)
          is_addr_query=1
          break
          ;;
      esac
    done

    if [[ $is_addr_query -eq 1 ]]; then
      _ip_format_ifconfig "$@"
      return 0
    fi
  fi

  print -u2 "$err_msg"
  return $rc
}

_net_active_ips() {
  local -a parts=()
  local vpn_ip=""
  local wlan_ip=""

  if command -v ip > /dev/null 2>&1; then
    local ip_out
    ip_out=$(command ip -4 -o addr show 2> /dev/null || true)
    if [[ -n "$ip_out" ]]; then
      vpn_ip=$(awk '$2 ~ /^(tailscale|tun|wg)/ {split($4, a, "/"); print a[1]; exit}' <<< "$ip_out")
      wlan_ip=$(awk '$2 ~ /^wlan/ {split($4, a, "/"); print a[1]; exit}' <<< "$ip_out")
    fi
  fi

  if [[ -z "$wlan_ip" ]]; then
    wlan_ip=$(getprop dhcp.wlan0.ipaddress 2> /dev/null || true)
  fi

  [[ -n "$vpn_ip" ]] && parts+=("${vpn_ip} (vpn)")
  [[ -n "$wlan_ip" ]] && parts+=("${wlan_ip} (wlan)")

  if (( ${#parts[@]} > 0 )); then
    print -r -- "${(j: · :)parts}"
  else
    print -r -- "offline"
  fi
}

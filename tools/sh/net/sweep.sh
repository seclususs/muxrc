#!/data/data/com.termux/files/usr/bin/bash

###########################
# Local Network ARP Sweeper
###########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../../lib/init.sh"

check_dependencies() {
  require_cmd nmap awk
}

validate_cidr() {
  local target_cidr="${1:-}"
  local cidr_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$'

  if [[ -z "${target_cidr}" ]]; then
    log_error "usage: net sweep [cidr] (see -h)"
    return 1
  fi

  if [[ ! "${target_cidr}" =~ ${cidr_regex} ]]; then
    log_error "invalid cidr: ${target_cidr}"
    return 1
  fi

  return 0
}

usage() {
  echo "usage: net sweep [cidr]"
  echo "scan active hosts in local arp subnet."
  echo "auto-detects subnet if cidr is omitted."
}

execute_arp_sweep() {
  local target_cidr="${1}"

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_warn "non-root: mac/vendor omitted by nmap"
  fi

  log_info "target: ${target_cidr}"
  printf "%-15s | %-17s | %s\n" "ip" "mac" "vendor (host)"

  nmap -sn "${target_cidr}" | awk '
function flush_host() {
    if (ip != "") {
        if (mac == "") {
            mac = "<unknown>"
            vendor = "(no root / local)"
        }
        if (host != "") {
            printf "%-15s | %-17s | %s (%s)\n", ip, mac, vendor, host
        } else {
            printf "%-15s | %-17s | %s\n", ip, mac, vendor
        }
    }
    ip = ""; host = ""; mac = ""; vendor = ""
}

/^Nmap scan report for/ {
    flush_host()
    ip = $5
    if (ip ~ /\(/) {
        ip = substr(ip, 2, length(ip)-2)
        host = ""
    } else {
        host = ""
        if (NF == 6) {
            host = $5
            ip = substr($6, 2, length($6)-2)
        }
    }
}
/^MAC Address:/ {
    mac = $3
    vendor = ""
    for(i=4; i<=NF; i++) {
        vendor = vendor $i " "
    }

    gsub(/^\(|\) $/, "", vendor)
}
END {
    flush_host()
}'

  log_success "sweep complete"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  check_dependencies || exit 1

  local cidr="${1:-}"

  if [[ -z "${cidr}" ]]; then
    if command -v ip > /dev/null 2>&1; then
      cidr=$(ip route show 2> /dev/null | grep -v 'default' | grep -vE 'dev (lo|tun|tap|wg)' | awk '{print $1}' | head -n 1 || true)
    fi
  fi

  if [[ -z "${cidr}" ]] && command -v termux-wifi-connectioninfo > /dev/null 2>&1; then
    local wifi_ip
    wifi_ip=$(termux-wifi-connectioninfo 2> /dev/null | jq -r '.ip // empty' 2> /dev/null || true)
    if [[ -n "${wifi_ip}" && "${wifi_ip}" != "null" && "${wifi_ip}" != "0.0.0.0" ]]; then
      cidr="${wifi_ip%.*}.0/24"
    fi
  fi

  if [[ -z "${cidr}" ]]; then
    log_error "could not auto-detect subnet. specify cidr: net sweep <cidr>"
    exit 1
  fi

  validate_cidr "${cidr}" || exit 1
  execute_arp_sweep "${cidr}"
}

main "$@"

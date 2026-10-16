#!/data/data/com.termux/files/usr/bin/bash

###########################
# Local Network ARP Sweeper
###########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd nmap awk
}

validate_cidr() {
  local target_cidr="${1:-}"
  local cidr_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$'

  if [[ -z "${target_cidr}" ]]; then
    log_error "usage: $(basename "$0") <cidr>"
    return 1
  fi

  if [[ ! "${target_cidr}" =~ ${cidr_regex} ]]; then
    log_error "invalid cidr format: ${target_cidr}"
    return 1
  fi

  return 0
}

execute_arp_sweep() {
  local target_cidr="${1}"

  log_info "target subnet: ${target_cidr}"
  log_info "initiating sweep..."
  printf "%-15s | %-17s | %s\n" "ip" "mac" "vendor (host)"

  nmap -sn "${target_cidr}" | awk '
/^Nmap scan report for/ {
    ip = $5
    if (ip ~ /\(/) {
        ip = substr(ip, 2, length(ip)-2)
        host = $5
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

    if (host != "") {
        printf "%-15s | %-17s | %s (%s)\n", ip, mac, vendor, host
    } else {
        printf "%-15s | %-17s | %s\n", ip, mac, vendor
    }
}'

  log_success "sweep complete."
}

main() {
  local cidr="${1:-}"

  validate_cidr "${cidr}" || exit 1
  check_dependencies || exit 1
  execute_arp_sweep "${cidr}"
}

main "$@"

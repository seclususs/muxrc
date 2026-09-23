#!/data/data/com.termux/files/usr/bin/bash

###########################
# Local Network ARP Sweeper
###########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/_core/init.sh"

cidr="${1:-}"
if [[ -z "$cidr" ]]; then
    log_error "usage: arp-sweeper.sh <cidr>"
    exit 1
fi

log_info "target subnet: $cidr"
log_info "initiating sweep..."
printf "%-15s | %-17s | %s\n" "ip" "mac" "vendor (host)"

nmap -sn "$cidr" | awk '
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

exit 0

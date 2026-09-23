#!/data/data/com.termux/files/usr/bin/bash

###########################
# Local Network ARP Sweeper
###########################
set -euo pipefail

cidr="${1:-}"

if [[ -z "$cidr" ]]; then
    echo "Usage: arp-sweeper.sh <cidr>"
    exit 1
fi

echo "[*] Target Subnet: $cidr"
echo "[*] Initiating Nmap ARP sweep..."
echo ""
printf "%-18s | %-19s | %s\n" "IP Address" "MAC Address" "Vendor / Hostname"
echo "----------------------------------------------------------------------"

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
        printf "%-18s | %-19s | %s (%s)\n", ip, mac, vendor, host
    } else {
        printf "%-18s | %-19s | %s\n", ip, mac, vendor
    }
}'

echo "----------------------------------------------------------------------"
echo "[+] Sweep complete."

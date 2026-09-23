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

nmap -sn "$cidr"

echo "[+] Sweep complete."

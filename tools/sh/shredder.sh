#!/data/data/com.termux/files/usr/bin/bash

##########################
# Permanent Media Shredder
##########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

target_file="${1:-}"
if [[ -z "$target_file" ]]; then
    log_error "usage: $(basename "$0") <target_file>"
    exit 1
fi

log_warn "permanently destroying:"
log_warn "$target_file"
log_prompt "type 'shred' to confirm (or anything else to exit): "
read -r confirm

if [[ "$confirm" == "SHRED" ]]; then
    trap '[[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null || true; echo -ne "\r\033[K"' EXIT
    start_spinner "shredding file"
    shred -u -z -n 3 "$target_file"
    stop_spinner "success" "file destroyed."
else
    log_warn "aborted."
    exit 1
fi

exit 0

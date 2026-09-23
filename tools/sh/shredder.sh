#!/data/data/com.termux/files/usr/bin/bash

##########################
# Permanent Media Shredder
##########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/_core/init.sh"

target_file="${1:-}"
if [[ -z "$target_file" ]]; then
    log_error "usage: $(basename "$0") <target_file>"
    exit 1
fi

log_warn "PERMANENTLY DESTROYING:"
log_warn "$target_file"
read -r -p "type 'SHRED' to confirm (or anything else to exit): " confirm

if [[ "$confirm" == "SHRED" ]]; then
    log_info "shredding file..."
    shred -u -z -n 3 "$target_file"
    log_success "file destroyed."
else
    log_warn "aborted."
    exit 1
fi

exit 0

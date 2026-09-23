#!/data/data/com.termux/files/usr/bin/bash

##############
# EXIF Spoofer
##############
set -euo pipefail

source "$(dirname "$(realpath "$0")")/_core/init.sh"

preset_file="${1:-}"
image_file="${2:-}"
if [[ -z "$preset_file" || -z "$image_file" ]]; then
    log_error "Usage: $(basename "$0") <preset_json_file> <target_image>"
    exit 1
fi
output_dir="$HOME/muxrc/tools/output/decoys"

mkdir -p "$output_dir"
output_file="$output_dir/$(basename "$image_file")"

declare -a args=()
while IFS="=" read -r key val; do
    args+=("-$key=$val")
done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$preset_file")

log_info "Injecting decoy metadata from $(basename "$preset_file")..."
exiftool "${args[@]}" -o "$output_file" "$image_file" >/dev/null
log_success "Decoy generated at: $output_file"

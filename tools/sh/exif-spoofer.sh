#!/data/data/com.termux/files/usr/bin/bash

##############
# EXIF Spoofer
##############
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

preset_file="${1:-}"
image_file="${2:-}"
if [[ -z "$preset_file" || -z "$image_file" ]]; then
    log_error "usage: $(basename "$0") <preset_json_file> <target_image>"
    exit 1
fi
output_dir="$HOME/muxrc/tools/output/decoys"

mkdir -p "$output_dir"
output_file="$output_dir/$(basename "$image_file")"

declare -a args=()
while IFS="=" read -r key val; do
    args+=("-$key=$val")
done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$preset_file")

trap '[[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null || true; echo -ne "\r\033[K"' EXIT
start_spinner "injecting decoy from $(basename "$preset_file")"
exiftool "${args[@]}" -o "$output_file" "$image_file" >/dev/null
stop_spinner "success" "decoy at: $output_file"
trap - EXIT

exit 0

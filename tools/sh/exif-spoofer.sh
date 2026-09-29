#!/data/data/com.termux/files/usr/bin/bash

##############
# EXIF Spoofer
##############
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

preset_file="${1:-}"
target_path="${2:-}"
if [[ -z "$preset_file" || -z "$target_path" ]]; then
    log_error "usage: $(basename "$0") <preset_json_file> <target_image_or_directory>"
    exit 1
fi
output_dir="$HOME/muxrc/tools/output/decoys"

mkdir -p "$output_dir"

if [[ -d "$target_path" ]]; then
    output_target="$output_dir/"
    msg_target="directory $(basename "$target_path")"
    elif [[ -f "$target_path" ]]; then
    output_target="$output_dir/$(basename "$target_path")"
    msg_target="file $(basename "$target_path")"
else
    log_error "target not found: $target_path"
    exit 1
fi

declare -a args=()
while IFS="=" read -r key val; do
    args+=("-$key=$val")
done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$preset_file")

trap '[[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null || true; echo -ne "\r\033[K"' EXIT
start_spinner "injecting decoy into $msg_target"
exiftool "${args[@]}" -o "$output_target" "$target_path" >/dev/null
stop_spinner "success" "decoy at: $output_target"
trap - EXIT

exit 0

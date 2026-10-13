#!/data/data/com.termux/files/usr/bin/bash

################
# Meta Date Sync
################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd exiftool
}

validate_target() {
  local target="${1:-}"

  if [[ -z "${target}" ]]; then
    log_error "usage: $(basename "$0") <file_or_directory>"
    return 1
  fi

  if [[ ! -e "${target}" ]]; then
    log_error "target '${target}' not found."
    return 1
  fi

  if [[ ! -r "${target}" ]]; then
    log_error "target '${target}' is not readable."
    return 1
  fi

  return 0
}

sync_metadata_dates() {
  local target="$1"

  trap 'cleanup_spinner' EXIT
  start_spinner "syncing metadata dates"

  exiftool -r -P -overwrite_original_in_place -d "%Y:%m:%d %H:%M:%S" -m -q \
    "-AllDates<FileModifyDate" \
    "-TrackCreateDate<FileModifyDate" \
    "-TrackModifyDate<FileModifyDate" \
    "-MediaCreateDate<FileModifyDate" \
    "-MediaModifyDate<FileModifyDate" \
    "-CreationTime<FileModifyDate" \
    "${target}" > /dev/null 2>&1 || true

  stop_spinner "success" "metadata dates synced."
  trap - EXIT
}

main() {
  local target="${1:-}"

  validate_target "${target}" || exit 1
  check_dependencies || exit 1
  sync_metadata_dates "${target}"
}

main "$@"

#!/data/data/com.termux/files/usr/bin/bash

################
# Meta Date Sync
################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../../lib/init.sh"

check_dependencies() {
  require_cmd exiftool
}

validate_target() {
  local target="${1:-}"

  if [[ -z "${target}" ]]; then
    log_error "usage: media sync <target> (see -h)"
    return 1
  fi

  if [[ ! -e "${target}" ]]; then
    log_error "target '${target}' not found"
    return 1
  fi

  if [[ ! -r "${target}" ]]; then
    log_error "target '${target}' not readable"
    return 1
  fi

  return 0
}

usage() {
  echo "usage: media sync <file_or_directory>"
  echo "sync file modification timestamps with internal"
  echo "exif creation dates (QuickTime UTC compatible)."
}

setup_timezone() {
  # Android does not export TZ by default; fetch from system property for Perl/exiftool
  if [[ -z "${TZ:-}" ]] && command -v getprop > /dev/null 2>&1; then
    local sys_tz
    sys_tz=$(getprop persist.sys.timezone 2> /dev/null || true)
    if [[ -n "${sys_tz}" ]]; then
      export TZ="${sys_tz}"
    fi
  fi
}

sync_metadata_dates() {
  local target="$1"

  setup_timezone

  trap 'cleanup_spinner' EXIT
  start_spinner "syncing metadata dates"

  # -api QuickTimeUTC converts local file time to UTC for QuickTime/MP4 container standards
  exiftool -r -P -overwrite_original_in_place -api QuickTimeUTC -d "%Y:%m:%d %H:%M:%S" -m -q \
    "-AllDates<FileModifyDate" \
    "-TrackCreateDate<FileModifyDate" \
    "-TrackModifyDate<FileModifyDate" \
    "-MediaCreateDate<FileModifyDate" \
    "-MediaModifyDate<FileModifyDate" \
    "-QuickTime:CreationDate<FileModifyDate" \
    "-CreationTime<FileModifyDate" \
    "${target}" > /dev/null 2>&1 || true

  stop_spinner "success" "metadata dates synced"
  trap - EXIT
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local target="${1:-}"

  validate_target "${target}" || exit 1
  check_dependencies || exit 1
  sync_metadata_dates "${target}"
}

main "$@"

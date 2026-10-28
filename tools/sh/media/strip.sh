#!/data/data/com.termux/files/usr/bin/bash

#######################
# EXIF Metadata Cleaner
#######################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../../lib/init.sh"

check_dependencies() {
  require_cmd exiftool
}

validate_target_dir() {
  local target_dir="${1:-}"

  if [[ -z "${target_dir}" ]]; then
    log_error "usage: media strip <directory> (see -h)"
    return 1
  fi

  validate_dir_readable "${target_dir}"
}

usage() {
  echo "usage: media strip <directory>"
  echo "strip all exif metadata from images."
  echo "output is saved to ~/muxrc-out/stripped/"
}

clean_metadata() {
  local target_dir="${1:-}"
  local output_dir="${2:-}"

  if [[ -z "${target_dir}" || -z "${output_dir}" ]]; then
    log_error "missing parameters for metadata cleaning"
    return 1
  fi

  if [[ ! -d "${output_dir}" ]]; then
    mkdir -p "${output_dir}"
  fi

  trap 'cleanup_spinner' EXIT
  start_spinner "stripping metadata"
  exiftool -all= -o "${output_dir}/" "${target_dir}" > /dev/null 2>&1 || true
  stop_spinner "success" "done. saved to ${output_dir}/"
  trap - EXIT
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local target_dir="${1:-}"
  local output_dir="${HOME}/muxrc-out/stripped"

  validate_target_dir "${target_dir}" || exit 1
  check_dependencies || exit 1

  clean_metadata "${target_dir}" "${output_dir}"
}

main "$@"

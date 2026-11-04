#!/data/data/com.termux/files/usr/bin/bash

#######################
# EXIF Metadata Cleaner
#######################
set -euo pipefail

source "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")/../../../lib/init.sh"

check_dependencies() {
  require_cmd exiftool
}

validate_target() {
  local target="${1:-}"

  if [[ -z "${target}" ]]; then
    log_error "usage: media strip <file_or_directory> (see -h)"
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
  echo "usage: media strip <file_or_directory>"
  echo "strip all exif metadata from image file or directory."
  echo "output is saved to ~/muxrc-out/stripped/"
}

clean_metadata() {
  local target="${1:-}"
  local output_dir="${2:-}"

  if [[ -z "${target}" || -z "${output_dir}" ]]; then
    log_error "missing strip parameters"
    return 1
  fi

  if [[ ! -d "${output_dir}" ]]; then
    mkdir -p "${output_dir}"
  fi

  if [[ -d "${target}" ]]; then
    local file_count=0
    file_count=$(find "${target}" -maxdepth 1 -type f 2> /dev/null | wc -l || echo 0)

    if [[ "${file_count}" -eq 0 ]]; then
      log_info "no files found in '${target}'"
      return 0
    fi

    local confirm=""
    log_prompt "strip metadata from ${file_count} files? [y/N]: "
    read -r confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      log_warn "aborted"
      return 1
    fi

    trap 'cleanup_spinner' EXIT
    start_spinner "stripping metadata"
    exiftool -all= -o "${output_dir}/" "${target}" > /dev/null 2>&1 || true
    stop_spinner "success" "done. saved to ${output_dir}/"
    trap - EXIT
  elif [[ -f "${target}" ]]; then
    local bname
    bname="$(basename "${target}")"
    local out_file="${output_dir}/${bname}"
    [[ -f "${out_file}" ]] && rm -f "${out_file}"

    trap 'cleanup_spinner' EXIT
    start_spinner "stripping metadata from ${bname}"
    exiftool -all= -o "${out_file}" "${target}" > /dev/null 2>&1 || true
    stop_spinner "success" "done. saved to ${out_file}"
    trap - EXIT
  else
    log_error "unsupported target type: ${target}"
    return 1
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local target="${1:-}"
  local output_dir="${HOME}/muxrc-out/stripped"

  validate_target "${target}" || exit 1
  check_dependencies || exit 1

  clean_metadata "${target}" "${output_dir}"
}

main "$@"

#!/data/data/com.termux/files/usr/bin/bash

##########################
# HEVC Video Re-compressor
##########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

CURRENT_TEMP=""

cleanup() {
  if [[ -n "${CURRENT_TEMP:-}" && -f "${CURRENT_TEMP}" ]]; then
    rm -f "${CURRENT_TEMP}" 2> /dev/null || true
  fi
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

check_dependencies() {
  require_cmd ffmpeg touch mv stat
}

compress_video() {
  local target_file="${1:-}"

  if [[ -z "${target_file}" ]]; then
    log_error "usage: $(basename "$0") <video_file>"
    return 1
  fi

  if [[ ! -f "${target_file}" ]]; then
    log_error "file '${target_file}' not found."
    return 1
  fi

  if [[ ! -r "${target_file}" ]]; then
    log_error "file '${target_file}' is not readable."
    return 1
  fi

  if [[ ! -w "${target_file}" ]]; then
    log_error "file '${target_file}' is not writable."
    return 1
  fi

  if [[ ! -s "${target_file}" ]]; then
    log_error "file '${target_file}' is empty (0 bytes)."
    return 1
  fi

  local dir_name
  dir_name="$(dirname "${target_file}")"
  local file_name
  file_name="$(basename "${target_file}")"

  local ext="${file_name##*.}"
  if [[ "${ext}" == "${file_name}" ]]; then
    log_error "file '${target_file}' has no extension."
    return 1
  fi

  local base="${file_name%.*}"
  local temp_file="${dir_name}/.${base}.muxrc-temp.${ext}"

  CURRENT_TEMP="${temp_file}"
  rm -f "${temp_file}" 2> /dev/null || true

  local orig_size
  orig_size=$(stat -c '%s' "${target_file}" 2> /dev/null || wc -c < "${target_file}")

  log_info "re-compressing '${file_name}' to hevc..."

  local -a mov_opts=()
  local ext_lower="${ext,,}"
  if [[ "${ext_lower}" =~ ^(mp4|mov|m4v)$ ]]; then
    mov_opts=(-movflags use_metadata_tags)
  fi

  if ! ffmpeg -hide_banner -loglevel error -stats -y -i "${target_file}" \
    -map 0 -c copy -c:v libx265 -preset slow -crf 18 \
    -map_metadata 0 "${mov_opts[@]}" \
    "${temp_file}"; then
    log_error "ffmpeg encoding failed."
    return 1
  fi

  if [[ ! -s "${temp_file}" ]]; then
    log_error "output file is missing or empty."
    return 1
  fi

  touch -r "${target_file}" "${temp_file}" 2> /dev/null || true

  local new_size
  new_size=$(stat -c '%s' "${temp_file}" 2> /dev/null || wc -c < "${temp_file}")

  mv -f "${temp_file}" "${target_file}"
  CURRENT_TEMP=""

  local orig_fmt
  orig_fmt=$(format_bytes "${orig_size}")
  local new_fmt
  new_fmt=$(format_bytes "${new_size}")

  if ((orig_size > 0 && new_size < orig_size)); then
    local saved_pct
    saved_pct=$(awk -v o="${orig_size}" -v n="${new_size}" 'BEGIN { printf "%.1f", ((o - n) / o) * 100 }')
    log_success "compression complete: ${orig_fmt} -> ${new_fmt} (${saved_pct}% saved)."
  elif ((new_size >= orig_size)); then
    log_warn "compression complete: ${orig_fmt} -> ${new_fmt} (output is larger or equal)."
  else
    log_success "compression complete: ${new_fmt}."
  fi
}

main() {
  check_dependencies || exit 1
  compress_video "$@"
}

main "$@"

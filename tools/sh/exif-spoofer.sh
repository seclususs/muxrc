#!/data/data/com.termux/files/usr/bin/bash

##############
# EXIF Spoofer
##############
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd exiftool jq
}

validate_inputs() {
  local preset_file="${1:-}"
  local target_path="${2:-}"

  if [[ -z "${preset_file}" || -z "${target_path}" ]]; then
    log_error "usage: $(basename "$0") <preset_json_file> <target_image_or_directory>"
    return 1
  fi

  validate_file_readable "${preset_file}" || return 1

  if [[ ! -e "${target_path}" ]]; then
    log_error "target not found: ${target_path}"
    return 1
  fi

  if [[ ! -r "${target_path}" ]]; then
    log_error "target is not readable: ${target_path}"
    return 1
  fi

  return 0
}

execute_spoof() {
  local preset_file="${1:-}"
  local target_path="${2:-}"
  local output_dir="${3:-}"

  if [[ -z "${preset_file}" || -z "${target_path}" || -z "${output_dir}" ]]; then
    log_error "missing parameters for spoof execution."
    return 1
  fi

  local output_target
  local msg_target
  local key
  local val
  local -a args=()

  if [[ ! -d "${output_dir}" ]]; then
    mkdir -p "${output_dir}"
  fi

  if [[ -d "${target_path}" ]]; then
    output_target="${output_dir}/"
    msg_target="directory $(basename "${target_path}")"
  elif [[ -f "${target_path}" ]]; then
    output_target="${output_dir}/$(basename "${target_path}")"
    msg_target="file $(basename "${target_path}")"
    [[ -f "${output_target}" ]] && rm -f "${output_target}"
  else
    log_error "unsupported target type: ${target_path}"
    return 1
  fi

  while IFS="=" read -r key val; do
    if [[ ! "${key}" =~ ^[A-Za-z0-9_]+$ ]]; then
      log_warn "skipping invalid metadata key: ${key}"
      continue
    fi
    args+=("-${key}=${val}")
  done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "${preset_file}")

  trap 'cleanup_spinner' EXIT
  start_spinner "injecting decoy into ${msg_target}"
  exiftool "${args[@]}" -o "${output_target}" "${target_path}" > /dev/null
  stop_spinner "success" "decoy at: ${output_target}"
  trap - EXIT
}

main() {
  local preset_file="${1:-}"
  local target_path="${2:-}"
  local output_dir="${HOME}/muxrc-out/decoys"

  validate_inputs "${preset_file}" "${target_path}" || exit 1
  check_dependencies || exit 1

  execute_spoof "${preset_file}" "${target_path}" "${output_dir}"
}

main "$@"

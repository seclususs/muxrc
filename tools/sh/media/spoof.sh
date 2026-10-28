#!/data/data/com.termux/files/usr/bin/bash

##############
# EXIF Spoofer
##############
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../../lib/init.sh"

check_dependencies() {
  require_cmd exiftool jq
}

usage() {
  echo "usage: media spoof [preset_json_file] <target>"
  echo "inject decoy exif metadata into target."
  echo "omitting preset selects a random natural template."
  echo "output is saved to ~/muxrc-out/decoys/"
}

resolve_preset() {
  local preset_input="${1:-}"
  local script_dir
  script_dir="$(dirname "$(realpath "$0")")"
  local repo_presets="${script_dir}/../../../tools/presets"
  local user_presets="${XDG_CONFIG_HOME:-${HOME}/.config}/muxrc/presets"
  local clean_name="${preset_input%.json}"

  if [[ -f "${preset_input}" ]]; then
    printf "%s\n" "${preset_input}"
    return 0
  elif [[ -f "${user_presets}/${clean_name}.json" ]]; then
    printf "%s\n" "${user_presets}/${clean_name}.json"
    return 0
  elif [[ -f "${repo_presets}/${clean_name}.json" ]]; then
    printf "%s\n" "${repo_presets}/${clean_name}.json"
    return 0
  fi

  log_error "preset '${preset_input}' not found in presets or path"
  return 1
}

select_random_preset() {
  local script_dir
  script_dir="$(dirname "$(realpath "$0")")"
  local repo_presets="${script_dir}/../../../tools/presets"
  local user_presets="${XDG_CONFIG_HOME:-${HOME}/.config}/muxrc/presets"
  local -A seen=()
  local -a candidates=()
  local p
  local bname

  if [[ -d "${user_presets}" ]]; then
    for p in "${user_presets}"/*.json; do
      if [[ -f "${p}" ]]; then
        bname="$(basename "${p}")"
        seen["${bname}"]=1
        candidates+=("${p}")
      fi
    done
  fi

  if [[ -d "${repo_presets}" ]]; then
    for p in "${repo_presets}"/*.json; do
      if [[ -f "${p}" ]]; then
        bname="$(basename "${p}")"
        if [[ -z "${seen[${bname}]:-}" ]]; then
          seen["${bname}"]=1
          candidates+=("${p}")
        fi
      fi
    done
  fi

  if [[ ${#candidates[@]} -eq 0 ]]; then
    log_error "no metadata templates found in presets"
    return 1
  fi

  local rand_idx=$((RANDOM % ${#candidates[@]}))
  printf "%s\n" "${candidates[rand_idx]}"
}

execute_spoof() {
  local preset_file="${1:-}"
  local target_path="${2:-}"
  local output_dir="${3:-}"

  if [[ -z "${preset_file}" || -z "${target_path}" || -z "${output_dir}" ]]; then
    log_error "missing parameters for spoof execution"
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
    msg_target="dir $(basename "${target_path}")"
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

  if [[ ${#args[@]} -eq 0 ]]; then
    log_error "no valid metadata keys found in preset"
    return 1
  fi

  trap 'cleanup_spinner' EXIT
  start_spinner "injecting decoy into ${msg_target}"
  if exiftool "${args[@]}" -o "${output_target}" "${target_path}" > /dev/null 2>&1; then
    stop_spinner "success" "decoy saved to ${output_target}"
    trap - EXIT
    return 0
  else
    stop_spinner "error" "decoy injection failed"
    trap - EXIT
    return 1
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local preset_file=""
  local target_path=""
  local output_dir="${HOME}/muxrc-out/decoys"

  if [[ $# -eq 1 ]]; then
    target_path="$1"
  elif [[ $# -ge 2 ]]; then
    preset_file=$(resolve_preset "$1") || exit 1
    target_path="$2"
  else
    log_error "usage: media spoof [preset_json_file] <target> (see -h)"
    exit 1
  fi

  if [[ ! -e "${target_path}" ]]; then
    log_error "target not found: ${target_path}"
    exit 1
  fi

  if [[ ! -r "${target_path}" ]]; then
    log_error "target not readable: ${target_path}"
    exit 1
  fi

  if [[ -z "${preset_file}" ]]; then
    preset_file=$(select_random_preset) || exit 1
    local p_name
    p_name="$(basename "${preset_file%.json}")"
    log_info "using random template: ${p_name}"
  fi

  check_dependencies || exit 1

  execute_spoof "${preset_file}" "${target_path}" "${output_dir}"
}

main "$@"

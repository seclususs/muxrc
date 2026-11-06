#!/data/data/com.termux/files/usr/bin/bash

##########################
# Permanent Media Shredder
##########################
[[ $- != *i* ]] && set -euo pipefail

if ! declare -F start_spinner > /dev/null 2>&1; then
  _shredder_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
  if [[ -f "${_shredder_dir}/init.sh" ]]; then
    source "${_shredder_dir}/init.sh"
  fi
fi

###############################
# Securely wipe and remove file
###############################
shred_file() {
  local target_file="${1:-}"
  local silent="${2:-0}"

  if [[ -z "${target_file}" || ! -f "${target_file}" ]]; then
    return 1
  fi

  if ! command -v shred > /dev/null 2>&1; then
    rm -P "${target_file}" 2> /dev/null || rm -f "${target_file}" 2> /dev/null || true
    return 0
  fi

  if ((silent == 1)); then
    shred -u -z -n 3 -- "${target_file}" 2> /dev/null || rm -f "${target_file}" 2> /dev/null || true
  else
    trap 'cleanup_spinner' EXIT
    start_spinner "shredding $(basename "${target_file}")"
    shred -u -z -n 3 -- "${target_file}"
    stop_spinner "success" "file destroyed"
    trap - EXIT
  fi
}

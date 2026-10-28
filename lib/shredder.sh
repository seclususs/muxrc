#!/data/data/com.termux/files/usr/bin/bash

##########################
# Permanent Media Shredder
##########################
[[ $- != *i* ]] && set -euo pipefail

_shredder_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
if [[ -f "${_shredder_dir}/init.sh" ]]; then
  source "${_shredder_dir}/init.sh"
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

confirm_destruction() {
  local target_file="${1:-}"
  local confirm=""

  log_warn "permanently destroying: ${target_file}"
  log_prompt "type 'shred' to confirm: "
  read -r confirm

  [[ "${confirm}" == "shred" || "${confirm}" == "SHRED" ]]
}

usage() {
  echo "usage: sec shred <file_path> [-f|--force]"
  echo "securely destroy file with 3-pass overwrite."
}

shred_main() {
  local target_file=""
  local force=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      -f | --force)
        force=1
        ;;
      -*)
        log_error "unknown option: $1 (see -h)"
        return 1
        ;;
      *)
        if [[ -z "${target_file}" ]]; then
          target_file="$1"
        else
          log_error "unexpected argument: $1"
          return 1
        fi
        ;;
    esac
    shift
  done

  if [[ -z "${target_file}" ]]; then
    log_error "usage: sec shred <file_path> (see -h)"
    return 1
  fi

  validate_file_writable "${target_file}" || return 1
  require_cmd shred || return 1

  if ((force == 1)) || confirm_destruction "${target_file}"; then
    shred_file "${target_file}" 0
  else
    log_warn "aborted"
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  shred_main "$@"
fi

#!/data/data/com.termux/files/usr/bin/bash

##########################
# Permanent Media Shredder
##########################
[[ $- != *i* ]] && set -euo pipefail

source "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")/init.sh"

confirm_destruction() {
  local target_file="${1:-}"
  local confirm=""

  log_warn "destroying: ${target_file}"
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
    log_error "usage: sec shred <file>"
    return 1
  fi

  validate_file_writable "${target_file}" || return 1

  if ((force == 1)) || confirm_destruction "${target_file}"; then
    shred_file "${target_file}" 0
  else
    log_warn "aborted"
    return 1
  fi
}

shred_main "$@"

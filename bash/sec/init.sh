#!/data/data/com.termux/files/usr/bin/bash

#######################
# Security Domain Setup
#######################

_sec_init_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
_repo_dir="$(dirname "$(dirname "${_sec_init_dir}")")"
export MUXRC_DIR="${MUXRC_DIR:-${_repo_dir}}"

# shellcheck source=../../sh/init.sh
source "${MUXRC_DIR}/sh/init.sh"

export VAULT_DIR="${VAULT_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/muxrc/vault}"

ensure_vault_dir() {
  local target_vault="${1:-${VAULT_DIR}}"
  mkdir -p "${target_vault}"
  if [[ ! -f "${target_vault}/.nomedia" ]]; then
    touch "${target_vault}/.nomedia"
  fi
}

unset _sec_init_dir _repo_dir

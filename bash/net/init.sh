#!/data/data/com.termux/files/usr/bin/bash

######################
# Network Domain Setup
######################

_net_init_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
_repo_dir="$(dirname "$(dirname "${_net_init_dir}")")"
export MUXRC_DIR="${MUXRC_DIR:-${_repo_dir}}"

# shellcheck source=../../sh/init.sh
source "${MUXRC_DIR}/sh/init.sh"

run_as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo > /dev/null 2>&1; then
    sudo "$@"
  elif command -v su > /dev/null 2>&1 && su -c true 2> /dev/null; then
    su -c "$*"
  else
    log_error "root required"
    return 1
  fi
}

unset _net_init_dir _repo_dir

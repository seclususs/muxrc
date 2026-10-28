#!/data/data/com.termux/files/usr/bin/bash

#####################
# Core Initialization
#####################
[[ $- != *i* ]] && set -euo pipefail

_lib_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"

for _lib_module in colors.sh logger.sh formatter.sh validator.sh net.sh; do
  if [[ -f "${_lib_dir}/${_lib_module}" ]]; then
    source "${_lib_dir}/${_lib_module}"
  else
    echo "[!] missing library module: ${_lib_dir}/${_lib_module}" >&2
    exit 1
  fi
done
unset _lib_dir _lib_module

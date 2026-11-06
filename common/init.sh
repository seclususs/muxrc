#!/data/data/com.termux/files/usr/bin/bash

#####################
# Core Initialization
#####################
[[ $- != *i* ]] && set -euo pipefail

_common_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"

for _common_module in colors.sh logger.sh formatter.sh validator.sh net.sh shredder.sh; do
  if [[ -f "${_common_dir}/${_common_module}" ]]; then
    source "${_common_dir}/${_common_module}"
  else
    echo "[!] missing library module: ${_common_dir}/${_common_module}" >&2
    exit 1
  fi
done
unset _common_dir _common_module

#!/data/data/com.termux/files/usr/bin/bash

######################
# Dossier Domain Setup
######################

_dossier_init_dir="${BASH_SOURCE[0]%/*}"
if [[ "${_dossier_init_dir}" == "${BASH_SOURCE[0]}" ]]; then
  _dossier_init_dir="."
fi
_repo_dir="$(cd "${_dossier_init_dir}/../.." && pwd -P 2> /dev/null || echo "${_dossier_init_dir}/../..")"
export MUXRC_DIR="${MUXRC_DIR:-${_repo_dir}}"

# shellcheck source=../../sh/init.sh
source "${MUXRC_DIR}/sh/init.sh"

export DOSSIER_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/dossier"
export DOSSIER_CONFIG_FILE="${DOSSIER_CONFIG_DIR}/config.env"

unset _dossier_init_dir _repo_dir

#!/data/data/com.termux/files/usr/bin/bash

####################
# Media Domain Setup
####################

_media_init_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
_repo_dir="$(dirname "$(dirname "${_media_init_dir}")")"
export MUXRC_DIR="${MUXRC_DIR:-${_repo_dir}}"

# shellcheck source=../../sh/init.sh
source "${MUXRC_DIR}/sh/init.sh"

export MUXRC_OUT="${MUXRC_OUT:-${HOME}/muxrc-out}"
export MUXRC_DECOY_OUT="${MUXRC_DECOY_OUT:-${MUXRC_OUT}/decoys}"
export MUXRC_COMP_OUT="${MUXRC_COMP_OUT:-${MUXRC_OUT}/compressed}"

ensure_media_dirs() {
  mkdir -p "${MUXRC_OUT}" "${MUXRC_DECOY_OUT}" "${MUXRC_COMP_OUT}"
}

unset _media_init_dir _repo_dir

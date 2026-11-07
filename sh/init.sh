#!/data/data/com.termux/files/usr/bin/sh

#####################
# Core Initialization
#####################
case "$-" in
  *i*) ;;
  *) set -eu ;;
esac

_sh_dir=""
if [ -n "${MUXRC_DIR:-}" ] && [ -d "${MUXRC_DIR}/sh" ]; then
  _sh_dir="${MUXRC_DIR}/sh"
elif [ -n "${SCRIPT_DIR:-}" ] && [ -d "${SCRIPT_DIR}/sh" ]; then
  _sh_dir="${SCRIPT_DIR}/sh"
elif [ -d "${HOME:-}/muxrc/sh" ]; then
  _sh_dir="${HOME:-}/muxrc/sh"
fi

if [ -z "${_sh_dir}" ]; then
  _self="$0"
  _dir="${_self%/*}"
  for _cand in "${_dir}" "${_dir}/sh" "${_dir}/../sh" "${_dir}/../../sh"; do
    if [ -f "${_cand}/lib/colors.sh" ] || [ -f "${_cand}/colors.sh" ]; then
      _sh_dir="${_cand}"
      break
    fi
  done
  unset _self _dir _cand
fi

_lib_dir="${_sh_dir}/lib"
[ ! -d "${_lib_dir}" ] && _lib_dir="${_sh_dir}"

for _module in colors.sh logger.sh formatter.sh validator.sh prompt.sh net.sh shredder.sh; do
  if [ -f "${_lib_dir}/${_module}" ]; then
    . "${_lib_dir}/${_module}"
  else
    printf '[!] missing library module: %s/%s\n' "${_lib_dir}" "${_module}" >&2
    exit 1
  fi
done
unset _sh_dir _lib_dir _module

#!/data/data/com.termux/files/usr/bin/sh

##########################
# Permanent Media Shredder
##########################
case "$-" in
  *i*) ;;
  *) set -eu ;;
esac

if ! command -v start_spinner > /dev/null 2>&1; then
  _shredder_dir="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
  if [ -f "${_shredder_dir}/../init.sh" ]; then
    . "${_shredder_dir}/../init.sh"
  elif [ -f "${_shredder_dir}/init.sh" ]; then
    . "${_shredder_dir}/init.sh"
  fi
fi

###############################
# Securely wipe and remove file
###############################
shred_file() {
  local target_file="${1:-}"
  local silent="${2:-0}"

  if [ -z "${target_file}" ] || [ ! -f "${target_file}" ]; then
    return 1
  fi

  if ! command -v shred > /dev/null 2>&1; then
    rm -P "${target_file}" 2> /dev/null || rm -f "${target_file}" 2> /dev/null || true
    return 0
  fi

  if [ "${silent}" -eq 1 ]; then
    shred -u -z -n 3 -- "${target_file}" 2> /dev/null || rm -f "${target_file}" 2> /dev/null || true
  else
    trap 'cleanup_spinner' EXIT
    start_spinner "shredding $(basename "${target_file}")"
    shred -u -z -n 3 -- "${target_file}"
    stop_spinner "success" "file destroyed"
    trap - EXIT
  fi
}

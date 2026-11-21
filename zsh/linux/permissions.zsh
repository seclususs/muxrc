###########################
# Safe permissions modifier
###########################

_is_shared_storage() {
  local p real_p
  for p in "$@"; do
    [[ "$p" == -* ]] && continue
    real_p="${p:A}"
    case "$real_p" in
      /sdcard | /sdcard/* | /storage/* | "$HOME/storage" | "$HOME/storage/"*) return 0 ;;
    esac
  done
  return 1
}

chmod() {
  local -a targets=()
  local mode_seen=0
  local arg
  for arg in "$@"; do
    if [[ "$arg" == --reference=* ]]; then
      targets+=("${arg#--reference=}")
      mode_seen=1
    elif [[ "$arg" == -* ]]; then
      continue
    elif (( ! mode_seen )); then
      mode_seen=1
    else
      targets+=("$arg")
    fi
  done
  if (( ${#targets} > 0 )) && _is_shared_storage "${targets[@]}"; then
    return 0
  fi
  command chmod "$@"
}

chown() {
  local -a targets=()
  local owner_seen=0
  local arg
  for arg in "$@"; do
    if [[ "$arg" == --reference=* ]]; then
      targets+=("${arg#--reference=}")
      owner_seen=1
    elif [[ "$arg" == -* ]]; then
      continue
    elif (( ! owner_seen )); then
      owner_seen=1
    else
      targets+=("$arg")
    fi
  done
  if (( ${#targets} > 0 )) && _is_shared_storage "${targets[@]}"; then
    return 0
  fi
  command chown "$@"
}

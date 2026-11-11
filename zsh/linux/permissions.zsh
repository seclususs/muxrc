###########################
# Safe permissions modifier
###########################

_is_shared_storage() {
  local p real_p
  for p in "$PWD" "$@"; do
    [[ "$p" == -* ]] && continue
    real_p="${p:A}"
    case "$real_p" in
      /sdcard | /sdcard/* | /storage/* | "$HOME/storage" | "$HOME/storage/"*) return 0 ;;
    esac
  done
  return 1
}

chmod() {
  if _is_shared_storage "$@"; then
    return 0
  fi
  command chmod "$@"
}

chown() {
  if _is_shared_storage "$@"; then
    return 0
  fi
  command chown "$@"
}

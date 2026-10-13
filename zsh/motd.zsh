###########################
# Message of the Day Banner
###########################
() {
  if [[ -o interactive && "$EUID" -ne 0 ]]; then
    local android_ver
    local device

    android_ver=$(getprop ro.build.version.release 2> /dev/null)
    device=$(getprop ro.product.model 2> /dev/null)

    print -P "%F{39}$(whoami)@termux%f - ${device:-unknown device} · Android ${android_ver:-?}"
    print -P "Storage: $(df -h "$HOME" | awk 'NR==2 {print $4" free"}')"
  fi
}

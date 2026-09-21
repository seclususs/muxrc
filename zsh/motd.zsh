###########################
# Message of the day banner
###########################
() {
    if [[ -o interactive && "$TERMUX_FAKEROOT" != "1" ]]; then
        local android_ver device
        
        android_ver=$(getprop ro.build.version.release 2>/dev/null)
        device=$(getprop ro.product.model 2>/dev/null)
        
        print -P "%F{39}$(whoami)@termux%f - ${device:-unknown device} · Android ${android_ver:-?}"
        print -P "Storage: $(df -h "$HOME" | awk 'NR==2 {print $4" free"}')"
    fi
}

###########################
# Message of the day banner
###########################
if [[ -o interactive && "$TERMUX_FAKEROOT" != "1" ]]; then
    local android_ver device batt_json batt_pct

    android_ver=$(getprop ro.build.version.release 2>/dev/null)
    device=$(getprop ro.product.model 2>/dev/null)

    if command -v termux-battery-status >/dev/null 2>&1; then
        batt_json=$(termux-battery-status 2>/dev/null)
        batt_pct="${batt_json##*\"percentage\": }"
        batt_pct="${batt_pct%%,*}"
    fi

    print -P "%F{39}$(whoami)@termux%f - ${device:-unknown device} · Android ${android_ver:-?}"
    [[ -n "$batt_pct" ]] && print -P "Battery: ${batt_pct}%%"
    print -P "Storage: $(df -h "$HOME" | awk 'NR==2 {print $4" free"}')"
fi

#############################
# Battery & ACPI info wrapper
#############################

acpi() {
  local -a orig_args=("$@")
  local mode="battery"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -b | --battery)
        mode="battery"
        ;;
      -t | --thermal)
        mode="thermal"
        ;;
      -a | --ac-adapter)
        mode="ac"
        ;;
      -V | --everything)
        mode="all"
        ;;
      -v | --version)
        print "acpi from muxrc (termux emulation)"
        return 0
        ;;
      -h | --help)
        print "Usage: acpi [options]"
        print ""
        print "Options:"
        print "  -b, --battery       show battery information"
        print "  -t, --thermal       show thermal information"
        print "  -a, --ac-adapter    show ac adapter information"
        print "  -V, --everything    show all information"
        print "  -v, --version       display version information and exit"
        return 0
        ;;
      *)
        ;;
    esac
    shift
  done

  if ! command -v termux-battery-status > /dev/null 2>&1; then
    if [[ -x /system/bin/acpi ]]; then
      /system/bin/acpi "${orig_args[@]}"
      return $?
    fi
    print -u2 "acpi: termux-api not installed (pkg install termux-api)"
    return 1
  fi

  local raw_json
  raw_json=$(termux-battery-status 2> /dev/null)
  if [[ -z "$raw_json" ]]; then
    print -u2 "acpi: unable to retrieve battery status"
    return 1
  fi

  print -r -- "$raw_json" | awk -v mode="$mode" '
    /^[[:space:]]*"status":/ {
      gsub(/[",]/, "", $2)
      st = $2
    }
    /^[[:space:]]*"percentage":/ {
      gsub(/[",]/, "", $2)
      pct = $2
    }
    /^[[:space:]]*"temperature":/ {
      gsub(/[",]/, "", $2)
      temp = $2
    }
    /^[[:space:]]*"plugged":/ {
      gsub(/[",]/, "", $2)
      plug = $2
    }
    END {
      st_low = tolower(st)
      if (st_low == "charging") st_out = "Charging"
      else if (st_low == "discharging") st_out = "Discharging"
      else if (st_low == "full") st_out = "Full"
      else st_out = st

      ac_state = "off-line"
      if (plug != "UNPLUGGED") ac_state = "on-line"

      if (mode == "thermal") {
        printf "Thermal 0: ok, %.1f degrees C\n", temp
      } else if (mode == "ac") {
        printf "Adapter 0: %s\n", ac_state
      } else if (mode == "all") {
        printf "Battery 0: %s, %s%%\n", st_out, pct
        printf "Thermal 0: ok, %.1f degrees C\n", temp
        printf "Adapter 0: %s\n", ac_state
      } else {
        printf "Battery 0: %s, %s%%, %.1f°C\n", st_out, pct, temp
      }
    }
  '
}

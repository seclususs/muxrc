#######################
# Memory & swap monitor
#######################

free() {
  if command -v free > /dev/null 2>&1; then
    if [[ $# -eq 0 ]]; then
      command free -h
    else
      command free "$@"
    fi
    return $?
  fi

  if [[ ! -r /proc/meminfo ]]; then
    print -u2 "free: /proc/meminfo not readable"
    return 1
  fi

  local human=0
  local unit_div=1024
  local unit_suffix="Ki"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --human)
        human=1
        ;;
      -b | --bytes)
        human=0
        unit_div=1
        unit_suffix="B"
        ;;
      -k | --kibi)
        human=0
        unit_div=1024
        unit_suffix="Ki"
        ;;
      -m | --mebi)
        human=0
        unit_div=1048576
        unit_suffix="Mi"
        ;;
      -g | --gibi)
        human=0
        unit_div=1073741824
        unit_suffix="Gi"
        ;;
      -V | --version)
        print "free from muxrc (procps emulation)"
        return 0
        ;;
      --help)
        print "Usage: free [options]"
        print ""
        print "Options:"
        print "  -b, --bytes         show output in bytes"
        print "  -k, --kibi          show output in kibibytes"
        print "  -m, --mebi          show output in mebibytes"
        print "  -g, --gibi          show output in gibibytes"
        print "  -h, --human         show human-readable output"
        print "  -V, --version       display version information and exit"
        return 0
        ;;
      *)
        ;;
    esac
    shift
  done

  awk -v human="$human" -v udiv="$unit_div" -v usuf="$unit_suffix" '
    function fmt(val_kb) {
      if (human == 1) {
        if (val_kb < 1024) return sprintf("%6.0fKi", val_kb);
        if (val_kb < 1048576) return sprintf("%6.1fMi", val_kb / 1024);
        if (val_kb < 1073741824) return sprintf("%6.1fGi", val_kb / 1048576);
        return sprintf("%6.1fTi", val_kb / 1073741824);
      } else {
        if (udiv == 1) return sprintf("%11.0f", val_kb * 1024);
        return sprintf("%11.0f", (val_kb * 1024) / udiv);
      }
    }
    /^MemTotal:/ { total = $2 }
    /^MemFree:/ { free = $2 }
    /^MemAvailable:/ { avail = $2 }
    /^Buffers:/ { buffers = $2 }
    /^Cached:/ { cached = $2 }
    /^SReclaimable:/ { sreclaim = $2 }
    /^Shmem:/ { shmem = $2 }
    /^SwapTotal:/ { swaptotal = $2 }
    /^SwapFree:/ { swapfree = $2 }
    END {
      buff_cache = buffers + cached + sreclaim
      used = total - free - buff_cache
      if (used < 0) used = 0
      swapused = swaptotal - swapfree
      if (swapused < 0) swapused = 0

      printf "%15s%12s%12s%12s%12s%12s\n", "total", "used", "free", "shared", "buff/cache", "available"
      printf "%-6s%12s%12s%12s%12s%12s%12s\n", "Mem:", fmt(total), fmt(used), fmt(free), fmt(shmem), fmt(buff_cache), fmt(avail)
      printf "%-6s%12s%12s%12s\n", "Swap:", fmt(swaptotal), fmt(swapused), fmt(swapfree)
    }
  ' /proc/meminfo
}

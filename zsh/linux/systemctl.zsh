#########################
# Service manager wrapper
#########################

systemctl() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: systemctl {start|stop|restart|status|enable|disable} <service>"
    return 1
  fi

  local action="$1"
  local service="${2%.service}"

  case "$action" in
    start) command sv up "$service" 2> /dev/null ;;
    stop) command sv down "$service" 2> /dev/null ;;
    restart) command sv restart "$service" 2> /dev/null ;;
    status) command sv status "$service" ;;
    enable)
      if [ -d "$PREFIX/share/termux-services/$service" ]; then
        ln -sf "$PREFIX/share/termux-services/$service" "$PREFIX/var/service/"
        echo "Created symlink /"etc"/systemd/system/multi-user.target.wants/${service}.service → /"lib"/systemd/system/${service}.service."
      else
        echo "Failed to enable unit: Unit file ${service}.service does not exist."
        return 1
      fi
      ;;
    disable)
      if command -v sv-disable > /dev/null 2>&1; then
        sv-disable "$service" > /dev/null 2>&1 || true
      fi
      rm -rf "$PREFIX/var/service/$service"
      echo "Removed /"etc"/systemd/system/multi-user.target.wants/${service}.service."
      ;;
    *)
      echo "Unknown operation '$action'."
      return 1
      ;;
  esac
}

service() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: service <service-name> {start|stop|restart|status|enable|disable}"
    echo "       service --status-all"
    return 1
  fi

  case "$1" in
    -h | --help)
      echo "Usage: service <service-name> {start|stop|restart|status|enable|disable}"
      echo "       service --status-all"
      return 0
      ;;
    list | check | call)
      if [[ -x /system/bin/service ]]; then
        /system/bin/service "$@"
      else
        print -u2 "service: /system/bin/service not found"
        return 1
      fi
      ;;
    --status-all)
      if [[ -d "$PREFIX/var/service" ]]; then
        local d
        for d in "$PREFIX/var/service"/*(N); do
          if [[ -d "$d" ]]; then
            command sv status "${d:t}"
          fi
        done
      fi
      ;;
    *)
      if [[ $# -ge 2 ]]; then
        local s_name="$1"
        local s_act="$2"
        systemctl "$s_act" "$s_name"
      else
        echo "Usage: service <service-name> {start|stop|restart|status|enable|disable}"
        return 1
      fi
      ;;
  esac
}


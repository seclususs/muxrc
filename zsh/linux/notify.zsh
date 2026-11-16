###########################
# Notification task wrapper
###########################

notify-send() {
  local title=""
  local content=""
  local priority="normal"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u | --urgency)
        shift
        case "$1" in
          low) priority="low" ;;
          critical) priority="high" ;;
          *) priority="normal" ;;
        esac
        ;;
      -h | --help)
        print "Usage: notify-send [OPTIONS] <SUMMARY> [BODY]"
        return 0
        ;;
      *)
        if [[ -z "$title" ]]; then
          title="$1"
        elif [[ -z "$content" ]]; then
          content="$1"
        else
          content="${content} $1"
        fi
        ;;
    esac
    shift
  done

  [[ -z "$title" ]] && return 1

  if command -v termux-notification > /dev/null 2>&1; then
    termux-notification --title "$title" --content "${content:-}" --priority "$priority" 2> /dev/null || true
  fi
}

notify-task() {
  (($# == 0)) && {
    echo "usage: notify-task <cmd> [args...]"
    return 1
  }

  local label="$*"
  local start=$(date +%s)

  "$@"
  local code=$?
  local secs=$(($(date +%s) - start))
  local task_status="done in ${secs}s"
  ((code != 0)) && task_status="failed (exit ${code}) after ${secs}s"

  command -v termux-vibrate > /dev/null 2>&1 && termux-vibrate -d 250 > /dev/null 2>&1 || true
  command -v termux-notification > /dev/null 2>&1 && termux-notification --id notify-task --title "${label:0:40}" --content "$task_status"
  return $code
}

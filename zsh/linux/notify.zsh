###########################
# Notification task wrapper
###########################

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

###########################
# Safe permissions modifier
###########################

chmod() {
  if [[ "$PWD" == "/sdcard"* || "$PWD" == *"/storage/"* || "$PWD" == *"$HOME/storage"* || "$*" == *"/sdcard"* || "$*" == *"/storage/emulated/"* || "$*" == *"$HOME/storage"* || "$*" == *"/storage/"* ]]; then
    return 0
  fi
  command chmod "$@"
}

chown() {
  if [[ "$PWD" == "/sdcard"* || "$PWD" == *"/storage/"* || "$PWD" == *"$HOME/storage"* || "$*" == *"/sdcard"* || "$*" == *"/storage/emulated/"* || "$*" == *"$HOME/storage"* || "$*" == *"/storage/"* ]]; then
    return 0
  fi
  command chown "$@"
}

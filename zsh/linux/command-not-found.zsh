###########################
# Command not found handler
###########################

command_not_found_handler() {
  local termux_cnf="${PREFIX:-/data/data/com.termux/files/usr}/libexec/termux/command-not-found"

  if [[ -x "$termux_cnf" ]]; then
    "$termux_cnf" "$1"
    return $?
  fi

  print -u2 "zsh: command not found: $1"
  return 127
}

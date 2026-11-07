###########################
# Command not found handler
###########################

command_not_found_handler() {
  local cmd="$1"
  local matches
  matches=$(pkg search "$cmd" 2> /dev/null | grep "^$cmd/")

  if [[ -n "$matches" ]]; then
    print -u2 "zsh: command not found: $cmd"
    print -u2 "Did you mean to install it? Try: pkg install $cmd"
  else
    print -u2 "zsh: command not found: $cmd"
  fi

  return 127
}

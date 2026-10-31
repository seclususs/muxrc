##################################
# NAME: module purpose in one line
##################################
# Sourced at shell startup: no output, prompts, or slow work at source time.

(( ${+_NAME_loaded} )) && return 0
typeset -g _NAME_loaded=1

NAME() {
  emulate -L zsh
  local arg="${1:-}"
  [[ -n ${arg} ]] || {
    print -u2 -r -- "usage: NAME ARG"
    return 2
  }
  (( $+commands[TOOL] )) || {
    print -u2 -r -- "missing command: TOOL (pkg install PACKAGE)"
    return 127
  }
  print -r -- "${arg}"
}

###################
# Logging Functions
###################

log_info() { print -P -n "%F{blue}[*]%f "; print -r -- "$*" }
log_success() { print -P -n "%F{green}[+]%f "; print -r -- "$*" }
log_warn() { print -P -n "%F{yellow}[-]%f "; print -r -- "$*" }
log_error() { print -u2 -P -n "%F{red}[!]%f "; print -u2 -r -- "$*" }

##################
# Wrapper for NAME
##################
# Native wording, streams, and exit codes: no log prefixes, no restyling.

NAME() {
  emulate -L zsh
  command NAME "$@"
}

#!/data/data/com.termux/files/usr/bin/sh

###########################
# NAME: purpose in one line
###########################

set -eu

usage() {
  cat << 'EOF'
Usage: NAME [options] ARG
One-line description.

Options:
  -h, --help   show this help
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" > /dev/null 2>&1 || die "missing command: $1 (install: pkg install PACKAGE)"
}

cleanup() {
  [ -z "${tmp:-}" ] || rm -rf "${tmp}"
}

main() {
  while [ $# -gt 0 ]; do
    case $1 in
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*) die "unknown option: $1" ;;
      *) break ;;
    esac
  done
  [ $# -ge 1 ] || die "missing argument (see --help)"
  require_cmd TOOL
  tmp=$(mktemp -d "${TMPDIR:-${PREFIX}/tmp}/NAME.XXXXXX")
  trap cleanup EXIT INT TERM
  printf '%s\n' "$1"
}

main "$@"

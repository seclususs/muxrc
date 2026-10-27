#!/bin/sh
# Run inside the sandbox:
#   sh scripts/sandbox-run.sh --stub-termux --twice -- tests/NAME.test.sh path/to/script
# HOME, PREFIX, TMPDIR point into the sandbox; termux-* commands are stubs.

set -u
script=${1:?usage: NAME.test.sh SCRIPT}
pass=0
fail=0

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3" >&2
  fi
}

assert_status() { # name expected_status command [args...]
  name=$1
  want=$2
  shift 2
  "$@" > /dev/null 2>&1
  assert_eq "${name}" "${want}" "$?"
}

assert_file() { # name path
  if [ -e "$2" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s: missing %s\n' "$1" "$2" >&2
  fi
}

assert_status "help exits 0" 0 sh "${script}" --help
assert_status "no argument fails" 1 sh "${script}"

printf '%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]

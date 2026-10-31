#!/bin/sh
# selftest.sh - smoke-test the shell tools under .agents/skills on this host.
# Builds a throwaway git repository, runs each tool once, and checks the exit
# status and one marker in the output. When PowerShell is installed, it also
# checks that the .ps1 flavors give the same results as the .sh flavors.
# It reports what works on this host; it does not prove behavior on a device.

# Single quotes are used on purpose for printf formats and -c texts that contain $
# shellcheck disable=SC2016
set -u

here=$(cd "$(dirname "$0")" && pwd)
skills=$(cd "${here}/../.." && pwd)

usage() {
  cat << 'EOF'
Usage: selftest.sh [--keep]

Runs one smoke test per tool and prints PASS, FAIL, or SKIP per line, then
  SELFTEST pass=N fail=N skip=N
A SKIP means a prerequisite is missing on this host (for example shfmt); it is
not a failure. The fixture lives in a temporary directory and is removed unless
--keep is given.
Exit: 0 no FAIL, 1 at least one FAIL, 2 usage error.
EOF
}

keep=0
case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  --keep) keep=1 ;;
  '') ;;
  *)
    usage >&2
    exit 2
    ;;
esac

tmp=$(mktemp -d 2> /dev/null || echo "${TMPDIR:-/tmp}/selftest.$$")
mkdir -p "${tmp}"
# shellcheck disable=SC2317,SC2329
cleanup() {
  if [ "${keep}" -eq 1 ]; then echo "selftest: fixture kept at ${tmp}"; else rm -rf "${tmp}"; fi
}
trap cleanup EXIT INT TERM

pass=0
fail=0
skip=0
ok() {
  pass=$((pass + 1))
  echo "PASS $1"
}
bad() {
  fail=$((fail + 1))
  echo "FAIL $1"
  [ -s "${tmp}/out" ] && sed -n '1,6p' "${tmp}/out" | sed 's/^/     | /'
}
skp() {
  skip=$((skip + 1))
  echo "SKIP $1 ($2)"
}
have() { command -v "$1" > /dev/null 2>&1; }

# run NAME EXPECTED_EXIT MARKER COMMAND...: exit status must match and MARKER (a
# fixed string, may be empty) must appear in stdout+stderr
run() {
  name=$1
  want=$2
  marker=$3
  shift 3
  "$@" > "${tmp}/out" 2>&1
  rc=$?
  if [ "${rc}" -eq "${want}" ] && { [ -z "${marker}" ] || grep -qF -- "${marker}" "${tmp}/out"; }; then
    ok "${name}"
  else
    echo "     exit=${rc} (wanted ${want}) marker='${marker}'"
    bad "${name}"
  fi
}

# Fixture: a git repository with one clean script, one script with a known finding,
# and an .editorconfig
fx="${tmp}/fixture"
mkdir -p "${fx}"
cd "${fx}" || exit 2
printf 'root = true\n\n[*.sh]\nindent_style = space\nindent_size = 2\nspace_redirects = true\n' > .editorconfig
printf '#!/bin/sh\n\ngreet() {\n  printf "hello %%s\\n" "$1"\n}\n\ngreet "${1:-world}"\n' > ok.sh
printf '#!/bin/sh\nrm -rf /tmp/selftest-demo\n' > bad.sh # lint-ignore: T001
printf 'extra-keys = [["ESC","TAB"]]\n' > termux.properties
printf 'greet-a\tgreet a\n' > cases.tsv
if have git; then
  git init -q . 2> /dev/null
  git add -A 2> /dev/null
  git -c user.name=selftest -c user.email=selftest@example.invalid commit -q -m fixture 2> /dev/null
  printf '# change\n' >> ok.sh
fi

S="${skills}"
run "detect-platform.sh tool paths" 0 "tool.sh=" sh "${S}/platform-detection/scripts/detect-platform.sh"
run "detect-platform.sh --brief" 0 "tool.missing=" sh "${S}/platform-detection/scripts/detect-platform.sh" --brief
run "repo-map.sh" 0 "" sh "${S}/using-termux-skills/scripts/repo-map.sh"
run "lint-shell.sh finds T001" 0 "[T001]" sh "${S}/termux-scripting/scripts/lint-shell.sh" --no-external
run "lint-shell.sh --out" 0 "findings written" sh "${S}/termux-scripting/scripts/lint-shell.sh" --no-external --out .artifacts/lint/report.txt
[ -s .artifacts/lint/report.txt ] || {
  : > "${tmp}/out"
  bad "lint-shell.sh --out wrote a file"
}
if have shfmt; then
  run "format-shell.sh check" 0 "SUMMARY" sh "${S}/termux-scripting/scripts/format-shell.sh"
else
  skp "format-shell.sh" "shfmt not installed"
fi
run "def-index.sh record" 0 "" sh "${S}/code-refactoring/scripts/def-index.sh" --out .artifacts/refactor/before.tsv
run "def-index.sh compare" 0 "" sh "${S}/code-refactoring/scripts/def-index.sh" --compare .artifacts/refactor/before.tsv
if have git; then
  run "diff-collect.sh" 0 "MANIFEST" sh "${S}/code-review/scripts/diff-collect.sh"
else
  skp "diff-collect.sh" "git not installed"
fi
printf '#!/bin/sh\ntermux-toast "hello"\nmkdir -p "$HOME/out" && echo ok > "$HOME/out/f"\n' > stub.sh
run "sandbox-run.sh stubs" 0 "termux-toast" sh "${S}/termux-scripting/scripts/sandbox-run.sh" --stub-termux -- stub.sh
printf '#!/bin/sh\nsudo ls || echo blocked\n' > sudo.sh
run "sandbox-run.sh blocks sudo" 0 "blocked" sh "${S}/termux-scripting/scripts/sandbox-run.sh" -- sudo.sh
run "trace-run.sh" 0 "trace-run:" sh "${S}/systematic-debugging/scripts/trace-run.sh" -- ok.sh
run "behavior-snapshot.sh record" 0 "recorded" sh "${S}/code-refactoring/scripts/behavior-snapshot.sh" record --dir .artifacts/snap --cases cases.tsv --source ok.sh
run "behavior-snapshot.sh compare" 0 "different=0" sh "${S}/code-refactoring/scripts/behavior-snapshot.sh" compare --dir .artifacts/snap --cases cases.tsv --source ok.sh
run "check-termux-config.sh" 0 "SUMMARY" sh "${S}/termux-customization/scripts/check-termux-config.sh" termux.properties
run "termux-sim.sh uname" 0 "Android" sh "${S}/termux-environment/scripts/termux-sim.sh" -c 'uname -o'
run "termux-sim.sh non-root su" 1 "No su program found" sh "${S}/termux-environment/scripts/termux-sim.sh" -c 'su -c id'
run "termux-sim.sh --root su" 0 "root-uid=0" sh "${S}/termux-environment/scripts/termux-sim.sh" --root -c 'echo root-uid=$(su -c "id -u")'
run "termux-sim.sh --facts" 0 "sim=yes" sh "${S}/termux-environment/scripts/termux-sim.sh" --facts

# PowerShell flavors: same markers, and lint output identical to the sh flavor
ps=""
for c in pwsh powershell powershell.exe; do
  if have "${c}"; then
    ps=${c}
    break
  fi
done
if [ -n "${ps}" ]; then
  P="${ps} -NoProfile -ExecutionPolicy Bypass -File"
  # shellcheck disable=SC2086
  run "detect-platform.ps1 tool paths" 0 "tool.sh=" ${P} "${S}/platform-detection/scripts/detect-platform.ps1"
  # shellcheck disable=SC2086
  run "detect-platform.ps1 --brief" 0 "tool.missing=" ${P} "${S}/platform-detection/scripts/detect-platform.ps1" --brief
  # shellcheck disable=SC2086
  run "lint-shell.ps1 finds T001" 0 "[T001]" ${P} "${S}/termux-scripting/scripts/lint-shell.ps1" --no-external
  sh "${S}/termux-scripting/scripts/lint-shell.sh" --no-external > "${tmp}/lint.sh.txt" 2>&1
  # shellcheck disable=SC2086
  ${P} "${S}/termux-scripting/scripts/lint-shell.ps1" --no-external > "${tmp}/lint.ps1.txt" 2>&1
  if tr -d '\r' < "${tmp}/lint.ps1.txt" | cmp -s - "${tmp}/lint.sh.txt"; then
    ok "lint-shell sh and ps1 output identical"
  else
    diff "${tmp}/lint.sh.txt" "${tmp}/lint.ps1.txt" > "${tmp}/out" 2>&1
    bad "lint-shell sh and ps1 output identical"
  fi
  if have shfmt; then
    # shellcheck disable=SC2086
    run "format-shell.ps1 check" 0 "SUMMARY" ${P} "${S}/termux-scripting/scripts/format-shell.ps1"
  fi
  if have git; then
    # shellcheck disable=SC2086
    run "diff-collect.ps1" 0 "MANIFEST" ${P} "${S}/code-review/scripts/diff-collect.ps1"
  fi
  # shellcheck disable=SC2086
  run "termux-sim.ps1 uname" 0 "Android" ${P} "${S}/termux-environment/scripts/termux-sim.ps1" -c 'uname -o'
else
  skp "PowerShell flavors" "no pwsh or powershell on PATH"
fi

echo "SELFTEST pass=${pass} fail=${fail} skip=${skip}"
[ "${fail}" -eq 0 ]

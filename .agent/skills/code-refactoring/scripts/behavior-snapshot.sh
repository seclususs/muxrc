#!/bin/sh
# behavior-snapshot.sh - record and compare the observable behavior of shell code across a refactor.
# Each case runs in a fresh Termux-like sandbox (termux-scripting/scripts/sandbox-run.sh).
# Indicative only: it does not replace a run on Termux itself.
set -u

usage() {
  cat << 'EOF'
Usage: behavior-snapshot.sh record  --dir DIR --cases FILE [options]
       behavior-snapshot.sh compare --dir DIR --cases FILE [options]

record   runs every case and stores the results in DIR (the baseline, taken before the refactor).
compare  runs every case again and compares the results with DIR (after each refactor step).

Cases file: one case per line, NAME<TAB>COMMAND LINE. Blank lines and lines starting with # are ignored.
NAME uses letters, digits, dot, underscore, and hyphen. Each case runs after every --source file is sourced.
Per case, DIR holds NAME.out (stdout), NAME.err (stderr), NAME.rc (exit status), and NAME.fx
(recorded stub calls and files created under the sandbox HOME and PREFIX). The sandbox path is replaced
by <SANDBOX>. Cases must be deterministic: avoid dates, process ids, and random values.

When the dialect is bash or zsh and at least one --source is given, the case __state__ is added. It lists
the functions, aliases, exported variable names, and (zsh) hook arrays and options present after sourcing,
which exposes a source line that went missing during a file split.

Options:
  --dir DIR          snapshot directory
  --cases FILE       cases file
  --dialect D        posix | bash | zsh (default: zsh when a --source ends in .zsh, else posix)
  --source FILE      file sourced before every case (repeatable, order preserved)
  --stub SPEC        sandbox stub NAME[=EXIT[:TEXT]] (repeatable)
  --stub-termux      stub the common termux-* API commands
  --seed SRC[:DEST]  copy a file or directory into the sandbox HOME (repeatable)
  --timeout S        per-case timeout in seconds (default 30)
  -h, --help         show this help
Exit codes: 0 recorded or identical, 1 differences found, 2 usage error, 3 no suitable shell or sandbox.
EOF
}

die_usage() {
  echo "behavior-snapshot: $1" >&2
  exit 2
}

[ $# -ge 1 ] || {
  usage >&2
  exit 2
}
case $1 in
  -h | --help)
    usage
    exit 0
    ;;
  record | compare) mode=$1 ;;
  *) die_usage "first argument must be record or compare" ;;
esac
shift

dir=""
cases=""
dialect=""
timeout_s=30
stub_termux=0
nl='
'
sources=""
stubs=""
seeds=""
while [ $# -gt 0 ]; do
  case $1 in
    --dir | --cases | --dialect | --source | --stub | --seed | --timeout)
      [ $# -ge 2 ] || die_usage "$1 needs a value"
      case $1 in
        --dir) dir=$2 ;;
        --cases) cases=$2 ;;
        --dialect) dialect=$2 ;;
        --source)
          [ -f "$2" ] || die_usage "source file not found: $2"
          sources="${sources}$(cd "$(dirname "$2")" && pwd)/$(basename "$2")${nl}"
          ;;
        --stub) stubs="${stubs}${2}${nl}" ;;
        --seed) seeds="${seeds}${2}${nl}" ;;
        --timeout) timeout_s=$2 ;;
      esac
      shift 2
      ;;
    --stub-termux)
      stub_termux=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die_usage "unknown option: $1" ;;
  esac
done

[ -n "${dir}" ] || die_usage "--dir is required"
[ -n "${cases}" ] || die_usage "--cases is required"
[ -f "${cases}" ] || die_usage "cases file not found: ${cases}"
case ${timeout_s} in '' | *[!0-9]*) die_usage "--timeout needs a positive integer" ;; esac
if [ -z "${dialect}" ]; then
  dialect=posix
  case ${sources} in *.zsh"${nl}"*) dialect=zsh ;; esac
fi
case ${dialect} in posix | bash | zsh) ;; *) die_usage "--dialect must be posix, bash, or zsh" ;; esac

here=$(cd "$(dirname "$0")" && pwd)
sandbox="${here}/../../termux-scripting/scripts/sandbox-run.sh"
[ -f "${sandbox}" ] || {
  echo "behavior-snapshot: sandbox-run.sh not found at ${sandbox}" >&2
  exit 3
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/behavior-snapshot.XXXXXX") || die_usage "cannot create a temporary directory"
trap 'rm -rf "${tmp}"' EXIT INT TERM HUP
if [ "${mode}" = record ]; then
  mkdir -p "${dir}" || die_usage "cannot create ${dir}"
  work=${dir}
else
  [ -d "${dir}" ] || die_usage "snapshot directory not found: ${dir}"
  work="${tmp}/current"
  mkdir -p "${work}"
fi

state_cmd() {
  case ${dialect} in
    zsh)
      cat << 'EOS'
print -r -- '[functions]'; print -rl -- ${(ko)functions}; print -r -- '[aliases]'; alias | LC_ALL=C sort; print -r -- '[exports]'; print -rl -- ${(ko)parameters[(R)*export*]}; print -r -- '[hooks]'; print -r -- "chpwd_functions=${(j: :)chpwd_functions}"; print -r -- "precmd_functions=${(j: :)precmd_functions}"; print -r -- "preexec_functions=${(j: :)preexec_functions}"; print -r -- "zshexit_functions=${(j: :)zshexit_functions}"; print -r -- '[options]'; setopt | LC_ALL=C sort
EOS
      ;;
    bash)
      cat << 'EOS'
echo '[functions]'; declare -F | LC_ALL=C sort; echo '[aliases]'; alias | LC_ALL=C sort; echo '[exports]'; compgen -e | LC_ALL=C sort
EOS
      ;;
  esac
}

replace_path() { # replace_path PATH LABEL < in > out (literal replacement, no regex)
  PATH_LITERAL=$1 PATH_LABEL=$2 awk '
    BEGIN { r = ENVIRON["PATH_LITERAL"]; l = ENVIRON["PATH_LABEL"]; n = length(r) }
    {
      s = $0; o = ""
      if (n > 0) { while ((i = index(s, r)) > 0) { o = o substr(s, 1, i - 1) l; s = substr(s, i + n) } }
      print o s
    }'
}

normalize() { # normalize SANDBOX_ROOT < in > out
  replace_path "$1" "<SANDBOX>" | replace_path "${tmp}" "<TMP>"
}

srcline=""
while IFS= read -r s; do
  [ -n "${s}" ] || continue
  [ -z "${srcline}" ] || srcline="${srcline}; "
  srcline="${srcline}. \"${s}\""
done << EOF
${sources}
EOF

run_case() { # run_case NAME COMMANDLINE
  rc_name=$1
  rc_cmd=$2
  drv="${tmp}/drv-${rc_name}.sh"
  printf '%s\n%s\n' "${srcline:-:}" "${rc_cmd}" > "${drv}"
  set -- --keep --dialect "${dialect}" --timeout "${timeout_s}"
  [ "${stub_termux}" -eq 1 ] && set -- "$@" --stub-termux
  while IFS= read -r st; do
    [ -n "${st}" ] && set -- "$@" --stub "${st}"
  done << EOF
${stubs}
EOF
  while IFS= read -r sd; do
    [ -n "${sd}" ] && set -- "$@" --seed "${sd}"
  done << EOF
${seeds}
EOF
  sh "${sandbox}" "$@" -- "${drv}" > "${tmp}/raw.out" 2> "${tmp}/raw.err"
  rc=$?
  root=$(sed -n 's/^sandbox: kept //p' "${tmp}/raw.err" | tail -n 1)
  if ! grep -q '^sandbox: shell=' "${tmp}/raw.err"; then
    cat "${tmp}/raw.err" >&2
    echo "behavior-snapshot: sandbox-run did not run the case (exit ${rc}); see platform-detection for missing shells" >&2
    exit 3
  fi
  normalize "${root}" < "${tmp}/raw.out" > "${work}/${rc_name}.out"
  grep -v '^sandbox:' "${tmp}/raw.err" | normalize "${root}" > "${work}/${rc_name}.err"
  grep '^sandbox:' "${tmp}/raw.err" | grep -v -E '^sandbox: (shell=|kept |note:)' | normalize "${root}" > "${work}/${rc_name}.fx"
  printf '%s\n' "${rc}" > "${work}/${rc_name}.rc"
  if [ -n "${root}" ] && [ -d "${root}/home" ] && [ -d "${root}/prefix" ]; then
    rm -rf "${root}"
  fi
}

tab=$(printf '\t')
: > "${tmp}/names"
total=0
while IFS="${tab}" read -r name cmd; do
  case ${name} in '' | '#'*) continue ;; esac
  case ${name} in *[!A-Za-z0-9._-]*) die_usage "invalid case name: ${name}" ;; esac
  [ -n "${cmd}" ] || die_usage "case ${name} has no command"
  run_case "${name}" "${cmd}"
  printf '%s\n' "${name}" >> "${tmp}/names"
  total=$((total + 1))
done < "${cases}"

if [ -n "${sources}" ] && [ "${dialect}" != posix ]; then
  run_case "__state__" "$(state_cmd)"
  printf '%s\n' "__state__" >> "${tmp}/names"
  total=$((total + 1))
fi

if [ "${mode}" = record ]; then
  echo "behavior-snapshot: recorded ${total} case(s) in ${dir} (dialect=${dialect})"
  while IFS= read -r n; do
    echo "  ${n} rc=$(cat "${dir}/${n}.rc")"
  done < "${tmp}/names"
  exit 0
fi

same=0
diff_n=0
while IFS= read -r n; do
  parts=""
  for ext in out err rc fx; do
    if [ ! -f "${dir}/${n}.${ext}" ]; then
      parts="${parts} ${ext}(no baseline)"
    elif ! cmp -s "${dir}/${n}.${ext}" "${work}/${n}.${ext}"; then
      parts="${parts} ${ext}"
    fi
  done
  if [ -z "${parts}" ]; then
    same=$((same + 1))
    echo "same ${n}"
  else
    diff_n=$((diff_n + 1))
    echo "DIFF ${n}:${parts}"
    for ext in out err rc fx; do
      if [ -f "${dir}/${n}.${ext}" ] && ! cmp -s "${dir}/${n}.${ext}" "${work}/${n}.${ext}"; then
        echo "--- ${n}.${ext} (baseline -> current)"
        diff -u "${dir}/${n}.${ext}" "${work}/${n}.${ext}" | sed '1,2d' | head -n 20
      fi
    done
  fi
done < "${tmp}/names"
echo "SUMMARY cases=${total} same=${same} different=${diff_n}"
[ "${diff_n}" -eq 0 ] || exit 1
exit 0

#!/bin/sh
# trace-run.sh - run a shell script under xtrace and print only bounded tails.
# Keeps $0, arguments, and the exit status of the script. Full logs stay on disk.

set -u

usage() {
  cat << 'EOF'
Usage: trace-run.sh [options] -- SCRIPT [ARGS...]

Run SCRIPT under xtrace with file:line prefixes where the shell supports them.
Prints the exit status, log paths, and the last N lines of stdout and of the
trace/stderr stream (full logs are kept on disk).

Options:
  --shell NAME   dash | busybox | sh | bash | zsh
                 default: from shebang/extension; posix -> dash, else busybox, else sh
  --tail N       lines shown per stream (default 30)
  --timeout S    kill after S seconds (default 60; needs the timeout command)
  --out DIR      keep logs in DIR (default: <project>/.artifacts/trace/<UTC time>, path printed)
  -h, --help     show this help

Notes:
  dash 0.5.12 does not set LINENO, so dash traces carry no line numbers;
  use --shell busybox or bash/zsh for line numbers.
Exit: the script's status (124 on timeout); 2 usage error; 3 no suitable shell.
EOF
}

shell_name=""
tail_n=30
timeout_s=60
outdir=""
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --shell)
      [ $# -ge 2 ] || {
        echo "trace-run: --shell needs a value" >&2
        exit 2
      }
      shell_name=$2
      shift 2
      ;;
    --tail)
      [ $# -ge 2 ] || {
        echo "trace-run: --tail needs a value" >&2
        exit 2
      }
      tail_n=$2
      shift 2
      ;;
    --timeout)
      [ $# -ge 2 ] || {
        echo "trace-run: --timeout needs a value" >&2
        exit 2
      }
      timeout_s=$2
      shift 2
      ;;
    --out)
      [ $# -ge 2 ] || {
        echo "trace-run: --out needs a value" >&2
        exit 2
      }
      outdir=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "trace-run: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *) break ;;
  esac
done
for n in "${tail_n}" "${timeout_s}"; do
  case ${n} in
    '' | *[!0-9]*)
      echo "trace-run: --tail and --timeout must be numbers" >&2
      exit 2
      ;;
  esac
done
if [ $# -lt 1 ] || [ ! -f "$1" ]; then
  echo "trace-run: SCRIPT missing or not a file (usage: trace-run.sh [options] -- SCRIPT [ARGS...])" >&2
  exit 2
fi
script=$1

have() { command -v "$1" > /dev/null 2>&1; }
cr=$(printf '\r')

# Dialect from shebang or extension: posix | bash | zsh
dialect=posix
first=""
IFS= read -r first 2> /dev/null < "${script}" || true
first=${first%"${cr}"}
case ${first} in
  '#!'*)
    case ${first} in
      *zsh*) dialect=zsh ;;
      *bash*) dialect=bash ;;
    esac
    ;;
  *)
    case ${script##*/} in
      *.zsh | .zshrc | .zshenv) dialect=zsh ;;
      *.bash) dialect=bash ;;
    esac
    ;;
esac

if [ -z "${shell_name}" ]; then
  case ${dialect} in
    zsh) shell_name=zsh ;;
    bash) shell_name=bash ;;
    *)
      if have dash; then
        shell_name=dash
      elif have busybox && busybox sh -c ':' > /dev/null 2>&1; then
        shell_name=busybox
      else
        shell_name="sh"
      fi
      ;;
  esac
fi
case ${shell_name} in
  dash | sh | bash | zsh) have "${shell_name}" || shell_name="" ;;
  busybox) { have busybox && busybox sh -c ':' > /dev/null 2>&1; } || shell_name="" ;;
  *)
    echo "trace-run: --shell must be dash, busybox, sh, bash, or zsh" >&2
    exit 2
    ;;
esac
if [ -z "${shell_name}" ]; then
  echo "trace-run: requested shell is not installed on this host (see platform-detection)" >&2
  exit 3
fi

if [ -n "${outdir}" ]; then
  mkdir -p "${outdir}" || exit 2
else
  # Output convention: .artifacts/ at the project root ignores itself in git
  root=$(git rev-parse --show-toplevel 2> /dev/null) || root=$(pwd)
  outdir="${root}/.artifacts/trace/$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mkdir -p "${outdir}" || exit 2
  [ -e "${root}/.artifacts/.gitignore" ] || printf '*\n' > "${root}/.artifacts/.gitignore"
fi
stdout_log="${outdir}/stdout.log"
trace_log="${outdir}/trace.log"

timeout_bin=""
have timeout && timeout_bin=timeout
run() {
  if [ -n "${timeout_bin}" ]; then
    timeout "${timeout_s}" "$@"
  else
    "$@"
  fi
}

lineno=yes
case ${shell_name} in
  bash)
    cat > "${outdir}/ps4.bash" << 'EOF'
PS4='+${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:+${FUNCNAME[0]}():} '
EOF
    run env BASH_ENV="${outdir}/ps4.bash" bash -x "$@" > "${stdout_log}" 2> "${trace_log}"
    rc=$?
    ;;
  zsh)
    mkdir -p "${outdir}/zdot"
    printf '%s\n' "PS4='+%x:%I> '" "setopt xtrace" > "${outdir}/zdot/.zshenv"
    run env ZDOTDIR="${outdir}/zdot" zsh "$@" > "${stdout_log}" 2> "${trace_log}"
    rc=$?
    ;;
  busybox)
    # shellcheck disable=SC2016
    run env 'PS4=+L${LINENO}: ' busybox sh -x "$@" > "${stdout_log}" 2> "${trace_log}"
    rc=$?
    ;;
  *)
    lineno=no
    run "${shell_name}" -x "$@" > "${stdout_log}" 2> "${trace_log}"
    rc=$?
    ;;
esac

# Drop the single trace line produced by the PS4 assignment itself.
if [ "${shell_name}" = bash ]; then
  sed '1{/^+ PS4=/d;}' "${trace_log}" > "${trace_log}.tmp" && mv "${trace_log}.tmp" "${trace_log}"
fi

n_out=$(wc -l < "${stdout_log}" | tr -d ' ')
n_trc=$(wc -l < "${trace_log}" | tr -d ' ')
echo "trace-run: shell=${shell_name} exit=${rc} lineno=${lineno} dir=${outdir}"
[ "${rc}" -eq 124 ] && echo "trace-run: timed out after ${timeout_s}s"
if [ -z "${timeout_bin}" ]; then
  echo "trace-run: note: timeout command not found; no time limit applied"
fi
echo "--- stdout (last ${tail_n} of ${n_out}) ---"
tail -n "${tail_n}" "${stdout_log}"
echo "--- trace+stderr (last ${tail_n} of ${n_trc}) ---"
tail -n "${tail_n}" "${trace_log}"
exit "${rc}"

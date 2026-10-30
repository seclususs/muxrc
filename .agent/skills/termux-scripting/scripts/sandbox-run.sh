#!/bin/sh
# sandbox-run.sh - run a script in an isolated Termux-like sandbox on the host.
# Fake HOME/PREFIX/TMPDIR in a temp dir, stub commands that record their calls,
# clean environment. Indicative only: real Termux behavior needs Termux itself.

set -u

usage() {
  cat << 'EOF'
Usage: sandbox-run.sh [options] -- SCRIPT [ARGS...]

Run SCRIPT in a temp sandbox that mimics Termux paths:
  HOME=<sandbox>/home  PREFIX=<sandbox>/prefix  TMPDIR=$PREFIX/tmp
  TERMUX_VERSION=sandbox  PATH=$PREFIX/bin:<host PATH>
The environment is cleared first (HOME, PREFIX, TMPDIR, PATH, TERM, LANG only).

Options:
  --dialect D        posix | bash | zsh (default: from shebang/extension)
  --stub SPEC        stub command NAME[=EXIT[:TEXT]]; records calls, prints TEXT
                     (repeatable), e.g. --stub termux-battery-status=0:{}
  --stub-termux      stub common termux-* API commands (exit 0, no output)
  --seed SRC[:DEST]  copy a file or directory into HOME (DEST relative to HOME)
  --overlay DIR      copy the contents of DIR into the sandbox root before the run
                     (DIR/home/..., DIR/prefix/..., DIR/sim/...); used by termux-sim
  --env NAME=VALUE   extra environment variable (repeatable); when a NAME
                     repeats, the last one wins; @SANDBOX@ in VALUE becomes the
                     sandbox directory; SANDBOX_DIR is always set
  --twice            run twice and report whether the second run changed files
  --timeout S        kill after S seconds (default 60; needs timeout command)
  --keep             keep the sandbox under <project>/.artifacts/sandbox/ (path printed)
  -h, --help         show this help

Report (stderr, prefix "sandbox:"): exit status, recorded stub calls, files
created under HOME/PREFIX. Literal /data/data/com.termux paths are not remapped.
sudo and doas are always stubbed (exit 127) so a script cannot run them on the host.
Exit: the script's status (124 on timeout); 2 usage error; 3 no suitable shell.
EOF
}

dialect=""
twice=0
keep=0
overlay=""
timeout_s=60
tmp=$(mktemp -d 2> /dev/null || echo "${TMPDIR:-/tmp}/sandbox-run.$$")
mkdir -p "${tmp}"
: > "${tmp}/stubs.list"
: > "${tmp}/seeds.list"
: > "${tmp}/envs.list"
stub_all=0
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      rm -rf "${tmp}"
      exit 0
      ;;
    --dialect | --stub | --seed | --timeout | --overlay | --env)
      if [ $# -lt 2 ]; then
        echo "sandbox-run: $1 needs a value" >&2
        rm -rf "${tmp}"
        exit 2
      fi
      case $1 in
        --dialect) dialect=$2 ;;
        --stub) printf '%s\n' "$2" >> "${tmp}/stubs.list" ;;
        --seed) printf '%s\n' "$2" >> "${tmp}/seeds.list" ;;
        --timeout) timeout_s=$2 ;;
        --overlay) overlay=$2 ;;
        --env)
          case $2 in
            [A-Za-z_]*=* | _*=*) printf '%s\n' "$2" >> "${tmp}/envs.list" ;;
            *)
              echo "sandbox-run: --env needs NAME=VALUE: $2" >&2
              rm -rf "${tmp}"
              exit 2
              ;;
          esac
          ;;
      esac
      shift 2
      ;;
    --stub-termux)
      stub_all=1
      shift
      ;;
    --twice)
      twice=1
      shift
      ;;
    --keep)
      keep=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "sandbox-run: unknown option: $1" >&2
      usage >&2
      rm -rf "${tmp}"
      exit 2
      ;;
    *) break ;;
  esac
done
case ${timeout_s} in
  '' | *[!0-9]*)
    echo "sandbox-run: --timeout must be a number" >&2
    rm -rf "${tmp}"
    exit 2
    ;;
esac
case ${dialect} in
  '' | posix | bash | zsh) ;;
  *)
    echo "sandbox-run: --dialect must be posix, bash, or zsh" >&2
    rm -rf "${tmp}"
    exit 2
    ;;
esac
if [ $# -lt 1 ] || [ ! -f "$1" ]; then
  echo "sandbox-run: SCRIPT missing or not a file (usage: sandbox-run.sh [options] -- SCRIPT [ARGS...])" >&2
  rm -rf "${tmp}"
  exit 2
fi
script=$1
shift
if [ -n "${overlay}" ] && [ ! -d "${overlay}" ]; then
  echo "sandbox-run: --overlay is not a directory: ${overlay}" >&2
  rm -rf "${tmp}"
  exit 2
fi

# Output directory convention: <project root>/.artifacts/<tool>/ (self-ignoring in git)
# shellcheck disable=SC2317,SC2329
artifacts_dir() {
  root=$(git rev-parse --show-toplevel 2> /dev/null) || root=$(pwd)
  mkdir -p "${root}/.artifacts/$1" 2> /dev/null || return 1
  [ -e "${root}/.artifacts/.gitignore" ] || printf '*\n' > "${root}/.artifacts/.gitignore"
  printf '%s\n' "${root}/.artifacts/$1"
}

# shellcheck disable=SC2317,SC2329
cleanup() {
  if [ "${keep}" -eq 1 ]; then
    dest=""
    base=$(artifacts_dir sandbox) && dest="${base}/$(date -u +%Y%m%dT%H%M%SZ)-$$"
    if [ -n "${dest}" ] && mv "${tmp}" "${dest}" 2> /dev/null; then
      echo "sandbox: kept ${dest}" >&2
    else
      echo "sandbox: kept ${tmp}" >&2
    fi
  else
    rm -rf "${tmp}"
  fi
}
trap cleanup EXIT INT TERM

have() { command -v "$1" > /dev/null 2>&1; }
cr=$(printf '\r')

# Dialect from shebang or extension
if [ -z "${dialect}" ]; then
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
fi
shell_name=""
case ${dialect} in
  zsh) have zsh && shell_name=zsh ;;
  bash) have bash && shell_name=bash ;;
  *)
    if have dash; then
      shell_name=dash
    elif have busybox && busybox sh -c ':' > /dev/null 2>&1; then
      shell_name=busybox
    elif have sh; then
      shell_name="sh"
    fi
    ;;
esac
if [ -z "${shell_name}" ]; then
  echo "sandbox-run: no ${dialect} shell on this host; use the Termux container or a device (see platform-detection)" >&2
  exit 3
fi

home="${tmp}/home"
prefix="${tmp}/prefix"
mkdir -p "${home}" "${prefix}/bin" "${prefix}/etc" "${prefix}/tmp" "${prefix}/var"
calls="${tmp}/calls.log"
: > "${calls}"
if [ -n "${overlay}" ]; then
  cp -R "${overlay}/." "${tmp}/" || {
    echo "sandbox-run: cannot copy --overlay ${overlay}" >&2
    exit 2
  }
fi

make_stub() {
  spec=$1
  name=${spec%%=*}
  rest=""
  [ "${name}" = "${spec}" ] || rest=${spec#*=}
  code=0
  text=""
  if [ -n "${rest}" ]; then
    code=${rest%%:*}
    [ "${code}" = "${rest}" ] || text=${rest#*:}
  fi
  case ${code} in
    '' | *[!0-9]*)
      echo "sandbox-run: bad stub exit code in: ${spec}" >&2
      exit 2
      ;;
  esac
  case ${name} in
    '' | */* | *[!A-Za-z0-9._+-]*)
      echo "sandbox-run: bad stub name in: ${spec}" >&2
      exit 2
      ;;
  esac
  [ -n "${text}" ] && printf '%s\n' "${text}" > "${prefix}/bin/.${name}.out"
  cat > "${prefix}/bin/${name}" << EOF
#!/bin/sh
printf '%s' '${name}' >> "\${SANDBOX_CALLS}"
for a in "\$@"; do printf ' %s' "\$a" >> "\${SANDBOX_CALLS}"; done
echo >> "\${SANDBOX_CALLS}"
[ -f "\${0%/*}/.${name}.out" ] && cat "\${0%/*}/.${name}.out"
exit ${code}
EOF
  chmod +x "${prefix}/bin/${name}"
}

if [ "${stub_all}" -eq 1 ]; then
  for n in termux-toast termux-notification termux-vibrate termux-clipboard-get termux-clipboard-set termux-open termux-open-url termux-wake-lock termux-wake-unlock termux-battery-status termux-wifi-connectioninfo termux-setup-storage termux-reload-settings termux-info; do
    make_stub "${n}"
  done
fi
while IFS= read -r spec; do
  [ -n "${spec}" ] && make_stub "${spec}"
done < "${tmp}/stubs.list"
# Privilege escalation never reaches the host: stub sudo and doas unless the caller did
for n in sudo doas; do
  [ -e "${prefix}/bin/${n}" ] || make_stub "${n}=127:${n}: command not found"
done

while IFS= read -r spec; do
  [ -n "${spec}" ] || continue
  src=${spec%%:*}
  dest=${src##*/}
  [ "${src}" = "${spec}" ] || dest=${spec#*:}
  if [ ! -e "${src}" ]; then
    echo "sandbox-run: --seed source not found: ${src}" >&2
    exit 2
  fi
  mkdir -p "${home}/$(dirname "${dest}")"
  cp -R "${src}" "${home}/${dest}"
done < "${tmp}/seeds.list"

timeout_bin=""
have timeout && timeout_bin=timeout
sed -n '1!G;h;$p' "${tmp}/envs.list" > "${tmp}/envs.rev"
run_script() {
  set -- "$@"
  case ${shell_name} in
    busybox) set -- busybox sh "$@" ;;
    *) set -- "${shell_name}" "$@" ;;
  esac
  if [ -n "${timeout_bin}" ]; then
    set -- timeout "${timeout_s}" "$@"
  fi
  # extra --env values go between the defaults and the command; envs.rev holds
  # them in reverse order so that prepending keeps the listed order
  while IFS= read -r kv; do
    while :; do
      case ${kv} in
        *@SANDBOX@*) kv="${kv%%@SANDBOX@*}${tmp}${kv#*@SANDBOX@}" ;;
        *) break ;;
      esac
    done
    [ -n "${kv}" ] && set -- "${kv}" "$@"
  done < "${tmp}/envs.rev"
  env -i HOME="${home}" PREFIX="${prefix}" TMPDIR="${prefix}/tmp" \
    PATH="${prefix}/bin:${PATH}" TERM="${TERM:-dumb}" LANG="${LANG:-C}" \
    TERMUX_VERSION=sandbox SANDBOX_CALLS="${calls}" SANDBOX_DIR="${tmp}" \
    ZDOTDIR="${home}" "$@"
}

snapshot() {
  (cd "${tmp}" && find home prefix -type f ! -path 'prefix/bin/*' -exec cksum {} + 2> /dev/null | LC_ALL=C sort -k3)
}

if [ "$(uname -s 2> /dev/null)" = "Darwin" ]; then
  echo "sandbox: note: macOS has BSD utilities; Termux uses GNU coreutils, results are indicative" >&2
fi
if [ -z "${timeout_bin}" ]; then
  echo "sandbox: note: timeout command not found; no time limit applied" >&2
fi

run_script "${script}" "$@"
rc=$?
if [ "${twice}" -eq 1 ]; then
  snapshot > "${tmp}/snap1"
  run_script "${script}" "$@" > /dev/null 2>&1
  snapshot > "${tmp}/snap2"
  if cmp -s "${tmp}/snap1" "${tmp}/snap2"; then
    echo "sandbox: idempotent: second run left home/prefix unchanged" >&2
  else
    echo "sandbox: NOT idempotent: second run changed files:" >&2
    diff "${tmp}/snap1" "${tmp}/snap2" | sed 's/^/sandbox:   /' | head -n 20 >&2
  fi
fi

echo "sandbox: shell=${shell_name} dialect=${dialect} exit=${rc}" >&2
[ "${rc}" -eq 124 ] && echo "sandbox: timed out after ${timeout_s}s" >&2
n_calls=$(wc -l < "${calls}" | tr -d ' ')
echo "sandbox: stub calls: ${n_calls}" >&2
head -n 40 "${calls}" | sed 's/^/sandbox:   /' >&2
echo "sandbox: files under home/prefix (excluding stubs):" >&2
(cd "${tmp}" && find home prefix -type f ! -path 'prefix/bin/*' | LC_ALL=C sort | head -n 40 | sed 's/^/sandbox:   /') >&2
exit "${rc}"

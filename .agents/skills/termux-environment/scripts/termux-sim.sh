#!/bin/sh
# termux-sim.sh - run a script or collect environment facts in a simulated Termux
# (root or non-root) on the host. Builds an overlay (Termux-like layout, profile,
# command stand-ins) and runs it through termux-scripting/scripts/sandbox-run.sh.
# Indicative only: it reproduces documented behavior, not the Android kernel,
# SELinux, bionic libc, or termux-exec. See references/simulation.md.

set -u

here=$(cd "$(dirname "$0")" && pwd)
sandbox="${here}/../../termux-scripting/scripts/sandbox-run.sh"
shim="${here}/termux-shim.sh"
facts="${here}/device-facts.sh"
defaults="${here}/../assets/sim/profile.env"

usage() {
  cat << 'EOF'
Usage: termux-sim.sh [options] -- SCRIPT [ARGS...]
       termux-sim.sh [options] -c 'SHELL TEXT'
       termux-sim.sh [options] --facts

Run SCRIPT (or SHELL TEXT, or scripts/device-facts.sh with --facts) inside a
simulated Termux. The simulation provides: Termux paths and variables (HOME,
PREFIX, TMPDIR, TERMUX_VERSION, TERMUX__PREFIX, ...), and stand-ins for uname,
getprop, id, whoami, su, pkg/apt/apt-get, dpkg, dpkg-query, termux-info,
termux-setup-storage, plus chmod/ln refusal inside simulated shared storage.
Host commands stay on PATH; sudo and doas are blocked.

Options:
  --root            simulate a rooted device: `su` works (default: non-root, where
                    `su` prints the "No su program found" text and exits 1)
  --profile FILE    key=value facts that replace the defaults; the output of
                    device-facts.sh from a real device works as is
  --arch A          aarch64 | arm | i686 | x86_64 (default aarch64)
  --sdk N           Android SDK level (default 34)
  --android V       Android release (default 14)
  --facts           run device-facts.sh inside the simulation
  -c TEXT           run TEXT as a POSIX sh script
  --stub SPEC | --stub-termux | --seed SRC[:DEST] | --env NAME=VALUE |
  --timeout S | --dialect D | --twice | --keep
                    passed to sandbox-run.sh (see its --help)
  -h, --help        show this help

Exit: the script's status; 2 usage error; 3 no suitable shell.
EOF
}

tmp=$(mktemp -d 2> /dev/null || echo "${TMPDIR:-/tmp}/termux-sim.$$")
mkdir -p "${tmp}"
# shellcheck disable=SC2317,SC2329
cleanup() { rm -rf "${tmp}"; }
trap cleanup EXIT INT TERM
: > "${tmp}/pass.list"
: > "${tmp}/extra.profile"

root=0
profile_file=""
mode=script
text=""
bad() {
  echo "termux-sim: $1" >&2
  exit 2
}
need() { [ "$1" -ge 2 ] || bad "$2 needs a value"; }

while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --root)
      root=1
      shift
      ;;
    --facts)
      mode=facts
      shift
      ;;
    --profile)
      need $# "$1"
      profile_file=$2
      shift 2
      ;;
    --arch)
      need $# "$1"
      case $2 in
        aarch64) printf 'arch.uname=aarch64\narch.packages=aarch64\n' >> "${tmp}/extra.profile" ;;
        arm) printf 'arch.uname=armv8l\narch.packages=arm\n' >> "${tmp}/extra.profile" ;;
        i686) printf 'arch.uname=i686\narch.packages=i686\n' >> "${tmp}/extra.profile" ;;
        x86_64) printf 'arch.uname=x86_64\narch.packages=x86_64\n' >> "${tmp}/extra.profile" ;;
        *) bad "--arch must be aarch64, arm, i686, or x86_64" ;;
      esac
      shift 2
      ;;
    --sdk)
      need $# "$1"
      case $2 in '' | *[!0-9]*) bad "--sdk must be a number" ;; esac
      printf 'android.sdk=%s\n' "$2" >> "${tmp}/extra.profile"
      shift 2
      ;;
    --android)
      need $# "$1"
      printf 'android.release=%s\n' "$2" >> "${tmp}/extra.profile"
      shift 2
      ;;
    -c)
      need $# "$1"
      mode=text
      text=$2
      shift 2
      ;;
    --stub | --seed | --env | --timeout | --dialect)
      need $# "$1"
      printf '%s\n%s\n' "$1" "$2" >> "${tmp}/pass.list"
      shift 2
      ;;
    --stub-termux | --twice | --keep)
      printf '%s\n' "$1" >> "${tmp}/pass.list"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "termux-sim: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *) break ;;
  esac
done

[ -f "${sandbox}" ] || bad "sandbox-run.sh not found at ${sandbox}"
[ -f "${shim}" ] || bad "termux-shim.sh not found next to this script"
[ -f "${defaults}" ] || bad "default profile not found: ${defaults}"
if [ -n "${profile_file}" ] && [ ! -f "${profile_file}" ]; then
  bad "--profile file not found: ${profile_file}"
fi

case ${mode} in
  facts) script=${facts} ;;
  text)
    script="${tmp}/text.sh"
    printf '#!/bin/sh\n%s\n' "${text}" > "${script}"
    ;;
  *)
    [ $# -ge 1 ] || bad "SCRIPT missing (usage: termux-sim.sh [options] -- SCRIPT [ARGS...])"
    script=$1
    shift
    ;;
esac
[ -f "${script}" ] || bad "script not found: ${script}"
# Script arguments are the positional parameters left after SCRIPT; keep them aside
: > "${tmp}/sargs.list"
for a in "$@"; do printf '%s\n' "${a}" >> "${tmp}/sargs.list"; done

# Profile: defaults, then root flag, then device facts, then option overrides
ov="${tmp}/overlay"
mkdir -p "${ov}/sim" "${ov}/sdcard" "${ov}/home/.termux" "${ov}/prefix/bin" \
  "${ov}/prefix/etc" "${ov}/prefix/lib" "${ov}/prefix/share" "${ov}/prefix/var/run"
{
  grep -E '^[A-Za-z0-9_.-]+=' "${defaults}"
  [ "${root}" -eq 1 ] && echo "root.available=yes"
  if [ -n "${profile_file}" ]; then grep -E '^[A-Za-z0-9_.-]+=' "${profile_file}"; fi
  cat "${tmp}/extra.profile"
  [ "${root}" -eq 1 ] && echo "root.available=yes"
} > "${ov}/sim/profile"

pv() { awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); r = $0 } END { print r }' "${ov}/sim/profile"; }

# Installed-package state from the profile (last value of each pkg.* key wins)
awk -F= '
  index($1, "pkg.") == 1 {
    k = substr($1, 5); v = $0; sub(/^[^=]*=/, "", v)
    if (!(k in val)) order[++n] = k
    val[k] = v
  }
  END { for (i = 1; i <= n; i++) if (val[order[i]] != "not-installed") print order[i], val[order[i]] }
' "${ov}/sim/profile" > "${ov}/sim/pkgs"

# Command stand-ins (copies, so symlink support is not required)
for n in uname getprop id whoami su pkg apt apt-get dpkg dpkg-query termux-info termux-setup-storage chmod ln; do
  cp "${shim}" "${ov}/prefix/bin/${n}"
  chmod +x "${ov}/prefix/bin/${n}"
done
# sh -> dash and bash resolve to host shells through small wrappers
host_sh=$(command -v dash 2> /dev/null || command -v sh 2> /dev/null || true)
host_bash=$(command -v bash 2> /dev/null || true)
if [ -n "${host_sh}" ]; then
  printf '#!/bin/sh\nexec "%s" "$@"\n' "${host_sh}" > "${ov}/prefix/bin/dash"
  chmod +x "${ov}/prefix/bin/dash"
  ln -s dash "${ov}/prefix/bin/sh" 2> /dev/null || cp "${ov}/prefix/bin/dash" "${ov}/prefix/bin/sh"
fi
if [ -n "${host_bash}" ]; then
  printf '#!/bin/sh\nexec "%s" "$@"\n' "${host_bash}" > "${ov}/prefix/bin/bash"
  chmod +x "${ov}/prefix/bin/bash"
fi

# Fidelity note: pipefail is present in dash 0.5.13.5 and absent in 0.5.12 (tested); versions in between are inferred
probe_sh=${host_sh:-sh}
host_pipefail=no
"${probe_sh}" -c '(set -o pipefail) 2> /dev/null' > /dev/null 2>&1 && host_pipefail=yes # lint-ignore: B021
want_pipefail=no
case $(pv pkg.dash) in
  0.5.1[3-9]* | 0.5.[2-9]* | 0.[6-9]* | [1-9]*) want_pipefail=yes ;;
esac

mode_name=non-root
[ "${root}" -eq 1 ] && mode_name=root
{
  echo "termux-sim: profile=${mode_name} arch=$(pv arch.uname) android=$(pv android.release)/sdk$(pv android.sdk) termux=$(pv termux.version)"
  if [ -n "${profile_file}" ]; then
    echo "termux-sim: profile overrides from ${profile_file}"
  else
    echo "termux-sim: values are placeholders; pass --profile with device-facts.sh output to match a device"
  fi
  if [ "${want_pipefail}" != "${host_pipefail}" ]; then
    echo "termux-sim: note: profile dash $(pv pkg.dash) has pipefail=${want_pipefail}, host sh has pipefail=${host_pipefail}; pipefail results follow the host"
  fi
} >&2

# Build the sandbox-run command
set -- sh "${sandbox}" --overlay "${ov}" \
  --env "TERMUX_VERSION=$(pv termux.version)" --env TERMUX_APP_PACKAGE_MANAGER=apt \
  --env 'TERMUX__ROOTFS=@SANDBOX@' --env 'TERMUX__PREFIX=@SANDBOX@/prefix' \
  --env 'TERMUX__HOME=@SANDBOX@/home' --env 'SHELL=@SANDBOX@/prefix/bin/bash' \
  --env ANDROID_ROOT=/system --env ANDROID_DATA=/data --env TERMUX_SIM=1
while IFS= read -r a; do
  set -- "$@" "${a}"
done < "${tmp}/pass.list"
set -- "$@" -- "${script}"
while IFS= read -r a; do
  set -- "$@" "${a}"
done < "${tmp}/sargs.list"
"$@"

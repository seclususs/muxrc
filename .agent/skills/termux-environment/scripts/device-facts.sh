#!/bin/sh
# device-facts.sh - read-only facts about a Termux install. Run it INSIDE Termux.
# On a non-Termux host it prints termux=no and exits 0. Output: key=value lines.

set -u

usage() {
  cat << 'EOF'
Usage: device-facts.sh [-h|--help]

Print read-only facts about the current Termux install as key=value lines:
termux version, PREFIX/HOME/TMPDIR, architecture, Android release and SDK,
what sh resolves to, shell feature probes (pipefail, LINENO), package versions
(dash bash zsh termux-exec termux-api termux-tools coreutils), storage and
boot setup, and tool presence. Nothing is changed and no Termux:API call is made.

Use: copy this file to the device (or paste its content), run `sh device-facts.sh`
in Termux, and give the output to the agent. Inside termux-sim the output carries
sim=yes and describes the simulation profile, not a device.
Exit codes: 0 ok, 2 usage error.
EOF
}

case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  '') ;;
  *)
    echo "device-facts: unknown option: $1" >&2
    usage >&2
    exit 2
    ;;
esac

have() { command -v "$1" > /dev/null 2>&1; }
val() { printf '%s=%s\n' "$1" "$2"; }

is_termux=no
if [ -n "${TERMUX_VERSION:-}" ]; then
  is_termux=yes
else
  case ${PREFIX:-} in
    */com.termux/*) is_termux=yes ;;
  esac
fi
val termux "${is_termux}"
# termux-sim sets TERMUX_SIM; the values below then come from a simulation profile
if [ -n "${TERMUX_SIM:-}" ]; then val sim yes; fi
if [ "${is_termux}" != yes ]; then
  echo "note=not inside Termux; run this script in Termux to collect device facts"
  exit 0
fi

val termux.version "${TERMUX_VERSION:-unknown}"
val prefix "${PREFIX:-unset}"
val home "${HOME:-unset}"
val tmpdir "${TMPDIR:-unset}"
val shell.login "${SHELL:-unset}"
val arch.uname "$(uname -m 2> /dev/null)"
if have dpkg; then
  val arch.packages "$(dpkg --print-architecture 2> /dev/null)"
fi
if have getprop; then
  val android.release "$(getprop ro.build.version.release 2> /dev/null)"
  val android.sdk "$(getprop ro.build.version.sdk 2> /dev/null)"
fi
val sh.link "$(readlink "${PREFIX:-/nonexistent}/bin/sh" 2> /dev/null || echo unknown)"
if [ -n "${TERMUX_SIM:-}" ]; then
  val android.system_sh not-simulated
elif [ -x /system/bin/sh ]; then
  val android.system_sh present
else
  val android.system_sh absent
fi # lint-ignore: T004

# Shell feature probes through the shell that `sh` resolves to
sh_bin="${PREFIX:-}/bin/sh"
[ -x "${sh_bin}" ] || sh_bin="sh"
if "${sh_bin}" -c '(set -o pipefail) 2> /dev/null' > /dev/null 2>&1; then val sh.pipefail yes; else val sh.pipefail no; fi # lint-ignore: B021
probe="${TMPDIR:-${PREFIX:-/tmp}/tmp}/device-facts.$$"
# shellcheck disable=SC2016
printf '%s\n' 'echo "${LINENO:-}"' > "${probe}" 2> /dev/null
ln_out=$("${sh_bin}" "${probe}" 2> /dev/null)
rm -f "${probe}"
if [ -n "${ln_out}" ]; then val sh.lineno yes; else val sh.lineno no; fi

# Package versions
if have dpkg-query; then
  for pkg in dash bash zsh termux-exec termux-api termux-tools coreutils; do
    # shellcheck disable=SC2016
    if v=$(dpkg-query -W -f='${Version}' "${pkg}" 2> /dev/null) && [ -n "${v}" ]; then
      val "pkg.${pkg}" "${v}"
    else
      val "pkg.${pkg}" not-installed
    fi
  done
fi

# Setup state and tool presence (no API calls are made)
if [ -d "${HOME:-/nonexistent}/storage" ]; then val storage.setup yes; else val storage.setup no; fi
if [ -d "${HOME:-/nonexistent}/.termux/boot" ]; then val boot.dir present; else val boot.dir absent; fi
# shellcheck disable=SC2012
val termux.files "$(ls -1 "${HOME:-/nonexistent}/.termux" 2> /dev/null | tr '\n' ' ')"
for t in termux-battery-status termux-wake-lock termux-clipboard-get shellcheck shfmt git curl jq; do
  if have "${t}"; then val "cmd.${t}" present; else val "cmd.${t}" absent; fi
done
# shellcheck disable=SC2012
val util.ls "$(ls --version 2> /dev/null | head -n 1)"
val util.sed "$(sed --version 2> /dev/null | head -n 1)"
echo "done=1"
exit 0

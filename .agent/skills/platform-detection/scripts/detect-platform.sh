#!/bin/sh
# detect-platform.sh - detect the development host (not the Termux target).
# Read-only: installs nothing, changes nothing. Output: key=value lines on stdout.

set -u

usage() {
  cat << 'EOF'
Usage: detect-platform.sh [--brief] [--tools LIST] [-h|--help]

Probe host OS, shell environment, package manager, tools, and capability fallbacks.

Output (stdout, key=value lines):
  host.os      linux | macos | windows | android | unknown
  host.env     native | wsl | git-bash | msys | cygwin | termux | unknown
  host.arch    machine architecture
  host.pkgmgr  first detected package manager, or none
  tool.NAME    absolute path, or "-" when missing (omitted with --brief)
  tool.missing space-separated missing tools (only with --brief)
  ver.NAME     version for shellcheck and shfmt when present
  cap.NAME     best available provider for a capability, or "none"
  hint.NAME    install hint for a missing tool (verify before use)
  run.scripts  script flavor to run on this host (sh)

Options:
  --brief       print one tool.missing line instead of one tool.NAME line per tool
  --tools LIST  comma-separated extra tool names to probe

Exit codes: 0 ok, 2 usage error.
EOF
}

extra=""
brief=0
while [ $# -gt 0 ]; do
  case $1 in
    --brief)
      brief=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --tools)
      if [ $# -lt 2 ]; then
        echo "detect-platform: --tools needs a value" >&2
        exit 2
      fi
      extra=$2
      shift 2
      ;;
    --tools=*)
      extra=${1#--tools=}
      shift
      ;;
    *)
      echo "detect-platform: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

have() { command -v "$1" > /dev/null 2>&1; }
path_of() { command -v "$1" 2> /dev/null || echo "-"; }

# Host OS and shell environment
uname_s=$(uname -s 2> /dev/null || echo unknown)
os=unknown
env=unknown
case ${uname_s} in
  Linux)
    os=linux
    env=native
    if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2> /dev/null; then
      env=wsl
    fi
    if [ -n "${TERMUX_VERSION:-}" ] || [ "$(uname -o 2> /dev/null)" = "Android" ]; then
      os=android
      env=termux
    fi
    ;;
  Darwin)
    os=macos
    env=native
    ;;
  MINGW*)
    os=windows
    env=git-bash
    ;;
  MSYS*)
    os=windows
    env=msys
    ;;
  CYGWIN*)
    os=windows
    env=cygwin
    ;;
esac
arch=$(uname -m 2> /dev/null || echo unknown)

# Package manager (first match; order depends on host)
case ${os} in
  macos) mgrs="brew port" ;;
  windows)
    if [ "${env}" = "msys" ]; then
      mgrs="pacman winget scoop choco"
    else
      mgrs="winget scoop choco pacman"
    fi
    ;;
  *) mgrs="apt-get dnf pacman zypper apk brew" ;;
esac
pkgmgr=none
for m in ${mgrs}; do
  if have "${m}"; then
    pkgmgr=${m}
    break
  fi
done

echo "host.os=${os}"
echo "host.env=${env}"
echo "host.arch=${arch}"
echo "host.pkgmgr=${pkgmgr}"
echo "run.scripts=sh"
if [ "${env}" = "termux" ]; then
  echo "note=running inside Termux (target); host-only assumptions do not apply"
fi

# Tool availability
default_tools="git sh dash bash zsh busybox shellcheck shfmt checkbashisms rg jq python3 node pwsh powershell.exe docker adb zip unzip tar curl"
extra_tools=$(printf '%s' "${extra}" | tr ',' ' ')
missing=""
for t in ${default_tools} ${extra_tools}; do
  p=$(path_of "${t}")
  [ "${brief}" -eq 1 ] || echo "tool.${t}=${p}"
  [ "${p}" = "-" ] && missing="${missing} ${t}"
done
if [ "${brief}" -eq 1 ]; then
  missing_list=${missing# }
  echo "tool.missing=${missing_list:-none}"
fi

if have shellcheck; then
  v=$(shellcheck --version 2> /dev/null | sed -n 's/^version: //p')
  echo "ver.shellcheck=${v:-unknown}"
fi
if have shfmt; then
  echo "ver.shfmt=$(shfmt --version 2> /dev/null | head -n 1)"
fi

# Capability resolution: first available provider wins, else the fallback.
if have shellcheck; then
  echo "cap.lint_posix_bash=shellcheck"
else
  echo "cap.lint_posix_bash=builtin-heuristics"
fi
if have shfmt; then
  echo "cap.format_posix_bash=shfmt"
  if printf 'echo hi\n' | shfmt -ln zsh > /dev/null 2>&1; then
    echo "cap.format_zsh=shfmt-diff-only"
  else
    echo "cap.format_zsh=manual"
  fi
else
  echo "cap.format_posix_bash=manual"
  echo "cap.format_zsh=manual"
fi
if have dash; then
  echo "cap.syntax_posix=dash"
elif have busybox && busybox sh -c ':' > /dev/null 2>&1; then
  echo "cap.syntax_posix=busybox"
elif have sh; then
  echo "cap.syntax_posix=sh-may-be-bash"
else
  echo "cap.syntax_posix=none"
fi
if have bash; then echo "cap.syntax_bash=bash"; else echo "cap.syntax_bash=none"; fi
if have zsh; then echo "cap.syntax_zsh=zsh"; else echo "cap.syntax_zsh=none"; fi
if have rg; then
  echo "cap.search=rg"
elif have grep; then
  echo "cap.search=grep"
else
  echo "cap.search=none"
fi
if have jq; then
  echo "cap.json=jq"
elif have python3; then
  echo "cap.json=python3"
elif have node; then
  echo "cap.json=node"
elif have pwsh; then
  echo "cap.json=pwsh"
else
  echo "cap.json=none"
fi
if have zip; then
  echo "cap.archive=zip"
elif have tar; then
  echo "cap.archive=tar"
else
  echo "cap.archive=none"
fi
if have sh || have bash; then echo "cap.sandbox=sandbox-run"; else echo "cap.sandbox=none"; fi
if have docker; then echo "cap.termux_container=docker"; else echo "cap.termux_container=none"; fi
if have adb; then echo "cap.device_transfer=adb"; else echo "cap.device_transfer=none"; fi

# Install hints for missing tools. Package ids are conventional names; verify
# with the package manager before proposing them to the user.
hint_pkg() {
  case $1:${pkgmgr} in
    shellcheck:apt-get) echo "sudo apt-get install -y shellcheck" ;;
    shellcheck:dnf) echo "sudo dnf install -y ShellCheck" ;;
    shellcheck:pacman) echo "sudo pacman -S shellcheck" ;;
    shellcheck:zypper) echo "sudo zypper install ShellCheck" ;;
    shellcheck:apk) echo "apk add shellcheck" ;;
    shellcheck:brew) echo "brew install shellcheck" ;;
    shellcheck:scoop) echo "scoop install shellcheck" ;;
    shellcheck:choco) echo "choco install shellcheck" ;;
    shfmt:apt-get) echo "sudo apt-get install -y shfmt" ;;
    shfmt:dnf) echo "sudo dnf install -y shfmt" ;;
    shfmt:pacman) echo "sudo pacman -S shfmt" ;;
    shfmt:apk) echo "apk add shfmt" ;;
    shfmt:brew) echo "brew install shfmt" ;;
    shfmt:scoop) echo "scoop install shfmt" ;;
    shfmt:choco) echo "choco install shfmt" ;;
    zsh:apt-get) echo "sudo apt-get install -y zsh" ;;
    zsh:dnf) echo "sudo dnf install -y zsh" ;;
    zsh:pacman) echo "sudo pacman -S zsh" ;;
    zsh:zypper) echo "sudo zypper install zsh" ;;
    zsh:apk) echo "apk add zsh" ;;
    zsh:brew) echo "brew install zsh" ;;
    dash:apt-get) echo "sudo apt-get install -y dash" ;;
    dash:dnf) echo "sudo dnf install -y dash" ;;
    dash:pacman) echo "sudo pacman -S dash" ;;
    dash:apk) echo "apk add dash" ;;
    dash:brew) echo "brew install dash" ;;
    busybox:apt-get) echo "sudo apt-get install -y busybox-static" ;;
    busybox:dnf) echo "sudo dnf install -y busybox" ;;
    busybox:pacman) echo "sudo pacman -S busybox" ;;
    busybox:apk) echo "apk add busybox" ;;
    busybox:brew) echo "brew install busybox" ;;
    jq:apt-get) echo "sudo apt-get install -y jq" ;;
    jq:dnf) echo "sudo dnf install -y jq" ;;
    jq:pacman) echo "sudo pacman -S jq" ;;
    jq:apk) echo "apk add jq" ;;
    jq:brew) echo "brew install jq" ;;
    jq:scoop) echo "scoop install jq" ;;
    jq:choco) echo "choco install jq" ;;
    *:winget) echo "winget search $1  # install the matching package id" ;;
    *) return 1 ;;
  esac
}
for t in ${missing}; do
  case ${t} in
    shellcheck | shfmt | zsh | dash | busybox | jq)
      h=$(hint_pkg "${t}") || h=""
      if [ -n "${h}" ]; then
        echo "hint.${t}=${h}"
      elif [ "${os}" = "windows" ] && { [ "${t}" = "zsh" ] || [ "${t}" = "dash" ]; }; then
        echo "hint.${t}=no native package; use WSL or MSYS2 (pacman -S ${t})"
      fi
      ;;
  esac
done

exit 0

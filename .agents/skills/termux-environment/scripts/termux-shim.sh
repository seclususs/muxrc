#!/bin/sh
# termux-shim.sh - stand-in for Termux/Android commands inside termux-sim.
# termux-sim installs this one file under several names (uname getprop id whoami
# su pkg apt apt-get dpkg dpkg-query termux-info termux-setup-storage chmod ln);
# the command it imitates is the name it was started under (${0##*/}).
# Facts come from the key=value profile that termux-sim writes to
# ${SANDBOX_DIR}/sim/profile. Not meant to be run directly.

# su runs its command in a subshell on purpose, so HOME changes stay out of the shim
# shellcheck disable=SC2030,SC2031
set -u

self=${0##*/}
selfdir=${0%/*}
state="${SANDBOX_DIR:-/nonexistent}/sim"
profile="${TERMUX_SIM_PROFILE:-${state}/profile}"

# pv KEY [DEFAULT]: last value of KEY in the profile
pv() {
  v=""
  [ -r "${profile}" ] && v=$(awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); r = $0 } END { print r }' "${profile}")
  printf '%s\n' "${v:-${2:-}}"
}

# record ARGS...: append "<name> <args>" to the sandbox call log
record() {
  [ -n "${SANDBOX_CALLS:-}" ] || return 0
  {
    printf '%s' "${self}"
    for a in "$@"; do printf ' %s' "${a}"; done
    echo
  } >> "${SANDBOX_CALLS}"
}

# real NAME: absolute path of the host command NAME, skipping this directory
real() {
  oldifs=${IFS}
  IFS=:
  # shellcheck disable=SC2086
  for d in ${PATH}; do
    [ "${d}" = "${selfdir}" ] && continue
    if [ -x "${d}/$1" ] && [ ! -d "${d}/$1" ]; then
      IFS=${oldifs}
      printf '%s\n' "${d}/$1"
      return 0
    fi
  done
  IFS=${oldifs}
  return 1
}

real_exec() {
  n=$1
  shift
  r=$(real "${n}") || {
    echo "${n}: command not found" >&2
    exit 127
  }
  exec "${r}" "$@"
}

in_su() { [ "${TERMUX_SIM_SU:-}" = 1 ]; }
cur_uid() { if in_su; then echo 0; else pv user.uid 10160; fi; }
cur_gid() { if in_su; then echo 0; else pv user.gid 10160; fi; }
cur_user() { if in_su; then echo root; else pv user.name u0_a160; fi; }

# Android ABI names per CPU architecture (NDK ABI list)
abilist64() {
  case $(pv arch.uname aarch64) in
    aarch64) echo arm64-v8a ;;
    x86_64) echo x86_64 ;;
  esac
}
abilist32() {
  case $(pv arch.uname aarch64) in
    aarch64 | arm | armv7l | armv8l) echo armeabi-v7a,armeabi ;;
    x86_64 | i686) echo x86 ;;
  esac
}
abilist() {
  a=$(abilist64)
  b=$(abilist32)
  printf '%s\n' "${a:+${a},}${b}"
}

sim_uname() {
  want=""
  [ $# -eq 0 ] && want=s
  for a in "$@"; do
    case ${a} in
      --all) want=${want}snrvmo ;;
      --kernel-name) want=${want}s ;;
      --nodename) want=${want}n ;;
      --kernel-release) want=${want}r ;;
      --kernel-version) want=${want}v ;;
      --machine) want=${want}m ;;
      --operating-system) want=${want}o ;;
      --*) real_exec uname "$@" ;;
      -?*)
        opts=${a#-}
        while [ -n "${opts}" ]; do
          c=${opts%"${opts#?}"}
          opts=${opts#?}
          case ${c} in
            a) want=${want}snrvmo ;;
            s | n | r | v | m | p | i | o) want=${want}${c} ;;
            *) real_exec uname "$@" ;;
          esac
        done
        ;;
      *) real_exec uname "$@" ;;
    esac
  done
  out=""
  for c in s n r v m p i o; do
    case ${want} in
      *"${c}"*) ;;
      *) continue ;;
    esac
    case ${c} in
      s) val=Linux ;;
      n) val=localhost ;;
      r) val=$(pv kernel.release) ;;
      v) val=$(pv kernel.version) ;;
      m) val=$(pv arch.uname aarch64) ;;
      p | i) val=unknown ;;
      o) val=Android ;;
    esac
    out=${out:+${out} }${val}
  done
  printf '%s\n' "${out}"
}

sim_getprop() {
  if [ $# -eq 0 ]; then
    printf '[ro.build.version.release]: [%s]\n' "$(pv android.release)"
    printf '[ro.build.version.sdk]: [%s]\n' "$(pv android.sdk)"
    printf '[ro.product.manufacturer]: [%s]\n' "$(pv device.manufacturer)"
    printf '[ro.product.model]: [%s]\n' "$(pv device.model)"
    printf '[ro.product.cpu.abilist]: [%s]\n' "$(abilist)"
    return 0
  fi
  case $1 in
    ro.build.version.release) pv android.release ;;
    ro.build.version.sdk) pv android.sdk ;;
    ro.product.manufacturer) pv device.manufacturer ;;
    ro.product.model) pv device.model ;;
    ro.product.cpu.abilist) abilist ;;
    ro.product.cpu.abilist64) abilist64 ;;
    ro.product.cpu.abilist32) abilist32 ;;
    *) printf '%s\n' "${2:-}" ;;
  esac
}

sim_id() {
  mode=all
  names=0
  for a in "$@"; do
    case ${a} in
      -u | --user) mode=u ;;
      -g | --group) mode=g ;;
      -n | --name) names=1 ;;
      -un | -nu)
        mode=u
        names=1
        ;;
      -gn | -ng)
        mode=g
        names=1
        ;;
      *) real_exec id "$@" ;;
    esac
  done
  u=$(cur_uid)
  g=$(cur_gid)
  n=$(cur_user)
  case ${mode} in
    u) if [ "${names}" -eq 1 ]; then echo "${n}"; else echo "${u}"; fi ;;
    g) if [ "${names}" -eq 1 ]; then echo "${n}"; else echo "${g}"; fi ;;
    *) echo "uid=${u}(${n}) gid=${g}(${n}) groups=${g}(${n})" ;;
  esac
}

# Termux ships $PREFIX/bin/su (termux-tools scripts/su.in): it looks for a su
# binary in fixed locations and prints this text when it finds none. With a su
# binary present (root.available=yes) the model below follows a generic su
# client: the caller's environment is inherited, HOME/USER/LOGNAME/SHELL are set
# for the target user unless -p/-m/--preserve-environment is given, and Termux's
# wrapper has already removed LD_LIBRARY_PATH/LD_PRELOAD and replaced PATH by
# Android directories. Host directories stand in for those Android directories.
sim_su() {
  record "$@"
  if [ "$(pv root.available no)" != yes ]; then
    printf '%s\n' 'No su program found on this device. Termux' \
      'does not supply tools for rooting, see e.g.' \
      'http://www.androidcentral.com/root for' \
      'information about rooting Android.'
    exit 1
  fi
  cmd=""
  keep=0
  shell=""
  while [ $# -gt 0 ]; do
    case $1 in
      -c | --command)
        [ $# -ge 2 ] || exit 2
        cmd=$2
        shift 2
        ;;
      -s | --shell)
        [ $# -ge 2 ] || exit 2
        shell=$2
        shift 2
        ;;
      -m | -p | --preserve-environment)
        keep=1
        shift
        ;;
      -g | -G | -Z | -t | --group | --supp-group | --context | --target) shift 2 ;;
      -M | -d | -i | -l | --mount-master | --drop-cap | --interactive | --login) shift ;;
      -v | -V | --version)
        echo "termux-sim su"
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  user=${1:-root}
  [ $# -gt 0 ] && shift
  case ${user} in
    root | 0) ;;
    *)
      echo "su: only root is simulated (got: ${user})" >&2
      exit 1
      ;;
  esac
  [ -n "${shell}" ] || shell=$(real sh) || shell=/bin/sh # lint-ignore: T001
  root_home="${state}/root-home"
  mkdir -p "${root_home}" 2> /dev/null
  # Android's own id/whoami/uname/getprop live in /system/bin; the stand-ins below
  # report uid 0 while TERMUX_SIM_SU is set
  android_bin="${state}/android-bin"
  mkdir -p "${android_bin}" 2> /dev/null
  for n in id whoami uname getprop; do
    [ -f "${android_bin}/${n}" ] || cp "${0}" "${android_bin}/${n}" 2> /dev/null
    chmod +x "${android_bin}/${n}" 2> /dev/null
  done
  android_path=${android_bin}
  oldifs=${IFS}
  IFS=:
  # shellcheck disable=SC2086
  for d in ${PATH}; do
    [ "${d}" = "${selfdir}" ] || android_path=${android_path}:${d}
  done
  IFS=${oldifs}
  (
    unset LD_LIBRARY_PATH LD_PRELOAD
    PATH=${android_path}
    TERMUX_SIM_SU=1
    export PATH TERMUX_SIM_SU
    if [ "${keep}" -ne 1 ]; then
      HOME=${root_home}
      USER=root
      LOGNAME=root
      SHELL=${shell}
      export HOME USER LOGNAME SHELL
    fi
    if [ -n "${cmd}" ]; then exec "${shell}" -c "${cmd}" "$@"; fi
    exec "${shell}"
  )
  exit $?
}

# State file ${state}/pkgs: one "name version" per installed package, written by
# termux-sim from the profile and updated by install/remove.
pkg_list() { cat "${state}/pkgs" 2> /dev/null; }
pkg_version() { pkg_list | awk -v n="$1" '$1 == n { print $2; exit }'; }
pkg_add() {
  [ -n "$(pkg_version "$1")" ] || printf '%s sim\n' "$1" >> "${state}/pkgs"
}
pkg_del() {
  grep -v "^$1 " "${state}/pkgs" > "${state}/pkgs.new" 2> /dev/null
  mv "${state}/pkgs.new" "${state}/pkgs" 2> /dev/null
}

sim_pkg() {
  sub=${1:-}
  [ $# -gt 0 ] && shift
  case ${sub} in
    update | upgrade | full-upgrade | dist-upgrade | autoclean | clean | autoremove)
      echo "sim: ${self} ${sub}: package index is not available offline; nothing changed" >&2
      ;;
    install | reinstall | add)
      record "${sub}" "$@"
      skip=0
      for p in "$@"; do
        if [ "${skip}" -eq 1 ]; then
          skip=0
          continue
        fi
        case ${p} in
          -o | --option) skip=1 ;;
          -*) ;;
          *)
            pkg_add "${p}"
            echo "sim: recorded install of ${p} (no network; host commands stay as they are)" >&2
            ;;
        esac
      done
      ;;
    remove | uninstall | purge | autopurge)
      record "${sub}" "$@"
      for p in "$@"; do
        case ${p} in -*) ;; *) pkg_del "${p}" ;; esac
      done
      ;;
    list-installed | list)
      pkg_list | while read -r n v; do
        echo "${n}/stable ${v} $(pv arch.packages aarch64) [installed]"
      done
      ;;
    '')
      echo "usage: ${self} <command> [arguments]" >&2
      exit 1
      ;;
    *)
      echo "sim: '${self} ${sub}' is not simulated; check on a device or in the Termux packages repository" >&2
      exit 1
      ;;
  esac
}

# fmt_pkg FORMAT NAME VERSION: expand dpkg-query ${Field} placeholders
fmt_pkg() {
  # shellcheck disable=SC2016
  out=$(printf '%s' "$1" | sed -e "s|\${Package}|$2|g" -e "s|\${Version}|$3|g" \
    -e 's|\${Status}|install ok installed|g' -e "s|\${Architecture}|$(pv arch.packages aarch64)|g")
  printf '%b' "${out}"
}

sim_dpkg_query() {
  # shellcheck disable=SC2016
  fmt='${Package}\t${Version}\n'
  mode=W
  while [ $# -gt 0 ]; do
    case $1 in
      -W | --show)
        mode=W
        shift
        ;;
      -s | --status)
        mode=s
        shift
        ;;
      -l | --list)
        mode=l
        shift
        ;;
      -f | --showformat)
        fmt=${2:-}
        shift 2
        ;;
      -f=* | --showformat=*)
        fmt=${1#*=}
        shift
        ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  case ${mode} in
    l)
      pkg_list | while read -r n v; do printf 'ii  %s %s %s\n' "${n}" "${v}" "$(pv arch.packages aarch64)"; done
      ;;
    s)
      for n in "$@"; do
        v=$(pkg_version "${n}")
        if [ -z "${v}" ]; then
          echo "dpkg-query: package '${n}' is not installed and no information is available" >&2
          exit 1
        fi
        printf 'Package: %s\nStatus: install ok installed\nVersion: %s\nArchitecture: %s\n' "${n}" "${v}" "$(pv arch.packages aarch64)"
      done
      ;;
    *)
      rc=0
      for n in "$@"; do
        v=$(pkg_version "${n}")
        if [ -z "${v}" ]; then
          echo "dpkg-query: no packages found matching ${n}" >&2
          rc=1
          continue
        fi
        fmt_pkg "${fmt}" "${n}" "${v}"
      done
      exit "${rc}"
      ;;
  esac
}

sim_dpkg() {
  case ${1:-} in
    --print-architecture) pv arch.packages aarch64 ;;
    -s | --status | -l | --list) sim_dpkg_query "$@" ;;
    *)
      echo "sim: 'dpkg $*' is not simulated" >&2
      exit 1
      ;;
  esac
}

sim_info() {
  echo "Termux Variables:"
  env | sed -n '/^TERMUX_/p' | LC_ALL=C sort
  echo "Packages CPU architecture:"
  pv arch.packages aarch64
  echo "Subscribed repositories:"
  echo "sim: repositories are not simulated"
  echo "Updatable packages:"
  echo "termux-tools version:"
  pv pkg.termux-tools unknown
  echo "Android version:"
  pv android.release
  echo "Kernel build information:"
  sim_uname -a
  echo "Device manufacturer:"
  pv device.manufacturer
  echo "Device model:"
  pv device.model
  echo "Supported ABIs:"
  echo "SUPPORTED_ABIS: $(abilist)"
  echo "SUPPORTED_32_BIT_ABIS: $(abilist32)"
  echo "SUPPORTED_64_BIT_ABIS: $(abilist64)"
  echo "LD Variables:"
  echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}"
  echo "LD_PRELOAD=${LD_PRELOAD:-}"
}

# Termux creates these links in ~/storage (TermuxInstaller.setupStorageSymlinks)
sim_storage() {
  record "$@"
  mkdir -p "${HOME}/storage" "${state}/../sdcard" 2> /dev/null || exit 1
  sd=$(cd "${state}/../sdcard" && pwd -P)
  for n in shared documents downloads dcim pictures music movies podcasts; do
    target=${sd}
    [ "${n}" = shared ] || target=${sd}/${n}
    mkdir -p "${target}" 2> /dev/null
    [ -e "${HOME}/storage/${n}" ] || ln -s "${target}" "${HOME}/storage/${n}" 2> /dev/null || true
  done
}

# Shared storage emulates a FAT filesystem: no chmod, no links (Termux wiki,
# termux-packages issue 4728). Only paths inside the simulated sdcard are blocked.
under_storage() {
  p=$1
  case ${p} in /*) ;; *) p=$(pwd)/${p} ;; esac
  d=${p%/*}
  if [ -d "${d}" ]; then
    d=$(cd -P "${d}" 2> /dev/null && pwd -P) || return 1
    p=${d}/${p##*/}
  fi
  sd=$(cd -P "${state}/../sdcard" 2> /dev/null && pwd -P) || return 1
  case ${p} in "${sd}" | "${sd}"/*) return 0 ;; esac
  return 1
}

sim_storage_guard() {
  case ${self} in
    chmod)
      for a in "$@"; do
        case ${a} in -*) continue ;; esac
        if [ -e "${a}" ] && under_storage "${a}"; then
          echo "chmod: changing permissions of '${a}': Operation not permitted" >&2
          exit 1
        fi
      done
      ;;
    ln)
      last=""
      for a in "$@"; do last=${a}; done
      if [ -n "${last}" ] && under_storage "${last}"; then
        echo "ln: failed to create link '${last}': Operation not permitted" >&2
        exit 1
      fi
      ;;
  esac
  real_exec "${self}" "$@"
}

case ${self} in
  uname) sim_uname "$@" ;;
  getprop) sim_getprop "$@" ;;
  id) sim_id "$@" ;;
  whoami) cur_user ;;
  su) sim_su "$@" ;;
  pkg | apt | apt-get) sim_pkg "$@" ;;
  dpkg) sim_dpkg "$@" ;;
  dpkg-query) sim_dpkg_query "$@" ;;
  termux-info) sim_info "$@" ;;
  termux-setup-storage) sim_storage "$@" ;;
  chmod | ln) sim_storage_guard "$@" ;;
  *)
    echo "termux-shim: no behavior defined for '${self}'" >&2
    exit 127
    ;;
esac

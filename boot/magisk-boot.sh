#!/system/bin/sh

######################################
# Muxrc Magisk Boot Runner (service.d)
######################################

while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 2
done

termux_home="${TERMUX_HOME:-/data/data/com.termux/files/home}"
termux_prefix="${TERMUX_PREFIX:-/data/data/com.termux/files/usr}"
boot_dir="${termux_home}/.termux/boot"

[ ! -d "${boot_dir}" ] && exit 0

termux_user="$(stat -c %U "${termux_home}" 2> /dev/null)" || exit 0
[ -z "${termux_user}" ] && exit 0

for script in "${boot_dir}"/*; do
  [ -f "${script}" ] && [ -x "${script}" ] || continue
  su "${termux_user}" -c "env -i \
    PATH=${termux_prefix}/bin:${termux_prefix}/bin/applets:/system/bin \
    HOME=${termux_home} \
    PREFIX=${termux_prefix} \
    TMPDIR=${termux_prefix}/tmp \
    ${termux_prefix}/bin/bash \"${script}\"" > /dev/null 2>&1 &
done

exit 0

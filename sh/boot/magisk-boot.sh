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

while [ "$(getprop sys.user.0.ce_available)" != "true" ] && [ "$(getprop vold.fbe.decrypted)" != "1" ]; do
  [ -d "${boot_dir}" ] && break
  sleep 3
done

sleep 2

[ ! -d "${boot_dir}" ] && exit 0

termux_uid="$(stat -c %u "${termux_home}" 2> /dev/null)" || exit 0
[ -z "${termux_uid}" ] && exit 0

for script in "${boot_dir}"/*; do
  [ -f "${script}" ] && [ -x "${script}" ] || continue
  su -g "${termux_uid}" -G 3003 -G 9997 "${termux_uid}" -c "env -i \
    PATH=${termux_prefix}/bin:${termux_prefix}/bin/applets:/system/bin \
    HOME=${termux_home} \
    PREFIX=${termux_prefix} \
    TMPDIR=${termux_prefix}/tmp \
    ${termux_prefix}/bin/bash \"${script}\"" > /dev/null 2>&1 &
done

exit 0

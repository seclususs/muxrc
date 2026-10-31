# Termux capability map

Load when looking for unused capabilities. Confirm availability before proposing: `pkg search NAME`, `pkg show termux-api`, and on a device `ls "$PREFIX/bin" | grep '^termux-'`.

| Capability | Mechanism | Package | Notes |
|---|---|---|---|
| Notifications, toasts, vibration | `termux-notification`, `termux-toast`, `termux-vibrate` | `termux-api` | needs the Termux:API app and permissions |
| Clipboard | `termux-clipboard-get`, `termux-clipboard-set` | `termux-api` | same |
| Battery and Wi-Fi info | `termux-battery-status`, `termux-wifi-connectioninfo` | `termux-api` | JSON output |
| Scheduled jobs | `termux-job-scheduler` | `termux-api` | verify current behavior in the wiki |
| Open files and URLs | `termux-open`, `termux-open-url` | `termux-tools` | |
| Keep device awake | `termux-wake-lock`, `termux-wake-unlock` | `termux-tools` | battery cost |
| Storage bridge | `termux-setup-storage`, `~/storage/*` | `termux-tools` | shared storage limits |
| Terminal UI | `termux.properties`, `colors.properties`, `font.ttf`, `termux-reload-settings` | `termux-tools` | skill `termux-customization` |
| Repair and move | `termux-fix-shebang`, `termux-backup`, `termux-restore`, `termux-change-repo` | `termux-tools` | |
| Start at device boot | scripts in `~/.termux/boot/` | Termux:Boot app | open the app once |
| Background services | `termux-services` (runit) | `termux-services` | verify commands in the wiki |
| Packages | `pkg`; repositories main, root-repo, x11-repo | | root-repo targets rooted devices |

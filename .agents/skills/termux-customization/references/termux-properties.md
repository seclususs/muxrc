# termux.properties reference

Source: official `termux.properties` template of the termux-tools repository (master, commit 05c857e, 2026-10-15; re-check the Termux wiki for newer keys). Apply with `termux-reload-settings`; some keys need the app process restarted.

| Key | Values | Note |
|---|---|---|
| `allow-external-apps` | `true`/`false` | security-sensitive: lets other apps run commands |
| `default-working-directory` | absolute path | |
| `disable-terminal-session-change-toast` | bool | |
| `hide-soft-keyboard-on-startup` | bool | |
| `soft-keyboard-toggle-behaviour` | `show/hide`, `enable/disable` | |
| `terminal-transcript-rows` | integer, max 50000 | scrollback |
| `volume-keys` | `virtual`, `volume` | `volume` = adjust volume instead of extra keys |
| `fullscreen`, `use-fullscreen-workaround` | bool | |
| `terminal-cursor-blink-rate` | `0` or 100-2000 | 0 disables blinking |
| `terminal-cursor-style` | `block`, `bar`, `underline` | |
| `terminal-margin-horizontal`, `terminal-margin-vertical` | non-negative integer | terminal margins |
| `extra-keys-style` | `default`, `arrows-only`, `arrows-all`, `all`, `none` | |
| `extra-keys-text-all-caps` | bool | |
| `extra-keys` | nested array | rows of strings or `{key: 'X', popup: {macro: '...', display: '...'}}` |
| `use-black-ui` | bool | |
| `disable-hardware-keyboard-shortcuts` | bool | |
| `shortcut.create-session`, `.next-session`, `.previous-session`, `.rename-session` | e.g. `ctrl + t` | modifier plus key |
| `bell-character` | `vibrate`, `beep`, `ignore` | |
| `back-key` | `escape`, `back` | |
| `enforce-char-based-input`, `ctrl-space-workaround` | bool | input workarounds |

`volume-keys=virtual` and `soft-keyboard-toggle-behaviour=show/hide` come from wiki/defaults, not the template text.

## extra-keys shape
```
extra-keys = [[ \
  'ESC', '/', \
  {key: 'END', popup: {macro: 'wakelock ENTER', display: 'wake'}} \
], [ \
  'TAB', 'CTRL', 'ALT' \
]]
```
Rows are arrays; a popup `macro` is a space-separated key sequence; keep each line ending in `\` except the last. Validate with `scripts/check-termux-config.sh` (or `.ps1`) of skill `termux-customization`.

## colors.properties
Keys: `foreground`, `background`, `cursor`, `color0` ... `color15`; values `#RGB` or `#RRGGBB`.

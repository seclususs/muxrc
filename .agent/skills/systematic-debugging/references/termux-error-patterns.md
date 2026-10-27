# Termux error patterns

Match the symptom, confirm with the check, then fix the cause.

| Symptom | Likely cause | Check / fix |
|---|---|---|
| `bad interpreter: /bin/sh^M` | CRLF line endings | lint `E001`; convert to LF; `.gitattributes` with `eol=lf` |
| `/usr/bin/env: not found`, `bad interpreter: /bin/...: No such file` | FHS shebang without termux-exec | use the `$PREFIX` shebang, or `pkg install termux-exec` and open a new session |
| `Permission denied` running a script | no exec bit, or file in shared storage (mounted noexec) | `chmod +x` in `$HOME`; move it out of `/sdcard` and `~/storage`, or run it as `sh file` |
| `Operation not permitted` on `chmod`, `ln -s`, `git clone` | target inside shared storage (no symlinks, no permission changes) | work in `$HOME`; symlink from `$HOME` into storage |
| `command not found: termux-*` | `termux-api` package or Termux:API app missing | `pkg install termux-api`; install the add-on app; grant permissions |
| `[Process completed (signal 9)]` | Android 12+ phantom process killer or memory kill | search the Termux issue tracker; reduce background child processes; system setting changes need the user's consent |
| `set: Illegal option -o pipefail` | dash older than 0.5.13 | probe: `(set -o pipefail) 2>/dev/null && set -o pipefail` |
| works in bash, fails in `sh` | bashism under dash | lint B-rules; `dash -n` |
| works in bash, odd in zsh | splitting, 1-indexing, globbing, `read -p` | `termux-scripting` `references/zsh.md` |
| `no matches found: ...` (zsh) | unmatched glob | `(N)` qualifier or quoting |
| `read-only variable: status`, commands vanish inside a zsh function | special parameter used as a name (`status`, `path`) | rename the variable |
| ShellCheck reports an unknown shell | no shebang or `shell=` directive | add one |
| `pkg` update or mirror errors | broken or slow mirror | `termux-change-repo` |
| `/tmp` or `/etc` not found | FHS path | `$TMPDIR`, `$PREFIX/etc` |
| log lines garbled in a pipe | prefixes or colors on stdout | logs to stderr; no prefixes in wrappers |

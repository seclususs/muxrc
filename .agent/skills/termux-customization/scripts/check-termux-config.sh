#!/bin/sh
# check-termux-config.sh - validate Termux .properties files (read-only).
# termux.properties: known keys/values (termux-keys.tsv) and extra-keys balance.
# colors.properties: standard color keys and #RGB/#RRGGBB values.

set -u

here=$(cd "$(dirname "$0")" && pwd)
keys="${here}/termux-keys.tsv"

usage() {
  cat << 'EOF'
Usage: check-termux-config.sh [--type auto|termux|colors|generic] FILE ...

Validate Termux configuration files as java.util.Properties text.
  termux    termux.properties (also termux.float.properties): key/value checks
  colors    colors.properties: foreground, background, cursor, color0..color15
  generic   Properties syntax checks only
  auto      by file name (default)

Output: LEVEL FILE:LINE [CODE] message, then one SUMMARY line.
  P001 key without value        P002 duplicate key (last wins)
  P003 unknown key (verify)     P004 trailing whitespace in value
  P005 extra-keys unbalanced    P006 invalid value for key
  P007 dangling continuation    K001 unknown color key
  K002 invalid color value      K003 standard color keys not set
  E001 CR byte (becomes part of values)

After editing on a device, apply with: termux-reload-settings
(some properties need the app process restarted).
Exit: 0 no ERROR, 1 findings, 2 usage error.
EOF
}

type=auto
files=""
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --type)
      [ $# -ge 2 ] || {
        echo "check-termux-config: --type needs a value" >&2
        exit 2
      }
      type=$2
      shift 2
      ;;
    -*)
      echo "check-termux-config: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      files="${files}
$1"
      shift
      ;;
  esac
done
case ${type} in
  auto | termux | colors | generic) ;;
  *)
    echo "check-termux-config: --type must be auto, termux, colors, or generic" >&2
    exit 2
    ;;
esac
if [ -z "${files}" ]; then
  echo "check-termux-config: no FILE given" >&2
  usage >&2
  exit 2
fi
if [ ! -f "${keys}" ]; then
  echo "check-termux-config: key table missing: ${keys}" >&2
  exit 2
fi

tmp=$(mktemp 2> /dev/null || echo "${TMPDIR:-/tmp}/check-termux-config.$$")
trap 'rm -f "${tmp}"' EXIT INT TERM
: > "${tmp}"

# shellcheck disable=SC2016
awk_prog='
function emit(level, ln, code, msg) { # lint-ignore: B002
  printf "%s %s:%d [%s] %s\n", level, F, ln, code, msg
}
function inset(v, set,   n, a, i) { # lint-ignore: B002
  n = split(set, a, "|")
  for (i = 1; i <= n; i++) if (a[i] == v) return 1
  return 0
}
function inrange(v, spec,   p) { # lint-ignore: B002
  split(spec, p, "-")
  return (v + 0 >= p[1] + 0 && v + 0 <= p[2] + 0)
}
function balanced(v,   i, c, q, d1, d2) { # lint-ignore: B002
  q = ""
  d1 = 0
  d2 = 0
  for (i = 1; i <= length(v); i++) {
    c = substr(v, i, 1)
    if (q != "") {
      if (c == q) q = ""
      continue
    }
    if (c == Q || c == DQ) { q = c; continue }
    if (c == "[") d1++
    else if (c == "]") d1--
    else if (c == "{") d2++
    else if (c == "}") d2--
    if (d1 < 0 || d2 < 0) return 0
  }
  return (q == "" && d1 == 0 && d2 == 0)
}
function check_value(key, value, ln,   t, s, ok) { # lint-ignore: B002
  t = kt[key]
  s = ks[key]
  ok = 1
  if (t == "bool") ok = (value == "true" || value == "false")
  else if (t == "enum") ok = inset(value, s)
  else if (t == "int") ok = (value ~ /^[0-9]+$/ && inrange(value, s))
  else if (t == "uint") ok = (value ~ /^[0-9]+$/)
  else if (t == "intset") ok = (value == "0" || (value ~ /^[0-9]+$/ && inrange(value, "100-2000")))
  else if (t == "path") ok = (substr(value, 1, 1) == "/")
  else if (t == "shortcut") ok = (value ~ /^(ctrl|alt|shift|meta)( *\+ *(ctrl|alt|shift|meta))* *\+ *[^ +]+$/)
  else if (t == "extra-keys") {
    if (substr(value, 1, 1) != "[" || !balanced(value)) {
      emit("ERROR", ln, "P005", "extra-keys must start with [ and have balanced [] {} and quotes")
      return
    }
  }
  if (!ok) emit("WARN", ln, "P006", key " = " value " : unexpected value for type " t (s != "" ? " (" s ")" : ""))
}
function process(line, ln,   i, n, c, key, rest, value) { # lint-ignore: B002
  n = length(line)
  key = ""
  i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    if (c == "\\") { key = key substr(line, i, 2); i += 2; continue }
    if (c == "=" || c == ":" || c == " " || c == "\t") break
    key = key c
    i++
  }
  rest = substr(line, i)
  sub("^" WS "*", "", rest)
  c = substr(rest, 1, 1)
  if (c == "=" || c == ":") {
    rest = substr(rest, 2)
    sub("^" WS "*", "", rest)
  }
  value = rest
  if (value == "") {
    emit("WARN", ln, "P001", "key without value: " key)
  } else if (value ~ (WS "$")) {
    emit("WARN", ln, "P004", "trailing whitespace is part of the value in java.util.Properties: " key)
  }
  if (key in seen) emit("WARN", ln, "P002", "duplicate key " key " (also line " seen[key] "; last wins)")
  seen[key] = ln
  if (T == "termux") {
    if (!(key in kt)) emit("WARN", ln, "P003", "unknown key " key " (not in the known-keys table; verify against the Termux wiki)")
    else if (value != "") check_value(key, value, ln)
  } else if (T == "colors") {
    if (key !~ /^(foreground|background|cursor|color[0-9]|color1[0-5])$/) {
      emit("WARN", ln, "K001", "unknown color key " key)
    } else {
      nset++
      if (value !~ /^#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$/ && value !~ /^#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$/) {
        emit("ERROR", ln, "K002", key " = " value " : expected #RGB or #RRGGBB")
      }
    }
  }
}
BEGIN {
  WS = "[ " "\t" "]"
  Q = sprintf("%c", 39)
  DQ = "\""
  if (T == "termux") {
    while ((getline kl < KEYS) > 0) {
      if (kl ~ /^#/ || kl ~ /^[ ]*$/) continue
      if (split(kl, f, "\t") < 3) continue
      kt[f[1]] = f[2]
      ks[f[1]] = f[3]
    }
    close(KEYS)
  }
  cont = 0
  crn = 0
  nset = 0
}
{
  raw = $0
  if (index(raw, "\r") > 0) {
    crn++
    if (crn == 1) crfirst = NR
    sub(/\r$/, "", raw)
  }
  t = raw
  sub("^" WS "*", "", t)
  if (cont == 0) {
    if (t == "" || t ~ /^[#!]/) next
    start = NR
    buf = t
  } else {
    buf = buf t
  }
  nb = 0
  if (match(buf, /\\+$/)) nb = RLENGTH
  if (nb % 2 == 1) {
    buf = substr(buf, 1, length(buf) - 1)
    cont = 1
    next
  }
  cont = 0
  process(buf, start)
}
END {
  if (cont) emit("WARN", start, "P007", "file ends inside a backslash continuation")
  if (crn > 0) emit("ERROR", crfirst, "E001", "CR byte in " crn " line(s); LF endings required (CR becomes part of values)")
  if (T == "colors" && nset < 19) emit("INFO", 1, "K003", (19 - nset) " of 19 standard color keys not set (Termux defaults apply)")
}'

printf '%s\n' "${files}" | while IFS= read -r f; do
  [ -n "${f}" ] || continue
  if [ ! -f "${f}" ]; then
    echo "ERROR ${f}:1 [IO] file not found" >> "${tmp}"
    continue
  fi
  t=${type}
  if [ "${t}" = auto ]; then
    case ${f##*/} in
      colors.properties | colors*.properties) t=colors ;;
      termux.properties | termux.float.properties) t=termux ;;
      *) t=generic ;;
    esac
  fi
  awk -v F="${f}" -v T="${t}" -v KEYS="${keys}" "${awk_prog}" "${f}" >> "${tmp}"
done

cat "${tmp}"
errors=$(grep -c '^ERROR ' "${tmp}" || true)
warns=$(grep -c '^WARN ' "${tmp}" || true)
infos=$(grep -c '^INFO ' "${tmp}" || true)
nfiles=$(printf '%s\n' "${files}" | grep -c . || true)
echo "SUMMARY files=${nfiles} errors=${errors} warnings=${warns} info=${infos}"
[ "${errors}" -gt 0 ] && exit 1
exit 0

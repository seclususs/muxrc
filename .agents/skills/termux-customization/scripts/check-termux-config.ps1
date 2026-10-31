# check-termux-config.ps1 - validate Termux .properties files (read-only).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File check-termux-config.ps1 [options]  (direct `& .\check-termux-config.ps1` is blocked by the execution policy)
# termux.properties: known keys/values (termux-keys.tsv) and extra-keys balance.
# colors.properties: standard color keys and #RGB/#RRGGBB values.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Same contract as check-termux-config.sh.

$ErrorActionPreference = 'Continue'
$keysPath = Join-Path $PSScriptRoot 'termux-keys.tsv'

function Show-Usage {
  @'
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File check-termux-config.ps1 [--type auto|termux|colors|generic] FILE ...

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
'@
}

$type = 'auto'
$files = New-Object System.Collections.Generic.List[string]
$i = 0
while ($i -lt $args.Count) {
  $a = [string]$args[$i]
  if ($a -eq '-h' -or $a -eq '--help') { Show-Usage; exit 0 }
  elseif ($a -eq '--type') {
    if ($i + 1 -ge $args.Count) { [Console]::Error.WriteLine('check-termux-config: --type needs a value'); exit 2 }
    $type = [string]$args[$i + 1]
    $i += 2
  }
  elseif ($a.StartsWith('-')) {
    [Console]::Error.WriteLine("check-termux-config: unknown option: $a")
    Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 2
  }
  else { $files.Add($a); $i++ }
}
if (@('auto', 'termux', 'colors', 'generic') -cnotcontains $type) { [Console]::Error.WriteLine('check-termux-config: --type must be auto, termux, colors, or generic'); exit 2 }
if ($files.Count -eq 0) {
  [Console]::Error.WriteLine('check-termux-config: no FILE given')
  Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
  exit 2
}
if (-not (Test-Path -LiteralPath $keysPath -PathType Leaf)) { [Console]::Error.WriteLine("check-termux-config: key table missing: $keysPath"); exit 2 }

$kt = @{}; $ks = @{}
foreach ($kl in [System.IO.File]::ReadAllLines($keysPath)) {
  if ($kl.StartsWith('#') -or $kl.Trim() -eq '') { continue }
  $f = $kl.Split("`t")
  if ($f.Count -lt 3) { continue }
  $kt[$f[0]] = $f[1]
  $ks[$f[0]] = $f[2]
}

$out = New-Object System.Collections.Generic.List[string]

function Test-InSet([string]$v, [string]$set) { return (($set.Split('|')) -ccontains $v) }
function Test-InRange([string]$v, [string]$spec) {
  $p = $spec.Split('-')
  $n = [double]$v
  return ($n -ge [double]$p[0] -and $n -le [double]$p[1])
}
function Test-Balanced([string]$v) {
  $q = ''; $d1 = 0; $d2 = 0
  foreach ($c in $v.ToCharArray()) {
    if ($q -ne '') { if ([string]$c -ceq $q) { $q = '' }; continue }
    if ($c -eq [char]39 -or $c -eq [char]34) { $q = [string]$c; continue }
    if ($c -eq '[') { $d1++ } elseif ($c -eq ']') { $d1-- } elseif ($c -eq '{') { $d2++ } elseif ($c -eq '}') { $d2-- }
    if ($d1 -lt 0 -or $d2 -lt 0) { return $false }
  }
  return ($q -eq '' -and $d1 -eq 0 -and $d2 -eq 0)
}

function Check-Value([string]$file, [string]$key, [string]$value, [int]$ln) {
  $t = $kt[$key]; $s = $ks[$key]; $ok = $true
  if ($t -eq 'bool') { $ok = ($value -ceq 'true' -or $value -ceq 'false') }
  elseif ($t -eq 'enum') { $ok = (Test-InSet $value $s) }
  elseif ($t -eq 'int') { $ok = ($value -cmatch '^[0-9]+$' -and (Test-InRange $value $s)) }
  elseif ($t -eq 'uint') { $ok = ($value -cmatch '^[0-9]+$') }
  elseif ($t -eq 'intset') { $ok = ($value -ceq '0' -or ($value -cmatch '^[0-9]+$' -and (Test-InRange $value '100-2000'))) }
  elseif ($t -eq 'path') { $ok = ($value.Substring(0, 1) -ceq '/') }
  elseif ($t -eq 'shortcut') { $ok = ($value -cmatch '^(ctrl|alt|shift|meta)( *\+ *(ctrl|alt|shift|meta))* *\+ *[^ +]+$') }
  elseif ($t -eq 'extra-keys') {
    if ($value.Substring(0, 1) -cne '[' -or -not (Test-Balanced $value)) {
      $out.Add("ERROR ${file}:${ln} [P005] extra-keys must start with [ and have balanced [] {} and quotes")
      return
    }
  }
  if (-not $ok) {
    $suffix = ''
    if ($s -ne '') { $suffix = " ($s)" }
    $out.Add("WARN ${file}:${ln} [P006] $key = $value : unexpected value for type $t$suffix")
  }
}

function Test-File([string]$file, [string]$t) {
  $seen = @{}; $script:nset = 0
  $bytes = [System.IO.File]::ReadAllBytes($file)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  $lines = $text.Split([char]10)
  if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }
  if ($bytes.Length -eq 0) { $lines = @() }
  $cont = $false; $crn = 0; $crfirst = 0; $start = 0; $buf = ''; $nr = 0
  foreach ($raw0 in $lines) {
    $nr++
    $raw = $raw0
    if ($raw.Contains([string][char]13)) {
      $crn++
      if ($crn -eq 1) { $crfirst = $nr }
      if ($raw.EndsWith([string][char]13)) { $raw = $raw.Substring(0, $raw.Length - 1) }
    }
    $tl = [regex]::Replace($raw, '^[ \t]*', '')
    if (-not $cont) {
      if ($tl -eq '' -or $tl.StartsWith('#') -or $tl.StartsWith('!')) { continue }
      $start = $nr
      $buf = $tl
    }
    else { $buf = $buf + $tl }
    $nb = 0
    $m = [regex]::Match($buf, '\\+$')
    if ($m.Success) { $nb = $m.Length }
    if ($nb % 2 -eq 1) { $buf = $buf.Substring(0, $buf.Length - 1); $cont = $true; continue }
    $cont = $false
    # process one logical line
    $n = $buf.Length; $key = ''; $k = 0
    while ($k -lt $n) {
      $c = $buf[$k]
      if ($c -eq '\') { $take = [Math]::Min(2, $n - $k); $key += $buf.Substring($k, $take); $k += 2; continue }
      if ($c -eq '=' -or $c -eq ':' -or $c -eq ' ' -or $c -eq "`t") { break }
      $key += [string]$c
      $k++
    }
    $rest = ''
    if ($k -lt $n) { $rest = $buf.Substring($k) }
    $rest = [regex]::Replace($rest, '^[ \t]*', '')
    if ($rest.Length -gt 0 -and ($rest[0] -eq '=' -or $rest[0] -eq ':')) {
      $rest = $rest.Substring(1)
      $rest = [regex]::Replace($rest, '^[ \t]*', '')
    }
    $value = $rest
    if ($value -eq '') { $out.Add("WARN ${file}:${start} [P001] key without value: $key") }
    elseif ($value -cmatch '[ \t]$') { $out.Add("WARN ${file}:${start} [P004] trailing whitespace is part of the value in java.util.Properties: $key") }
    if ($seen.ContainsKey($key)) { $out.Add("WARN ${file}:${start} [P002] duplicate key $key (also line $($seen[$key]); last wins)") }
    $seen[$key] = $start
    if ($t -eq 'termux') {
      if (-not $kt.ContainsKey($key)) { $out.Add("WARN ${file}:${start} [P003] unknown key $key (not in the known-keys table; verify against the Termux wiki)") }
      elseif ($value -ne '') { Check-Value $file $key $value $start }
    }
    elseif ($t -eq 'colors') {
      if ($key -cnotmatch '^(foreground|background|cursor|color[0-9]|color1[0-5])$') { $out.Add("WARN ${file}:${start} [K001] unknown color key $key") }
      else {
        $script:nset++
        if ($value -cnotmatch '^#[0-9a-fA-F]{3}$' -and $value -cnotmatch '^#[0-9a-fA-F]{6}$') { $out.Add("ERROR ${file}:${start} [K002] $key = $value : expected #RGB or #RRGGBB") }
      }
    }
  }
  if ($cont) { $out.Add("WARN ${file}:${start} [P007] file ends inside a backslash continuation") }
  if ($crn -gt 0) { $out.Add("ERROR ${file}:${crfirst} [E001] CR byte in $crn line(s); LF endings required (CR becomes part of values)") }
  if ($t -eq 'colors' -and $script:nset -lt 19) { $out.Add("INFO ${file}:1 [K003] $(19 - $script:nset) of 19 standard color keys not set (Termux defaults apply)") }
}

foreach ($f in $files) {
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { $out.Add("ERROR ${f}:1 [IO] file not found"); continue }
  $t = $type
  if ($t -eq 'auto') {
    $leaf = [System.IO.Path]::GetFileName($f)
    if ($leaf -clike 'colors*.properties') { $t = 'colors' }
    elseif ($leaf -ceq 'termux.properties' -or $leaf -ceq 'termux.float.properties') { $t = 'termux' }
    else { $t = 'generic' }
  }
  Test-File $f $t
}

foreach ($l in $out) { Write-Output $l }
$errors = @($out | Where-Object { $_.StartsWith('ERROR ') }).Count
$warns = @($out | Where-Object { $_.StartsWith('WARN ') }).Count
$infos = @($out | Where-Object { $_.StartsWith('INFO ') }).Count
Write-Output "SUMMARY files=$($files.Count) errors=$errors warnings=$warns info=$infos"
if ($errors -gt 0) { exit 1 }
exit 0

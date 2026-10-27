# lint-shell.ps1 - host-side quality gate for shell code that targets Termux.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File lint-shell.ps1 [options]  (direct `& .\lint-shell.ps1` is blocked by the execution policy)
# Read-only. Uses ShellCheck/shfmt/shell syntax checks when present and falls
# back to built-in heuristics (patterns.tsv) when a tool is missing.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Same contract as lint-shell.sh.

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = (New-Object System.Text.UTF8Encoding($false)) } catch { }
$rulesPath = Join-Path $PSScriptRoot 'patterns.tsv'
$wrappersPath = Join-Path $PSScriptRoot 'wrapper-names.txt'

function Show-Usage {
  @'
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File lint-shell.ps1 [options] [PATH ...]

Quality gate for shell code targeting Termux:
  sh/bash  ShellCheck + shfmt (project .editorconfig) + syntax check
  zsh      zsh -n only (ShellCheck unsupported; shfmt can corrupt zsh syntax)
  all      built-in heuristics: line endings, banner borders, bashisms,
           zsh pitfalls, Termux path/command compatibility, log-prefix scope
No PATH: lints the shell-like files of the repository (agent dirs excluded).

Options:
  --dialect D        force dialect: posix | bash | zsh (default: auto)
  --root DIR         project root (default: git toplevel, else current dir)
  --no-external      skip ShellCheck/shfmt/syntax tools (heuristics only)
  --strict           exit 1 on WARN as well
  --max-per-rule N   cap findings per rule per file (default 5)
  -h, --help         show this help

Output: LEVEL FILE:LINE [CODE] message, then one SUMMARY line.
  LEVEL: ERROR | WARN | INFO | NOTE | SKIP
Exit: 0 no ERROR (and no WARN with --strict), 1 findings, 2 usage error.
Suppress a heuristic on one line with a trailing comment: lint-ignore: CODE
L002 flags log prefixes inside wrapper-like functions; names: scripts/wrapper-names.txt
ShellCheck notes count as WARN (judge new findings in changed files).
'@
}
function Fail-Usage([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }

$dialectForce = ''; $root = ''; $external = $true; $strict = $false; $maxPer = 5
$argPaths = New-Object System.Collections.Generic.List[string]
$i = 0
while ($i -lt $args.Count) {
  $a = [string]$args[$i]
  if ($a -eq '-h' -or $a -eq '--help') { Show-Usage; exit 0 }
  elseif ($a -eq '--dialect' -or $a -eq '--root' -or $a -eq '--max-per-rule') {
    if ($i + 1 -ge $args.Count) { Fail-Usage "lint-shell: $a needs a value" }
    $v = [string]$args[$i + 1]
    if ($a -eq '--dialect') { $dialectForce = $v } elseif ($a -eq '--root') { $root = $v } else { $maxText = $v }
    $i += 2
  }
  elseif ($a -eq '--no-external') { $external = $false; $i++ }
  elseif ($a -eq '--strict') { $strict = $true; $i++ }
  elseif ($a -eq '--') { $i++; while ($i -lt $args.Count) { $argPaths.Add([string]$args[$i]); $i++ } }
  elseif ($a.StartsWith('-')) { [Console]::Error.WriteLine("lint-shell: unknown option: $a"); Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }; exit 2 }
  else { $argPaths.Add($a); $i++ }
}
if ($dialectForce -and @('posix', 'bash', 'zsh') -cnotcontains $dialectForce) { Fail-Usage 'lint-shell: --dialect must be posix, bash, or zsh' }
if ($null -ne $maxText) {
  if ($maxText -notmatch '^[0-9]+$') { Fail-Usage 'lint-shell: --max-per-rule must be a number' }
  $maxPer = [int]$maxText
}
if (-not (Test-Path -LiteralPath $rulesPath -PathType Leaf)) { Fail-Usage "lint-shell: rules file missing: $rulesPath" }

# Rules from patterns.tsv
$rules = New-Object System.Collections.Generic.List[object]
foreach ($rl in [System.IO.File]::ReadAllLines($rulesPath)) {
  if ($rl.StartsWith('#') -or $rl.Trim() -eq '') { continue }
  $f = $rl.Split("`t")
  if ($f.Count -lt 5) { continue }
  $rules.Add([pscustomobject]@{ Dialects = (',' + $f[0] + ','); Severity = $f[1]; Code = $f[2]; Regex = (New-Object System.Text.RegularExpressions.Regex($f[3])); Message = $f[4] })
}
$wrapNames = @{}
$wrapPrefixes = @()
if (Test-Path -LiteralPath $wrappersPath -PathType Leaf) {
  foreach ($wl in [System.IO.File]::ReadAllLines($wrappersPath)) {
    $x = [regex]::Replace($wl, '#.*$', '')
    $x = [regex]::Replace($x, '[ \t\r]', '')
    if ($x -eq '' -or $x -eq '*') { continue }
    if ($x.EndsWith('*')) { $wrapPrefixes += $x.Substring(0, $x.Length - 1) } else { $wrapNames[$x] = $true }
  }
}
function Test-Wrapper([string]$name) {
  if ($wrapNames.ContainsKey($name)) { return $true }
  foreach ($p in $wrapPrefixes) { if ($name.StartsWith($p, [System.StringComparison]::Ordinal)) { return $true } }
  return $false
}
$ws = '[ \t]'
$nm = '[A-Za-z_][A-Za-z0-9_:.-]*'
$reFn1 = New-Object System.Text.RegularExpressions.Regex("^$ws*(function$ws+)?($nm)$ws*\(\)")
$reFn2 = New-Object System.Text.RegularExpressions.Regex("^$ws*function$ws+($nm)")
$reOneLiner = New-Object System.Text.RegularExpressions.Regex('\{.*\}[ ]*(#.*)?$')
$reLuPrefix = New-Object System.Text.RegularExpressions.Regex('(^|[^A-Za-z0-9_])\[[*+!?-]\]([^}]|$)')
$reLuCall = New-Object System.Text.RegularExpressions.Regex('(^|[^A-Za-z0-9_])log_(info|success|warn|error|prompt)([^A-Za-z0-9_]|$)')
$reTrailWs = New-Object System.Text.RegularExpressions.Regex('[ \t]+$')
$reCommentLine = New-Object System.Text.RegularExpressions.Regex('^[ ]*#')
$reHdStart = New-Object System.Text.RegularExpressions.Regex('(^|[^<])<<-?[ ]*["''\\]?[A-Za-z_][A-Za-z0-9_]*')
$reHdStrip = New-Object System.Text.RegularExpressions.Regex('[ "''\\]')

# Tool lookup (Git for Windows and MSYS2 ship POSIX tools that are often not on PATH)
$onWindows = ([System.Environment]::OSVersion.Platform.ToString() -eq 'Win32NT')
$extraDirs = @()
if ($onWindows) {
  foreach ($r in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
    if ($r) { foreach ($sub in @('usr\bin', 'bin', 'mingw64\bin')) { $extraDirs += (Join-Path (Join-Path $r 'Git') $sub) } }
  }
  foreach ($varName in @('MSYS2_ROOT', 'MSYS_ROOT')) {
    $mr = [Environment]::GetEnvironmentVariable($varName, 'Process')
    if (-not $mr) { $mr = [Environment]::GetEnvironmentVariable($varName, 'User') }
    if (-not $mr) { $mr = [Environment]::GetEnvironmentVariable($varName, 'Machine') }
    if ($mr -and (Test-Path -LiteralPath $mr -PathType Container)) {
      foreach ($sub in @('usr\bin', 'mingw64\bin', 'ucrt64\bin', 'bin')) {
        $p = Join-Path $mr $sub
        if (Test-Path -LiteralPath $p -PathType Container) { $extraDirs += $p }
      }
    }
  }
}
function Find-Tool([string]$name) {
  $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return [string]$cmd.Source }
  foreach ($dir in $extraDirs) {
    foreach ($ext in @('', '.exe')) {
      $p = Join-Path $dir ($name + $ext)
      if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
  }
  return ''
}
$shellcheck = Find-Tool 'shellcheck'
$shfmt = Find-Tool 'shfmt'
$bashExe = Find-Tool 'bash'
$zshExe = Find-Tool 'zsh'
$posixKind = ''; $posixExe = ''
$t = Find-Tool 'dash'
if ($t) { $posixKind = 'dash'; $posixExe = $t }
else {
  $t = Find-Tool 'busybox'
  if ($t) { & $t sh -c ':' *> $null; if ($LASTEXITCODE -eq 0) { $posixKind = 'busybox'; $posixExe = $t } }
  if (-not $posixKind) { $t = Find-Tool 'sh'; if ($t) { $posixKind = 'sh'; $posixExe = $t } }
}

function Get-FirstLine([string]$path) {
  try {
    $sr = New-Object System.IO.StreamReader($path)
    try { $l = $sr.ReadLine() } finally { $sr.Dispose() }
    if ($null -eq $l) { return '' }
    return $l
  } catch { return '' }
}
function Get-ShebangDialect([string]$first) {
  $parts = @(($first.Substring(2).Trim()) -split '\s+' | Where-Object { $_ })
  if ($parts.Count -eq 0) { return 'other' }
  $interp = [System.IO.Path]::GetFileName(([string]$parts[0]).Replace('\', '/'))
  if ($interp -eq 'env') {
    $interp = ''
    for ($k = 1; $k -lt $parts.Count; $k++) {
      $p = [string]$parts[$k]
      if ($p.StartsWith('-') -or $p.Contains('=')) { continue }
      $interp = [System.IO.Path]::GetFileName($p.Replace('\', '/'))
      break
    }
  }
  switch ($interp) {
    { $_ -in @('sh', 'dash', 'ash') } { return 'posix' }
    'bash' { return 'bash' }
    'zsh' { return 'zsh' }
    default { return 'other' }
  }
}
function Get-Dialect([string]$path) {
  $first = Get-FirstLine $path
  if ($first.StartsWith('#!')) { return (Get-ShebangDialect $first) }
  $base = [System.IO.Path]::GetFileName($path)
  if ($base -cmatch '\.zsh$' -or @('.zshrc', '.zshenv', '.zprofile', '.zlogin') -ccontains $base) { return 'zsh' }
  if ($base -cmatch '\.bash$' -or @('.bashrc', '.bash_profile') -ccontains $base) { return 'bash' }
  if ($base -cmatch '\.(sh|ksh)$' -or $base -ceq '.profile') { return 'posix' }
  return 'other'
}

$out = New-Object System.Collections.Generic.List[string]
$script:skipped = @()
function Skip-Once([string]$tool, [string]$reason) {
  if ($script:skipped -contains $tool) { return }
  $script:skipped += $tool
  $out.Add("SKIP ${tool}: $reason")
}
function Has-EditorConfig([string]$path) {
  $d = Split-Path -Parent ([System.IO.Path]::GetFullPath($path))
  while ($d) {
    if (Test-Path -LiteralPath (Join-Path $d '.editorconfig') -PathType Leaf) { return $true }
    $parent = Split-Path -Parent $d
    if (-not $parent -or $parent -eq $d) { break }
    $d = $parent
  }
  return $false
}
function Invoke-Native([string]$exe, [string[]]$arguments) {
  $res = @(& $exe @arguments 2>&1 | ForEach-Object { [string]$_ })
  return $res
}

# Heuristic pass (same logic as the awk program in lint-shell.sh)
function Invoke-Heuristics([string]$file, [string]$dialect) {
  $bytes = [System.IO.File]::ReadAllBytes($file)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  $lines = $text.Split([char]10)
  if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }
  if ($bytes.Length -eq 0) { $lines = @() }
  $cnt = @{}; $lcnt = @{}; $lfirst = @{}
  $crn = 0; $crfirst = 0; $p1 = ''; $p2 = ''; $nr = 0
  $inhd = $false; $hdterm = ''; $hdtab = $false; $hdline = 0
  $infn = ''; $fnwrap = $false; $fnend = $null
  function Add-L002([int]$n, [string]$fn) {
    if ($cnt.ContainsKey('L002')) { $cnt['L002']++ } else { $cnt['L002'] = 1 }
    if ($cnt['L002'] -le $maxPer) { $res.Add(('WARN {0}:{1} [L002] UI log prefix inside wrapper-like function {2}: wrappers and CLI integrations keep native output (no prefixes)' -f $file, $n, $fn)) }
  }
  $res = New-Object System.Collections.Generic.List[string]
  foreach ($line in $lines) {
    $nr++
    if ($line.Contains([string][char]13)) { $crn++; if ($crfirst -eq 0) { $crfirst = $nr } }
    if ($reTrailWs.IsMatch($line)) {
      if ($cnt.ContainsKey('W001')) { $cnt['W001']++ } else { $cnt['W001'] = 1 }
      if ($cnt['W001'] -le $maxPer) { $res.Add("WARN ${file}:${nr} [W001] trailing whitespace") }
    }
    if ($line -cmatch '^#+$' -and $line.Length -ge 3 -and $p1 -cmatch '^# ' -and $p2 -cmatch '^#+$' -and $p2.Length -ge 3 -and $p1 -cnotmatch '[^ -~]') {
      if ($p2.Length -ne $p1.Length -or $line.Length -ne $p1.Length) {
        $res.Add(('WARN {0}:{1} [C001] banner borders {2}/{3} must equal title length {4}' -f $file, ($nr - 2), $p2.Length, $line.Length, $p1.Length))
      }
    }
    $p2 = $p1; $p1 = $line
    if ($inhd) {
      $cmp = $line
      if ($cmp.EndsWith([string][char]13)) { $cmp = $cmp.Substring(0, $cmp.Length - 1) }
      if ($hdtab) { $cmp = $cmp.TrimStart([char]9) }
      if ($cmp -ceq $hdterm) { $inhd = $false }
      continue
    }
    if ($nr -eq 1 -and $line.StartsWith('#!')) { continue }
    if ($reCommentLine.IsMatch($line)) { continue }
    for ($ri = 0; $ri -lt $rules.Count; $ri++) {
      $r = $rules[$ri]
      if (-not ($r.Dialects.Contains(',' + $dialect + ',') -or $r.Dialects.Contains(',*,'))) { continue }
      if (-not $r.Regex.IsMatch($line)) { continue }
      if ($line.Contains('lint-ignore') -and $line.Contains($r.Code)) { continue }
      if ($r.Severity -eq 'COUNT') {
        if ($lcnt.ContainsKey($ri)) { $lcnt[$ri]++ } else { $lcnt[$ri] = 1; $lfirst[$ri] = $nr }
        continue
      }
      if ($cnt.ContainsKey($r.Code)) { $cnt[$r.Code]++ } else { $cnt[$r.Code] = 1 }
      if ($cnt[$r.Code] -le $maxPer) { $res.Add(('{0} {1}:{2} [{3}] {4}' -f $r.Severity, $file, $nr, $r.Code, $r.Message)) }
    }
    $lg = ($line.Contains('lint-ignore') -and $line.Contains('L002'))
    if ($infn -eq '') {
      $fname = ''
      $m1 = $reFn1.Match($line)
      if ($m1.Success) { $fname = $m1.Groups[2].Value }
      else { $m2 = $reFn2.Match($line); if ($m2.Success) { $fname = $m2.Groups[1].Value } }
      if ($fname -ne '') {
        $wrap = Test-Wrapper $fname
        if ($wrap -and -not $lg -and ($reLuPrefix.IsMatch($line) -or $reLuCall.IsMatch($line))) { Add-L002 $nr $fname }
        if (-not $reOneLiner.IsMatch($line)) {
          $infn = $fname
          $fnwrap = $wrap
          $fnind = $line.Length - $line.TrimStart(' ').Length
          $fnend = New-Object System.Text.RegularExpressions.Regex('^' + (' ' * $fnind) + '\}[ ]*(#.*)?$')
        }
      }
    }
    else {
      if ($fnwrap -and -not $lg -and ($reLuPrefix.IsMatch($line) -or $reLuCall.IsMatch($line))) { Add-L002 $nr $infn }
      if ($fnend.IsMatch($line)) { $infn = '' }
    }
    if (-not $line.Contains('((')) {
      $hm = $reHdStart.Match($line)
      if ($hm.Success) {
        $hd = $hm.Value
        $hd = $hd.Substring($hd.IndexOf('<<') + 2)
        $hdtab = $hd.StartsWith('-')
        if ($hdtab) { $hd = $hd.Substring(1) }
        $hdterm = $reHdStrip.Replace($hd, '')
        $hdline = $nr
        $inhd = $true
      }
    }
  }
  $shown = @{}
  foreach ($r in $rules) {
    if ($cnt.ContainsKey($r.Code) -and $cnt[$r.Code] -gt $maxPer -and -not $shown.ContainsKey($r.Code)) {
      $shown[$r.Code] = $true
      $res.Add(('NOTE {0} [{1}] {2} more finding(s) suppressed (raise --max-per-rule)' -f $file, $r.Code, ($cnt[$r.Code] - $maxPer)))
    }
  }
  if ($cnt.ContainsKey('W001') -and $cnt['W001'] -gt $maxPer) {
    $res.Add(('NOTE {0} [W001] {1} more finding(s) suppressed (raise --max-per-rule)' -f $file, ($cnt['W001'] - $maxPer)))
  }
  if ($cnt.ContainsKey('L002') -and $cnt['L002'] -gt $maxPer) {
    $res.Add(('NOTE {0} [L002] {1} more finding(s) suppressed (raise --max-per-rule)' -f $file, ($cnt['L002'] - $maxPer)))
  }
  if ($crn -gt 0) { $res.Add(('ERROR {0}:{1} [E001] CR byte in {2} line(s); LF line endings required' -f $file, $crfirst, $crn)) }
  if ($inhd) { $res.Add(('WARN {0}:{1} [H001] here-document delimiter {2} never closed; later lines were not checked' -f $file, $hdline, $hdterm)) }
  for ($ri = 0; $ri -lt $rules.Count; $ri++) {
    if ($lcnt.ContainsKey($ri)) { $res.Add(('INFO {0}:{1} [{2}] {3} line(s): {4}' -f $file, $lfirst[$ri], $rules[$ri].Code, $lcnt[$ri], $rules[$ri].Message)) }
  }
  return $res
}

function Cut200([string]$s) { if ($s.Length -gt 200) { return $s.Substring(0, 200) } else { return $s } }

function Lint-File([string]$f, [string]$d) {
  $first = Get-FirstLine $f
  $hasBang = $false
  if ($first.StartsWith('#!')) {
    $hasBang = $true
    if ($first.StartsWith('#!/bin/') -or $first.StartsWith('#!/usr/')) {
      $out.Add("INFO ${f}:1 [S003] FHS shebang resolves in Termux only via termux-exec; follow the project convention")
    }
  }
  elseif ($d -ne 'zsh') { $out.Add("INFO ${f}:1 [S001] no shebang (sourced/library file assumed)") }
  $fs = [System.IO.File]::OpenRead($f)
  try {
    if ($fs.Length -gt 0) {
      $null = $fs.Seek(-1, [System.IO.SeekOrigin]::End)
      if ($fs.ReadByte() -ne 10) { $out.Add("WARN ${f}:1 [E002] no newline at end of file") }
    }
  } finally { $fs.Dispose() }
  foreach ($l in (Invoke-Heuristics $f $d)) { $out.Add($l) }
  if (-not $external) { return }
  $fp = $f.Replace('\', '/')
  if ($d -eq 'posix' -or $d -eq 'bash') {
    if ($shellcheck) {
      $scArgs = @('-f', 'gcc')
      if (-not $hasBang) { if ($d -eq 'bash') { $scArgs += @('-s', 'bash') } else { $scArgs += @('-s', 'sh') } }
      $scArgs += $fp
      foreach ($line in (Invoke-Native $shellcheck $scArgs)) {
        $m = [regex]::Match($line, '^(.*?):([0-9]+):[0-9]+: (error|warning|note): (.*)$')
        if (-not $m.Success) { continue }
        $lv = if ($m.Groups[3].Value -ceq 'error') { 'ERROR' } else { 'WARN' }
        $rest = $m.Groups[4].Value
        $code = 'SC'
        $cm = [regex]::Match($rest, ' \[(SC[0-9]+)\]$')
        if ($cm.Success) { $code = $cm.Groups[1].Value; $rest = $rest.Substring(0, $cm.Index) }
        $out.Add(('{0} {1}:{2} [{3}] {4}' -f $lv, $m.Groups[1].Value, $m.Groups[2].Value, $code, $rest))
      }
    }
    else { Skip-Once 'shellcheck' 'not installed; heuristics only (see platform-detection for hints)' }
    $se = ''
    if ($d -eq 'bash') {
      if ($bashExe) { $se = [string](Invoke-Native $bashExe @('-n', $fp) | Select-Object -First 1) }
      else { Skip-Once 'bash-syntax' 'bash not installed' }
    }
    elseif ($posixKind) {
      if ($posixKind -eq 'busybox') { $se = [string](Invoke-Native $posixExe @('sh', '-n', $fp) | Select-Object -First 1) }
      else { $se = [string](Invoke-Native $posixExe @('-n', $fp) | Select-Object -First 1) }
    }
    else { Skip-Once 'posix-syntax' 'no POSIX shell available' }
    if ($se) { $out.Add((Cut200 "ERROR ${f}:1 [SYN] $se")) }
    if ($shfmt) {
      if (Has-EditorConfig $f) {
        $fd = Invoke-Native $shfmt @('-d', $fp)
        if ($LASTEXITCODE -ne 0) {
          $joined = ($fd -join "`n")
          if ($joined.StartsWith('---') -or $joined.StartsWith('diff')) {
            $hunks = @($fd | Where-Object { $_.StartsWith('@@') }).Count
            $out.Add("WARN ${f}:1 [FMT] shfmt: $hunks hunk(s) differ from .editorconfig style (fix: shfmt -w $f)")
          }
          else { $out.Add((Cut200 ("WARN ${f}:1 [FMT] shfmt could not parse: " + [string]($fd | Select-Object -First 1)))) }
        }
      }
      else { Skip-Once 'shfmt' 'no .editorconfig found; formatting style unverifiable' }
    }
    else { Skip-Once 'shfmt' 'not installed; formatting unverified (see platform-detection)' }
  }
  elseif ($d -eq 'zsh') {
    if ($zshExe) {
      $se = [string](Invoke-Native $zshExe @('-n', $fp) | Select-Object -First 1)
      if ($se) { $out.Add((Cut200 "ERROR ${f}:1 [SYN] $se")) }
    }
    else { Skip-Once 'zsh-syntax' 'zsh not installed (WSL or MSYS2 provide it); zsh files checked by heuristics only' }
    if ($f -cmatch '\.zsh$' -and $shfmt -and (Has-EditorConfig $f)) {
      $fd = Invoke-Native $shfmt @('-d', $fp)
      $hunks = @($fd | Where-Object { $_.StartsWith('@@') }).Count
      if ($hunks -gt 0) { $out.Add("INFO ${f}:1 [FMT] shfmt advisory (zsh): $hunks hunk(s) differ from .editorconfig; review with shfmt -d, never write") }
    }
  }
}

# Build the file list.
$fileList = New-Object System.Collections.Generic.List[string]
function Walk-Files([string]$dir) {
  $found = New-Object System.Collections.Generic.List[string]
  foreach ($x in (Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    $p = $x.FullName
    if ($p -match '[\\/]\.git[\\/]') { continue }
    $found.Add($p)
  }
  $arr = $found.ToArray(); [Array]::Sort($arr, [System.StringComparer]::Ordinal)
  return $arr
}
if ($argPaths.Count -gt 0) {
  foreach ($a in $argPaths) {
    if (Test-Path -LiteralPath $a -PathType Container) { foreach ($x in (Walk-Files $a)) { $fileList.Add($x) } }
    elseif (Test-Path -LiteralPath $a -PathType Leaf) { $fileList.Add($a) }
    else { [Console]::Error.WriteLine("lint-shell: not found: $a"); exit 2 }
  }
}
else {
  $haveGit = [bool](Get-Command git -CommandType Application -ErrorAction SilentlyContinue)
  if (-not $root) { if ($haveGit) { $root = [string](& git rev-parse --show-toplevel 2>$null) }; if (-not $root) { $root = (Get-Location).Path } }
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { [Console]::Error.WriteLine("lint-shell: cannot enter root: $root"); exit 2 }
  Set-Location -LiteralPath $root
  [System.IO.Directory]::SetCurrentDirectory((Get-Location).Path)
  $inGit = $false
  if ($haveGit) { $null = & git rev-parse --is-inside-work-tree 2>$null; $inGit = ($LASTEXITCODE -eq 0) }
  if ($inGit) {
    foreach ($x in @(& git -c core.quotepath=off ls-files -co --exclude-standard 2>$null)) { if ($x -and ($x -notmatch '^\.agents?/')) { $fileList.Add($x) } }
  }
  else {
    $prefixLen = (Get-Location).Path.TrimEnd('\', '/').Length + 1
    foreach ($x in (Walk-Files (Get-Location).Path)) {
      $rel = $x.Substring($prefixLen).Replace('\', '/')
      if ($rel -match '(^|/)node_modules/' -or $rel -match '^\.agents?/') { continue }
      $fileList.Add($rel)
    }
  }
}

$nfiles = 0
foreach ($f in $fileList) {
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
  if ($dialectForce) { $d = $dialectForce } else { $d = Get-Dialect $f }
  if ($d -eq 'other') { continue }
  $nfiles++
  Lint-File $f $d
}

if (-not $external) { $script:skipped += 'external-tools(requested)' }
if ($nfiles -eq 0) { Write-Output 'NOTE no shell-like files found' }
foreach ($l in $out) { Write-Output $l }
$errors = @($out | Where-Object { $_.StartsWith('ERROR ') }).Count
$warns = @($out | Where-Object { $_.StartsWith('WARN ') }).Count
$infos = @($out | Where-Object { $_.StartsWith('INFO ') }).Count
$cov = if ($script:skipped.Count -gt 0) { 'partial' } else { 'full' }
Write-Output ("SUMMARY files=$nfiles errors=$errors warnings=$warns info=$infos coverage=$cov skipped=" + ($script:skipped -join ','))
if ($errors -gt 0) { exit 1 }
if ($strict -and $warns -gt 0) { exit 1 }
exit 0

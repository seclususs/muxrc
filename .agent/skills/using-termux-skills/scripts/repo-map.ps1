# repo-map.ps1 - compact, fact-only snapshot of a repository's shell/config layout.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File repo-map.ps1 [options]  (direct `& .\repo-map.ps1` is blocked by the execution policy)
# Read-only. Output: tagged lines on stdout. Use it instead of assuming paths.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Same contract as repo-map.sh.

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = (New-Object System.Text.UTF8Encoding($false)) } catch { }

function Show-Usage {
  @'
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File repo-map.ps1 [--root DIR] [--max N] [-h|--help]

Snapshot of repository facts (read-only):
  root, git        repository root, branch@commit, dirty file count
  conf             known config files present (editorconfig, shellcheckrc, ...)
  dirs             file count per top-level directory
  files            total files and shell-like files
  dialect.*        shell-like files per dialect: posix | bash | zsh | other
  shebang          first-line forms and their counts
  loc.shell        total lines in shell-like files
  def              function/alias definitions as FILE:LINE KIND NAME (up to N)
  termux_cmds      termux-* commands referenced, with counts
  ext_cmds         external commands guarded by command -v / require_cmd
  logui.prefix     files containing [*] [+] [-] [!] [?] prefix tokens, with counts
  logui.calls      files calling log_info/success/warn/error/prompt, with counts
  commits          last 8 commit subjects (style reference)

Options:
  --root DIR   repository root (default: git toplevel, else current directory)
  --max N      cap definition lines (default 80)

Exit codes: 0 ok, 2 usage error or unreadable root.
'@
}

$root = ''
$max = 80
$i = 0
while ($i -lt $args.Count) {
  $a = [string]$args[$i]
  if ($a -eq '-h' -or $a -eq '--help') { Show-Usage; exit 0 }
  elseif ($a -eq '--root' -or $a -eq '--max') {
    if ($i + 1 -ge $args.Count) { [Console]::Error.WriteLine("repo-map: $a needs a value"); exit 2 }
    if ($a -eq '--root') { $root = [string]$args[$i + 1] } else { $maxText = [string]$args[$i + 1]; if ($maxText -notmatch '^[0-9]+$') { [Console]::Error.WriteLine('repo-map: --max must be a number'); exit 2 }; $max = [int]$maxText }
    $i += 2
  }
  else {
    [Console]::Error.WriteLine("repo-map: unknown option: $a")
    Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 2
  }
}

$haveGit = [bool](Get-Command git -CommandType Application -ErrorAction SilentlyContinue)
if (-not $root) {
  if ($haveGit) { $root = [string](& git rev-parse --show-toplevel 2>$null) }
  if (-not $root) { $root = (Get-Location).Path }
}
if (-not (Test-Path -LiteralPath $root -PathType Container)) { [Console]::Error.WriteLine("repo-map: cannot enter root: $root"); exit 2 }
Set-Location -LiteralPath $root
$root = (Get-Location).Path
[System.IO.Directory]::SetCurrentDirectory($root)

$inGit = $false
if ($haveGit) { $null = & git rev-parse --is-inside-work-tree 2>$null; $inGit = ($LASTEXITCODE -eq 0) }

# File inventory: tracked + untracked-not-ignored via git, else a directory walk.
if ($inGit) {
  $files = @(& git -c core.quotepath=off ls-files -co --exclude-standard 2>$null)
}
else {
  $prefixLen = $root.TrimEnd('\', '/').Length + 1
  $list = New-Object System.Collections.Generic.List[string]
  foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)) {
    $rel = $f.FullName.Substring($prefixLen).Replace('\', '/')
    if ($rel -match '(^|/)\.git/' -or $rel -match '(^|/)node_modules/') { continue }
    $list.Add($rel)
  }
  $files = $list.ToArray()
  [Array]::Sort($files, [System.StringComparer]::Ordinal)
}
# The agent tooling directory is not project code; leave it out of the facts.
$files = @($files | Where-Object { $_ -and ($_ -notmatch '^\.agents?/') -and ($_ -notmatch '^\.termux-agent/') })

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
function Get-FirstLine([string]$path) {
  try {
    $sr = New-Object System.IO.StreamReader($path)
    try { $l = $sr.ReadLine() } finally { $sr.Dispose() }
    if ($null -eq $l) { return '' }
    return $l
  } catch { return '' }
}

$lists = @{ posix = (New-Object System.Collections.Generic.List[string]); bash = (New-Object System.Collections.Generic.List[string]); zsh = (New-Object System.Collections.Generic.List[string]); other = (New-Object System.Collections.Generic.List[string]) }
$shebangs = @{}
foreach ($f in $files) {
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
  $base = [System.IO.Path]::GetFileName($f)
  $first = ''
  $known = $base -cmatch '\.(sh|bash|zsh|ksh)$' -or @('.zshrc', '.zshenv', '.zprofile', '.zlogin', '.bashrc', '.bash_profile', '.profile') -ccontains $base
  if ($known) { $first = Get-FirstLine $f }
  elseif ($base.Contains('.')) { continue }
  else {
    $first = Get-FirstLine $f
    if (-not $first.StartsWith('#!')) { continue }
  }
  if ($first.StartsWith('#!')) {
    $d = Get-ShebangDialect $first
    if ($shebangs.ContainsKey($first)) { $shebangs[$first]++ } else { $shebangs[$first] = 1 }
  }
  else {
    if ($base -cmatch '\.zsh$' -or @('.zshrc', '.zshenv', '.zprofile', '.zlogin') -ccontains $base) { $d = 'zsh' }
    elseif ($base -cmatch '\.bash$' -or @('.bashrc', '.bash_profile') -ccontains $base) { $d = 'bash' }
    else { $d = 'posix' }
  }
  $lists[$d].Add($f)
}
$shell = @($lists['posix']) + @($lists['bash']) + @($lists['zsh']) + @($lists['other'])

Write-Output "root=$root"
if ($inGit) {
  $br = [string](& git rev-parse --abbrev-ref HEAD 2>$null); if (-not $br) { $br = 'unknown' }
  $sha = [string](& git rev-parse --short HEAD 2>$null); if (-not $sha) { $sha = 'none' }
  $dirty = @(& git status --porcelain -- . ':(exclude).agent' ':(exclude).agents' 2>$null).Count
  Write-Output "git=$br@$sha dirty=$dirty"
}
else { Write-Output 'git=none' }

$conf = @()
foreach ($c in @('.editorconfig', '.shellcheckrc', '.gitattributes', '.gitignore', '.gitmodules', '.github', 'Makefile', 'README.md')) {
  if (Test-Path -LiteralPath $c) { $conf += $c }
}
Write-Output ('conf=' + ($conf -join ' '))

$dirCount = @{}
foreach ($f in $files) {
  $slash = $f.IndexOf('/')
  $k = if ($slash -ge 0) { $f.Substring(0, $slash) } else { '.' }
  if ($dirCount.ContainsKey($k)) { $dirCount[$k]++ } else { $dirCount[$k] = 1 }
}
$dirKeys = @($dirCount.Keys); [Array]::Sort($dirKeys, [System.StringComparer]::Ordinal)
Write-Output ('dirs=' + (($dirKeys | ForEach-Object { $_ + ':' + $dirCount[$_] }) -join ' '))
Write-Output ('files=' + $files.Count + ' shell=' + $shell.Count)
foreach ($d in @('posix', 'bash', 'zsh', 'other')) { Write-Output ("dialect.$d=" + $lists[$d].Count) }
$sbSorted = $shebangs.GetEnumerator() | Sort-Object @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key }; Ascending = $true }
foreach ($e in $sbSorted) { Write-Output ('shebang=' + $e.Key + ' (' + $e.Value + ')') }

# One pass over shell-like files: definitions, counts, loc.
$ws = '[ \t]'
$nm = '[A-Za-z_][A-Za-z0-9_:.-]*'
$reComment = New-Object System.Text.RegularExpressions.Regex("^$ws*#")
$reFuncParen = New-Object System.Text.RegularExpressions.Regex("^$ws*(function$ws+)?($nm)$ws*\(\)")
$reFuncKw = New-Object System.Text.RegularExpressions.Regex("^$ws*function$ws+($nm)")
$reAlias = New-Object System.Text.RegularExpressions.Regex("^$ws*alias$ws+(-[a-zA-Z]+$ws+)?($nm)=")
$reTermux = New-Object System.Text.RegularExpressions.Regex('termux-[a-z][a-z-]*')
$reExt = New-Object System.Text.RegularExpressions.Regex('(command -v|require_cmd)[ ]+[^ ;|&)(]+')
$reExtPrefix = New-Object System.Text.RegularExpressions.Regex('^(command -v|require_cmd)[ ]+')
$reLuPrefix = New-Object System.Text.RegularExpressions.Regex('(^|[^A-Za-z0-9_])\[[*+!?-]\]([^}]|$)')
$reLuCall = New-Object System.Text.RegularExpressions.Regex('(^|[^A-Za-z0-9_])log_(info|success|warn|error|prompt)([^A-Za-z0-9_]|$)')
$reName = New-Object System.Text.RegularExpressions.Regex('^[A-Za-z0-9_.-]+$')

$loc = 0; $ndef = 0
$tc = @{}; $ec = @{}; $lu = @{}; $cu = @{}
$defLines = New-Object System.Collections.Generic.List[string]
foreach ($file in $shell) {
  $n = 0; $lc = 0; $cc = 0
  $lines = @()
  try { $lines = [System.IO.File]::ReadAllLines((Join-Path $root $file)) } catch { continue }
  foreach ($line in $lines) {
    $n++; $loc++
    if ($reComment.IsMatch($line)) { continue }
    $nmv = ''; $kind = ''
    $m = $reFuncParen.Match($line)
    if ($m.Success) { $nmv = $m.Groups[2].Value; $kind = 'func' }
    else {
      $m = $reFuncKw.Match($line)
      if ($m.Success) { $nmv = $m.Groups[1].Value; $kind = 'func' }
      else {
        $m = $reAlias.Match($line)
        if ($m.Success) { $nmv = $m.Groups[2].Value; $kind = 'alias' }
      }
    }
    if ($nmv) {
      $ndef++
      if ($ndef -le $max) { $defLines.Add("def ${file}:${n} $kind $nmv") }
    }
    foreach ($mm in $reTermux.Matches($line)) { $k = $mm.Value; if ($tc.ContainsKey($k)) { $tc[$k]++ } else { $tc[$k] = 1 } }
    foreach ($mm in $reExt.Matches($line)) {
      $w = $reExtPrefix.Replace($mm.Value, '')
      $w = $w.Replace("'", '').Replace('"', '')
      if ($reName.IsMatch($w)) { if ($ec.ContainsKey($w)) { $ec[$w]++ } else { $ec[$w] = 1 } }
    }
    if ($reLuPrefix.IsMatch($line)) { $lc++ }
    if (-not $nmv -and $reLuCall.IsMatch($line)) { $cc++ }
  }
  if ($lc -gt 0) { $lu[$file] = $lc }
  if ($cc -gt 0) { $cu[$file] = $cc }
}
if ($ndef -gt $max) { $defLines.Add('def ... ' + ($ndef - $max) + ' more (use --max)') }

Write-Output "loc.shell=$loc"
foreach ($l in $defLines) { Write-Output $l }
function Format-Counts($h) {
  $items = $h.GetEnumerator() | Sort-Object @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key }; Ascending = $true }
  return (($items | ForEach-Object { $_.Key + '(' + $_.Value + ')' }) -join ' ')
}
function Format-Locs($h) {
  $keys = @($h.Keys); [Array]::Sort($keys, [System.StringComparer]::Ordinal)
  return (($keys | ForEach-Object { $_ + ':' + $h[$_] }) -join ' ')
}
Write-Output ('termux_cmds=' + (Format-Counts $tc))
Write-Output ('ext_cmds=' + (Format-Counts $ec))
Write-Output ('logui.prefix=' + (Format-Locs $lu))
Write-Output ('logui.calls=' + (Format-Locs $cu))
if ($inGit) {
  Write-Output 'commits:'
  foreach ($s in (& git log -n 8 --format='  %s' 2>$null)) { Write-Output $s }
}
exit 0

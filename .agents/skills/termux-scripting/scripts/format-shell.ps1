# format-shell.ps1 - host-side shfmt wrapper that follows the project's .editorconfig.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File format-shell.ps1 [options]  (direct `& .\format-shell.ps1` is blocked by the execution policy)
# Check mode by default (prints a diff, changes nothing); --write rewrites sh and bash files.
# zsh files are never rewritten. File discovery is lint-shell.ps1 --list.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Same contract as format-shell.sh.

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = (New-Object System.Text.UTF8Encoding($false)) } catch { }
$lintPath = Join-Path $PSScriptRoot 'lint-shell.ps1'

function Show-Usage {
  @'
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File format-shell.ps1 [options] [PATH ...]

Format sh/bash files with shfmt using the project's .editorconfig. No style flags
are passed on purpose: any shfmt parser or printer flag makes shfmt ignore
.editorconfig. A file without an .editorconfig in its directory chain is skipped,
because shfmt would apply its own defaults (tabs). zsh files are skipped:
shfmt can corrupt zsh syntax, so review them with shfmt -d by hand.
No PATH: every shell-like file of the repository (agent dirs excluded).

Options:
  --write         rewrite sh and bash files in place (default: print the diff only)
  --root DIR      project root (default: git toplevel, else current dir)
  --out FILE      write the diff to FILE (UTF-8, LF); convention:
                  .artifacts/format/diff.txt at the project root
  -h, --help      show this help

Output: diff (check mode), SKIP lines, then one line:
  SUMMARY files=N differing=N written=N skipped=N shfmt=VERSION
Exit: 0 nothing differs (or --write succeeded), 1 files differ in check mode
or shfmt reported an error, 2 usage error, 3 shfmt not installed.
'@
}
function Fail-Usage([string]$msg) { [Console]::Error.WriteLine($msg); exit 2 }

$write = $false; $root = ''; $outFile = ''
$argPaths = New-Object System.Collections.Generic.List[string]
$i = 0
while ($i -lt $args.Count) {
  $a = [string]$args[$i]
  if ($a -eq '-h' -or $a -eq '--help') { Show-Usage; exit 0 }
  elseif ($a -eq '--write') { $write = $true; $i++ }
  elseif ($a -eq '--root' -or $a -eq '--out') {
    if ($i + 1 -ge $args.Count) { Fail-Usage "format-shell: $a needs a value" }
    $v = [string]$args[$i + 1]
    if ($a -eq '--root') { $root = $v } else { $outFile = [System.IO.Path]::GetFullPath($v) }
    $i += 2
  }
  elseif ($a -eq '--') { $i++; while ($i -lt $args.Count) { $argPaths.Add([string]$args[$i]); $i++ } }
  elseif ($a.StartsWith('-')) { [Console]::Error.WriteLine("format-shell: unknown option: $a"); Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }; exit 2 }
  else { $argPaths.Add($a); $i++ }
}

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

$shfmt = Find-Tool 'shfmt'
if (-not $shfmt) {
  [Console]::Error.WriteLine('format-shell: shfmt not installed; formatting not checked.')
  [Console]::Error.WriteLine('format-shell: install it (see platform-detection for the host package manager) or format by hand following .editorconfig.')
  exit 3
}
if (-not (Test-Path -LiteralPath $lintPath -PathType Leaf)) { Fail-Usage 'format-shell: lint-shell.ps1 not found next to this script' }

# File discovery and dialect detection are shared with the linter
$listArgs = @('--list')
if ($root) { $listArgs += @('--root', $root) }
foreach ($p in $argPaths) { $listArgs += $p }
$listing = @(& $lintPath @listArgs)
if ($argPaths.Count -eq 0) {
  if (-not $root) {
    $haveGit = [bool](Get-Command git -CommandType Application -ErrorAction SilentlyContinue)
    if ($haveGit) { $root = [string](& git rev-parse --show-toplevel 2>$null) }
    if (-not $root) { $root = (Get-Location).Path }
  }
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { Fail-Usage "format-shell: cannot enter root: $root" }
  Set-Location -LiteralPath $root
  [System.IO.Directory]::SetCurrentDirectory((Get-Location).Path)
}

$total = 0; $differing = 0; $written = 0; $skipped = 0; $failed = 0
$diffText = New-Object System.Collections.Generic.List[string]
$report = New-Object System.Collections.Generic.List[string]
foreach ($line in $listing) {
  $parts = ([string]$line).Split("`t", 2)
  if ($parts.Count -lt 2 -or -not $parts[1]) { continue }
  $dialect = $parts[0]; $f = $parts[1]
  $total++
  if ($dialect -eq 'zsh') { $report.Add("SKIP ${f}: zsh is never rewritten; review with shfmt -d by hand"); $skipped++; continue }
  if (-not (Has-EditorConfig $f)) { $report.Add("SKIP ${f}: no .editorconfig; shfmt defaults would restyle the file"); $skipped++; continue }
  $res = Invoke-Native $shfmt @('-d', $f)
  if ($LASTEXITCODE -eq 0) { continue }
  if (-not (@($res | Where-Object { $_.Contains('@@') }).Count)) {
    $first = [string]($res | Select-Object -First 1)
    $report.Add("ERROR ${f}: shfmt could not parse: $first")
    $failed++
    continue
  }
  $differing++
  if ($write) {
    $null = Invoke-Native $shfmt @('-w', $f)
    if ($LASTEXITCODE -eq 0) { $written++; $report.Add("WROTE $f") }
    else { $report.Add("ERROR ${f}: shfmt could not write"); $failed++ }
  }
  else { foreach ($l in $res) { $diffText.Add($l) } }
}

$verOut = Invoke-Native $shfmt @('--version')
$version = [string]($verOut | Select-Object -First 1)
if (-not $version) { $version = 'unknown' }
$summary = "SUMMARY files=$total differing=$differing written=$written skipped=$skipped shfmt=$version"
if ($outFile -ne '') {
  $dir = Split-Path -Parent $outFile
  if ($dir) { $null = New-Item -ItemType Directory -Force -Path $dir }
  $all = @($diffText) + @($report) + $summary
  [System.IO.File]::WriteAllText($outFile, ($all -join "`n") + "`n")
  $norm = $outFile.Replace('\', '/')
  $idx = $norm.IndexOf('/.artifacts/')
  if ($idx -ge 0) {
    $gi = $norm.Substring(0, $idx) + '/.artifacts/.gitignore'
    if (-not (Test-Path -LiteralPath $gi)) { [System.IO.File]::WriteAllText($gi, "*`n") }
  }
  Write-Output "format-shell: output written to $outFile"
}
else {
  foreach ($l in $diffText) { Write-Output $l }
  foreach ($l in $report) { Write-Output $l }
}
Write-Output $summary
if ($failed -gt 0) { exit 1 }
if (-not $write -and $differing -gt 0) { exit 1 }
exit 0

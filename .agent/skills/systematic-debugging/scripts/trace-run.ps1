# trace-run.ps1 - PowerShell launcher for trace-run.sh.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File trace-run.ps1 [options] -- SCRIPT [ARGS...]  (direct `& .\trace-run.ps1` is blocked by the execution policy)
# Runs a shell script under xtrace and prints bounded tails; keeps $0, args, and exit status.
# Needs a POSIX shell: sh/bash on PATH or the one bundled with Git for Windows.
# Without one it exits 3 and says how to proceed. Compatible with Windows PowerShell 5.1 and PowerShell 7+.

$ErrorActionPreference = 'Continue'
$onWindows = ([System.Environment]::OSVersion.Platform.ToString() -eq 'Win32NT')

$extraDirs = @()
if ($onWindows) {
  foreach ($r in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
    if ($r) { foreach ($sub in @('usr\bin', 'bin')) { $extraDirs += (Join-Path (Join-Path $r 'Git') $sub) } }
  }
  foreach ($varName in @('MSYS2_ROOT', 'MSYS_ROOT')) {
    $mr = [Environment]::GetEnvironmentVariable($varName, 'Process')
    if (-not $mr) { $mr = [Environment]::GetEnvironmentVariable($varName, 'User') }
    if (-not $mr) { $mr = [Environment]::GetEnvironmentVariable($varName, 'Machine') }
    if ($mr -and (Test-Path -LiteralPath $mr -PathType Container)) {
      foreach ($sub in @('usr\bin', 'bin')) {
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

$sh = Find-Tool 'sh'
if (-not $sh) { $sh = Find-Tool 'bash' }
if (-not $sh) {
  [Console]::Error.WriteLine('trace-run: no POSIX shell found (sh/bash). Install Git for Windows (bundles sh.exe) or use WSL.')
  [Console]::Error.WriteLine('trace-run: for runtime verification of Termux behavior use the Termux container or a device (see platform-detection).')
  exit 3
}
# Make the shell's sibling tools (env, mktemp, sed, ...) resolvable first on Windows.
if ($onWindows) { $env:PATH = (Split-Path -Parent $sh) + ';' + $env:PATH }

if ($args -contains '--help' -or $args -contains '-h') { Write-Output "Run via: powershell -NoProfile -ExecutionPolicy Bypass -File trace-run.ps1 [options] -- SCRIPT [ARGS...]  (options below)" }
$target = (Join-Path $PSScriptRoot 'trace-run.sh')
if ($onWindows) { $target = $target.Replace('\', '/') }
$fwd = @()
foreach ($a in $args) {
  $s = [string]$a
  if ($onWindows -and ($s -match '^[A-Za-z]:\\' -or ($s.Contains('\') -and (Test-Path -LiteralPath $s)))) { $s = $s.Replace('\', '/') }
  $fwd += $s
}
& $sh $target @fwd
exit $LASTEXITCODE

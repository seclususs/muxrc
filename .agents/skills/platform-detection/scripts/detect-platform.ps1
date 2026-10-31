# detect-platform.ps1 - detect the development host (not the Termux target).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File detect-platform.ps1 [options]  (direct `& .\detect-platform.ps1` is blocked by the execution policy)
# Read-only: installs nothing, changes nothing. Output: key=value lines.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Same contract as detect-platform.sh.

$ErrorActionPreference = 'SilentlyContinue'

function Show-Usage {
  @'
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File detect-platform.ps1 [--brief] [--tools LIST] [-h|--help]

Probe host OS, shell environment, package manager, tools, and capability fallbacks.

Output (stdout, key=value lines):
  host.os      linux | macos | windows | android | unknown
  host.env     native | wsl | git-bash | msys | cygwin | termux | unknown
  host.arch    machine architecture
  host.pkgmgr  first detected package manager, or none
  tool.NAME    absolute path, or "-" when missing (omitted with --brief); call a tool by
               this path, because a bare name can be absent from PATH (Git for Windows, MSYS2)
  tool.missing space-separated missing tools (only with --brief)
  ver.NAME     version for shellcheck and shfmt when present
  cap.NAME     best available provider for a capability, or "none"
  hint.NAME    install hint for a missing tool (verify before use)
  run.scripts  script flavor to run on this host (ps1)

Options:
  --brief       print one tool.missing line instead of one tool.NAME line per tool;
                no paths, so use it only to check availability
  --tools LIST  comma-separated extra tool names to probe

Exit codes: 0 ok, 2 usage error.
'@
}

$extra = ''
$brief = $false
$i = 0
while ($i -lt $args.Count) {
  $a = [string]$args[$i]
  if ($a -eq '-h' -or $a -eq '--help') { Show-Usage; exit 0 }
  elseif ($a -eq '--brief') { $brief = $true; $i++ }
  elseif ($a -eq '--tools') {
    if ($i + 1 -ge $args.Count) { [Console]::Error.WriteLine('detect-platform: --tools needs a value'); exit 2 }
    $extra = [string]$args[$i + 1]
    $i += 2
  }
  elseif ($a.StartsWith('--tools=')) { $extra = $a.Substring(8); $i++ }
  else {
    [Console]::Error.WriteLine("detect-platform: unknown option: $a")
    Show-Usage | ForEach-Object { [Console]::Error.WriteLine($_) }
    exit 2
  }
}

$onWindows = ([System.Environment]::OSVersion.Platform.ToString() -eq 'Win32NT')

# Extra lookup dirs: Git for Windows and MSYS2 ship POSIX tools that are often not on PATH.
$extraDirs = @()
if ($onWindows) {
  foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs'))) {
    if ($root) {
      foreach ($sub in @('usr\bin', 'bin', 'mingw64\bin')) {
        $extraDirs += (Join-Path (Join-Path $root 'Git') $sub)
      }
    }
  }
  $hasMsys = $false
  foreach ($varName in @('MSYS2_ROOT', 'MSYS_ROOT')) {
    $mr = [Environment]::GetEnvironmentVariable($varName, 'Process')
    if (-not $mr) { $mr = [Environment]::GetEnvironmentVariable($varName, 'User') }
    if (-not $mr) { $mr = [Environment]::GetEnvironmentVariable($varName, 'Machine') }
    if ($mr -and (Test-Path -LiteralPath $mr -PathType Container)) {
      $hasMsys = $true
      foreach ($sub in @('usr\bin', 'mingw64\bin', 'ucrt64\bin', 'bin')) {
        $p = Join-Path $mr $sub
        if (Test-Path -LiteralPath $p -PathType Container) { $extraDirs += $p }
      }
      break
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
  return '-'
}
function Have([string]$name) { return ((Find-Tool $name) -ne '-') }

# Host OS and shell environment
$os = 'unknown'
$envk = 'unknown'
if ($onWindows) {
  $os = 'windows'
  $envk = if ($hasMsys) { 'msys' } else { 'native' }
  $arch = switch ($env:PROCESSOR_ARCHITECTURE) { 'AMD64' { 'x86_64' } 'ARM64' { 'aarch64' } 'x86' { 'i686' } default { [string]$env:PROCESSOR_ARCHITECTURE } }
}
else {
  $un = [string](& uname -s 2>$null)
  $arch = [string](& uname -m 2>$null)
  if ($un -eq 'Linux') {
    $os = 'linux'
    $envk = 'native'
    if ($env:WSL_DISTRO_NAME -or ((Test-Path '/proc/version') -and ((Get-Content '/proc/version' -TotalCount 1) -match 'microsoft'))) { $envk = 'wsl' }
    if ($env:TERMUX_VERSION -or ([string](& uname -o 2>$null)) -eq 'Android') { $os = 'android'; $envk = 'termux' }
  }
  elseif ($un -eq 'Darwin') { $os = 'macos'; $envk = 'native' }
}
if (-not $arch) { $arch = 'unknown' }

# Package manager (first match; order depends on host)
$mgrs = if ($os -eq 'macos') { @('brew', 'port') } elseif ($os -eq 'windows') { if ($envk -eq 'msys') { @('pacman', 'winget', 'scoop', 'choco') } else { @('winget', 'scoop', 'choco', 'pacman') } } else { @('apt-get', 'dnf', 'pacman', 'zypper', 'apk', 'brew') }
$pkgmgr = 'none'
foreach ($m in $mgrs) { if (Have $m) { $pkgmgr = $m; break } }

Write-Output "host.os=$os"
Write-Output "host.env=$envk"
Write-Output "host.arch=$arch"
Write-Output "host.pkgmgr=$pkgmgr"
Write-Output 'run.scripts=ps1'
if ($envk -eq 'termux') { Write-Output 'note=running inside Termux (target); host-only assumptions do not apply' }

# Tool availability
$defaultTools = 'git sh dash bash zsh busybox shellcheck shfmt checkbashisms rg jq python3 node pwsh powershell.exe docker adb zip unzip tar curl'.Split(' ')
$extraTools = @()
if ($extra) { $extraTools = $extra.Split(',') | Where-Object { $_ } }
$missing = @()
$found = @{}
foreach ($t in ($defaultTools + $extraTools)) {
  $p = Find-Tool $t
  $found[$t] = $p
  if (-not $brief) { Write-Output "tool.$t=$p" }
  if ($p -eq '-') { $missing += $t }
}
if ($brief) {
  $ml = ($missing -join ' ')
  if (-not $ml) { $ml = 'none' }
  Write-Output "tool.missing=$ml"
}

if ($found['shellcheck'] -and $found['shellcheck'] -ne '-') {
  $v = ''
  foreach ($line in (& $found['shellcheck'] --version 2>$null)) { if ([string]$line -match '^version: (.+)$') { $v = $Matches[1] } }
  if (-not $v) { $v = 'unknown' }
  Write-Output "ver.shellcheck=$v"
}
if ($found['shfmt'] -and $found['shfmt'] -ne '-') {
  Write-Output ('ver.shfmt=' + [string](& $found['shfmt'] --version 2>$null | Select-Object -First 1))
}

# Capability resolution: first available provider wins, else the fallback.
function Has([string]$t) { return ($found.ContainsKey($t) -and $found[$t] -ne '-') }
if (Has 'shellcheck') { Write-Output 'cap.lint_posix_bash=shellcheck' } else { Write-Output 'cap.lint_posix_bash=builtin-heuristics' }
if (Has 'shfmt') {
  Write-Output 'cap.format_posix_bash=shfmt'
  $zshOk = $false
  try {
    $tmpf = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpf, "echo hi`n")
    & $found['shfmt'] -ln zsh $tmpf *> $null
    $zshOk = ($LASTEXITCODE -eq 0)
    Remove-Item -LiteralPath $tmpf -Force
  } catch { $zshOk = $false }
  if ($zshOk) { Write-Output 'cap.format_zsh=shfmt-diff-only' } else { Write-Output 'cap.format_zsh=manual' }
}
else {
  Write-Output 'cap.format_posix_bash=manual'
  Write-Output 'cap.format_zsh=manual'
}
if (Has 'dash') { Write-Output 'cap.syntax_posix=dash' }
elseif (Has 'busybox') { Write-Output 'cap.syntax_posix=busybox' }
elseif (Has 'sh') { Write-Output 'cap.syntax_posix=sh-may-be-bash' }
else { Write-Output 'cap.syntax_posix=none' }
if (Has 'bash') { Write-Output 'cap.syntax_bash=bash' } else { Write-Output 'cap.syntax_bash=none' }
if (Has 'zsh') { Write-Output 'cap.syntax_zsh=zsh' } else { Write-Output 'cap.syntax_zsh=none' }
if (Has 'rg') { Write-Output 'cap.search=rg' } else { Write-Output 'cap.search=select-string' }
if (Has 'jq') { Write-Output 'cap.json=jq' } else { Write-Output 'cap.json=powershell-builtin' }
if (Has 'zip') { Write-Output 'cap.archive=zip' } elseif (Has 'tar') { Write-Output 'cap.archive=tar' } else { Write-Output 'cap.archive=compress-archive' }
if ((Has 'sh') -or (Has 'bash')) { Write-Output 'cap.sandbox=sandbox-run' } else { Write-Output 'cap.sandbox=none' }
if (Has 'docker') { Write-Output 'cap.termux_container=docker' } else { Write-Output 'cap.termux_container=none' }
if (Has 'adb') { Write-Output 'cap.device_transfer=adb' } else { Write-Output 'cap.device_transfer=none' }

# Install hints for missing tools. Package ids are conventional names; verify
# with the package manager before proposing them to the user.
function Get-Hint([string]$tool) {
  $map = @{
    'shellcheck:apt-get' = 'sudo apt-get install -y shellcheck'; 'shellcheck:dnf' = 'sudo dnf install -y ShellCheck'
    'shellcheck:pacman' = 'sudo pacman -S shellcheck'; 'shellcheck:zypper' = 'sudo zypper install ShellCheck'
    'shellcheck:apk' = 'apk add shellcheck'; 'shellcheck:brew' = 'brew install shellcheck'
    'shellcheck:scoop' = 'scoop install shellcheck'; 'shellcheck:choco' = 'choco install shellcheck'
    'shfmt:apt-get' = 'sudo apt-get install -y shfmt'; 'shfmt:dnf' = 'sudo dnf install -y shfmt'
    'shfmt:pacman' = 'sudo pacman -S shfmt'; 'shfmt:apk' = 'apk add shfmt'; 'shfmt:brew' = 'brew install shfmt'
    'shfmt:scoop' = 'scoop install shfmt'; 'shfmt:choco' = 'choco install shfmt'
    'zsh:apt-get' = 'sudo apt-get install -y zsh'; 'zsh:dnf' = 'sudo dnf install -y zsh'
    'zsh:pacman' = 'sudo pacman -S zsh'; 'zsh:zypper' = 'sudo zypper install zsh'
    'zsh:apk' = 'apk add zsh'; 'zsh:brew' = 'brew install zsh'
    'dash:apt-get' = 'sudo apt-get install -y dash'; 'dash:dnf' = 'sudo dnf install -y dash'
    'dash:pacman' = 'sudo pacman -S dash'; 'dash:apk' = 'apk add dash'; 'dash:brew' = 'brew install dash'
    'busybox:apt-get' = 'sudo apt-get install -y busybox-static'; 'busybox:dnf' = 'sudo dnf install -y busybox'
    'busybox:pacman' = 'sudo pacman -S busybox'; 'busybox:apk' = 'apk add busybox'; 'busybox:brew' = 'brew install busybox'
    'jq:apt-get' = 'sudo apt-get install -y jq'; 'jq:dnf' = 'sudo dnf install -y jq'
    'jq:pacman' = 'sudo pacman -S jq'; 'jq:apk' = 'apk add jq'; 'jq:brew' = 'brew install jq'
    'jq:scoop' = 'scoop install jq'; 'jq:choco' = 'choco install jq'
  }
  $key = $tool + ':' + $pkgmgr
  if ($map.ContainsKey($key)) { return $map[$key] }
  if ($pkgmgr -eq 'winget') { return "winget search $tool  # install the matching package id" }
  return ''
}
foreach ($t in $missing) {
  if (@('shellcheck', 'shfmt', 'zsh', 'dash', 'busybox', 'jq') -contains $t) {
    $h = Get-Hint $t
    if ($h) { Write-Output "hint.$t=$h" }
    elseif ($os -eq 'windows' -and ($t -eq 'zsh' -or $t -eq 'dash')) { Write-Output "hint.$t=no native package; use WSL or MSYS2 (pacman -S $t)" }
  }
}
exit 0

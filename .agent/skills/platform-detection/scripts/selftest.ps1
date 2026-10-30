# selftest.ps1 - smoke-test the PowerShell flavors of the .agent tools on this host.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File selftest.ps1 [--keep]
# Builds a throwaway git repository, runs each tool once in a child PowerShell, and
# checks the exit status and one marker in the output. Tools that need a POSIX shell
# (sandbox-run, termux-sim, trace-run) report SKIP when none is installed.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Same output format as selftest.sh.

$ErrorActionPreference = 'Continue'
$keep = $false
foreach ($a in $args) {
  if ($a -eq '--keep') { $keep = $true }
  elseif ($a -eq '-h' -or $a -eq '--help') {
    Write-Output 'Usage: selftest.ps1 [--keep]'
    Write-Output 'Prints PASS, FAIL, or SKIP per tool, then: SELFTEST pass=N fail=N skip=N'
    Write-Output 'Exit: 0 no FAIL, 1 at least one FAIL, 2 usage error.'
    exit 0
  }
  else { [Console]::Error.WriteLine("selftest: unknown option: $a"); exit 2 }
}

$skills = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
$psExe = (Get-Process -Id $PID).Path
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fx = Join-Path $tmp 'fixture'
$null = New-Item -ItemType Directory -Force -Path $fx
$script:pass = 0; $script:fail = 0; $script:skip = 0
$haveGit = [bool](Get-Command git -CommandType Application -ErrorAction SilentlyContinue)
$haveShfmt = [bool](Get-Command shfmt -CommandType Application -ErrorAction SilentlyContinue)

function Write-File([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $fx $name), $text)
}

# Run SCRIPT ARGS in a child PowerShell inside the fixture; returns exit code and text
function Invoke-Tool([string]$rel, [string[]]$toolArgs) {
  $script = Join-Path $skills $rel
  Push-Location $fx
  try {
    $text = (& $psExe -NoProfile -ExecutionPolicy Bypass -File $script @toolArgs 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
    return @{ Code = $LASTEXITCODE; Text = $text }
  }
  finally { Pop-Location }
}

function Test-Tool([string]$name, [int]$want, [string]$marker, [string]$rel, [string[]]$toolArgs) {
  $r = Invoke-Tool $rel $toolArgs
  if ($r.Code -eq $want -and ($marker -eq '' -or $r.Text.Contains($marker))) {
    $script:pass++; Write-Output "PASS $name"
  }
  elseif ($r.Code -eq 3 -and $r.Text -match 'POSIX shell|no suitable shell') {
    $script:skip++; Write-Output "SKIP $name (no POSIX shell on this host)"
  }
  else {
    $script:fail++; Write-Output "FAIL $name"
    Write-Output "     exit=$($r.Code) (wanted $want) marker='$marker'"
    ($r.Text -split "`n" | Select-Object -First 6) | ForEach-Object { Write-Output "     | $_" }
  }
}

# Fixture: a git repository with one clean script, one script with a known finding,
# and an .editorconfig
Write-File '.editorconfig' "root = true`n`n[*.sh]`nindent_style = space`nindent_size = 2`nspace_redirects = true`n"
Write-File 'ok.sh' "#!/bin/sh`n`ngreet() {`n  printf 'hello %s\n' `"`$1`"`n}`n`ngreet `"`${1:-world}`"`n"
Write-File 'bad.sh' "#!/bin/sh`nrm -rf /tmp/selftest-demo`n"
Write-File 'termux.properties' "extra-keys = [[`"ESC`",`"TAB`"]]`n"
if ($haveGit) {
  Push-Location $fx
  & git init -q . 2>$null
  & git add -A 2>$null
  & git -c user.name=selftest -c user.email=selftest@example.invalid commit -q -m fixture 2>$null
  [System.IO.File]::AppendAllText((Join-Path $fx 'ok.sh'), "# change`n")
  Pop-Location
}

Test-Tool 'detect-platform.ps1' 0 'host.os=' 'platform-detection/scripts/detect-platform.ps1' @('--brief')
Test-Tool 'repo-map.ps1' 0 '' 'using-termux-skills/scripts/repo-map.ps1' @()
Test-Tool 'lint-shell.ps1 finds T001' 0 '[T001]' 'termux-scripting/scripts/lint-shell.ps1' @('--no-external')
if ($haveShfmt) { Test-Tool 'format-shell.ps1 check' 0 'SUMMARY' 'termux-scripting/scripts/format-shell.ps1' @() }
else { $script:skip++; Write-Output 'SKIP format-shell.ps1 (shfmt not installed)' }
Test-Tool 'def-index.ps1 record' 0 '' 'code-refactoring/scripts/def-index.ps1' @('--out', '.artifacts/refactor/before.tsv')
Test-Tool 'def-index.ps1 compare' 0 '' 'code-refactoring/scripts/def-index.ps1' @('--compare', '.artifacts/refactor/before.tsv')
if ($haveGit) { Test-Tool 'diff-collect.ps1' 0 'MANIFEST' 'code-review/scripts/diff-collect.ps1' @() }
else { $script:skip++; Write-Output 'SKIP diff-collect.ps1 (git not installed)' }
Test-Tool 'check-termux-config.ps1' 0 'SUMMARY' 'termux-customization/scripts/check-termux-config.ps1' @('termux.properties')
Write-File 'stub.sh' "#!/bin/sh`ntermux-toast `"hello`"`n"
Test-Tool 'sandbox-run.ps1 stubs' 0 'termux-toast' 'termux-scripting/scripts/sandbox-run.ps1' @('--stub-termux', '--', 'stub.sh')
Test-Tool 'trace-run.ps1' 0 'trace-run:' 'systematic-debugging/scripts/trace-run.ps1' @('--', 'ok.sh')
Test-Tool 'termux-sim.ps1 uname' 0 'Android' 'termux-environment/scripts/termux-sim.ps1' @('-c', 'uname -o')

Write-Output "SELFTEST pass=$($script:pass) fail=$($script:fail) skip=$($script:skip)"
if ($keep) { Write-Output "selftest: fixture kept at $tmp" }
else { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
if ($script:fail -eq 0) { exit 0 } else { exit 1 }

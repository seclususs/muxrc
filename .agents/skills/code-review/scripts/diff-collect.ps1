# diff-collect.ps1 - write the complete git diff to disk and verify it against git statistics.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File diff-collect.ps1 [options]
# Read-only for the repository: writes only under the output directory.
# Same contract as diff-collect.sh: key=value lines and a manifest on stdout; the last line is END.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Patch files are written by git itself
# (--output), because redirection in Windows PowerShell 5.1 writes UTF-16.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$usage = @'
Usage: diff-collect.ps1 [options]

Writes the full diff to files so no pager, terminal buffer, or tool output limit can truncate it,
then checks the files against `git diff --numstat`.

Scope (default: working tree vs HEAD, staged + unstaged, plus untracked files):
  --staged             staged changes only (git diff --cached)
  --unstaged           unstaged changes plus untracked files
  --range A..B         commit range (A..B or A...B); untracked files are not included
Options:
  --out DIR            output directory (default: <root>/.artifacts/diff, inside the workspace);
                       a relative path starts at the repository root
  --context N          context lines per hunk (default 3)
  --chunk N            lines per read range printed in the read plan (default 250)
  --no-untracked       skip untracked files
  --include-agent      include .agent and .agents (excluded by default: agent tooling is not project code)
  --max-untracked-kb N untracked files larger than this are listed, not diffed (default 512)
  --root DIR           run in this directory instead of the current one
  -h, --help           show this help

Files written: tracked.diff, untracked.diff, MANIFEST.tsv
Manifest columns: part, status, add, del, first-line, last-line, path (lines refer to the part file).
Exit codes: 0 verified, 1 verification mismatch, 2 usage or not a git repository, 3 git failure.
'@

function Out-Line([string]$s) { [Console]::Out.WriteLine($s) }
function Fail([string]$msg, [int]$code) {
  [Console]::Error.WriteLine("diff-collect: $msg")
  exit $code
}
function Need-Num([string]$name, [string]$v) {
  if ($v -notmatch '^[0-9]+$') { Fail "$name needs a non-negative integer" 2 }
}

$scope = 'all'; $range = ''; $out = ''; $ctx = '3'; $chunk = '250'; $untracked = $true; $agent = $false; $maxkb = '512'; $root = ''
for ($i = 0; $i -lt $args.Count; $i++) {
  $a = [string]$args[$i]
  switch -CaseSensitive ($a) {
    '--staged' { $scope = 'staged' }
    '--unstaged' { $scope = 'unstaged' }
    '--range' { if ($i + 1 -ge $args.Count) { Fail '--range needs a value' 2 }; $scope = 'range'; $i++; $range = [string]$args[$i] }
    '--out' { if ($i + 1 -ge $args.Count) { Fail '--out needs a value' 2 }; $i++; $out = [string]$args[$i] }
    '--context' { if ($i + 1 -ge $args.Count) { Fail '--context needs a value' 2 }; $i++; $ctx = [string]$args[$i] }
    '--chunk' { if ($i + 1 -ge $args.Count) { Fail '--chunk needs a value' 2 }; $i++; $chunk = [string]$args[$i] }
    '--no-untracked' { $untracked = $false }
    '--include-agent' { $agent = $true }
    '--max-untracked-kb' { if ($i + 1 -ge $args.Count) { Fail '--max-untracked-kb needs a value' 2 }; $i++; $maxkb = [string]$args[$i] }
    '--root' { if ($i + 1 -ge $args.Count) { Fail '--root needs a value' 2 }; $i++; $root = [string]$args[$i] }
    '-h' { Out-Line $usage; exit 0 }
    '--help' { Out-Line $usage; exit 0 }
    default { Fail "unknown option: $a" 2 }
  }
}
Need-Num '--context' $ctx
Need-Num '--chunk' $chunk
Need-Num '--max-untracked-kb' $maxkb
if ([int]$chunk -le 0) { Fail '--chunk must be greater than 0' 2 }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git not found on this host (see platform-detection)' 3 }
if ($root -ne '') {
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { Fail 'cannot enter --root directory' 2 }
  Set-Location -LiteralPath $root
}

$env:GIT_PAGER = 'cat'
$env:PAGER = 'cat'

function Invoke-Git([string[]]$gitArgs) {
  $all = @('--no-pager', '-c', 'core.quotepath=off', '-c', 'color.ui=never') + $gitArgs
  $o = @(& git @all)
  $script:gitExit = $LASTEXITCODE
  return , $o
}

$null = Invoke-Git @('rev-parse', '--is-inside-work-tree')
if ($script:gitExit -ne 0) { Fail 'not inside a git work tree' 2 }
$top = [string](Invoke-Git @('rev-parse', '--show-toplevel'))[0]
if ($script:gitExit -ne 0) { Fail 'cannot resolve the repository root' 3 }
Set-Location -LiteralPath $top
[Environment]::CurrentDirectory = $top
if ($out -eq '') { $out = "$top/.artifacts/diff" }
try { $null = New-Item -ItemType Directory -Force -Path $out } catch { Fail "cannot create output directory: $out" 2 }
# Output convention: .artifacts/ at the project root ignores itself in git
if ($out.Replace('\', '/').StartsWith("$top/.artifacts")) {
  $gi = "$top/.artifacts/.gitignore"
  if (-not (Test-Path -LiteralPath $gi)) { [System.IO.File]::WriteAllText($gi, "*`n") }
}

$dopts = @('--no-renames', '--no-ext-diff', '--no-textconv', '--no-color', '--src-prefix=a/', '--dst-prefix=b/')
$pspec = @()
if (-not $agent) { $pspec = @('.', ':(exclude).agent', ':(exclude).agents') }
$sargs = @()
switch ($scope) {
  'all' {
    $null = Invoke-Git @('rev-parse', '--verify', '-q', 'HEAD')
    if ($script:gitExit -ne 0) { Fail 'no commits yet; use --staged or --unstaged' 2 }
    $sargs = @('HEAD')
  }
  'staged' { $sargs = @('--cached') }
  'unstaged' { $sargs = @() }
  'range' { $sargs = @($range) }
}

$trackedPath = Join-Path $out 'tracked.diff'
$untrackedPath = Join-Path $out 'untracked.diff'
$manifestPath = Join-Path $out 'MANIFEST.tsv'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('diff-collect.' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $tmp

function Get-Lines([string]$path) {
  $t = [System.Text.Encoding]::GetEncoding(28591).GetString([System.IO.File]::ReadAllBytes($path))
  if ($t.Length -eq 0) { return , @() }
  $a = $t.Split([char]10)
  if ($a[$a.Length - 1].Length -eq 0) { $a = $a[0..($a.Length - 2)] }
  return , $a
}

function Get-Scan([string]$path) {
  $rows = New-Object System.Collections.ArrayList
  $lines = Get-Lines $path
  $n = 0; $start = 0; $add = 0; $del = 0; $bin = $false; $inh = $false
  $ord = [System.StringComparison]::Ordinal
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = [string]$lines[$i]
    if ($l.StartsWith('diff --git ', $ord)) {
      if ($n -gt 0) { [void]$rows.Add([pscustomobject]@{ Start = $start; End = $i; Add = $add; Del = $del; Bin = $bin }) }
      $n++; $start = $i + 1; $add = 0; $del = 0; $bin = $false; $inh = $false
      continue
    }
    if ($n -eq 0) { continue }
    if ($l.StartsWith('@@ ', $ord)) { $inh = $true; continue }
    if ($l.StartsWith('Binary files ', $ord) -or $l.StartsWith('GIT binary patch', $ord)) { $bin = $true; continue }
    if ($inh -and $l.Length -gt 0) {
      $c = $l[0]
      if ($c -eq '+') { $add++ } elseif ($c -eq '-') { $del++ }
    }
  }
  if ($n -gt 0) { [void]$rows.Add([pscustomobject]@{ Start = $start; End = $lines.Count; Add = $add; Del = $del; Bin = $bin }) }
  return , $rows
}

function Get-RangePlan([int]$n, [int]$c) {
  $s = 1; $k = 0; $parts = @()
  while ($s -le $n) {
    $e = $s + $c - 1; if ($e -gt $n) { $e = $n }
    $parts += "$s-$e"; $s = $e + 1; $k++
    if ($k -ge 100) { $parts += '...'; break }
  }
  return ($parts -join ' ')
}

$verifyErrors = New-Object System.Collections.ArrayList
$rows = New-Object System.Collections.ArrayList
$tFiles = 0; $tAdd = 0; $tDel = 0; $uFiles = 0; $uAdd = 0; $skipped = 0; $bad = 0
$exitCode = 0

try {
  $diffArgs = @('diff') + $dopts + @("-U$ctx", "--output=$trackedPath") + $sargs + @('--') + $pspec
  $null = Invoke-Git $diffArgs
  if ($script:gitExit -ne 0) { Fail 'git diff failed' 3 }
  $numstat = Invoke-Git (@('diff') + $dopts + @('--numstat') + $sargs + @('--') + $pspec)
  if ($script:gitExit -ne 0) { exit 3 }
  $names = Invoke-Git (@('diff') + $dopts + @('--name-status') + $sargs + @('--') + $pspec)
  if ($script:gitExit -ne 0) { exit 3 }

  $ulist = New-Object System.Collections.ArrayList
  $skippedList = New-Object System.Collections.ArrayList
  $ufs = New-Object System.IO.FileStream($untrackedPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
  try {
    if ($untracked -and ($scope -eq 'all' -or $scope -eq 'unstaged')) {
      $others = Invoke-Git @('ls-files', '--others', '--exclude-standard')
      if ($script:gitExit -ne 0) { exit 3 }
      $limit = [int64]$maxkb * 1024
      $one = Join-Path $tmp 'one.diff'
      foreach ($f in $others) {
        $f = [string]$f
        if ($f.Length -eq 0) { continue }
        if (Test-Path -LiteralPath $f -PathType Container) { continue }
        if (-not $agent -and ($f.StartsWith('.agent/') -or $f.StartsWith('.agents/') -or $f.StartsWith('.artifacts/'))) { continue }
        if ($f.StartsWith('"')) { [void]$skippedList.Add($f); continue }
        $size = -1
        try { $size = (Get-Item -LiteralPath $f -Force).Length } catch { }
        if ($size -lt 0 -or $size -gt $limit) { [void]$skippedList.Add($f); continue }
        if (Test-Path -LiteralPath $one) { Remove-Item -LiteralPath $one -Force }
        $null = Invoke-Git (@('diff') + $dopts + @("-U$ctx", '--no-index', "--output=$one", '--', '/dev/null', $f))
        if (Test-Path -LiteralPath $one) {
          $b = [System.IO.File]::ReadAllBytes($one)
          $ufs.Write($b, 0, $b.Length)
        }
        [void]$ulist.Add($f)
      }
    }
  }
  finally { $ufs.Dispose() }

  # tracked rows
  $scanT = Get-Scan $trackedPath
  $nn = $names.Count; $nu = $numstat.Count; $ns = $scanT.Count
  $aligned = $true
  if ($nn -ne $nu -or $nn -ne $ns) {
    $aligned = $false; $bad++
    [void]$verifyErrors.Add("verify_error=tracked entry count differs (name-status=$nn numstat=$nu patch=$ns); the patch file is incomplete or git output changed")
  }
  for ($i = 0; $i -lt $nn; $i++) {
    $nl = [string]$names[$i]; $p = $nl.IndexOf("`t")
    $st = $nl.Substring(0, $p); $nm = $nl.Substring($p + 1)
    $ad = '?'; $dl = '?'
    if ($i -lt $nu) { $np = ([string]$numstat[$i]).Split("`t", 3); $ad = $np[0]; $dl = $np[1] }
    $s1 = '?'; $s2 = '?'
    if ($aligned) { $sc = $scanT[$i]; $s1 = [string]$sc.Start; $s2 = [string]$sc.End }
    if ($ad -eq '-') {
      if ($aligned -and -not $scanT[$i].Bin) { $bad++; [void]$verifyErrors.Add("verify_error=binary file not marked binary in patch: $nm") }
    }
    else {
      if ($ad -match '^[0-9]+$') { $tAdd += [int]$ad; $tDel += [int]$dl }
      if ($aligned -and ([string]$ad -ne [string]$scanT[$i].Add -or [string]$dl -ne [string]$scanT[$i].Del)) {
        $bad++; [void]$verifyErrors.Add("verify_error=count mismatch for $nm (numstat +$ad -$dl, patch +$($scanT[$i].Add) -$($scanT[$i].Del))")
      }
    }
    [void]$rows.Add("tracked`t$st`t$ad`t$dl`t$s1`t$s2`t$nm")
  }
  $tFiles = $nn

  # untracked rows
  $scanU = Get-Scan $untrackedPath
  $un = $ulist.Count
  $alignedU = $true
  if ($un -ne $scanU.Count) {
    $alignedU = $false; $bad++
    [void]$verifyErrors.Add("verify_error=untracked entry count differs (list=$un patch=$($scanU.Count)); the patch file is incomplete")
  }
  for ($i = 0; $i -lt $un; $i++) {
    $nm = [string]$ulist[$i]
    if (-not $alignedU) { [void]$rows.Add("untracked`t?`t?`t?`t?`t?`t$nm"); continue }
    $sc = $scanU[$i]
    if ($sc.Bin) { $a2 = '-'; $d2 = '-' }
    else {
      $cnt = (Get-Lines $nm).Count
      $a2 = [string]$sc.Add; $d2 = [string]$sc.Del; $uAdd += $sc.Add
      if ([int]$a2 -ne $cnt -or [int]$d2 -ne 0) {
        $bad++; [void]$verifyErrors.Add("verify_error=count mismatch for untracked $nm (file lines $cnt, patch +$a2 -$d2)")
      }
    }
    [void]$rows.Add("untracked`t?`t$a2`t$d2`t$($sc.Start)`t$($sc.End)`t$nm")
  }
  $uFiles = $un
  foreach ($f in $skippedList) { $skipped++; [void]$rows.Add("skipped`t?`t-`t-`t-`t-`t$f") }

  $manifestText = ''
  if ($rows.Count -gt 0) { $manifestText = ($rows -join "`n") + "`n" }
  [System.IO.File]::WriteAllText($manifestPath, $manifestText, (New-Object System.Text.UTF8Encoding($false)))

  $trackedLines = (Get-Lines $trackedPath).Count
  $untrackedLines = (Get-Lines $untrackedPath).Count
  $trackedBytes = (Get-Item -LiteralPath $trackedPath).Length
  $untrackedBytes = (Get-Item -LiteralPath $untrackedPath).Length

  Out-Line "diff-collect scope=$scope out=$out"
  Out-Line "part=tracked.diff lines=$trackedLines bytes=$trackedBytes"
  Out-Line "part=untracked.diff lines=$untrackedLines bytes=$untrackedBytes"
  Out-Line "files=$($tFiles + $uFiles) tracked=$tFiles untracked=$uFiles skipped=$skipped additions=$($tAdd + $uAdd) deletions=$tDel"
  if ($bad -eq 0) { Out-Line 'verify=ok' }
  else {
    Out-Line 'verify=mismatch'
    foreach ($e in $verifyErrors) { Out-Line $e }
    $exitCode = 1
  }
  Out-Line "chunk=$chunk"
  if ($trackedLines -gt 0) { Out-Line ('ranges tracked.diff: ' + (Get-RangePlan $trackedLines ([int]$chunk))) }
  if ($untrackedLines -gt 0) { Out-Line ('ranges untracked.diff: ' + (Get-RangePlan $untrackedLines ([int]$chunk))) }
  if ($skipped -gt 0) { Out-Line 'skipped files (not diffed; read them directly in ranges): see MANIFEST.tsv rows with part=skipped' }
  Out-Line (("manifest=" + $manifestPath).Replace('\', '/'))
  if ($rows.Count -gt 0) {
    Out-Line 'rows (part status add del first last path):'
    $shown = 0
    foreach ($r in $rows) { if ($shown -ge 60) { break }; Out-Line ($r.Replace("`t", ' ')); $shown++ }
    if ($rows.Count -gt 60) { Out-Line "... $($rows.Count - 60) more rows in MANIFEST.tsv" }
  }
  Out-Line 'END'
}
finally {
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
exit $exitCode

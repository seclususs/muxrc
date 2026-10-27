# def-index.ps1 - index shell definitions and compare two indexes (static, nothing is executed).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File def-index.ps1 [options] [PATH ...]
# Kinds: func, alias, var (top-level), hook (add-zsh-hook), widget (zle -N), source.
# Same contract as def-index.sh. Compatible with Windows PowerShell 5.1 and PowerShell 7+.

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$usage = @'
Usage: def-index.ps1 [options] [PATH ...]

Index mode (default): prints "kind<TAB>name<TAB>file:line" lines, sorted. Save a baseline with --out:
  def-index.ps1 --out .termux-agent/refactor/before.tsv
Compare mode: indexes the current files and compares them with a saved baseline:
  def-index.ps1 --compare .termux-agent/refactor/before.tsv [--rename OLD=NEW ...]
Reports: removed, added, moved (same name, different file set), renamed (declared with --rename),
duplicate (func or alias defined more often than in the baseline). Exit 1 on removed or duplicate.

Options:
  --out FILE       write the index to FILE (UTF-8, LF) instead of stdout
  --compare FILE   baseline index to compare against
  --rename OLD=NEW expected rename of a func, alias, or var (repeatable)
  --root DIR       run in this directory instead of the current one
  -h, --help       show this help

PATH arguments (files or directories) limit the scan. Without PATH, the scan covers git-tracked and
untracked, non-ignored files (or every file under the directory outside git), excluding .agent, .agents, and .termux-agent.
Detection is line-based: it finds definitions at the usual positions and does not evaluate code.
Dynamic definitions (eval, generated names) are not seen; verify them with behavior-snapshot.
Variables count only at column 0 (top level); definitions inside functions are not indexed.
Exit codes: 0 ok, 1 removed or duplicate found, 2 usage error.
'@

function Out-Line([string]$s) { [Console]::Out.WriteLine($s) }
function Fail([string]$msg, [int]$code) {
  [Console]::Error.WriteLine("def-index: $msg")
  exit $code
}

$compare = ''; $outfile = ''; $root = ''; $renames = @{}; $paths = New-Object System.Collections.ArrayList
$dashdash = $false
for ($i = 0; $i -lt $args.Count; $i++) {
  $a = [string]$args[$i]
  if ($dashdash) { [void]$paths.Add($a); continue }
  switch -CaseSensitive ($a) {
    '--out' { if ($i + 1 -ge $args.Count) { Fail '--out needs a value' 2 }; $i++; $outfile = [string]$args[$i] }
    '--compare' { if ($i + 1 -ge $args.Count) { Fail '--compare needs a value' 2 }; $i++; $compare = [string]$args[$i] }
    '--rename' {
      if ($i + 1 -ge $args.Count) { Fail '--rename needs OLD=NEW' 2 }
      $i++; $r = [string]$args[$i]; $eq = $r.IndexOf('=')
      if ($eq -lt 1 -or $eq -ge $r.Length - 1) { Fail '--rename needs OLD=NEW' 2 }
      $renames[$r.Substring(0, $eq)] = $r.Substring($eq + 1)
    }
    '--root' { if ($i + 1 -ge $args.Count) { Fail '--root needs a value' 2 }; $i++; $root = [string]$args[$i] }
    '-h' { Out-Line $usage; exit 0 }
    '--help' { Out-Line $usage; exit 0 }
    '--' { $dashdash = $true }
    default {
      if ($a.StartsWith('-') -and $a.Length -gt 1) { Fail "unknown option: $a" 2 }
      [void]$paths.Add($a)
    }
  }
}

if ($root -ne '') {
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { Fail 'cannot enter --root directory' 2 }
  Set-Location -LiteralPath $root
}
[Environment]::CurrentDirectory = (Get-Location).Path
if ($compare -ne '' -and -not (Test-Path -LiteralPath $compare -PathType Leaf)) { Fail "baseline not found: $compare" 2 }

$utf8 = New-Object System.Text.UTF8Encoding($false)
$ord = [System.StringComparer]::Ordinal
$skipDirs = @('.git', '.agent', '.agents', '.termux-agent', 'node_modules')

function Get-AllFiles([string]$dir) {
  $acc = New-Object System.Collections.ArrayList
  $stack = New-Object System.Collections.Stack
  $stack.Push($dir)
  while ($stack.Count -gt 0) {
    $d = [string]$stack.Pop()
    foreach ($e in (Get-ChildItem -LiteralPath $d -Force)) {
      if ($e.PSIsContainer) { if ($skipDirs -notcontains $e.Name) { $stack.Push($e.FullName) } }
      else { [void]$acc.Add($e.FullName) }
    }
  }
  return , $acc
}

function Get-Candidates {
  $list = New-Object System.Collections.ArrayList
  if ($paths.Count -gt 0) {
    foreach ($p in $paths) {
      if (Test-Path -LiteralPath $p -PathType Container) {
        $base = (Resolve-Path -LiteralPath $p).Path
        foreach ($f in (Get-AllFiles $base)) { [void]$list.Add($f) }
      }
      elseif (Test-Path -LiteralPath $p -PathType Leaf) { [void]$list.Add($p) }
      else { [Console]::Error.WriteLine("def-index: not found: $p") }
    }
    return , $list
  }
  $inGit = $false
  if (Get-Command git -ErrorAction SilentlyContinue) {
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $null = & git rev-parse --is-inside-work-tree 2>$null
      if ($LASTEXITCODE -eq 0) { $inGit = $true }
    }
    catch { $inGit = $false }
    $ErrorActionPreference = $prevPref
  }
  if ($inGit) {
    foreach ($l in @(& git -c core.quotepath=off ls-files -co --exclude-standard)) {
      $l = [string]$l
      if ($l -cmatch '^\.agents?/' -or $l -cmatch '^\.termux-agent/') { continue }
      [void]$list.Add($l)
    }
  }
  else {
    $here = (Get-Location).Path
    foreach ($f in (Get-AllFiles $here)) {
      $rel = $f.Substring($here.Length).TrimStart('\', '/').Replace('\', '/')
      [void]$list.Add($rel)
    }
  }
  return , $list
}

function Test-ShellName([string]$path) {
  $n = [System.IO.Path]::GetFileName($path)
  if ($n -cmatch '\.(sh|bash|zsh|ksh)$') { return 0 }
  if (@('.zshrc', '.zshenv', '.zprofile', '.zlogin', '.zlogout', '.bashrc', '.bash_profile', '.bash_login', '.profile') -ccontains $n) { return 0 }
  if ($n.Contains('.')) { return 1 }
  return 2
}

function Test-Shebang([string]$first) {
  if (-not $first.StartsWith('#!')) { return $false }
  $words = @(($first.Substring(2).Trim(" `t")) -split '[ \t]+' | Where-Object { $_ -ne '' })
  if ($words.Count -eq 0) { return $false }
  $interp = ($words[0] -split '/')[-1]
  if ($interp -ceq 'env') {
    $k = 1
    while ($k -lt $words.Count -and $words[$k].StartsWith('-')) { $k++ }
    if ($k -ge $words.Count) { return $false }
    $interp = ($words[$k] -split '/')[-1]
  }
  return (@('sh', 'bash', 'zsh', 'dash', 'ksh', 'ash', 'mksh', 'busybox') -ccontains $interp)
}

$rows = New-Object System.Collections.ArrayList
function Add-Def([string]$kind, [string]$name, [string]$file, [int]$ln) {
  if ($name -ne '') { [void]$rows.Add("$kind`t$name`t${file}:$ln") }
}
function Unquote([string]$s) {
  $s = [regex]::Replace($s, '^["'']', '', 'None')
  return [regex]::Replace($s, '["'']$', '', 'None')
}
function Rx([string]$s, [string]$pat) { return [regex]::IsMatch($s, $pat) }
function Rr([string]$s, [string]$pat, [string]$rep) { return [regex]::Replace($s, $pat, $rep) }

function Read-DefLine([string]$line, [string]$f, [int]$ln) {
  if (Rx $line '^[ \t]*#') { return }
  if (Rx $line '^[ \t]*function[ \t]+[^ \t(){;]') {
    $s = Rr $line '^[ \t]*function[ \t]+' ''
    $m = [regex]::Match($s, '^[^ \t(){;]+')
    Add-Def 'func' $m.Value $f $ln; return
  }
  $m = [regex]::Match($line, '^[ \t]*[A-Za-z_][A-Za-z0-9_.:+@-]*[ \t]*\(\)')
  if ($m.Success) {
    $s = Rr $m.Value '^[ \t]*' ''
    $s = Rr $s '[ \t]*\(\)$' ''
    Add-Def 'func' $s $f $ln; return
  }
  if (Rx $line '^[ \t]*alias[ \t]+') {
    $s = Rr $line '^[ \t]*alias[ \t]+' ''
    while (Rx $s '^-[A-Za-z]+[ \t]+') { $s = Rr $s '^-[A-Za-z]+[ \t]+' '' }
    if ($s.Contains('=')) {
      $name = Rr $s '=.*$' ''
      $name = Unquote $name
      if (-not (Rx $name '[ \t]')) { Add-Def 'alias' $name $f $ln }
    }
    return
  }
  if (Rx $line '^[ \t]*add-zsh-hook[ \t]+') {
    $s = Rr $line '^[ \t]*add-zsh-hook[ \t]+' ''
    if (Rx $s '^-[A-Za-z]*[dD]') { return }
    while (Rx $s '^-[A-Za-z]+[ \t]+') { $s = Rr $s '^-[A-Za-z]+[ \t]+' '' }
    $w = [regex]::Split($s, '[ \t]+')
    if ($w.Length -ge 2) { $fn = Rr $w[1] '[;&|].*$' ''; Add-Def 'hook' ($w[0] + ':' + $fn) $f $ln }
    return
  }
  if (Rx $line '^[ \t]*zle[ \t]+-N[ \t]+') {
    $s = Rr $line '^[ \t]*zle[ \t]+-N[ \t]+' ''
    $w = [regex]::Split($s, '[ \t]+')
    Add-Def 'widget' (Unquote $w[0]) $f $ln; return
  }
  if (Rx $line '^(export|readonly|typeset|declare)[ \t]+') {
    $s = Rr $line '^(export|readonly|typeset|declare)[ \t]+' ''
    while (Rx $s '^-[A-Za-z]+[ \t]+') { $s = Rr $s '^-[A-Za-z]+[ \t]+' '' }
    $m = [regex]::Match($s, '^[A-Za-z_][A-Za-z0-9_]*')
    if ($m.Success) { Add-Def 'var' $m.Value $f $ln }
    return
  }
  $m = [regex]::Match($line, '^[A-Za-z_][A-Za-z0-9_]*[+]?=')
  if ($m.Success) {
    $name = $m.Value.Substring(0, $m.Length - 1)
    $name = Rr $name '[+]$' ''
    Add-Def 'var' $name $f $ln; return
  }
  $m = [regex]::Match($line, '(^|[;&|({]|then|do|else)[ \t]*(source|\.)[ \t]+[^ \t]+')
  if ($m.Success) {
    $w = [regex]::Split($m.Value, '[ \t]+')
    $fn = Rr $w[$w.Length - 1] '[;&|)}]+$' ''
    Add-Def 'source' $fn $f $ln
  }
}

function Build-Index {
  $list = Get-Candidates
  $uniq = New-Object System.Collections.Generic.HashSet[string]
  foreach ($x in $list) { [void]$uniq.Add([string]$x) }
  $cands = [string[]]@($uniq)
  [Array]::Sort($cands, $ord)
  foreach ($f in $cands) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
    $kind = Test-ShellName $f
    if ($kind -eq 1) { continue }
    if ($kind -eq 2) {
      $first = ''
      try {
        $sr = New-Object System.IO.StreamReader($f, $utf8)
        try { $first = [string]$sr.ReadLine() } finally { $sr.Dispose() }
      } catch { $first = '' }
      if (-not (Test-Shebang $first)) { continue }
    }
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $f).Path, $utf8)
    $lines = $text.Split([char]10)
    $n = $lines.Length
    if ($n -gt 0 -and $lines[$n - 1].Length -eq 0) { $n-- }
    for ($i = 0; $i -lt $n; $i++) { Read-DefLine ([string]$lines[$i]) $f ($i + 1) }
  }
  $arr = $rows.ToArray()
  [Array]::Sort($arr, $ord)
  return , $arr
}

$current = Build-Index
if ($compare -eq '') {
  if ($outfile -ne '') {
    $body = ''
    if ($current.Length -gt 0) { $body = (($current | ForEach-Object { [string]$_ }) -join "`n") + "`n" }
    [System.IO.File]::WriteAllText($outfile, $body, $utf8)
    Out-Line "def-index: wrote $($current.Length) entries to $outfile"
    exit 0
  }
  foreach ($l in $current) { Out-Line ([string]$l) }
  exit 0
}

# compare mode
$script:seenf = @{}; $script:fl = @{}; $script:nf = @{}; $script:cnt = @{}; $script:first = @{}; $script:locs = @{}
$script:total = @{ b = 0; c = 0 }
$bset = @{}; $cset = @{}
function Add-Rec([hashtable]$arr, [string]$tag, [string]$k, [string]$f, [string]$loc) {
  $sk = "$tag|$k|$f"
  if (-not $script:seenf.ContainsKey($sk)) {
    $script:seenf[$sk] = $true
    $tk = "$tag|$k"
    if ($script:fl.ContainsKey($tk)) { $script:fl[$tk] = $script:fl[$tk] + ',' + $f } else { $script:fl[$tk] = $f }
    if ($script:nf.ContainsKey($tk)) { $script:nf[$tk]++ } else { $script:nf[$tk] = 1 }
  }
  $tk = "$tag|$k"
  if ($script:cnt.ContainsKey($tk)) { $script:cnt[$tk]++ } else { $script:cnt[$tk] = 1 }
  if (-not $script:first.ContainsKey($tk)) { $script:first[$tk] = $loc }
  if ($script:locs.ContainsKey($tk)) { $script:locs[$tk] = $script:locs[$tk] + ',' + $loc } else { $script:locs[$tk] = $loc }
  $arr[$k] = $true
  $script:total[$tag]++
}
function Read-Idx([string[]]$lines, [string]$tag, [hashtable]$arr) {
  foreach ($line in $lines) {
    if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
    $a = $line.Split("`t")
    if ($a.Length -lt 3) { continue }
    $k = $a[0] + "`t" + $a[1]
    $f = [regex]::Replace($a[2], ':[0-9]+$', '')
    Add-Rec $arr $tag $k $f $a[2]
  }
}
function Test-SameFiles([string]$k) {
  if ($script:nf["b|$k"] -ne $script:nf["c|$k"]) { return $false }
  foreach ($f in $script:fl["c|$k"].Split(',')) { if (-not $script:seenf.ContainsKey("b|$k|$f")) { return $false } }
  return $true
}

$baseLines = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $compare).Path, $utf8).Split([char]10)
Read-Idx ($baseLines | ForEach-Object { $_.TrimEnd([char]13) }) 'b' $bset
Read-Idx ([string[]]$current) 'c' $cset

$report = New-Object System.Collections.ArrayList
$nrem = 0; $nadd = 0; $nmov = 0; $nren = 0; $ndup = 0; $done = @{}
foreach ($k in $bset.Keys) {
  $p = $k.Split("`t"); $kind = $p[0]; $name = $p[1]
  if ($renames.ContainsKey($name) -and ($kind -ceq 'func' -or $kind -ceq 'alias' -or $kind -ceq 'var')) {
    $nk = $kind + "`t" + $renames[$name]
    if ($cset.ContainsKey($nk) -and -not $bset.ContainsKey($nk)) {
      [void]$report.Add("renamed $kind $name -> $($renames[$name]) ($($script:first["c|$nk"]))"); $nren++; $done[$nk] = $true; continue
    }
  }
  if (-not $cset.ContainsKey($k)) { [void]$report.Add("removed $kind $name ($($script:first["b|$k"]))"); $nrem++; continue }
  if (-not (Test-SameFiles $k)) { [void]$report.Add("moved $kind $name ($($script:fl["b|$k"]) -> $($script:fl["c|$k"]))"); $nmov++ }
}
foreach ($k in $cset.Keys) {
  $p = $k.Split("`t"); $kind = $p[0]; $name = $p[1]
  if (-not $bset.ContainsKey($k) -and -not $done.ContainsKey($k)) { [void]$report.Add("added $kind $name ($($script:first["c|$k"]))"); $nadd++ }
  $cc = $script:cnt["c|$k"]; $bc = 0
  if ($script:cnt.ContainsKey("b|$k")) { $bc = $script:cnt["b|$k"] }
  if (($kind -ceq 'func' -or $kind -ceq 'alias') -and $cc -gt 1 -and $cc -gt $bc) { [void]$report.Add("duplicate $kind $name ($($script:locs["c|$k"]))"); $ndup++ }
}
$arr = $report.ToArray()
[Array]::Sort($arr, $ord)
foreach ($l in $arr) { Out-Line ([string]$l) }
$summary = "SUMMARY removed=$nrem added=$nadd moved=$nmov renamed=$nren duplicate=$ndup base=$($script:total['b']) current=$($script:total['c'])"
Out-Line $summary
if ($nrem -eq 0 -and $ndup -eq 0) { exit 0 }
exit 1

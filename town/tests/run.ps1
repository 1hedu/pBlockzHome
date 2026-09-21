<#
.SYNOPSIS
  Runs the test suite. All of it, or whatever matches -Only.

.DESCRIPTION
  There are 83 test files in this folder and until now every one of them was launched by
  hand, which meant the set that actually ran was whatever anybody remembered. That is not a
  small tax: raising HURT_KNOCK silently broke hitbox_test, and it was only caught because
  that one happened to get run for an unrelated reason.

  What this does NOT do is decide whether a test passed by reading tea leaves. Every test
  here ends with either "N passed, M failed" or "N right, M wrong"; a run that prints neither
  is reported as NO RESULT and counts as a failure, because a test whose output cannot be
  read is a test nobody is reading.

  Concurrency is real but bounded by ports. The networked tests each listen on a fixed port
  and four of them share 8892, so two of those running at once is one test joining the
  other's town and both of them lying. Tests are scheduled so no two sharing a port ever run
  together; play-solo tests have no port and are free.

.PARAMETER Only
  Regex against the test's name. -Only 'knock|jump' runs four of them.

.PARAMETER Jobs
  How many at once. Default 3. The networked ones start six to eight processes each, so this
  is about RAM, not cores.

.PARAMETER Timeout
  Seconds before a test is killed and called a failure. Default 300; the loaded net tests
  need ~200 of it.

.PARAMETER List
  Print what would run and stop.

.EXAMPLE
  .\tests\run.ps1 -Only 'knock|hitbox|jump'      # before committing a combat change
  .\tests\run.ps1                                # the lot
#>
param(
    [string]$Only = "",
    [int]$Jobs = 3,
    [int]$Timeout = 300,
    [switch]$List
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$demo = Split-Path -Parent $here
$logs = Join-Path $here "logs\run"
New-Item -ItemType Directory -Force -Path $logs | Out-Null

# The staged catalogue, which several tests need something to hold. Built if absent.
$staged = Join-Path (Resolve-Path (Join-Path $demo "..\..\..")) ".preview"
if (-not (Test-Path (Join-Path $staged "manifest.json"))) {
    Write-Host "staging the catalogue (first run)..."
    & node (Join-Path (Resolve-Path (Join-Path $demo "..\..\..")) "scripts\stage-preview.js") all $staged | Out-Null
}

$godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
if (-not $godot) {
    foreach ($c in @("C:\tools\godot\Godot_v4.3-stable_win64.exe",
                     "C:\Program Files\Godot\Godot_v4.3-stable_win64.exe")) {
        if (Test-Path $c) { $godot = $c; break }
    }
}
if (-not $godot) { Write-Error "no Godot on PATH and none where I looked"; exit 2 }

# Which port each test pins itself to, so two that share one never run together.
function Get-Port($file) {
    $m = Select-String -Path $file -Pattern 'PORT\s*:?=\s*(\d{4,5})' | Select-Object -First 1
    if ($m) { return [int]$m.Matches[0].Groups[1].Value }
    return 0
}

# How a test says it wants to be run: its own usage line.
#
# Every file in here opens with one -- "#   godot --headless --path . -s res://tests/x.gd -- <dir>"
# -- and four of them were being launched without the argument it asks for, which is not a
# failure so much as never starting: spoon_test, grip_test and offhand_test sat there until
# the timeout with an empty log. So the line is read rather than assumed.
#
# <...dir> placeholders are filled in: anything mentioning shots gets a fresh folder under
# the logs, and everything else gets the staged catalogue, which is what those tests want --
# they need items to put in a hand. A usage line with no --headless wants a window.
function Get-Usage($file) {
    $m = Select-String -Path $file -Pattern '^#\s+godot\s+(.+)$' | Select-Object -First 1
    if (-not $m) { return @{ Headless = $true; Args = @() } }
    $line = $m.Matches[0].Groups[1].Value
    $headless = $line -match '--headless'
    $extra = @()
    if ($line -match '--\s+(.+)$') {
        # Matched as whole <...> groups rather than split on spaces: the placeholders have
        # spaces IN them -- "<staged dir>" -- so splitting gave "<staged" and "dir>" and
        # neither looked like a placeholder. grip_test and offhand_test were launched with no
        # argument at all and sat there to the timeout.
        foreach ($m2 in [regex]::Matches($Matches[1], '<[^>]+>')) {
            $tok = $m2.Value
            if ($tok -match 'shot') {
                $d = Join-Path $logs ("shots-" + [IO.Path]::GetFileNameWithoutExtension($file))
                New-Item -ItemType Directory -Force -Path $d | Out-Null
                $extra += $d
            } else {
                $extra += $staged
            }
        }
    }
    return @{ Headless = $headless; Args = $extra }
}

$tests = Get-ChildItem (Join-Path $here "*_test.gd") | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{
        Name = $_.BaseName
        Path = $_.FullName
        Port = (Get-Port $_.FullName)
        Usage = (Get-Usage $_.FullName)
    }
}
if ($Only -ne "") { $tests = $tests | Where-Object { $_.Name -match $Only } }
if ($tests.Count -eq 0) { Write-Error "nothing matches '$Only'"; exit 2 }

if ($List) {
    $tests | ForEach-Object {
        $how = if ($_.Port) { "port $($_.Port)" } else { "play solo" }
        if (-not $_.Usage.Headless) { $how += ", NEEDS A WINDOW" }
        if ($_.Usage.Args.Count) { $how += ", $($_.Usage.Args.Count) arg(s)" }
        "{0,-28} {1}" -f $_.Name, $how
    }
    exit 0
}

"running $($tests.Count) test(s), $Jobs at a time, logs in tests\logs\run"
""

# Windowed last, and one at a time.
#
# A test that needs a window needs the FOCUS -- an unfocused window swallows every click and
# key, and the whole suite would read as dead buttons. Two of them at once is the same
# problem wearing a hat, so they queue behind everything else and run alone.
$windowed = @($tests | Where-Object { -not $_.Usage.Headless })
$tests = @($tests | Where-Object { $_.Usage.Headless }) + $windowed
if ($windowed.Count -gt 0) {
    "  ($($windowed.Count) of these need a window and will run last, one at a time)"
}

$running = @()      # @{ Test; Proc; Log; Started }
$done = @()
$queue = [System.Collections.ArrayList]@($tests)

function Read-Result($logPath) {
    if (-not (Test-Path $logPath)) { return $null }
    $text = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
    if (-not $text) { return $null }
    # Both shapes the suite actually prints, last one wins.
    $m = [regex]::Matches($text, '(\d+)\s+passed,\s+(\d+)\s+failed')
    if ($m.Count -gt 0) {
        $last = $m[$m.Count - 1]
        return @{ Pass = [int]$last.Groups[1].Value; Fail = [int]$last.Groups[2].Value }
    }
    $m = [regex]::Matches($text, '(\d+)\s+right,\s+(\d+)\s+wrong')
    if ($m.Count -gt 0) {
        $last = $m[$m.Count - 1]
        return @{ Pass = [int]$last.Groups[1].Value; Fail = [int]$last.Groups[2].Value }
    }
    return $null
}

function Start-One($t) {
    $log = Join-Path $logs ($t.Name + ".log")
    if (Test-Path $log) { Remove-Item $log -Force }
    $a = @()
    if ($t.Usage.Headless) { $a += "--headless" }
    $a += @("--path", $demo, "-s", "res://tests/$($t.Name).gd")
    if ($t.Usage.Args.Count) { $a += "--"; $a += $t.Usage.Args }
    $style = if ($t.Usage.Headless) { "Hidden" } else { "Normal" }
    $p = Start-Process -FilePath $godot -PassThru -WindowStyle $style `
        -ArgumentList $a `
        -RedirectStandardOutput $log -RedirectStandardError ($log + ".err")
    return [pscustomobject]@{ Test = $t; Proc = $p; Log = $log; Started = Get-Date }
}

while ($queue.Count -gt 0 -or $running.Count -gt 0) {
    # Start whatever can start: room for another, and nobody running on its port.
    while ($running.Count -lt $Jobs -and $queue.Count -gt 0) {
        # One at a time once the windowed ones start, and never beside anything else.
        $nextIsWindowed = -not $queue[0].Usage.Headless
        if ($nextIsWindowed -and $running.Count -gt 0) { break }
        $busy = @($running | ForEach-Object { $_.Test.Port } | Where-Object { $_ -ne 0 })
        $next = $null
        foreach ($t in $queue) {
            if ($t.Port -eq 0 -or $busy -notcontains $t.Port) { $next = $t; break }
        }
        if (-not $next) { break }      # everything left is blocked on a port in use
        $queue.Remove($next)
        $running += (Start-One $next)
        "  start  $($next.Name)"
    }

    Start-Sleep -Milliseconds 700

    $still = @()
    foreach ($r in $running) {
        $age = ((Get-Date) - $r.Started).TotalSeconds
        if ($r.Proc.HasExited) {
            $res = Read-Result $r.Log
            $done += [pscustomobject]@{
                Name = $r.Test.Name
                Pass = $(if ($res) { $res.Pass } else { 0 })
                Fail = $(if ($res) { $res.Fail } else { 0 })
                State = $(if (-not $res) { "NO RESULT" } elseif ($res.Fail -gt 0) { "FAILED" } else { "ok" })
                Secs = [math]::Round($age)
            }
            $d = $done[$done.Count - 1]
            "  {0,-6} {1,-28} {2}" -f $d.State, $d.Name, "$($d.Pass) passed, $($d.Fail) failed  [$($d.Secs)s]"
        }
        elseif ($age -gt $Timeout) {
            try { $r.Proc.Kill() } catch {}
            $done += [pscustomobject]@{ Name = $r.Test.Name; Pass = 0; Fail = 0; State = "TIMEOUT"; Secs = [math]::Round($age) }
            "  TIMEOUT $($r.Test.Name) after $([math]::Round($age))s"
        }
        else { $still += $r }
    }
    $running = @($still)
}

""
"---- summary ----"
$bad = @($done | Where-Object { $_.State -ne "ok" })
$done | Sort-Object Name | ForEach-Object {
    "{0,-9} {1,-28} {2} passed, {3} failed  [{4}s]" -f $_.State, $_.Name, $_.Pass, $_.Fail, $_.Secs
}
""
$totalPass = ($done | Measure-Object -Property Pass -Sum).Sum
$totalFail = ($done | Measure-Object -Property Fail -Sum).Sum
"$($done.Count) test file(s): $totalPass checks passed, $totalFail failed, $($bad.Count) file(s) not ok"
$summary = Join-Path $logs "summary.txt"
$done | Sort-Object Name | ForEach-Object { "{0,-9} {1,-28} {2} passed, {3} failed" -f $_.State, $_.Name, $_.Pass, $_.Fail } | Set-Content -Encoding utf8 $summary
"written to tests\logs\run\summary.txt"
if ($bad.Count -gt 0) { exit 1 }
exit 0

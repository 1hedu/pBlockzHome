# Start the town and a few dummies. Join it yourself with:
#   & "C:\tools\godot\Godot_v4.3-stable_win64.exe" "--path" "." "-s" "res://Join.gd"
$godot = "C:\tools\godot\Godot_v4.3-stable_win64_console.exe"
$here  = Split-Path -Parent $PSScriptRoot
# Everything each process says, into tests/logs/, because the window it says it in is
# minimised and gone the moment it is closed. Five rounds of "nothing is fixed" were spent
# without anybody having read the SERVER's console once -- the fight, the trampolines, the
# hearts' flag and every script error live in that window and nowhere else.
$logs = Join-Path $here "tests\logs"
New-Item -ItemType Directory -Force -Path $logs | Out-Null
Get-ChildItem -Path $logs -Filter *.log -ErrorAction SilentlyContinue | Remove-Item -Force

# The shop's unpublished work, painted to disk so the town can wear it.
#
# A catalogue item that has never been published is simply not in the world, and one whose
# model CHANGED since it was published is in the world at its old shape -- which looks
# exactly like the change never having been made. The 3x Roma and the gold shoes' sole are
# both that, and both were reported as missing.
#
# Cheap, and run every time on purpose: it is how an edit to catalogue.js reaches the next
# run without a publish. serve_bots reads what this writes.
$repo = Resolve-Path (Join-Path $here "..\..\..")
Write-Host "staging the catalogue off disk..."
& node (Join-Path $repo "scripts\stage-preview.js") all (Join-Path $repo ".preview") | Select-Object -Last 1

Start-Process -FilePath $godot -ArgumentList @("--headless","--path","`"$here`"","-s","res://tests/serve_bots.gd") -WindowStyle Minimized -RedirectStandardOutput (Join-Path $logs "server.log") -RedirectStandardError (Join-Path $logs "server.err.log")
Start-Sleep -Seconds 6
# The name is QUOTED, and it has to be. Start-Process joins -ArgumentList with spaces and
# quotes nothing, so "--name=Spoonie" arrived as two arguments and the bot called itself
# "Crude" -- which is not a weapon serve_bots.gd knows, so it was handed nothing to swing.
# Seven of the ten names there used to be had a space in them, so seven dummies stood there
# empty-handed and only the big spoon ever struck anybody.
#
# Three, not ten: eleven Godot processes plus the player's own window ran the machine out of
# memory, and the player's clicks and equips stopped reaching the server. One to chase, one
# long blade, one burn.
foreach ($n in @("Runner","BFS 9000","HEX Torch")) {
  $safe = $n -replace '[^A-Za-z0-9]', ''
  Start-Process -FilePath $godot -ArgumentList @("--headless","--path","`"$here`"","-s","res://tests/bot.gd","--","`"--name=$n`"") -WindowStyle Minimized -RedirectStandardOutput (Join-Path $logs "bot-$safe.log") -RedirectStandardError (Join-Path $logs "bot-$safe.err.log")
  Start-Sleep -Milliseconds 700
}
Write-Host ""
Write-Host "Every console is in tests\logs\ -- server.log first when anything is wrong."
Write-Host ""
Write-Host "Town on UDP 8800 with 3 bots. Join it and go and hit them:"
Write-Host '  & "C:\tools\godot\Godot_v4.3-stable_win64.exe" "--path" "." "-s" "res://Join.gd"'
Write-Host ""
Write-Host "PvP must already be ON on chain before this runs: the Funmaster reads the flag"
Write-Host "once at startup and hands it to every bot as it joins, so turning it on after"
Write-Host "they are in leaves them peaceful and nothing you swing will land."

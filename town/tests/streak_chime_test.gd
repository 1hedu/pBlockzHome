# The kill-streak chime, sampled every frame off the two client voices: the lead climbs
# C5 E5 G5 C6 E6 G6 C7 on the 2A03 25% pulse, the echo follows an octave down on the 12.5% pulse,
# both fall silent, the banner plays no menu click, and the key rises with the streak.
#
#   godot --headless --path . -s res://tests/streak_chime_test.gd
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the streak chime")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	_run()

func _said(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

func _run() -> void:
	# 14 s: the place's waveforms have arrived and the town's scripts are up by then.
	await create_timer(14.0).timeout
	world.run_client_chunk("sample", """
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local rs = game:GetService("ReplicatedStorage")
local NesEngine = require(rs.NesEngine)
print("READY " .. tostring(NesEngine.ready()))
local clicks = 0
SoundService.ChildAdded:Connect(function(s) if s.Name == "menu" then clicks += 1 end end)
local lead, echo = {}, {}
local function note(list, s)
	if not s then return end
	local speed = s.Playing and s.Volume > 0.001 and math.floor(s.PlaybackSpeed * 1000 + 0.5) or 0
	if list[#list] ~= speed then table.insert(list, speed) end
end
local started = os.clock()
local conn
conn = RunService.Heartbeat:Connect(function()
	note(lead, SoundService:FindFirstChild("Nes_streakLead"))
	note(echo, SoundService:FindFirstChild("Nes_streakEcho"))
	if os.clock() - started > 12 then
		conn:Disconnect()
		local l = SoundService:FindFirstChild("Nes_streakLead")
		local e = SoundService:FindFirstChild("Nes_streakEcho")
		print("LEAD " .. table.concat(lead, ","))
		print("ECHO " .. table.concat(echo, ","))
		print("VOICES " .. tostring(l and l.SoundId ~= "") .. "|" .. tostring(e and e.SoundId ~= ""))
		print("CLICKS " .. clicks)
	end
end)
""")
	await create_timer(0.3).timeout
	# 1.6 s apart, so each chime finishes before the next announcement.
	for n in [5, 3, 10, 15, 40]:
		world.run_chunk("news", """
game:GetService("ReplicatedStorage").CombatNews:FireAllClients("Tester's streak", %d)
""" % n)
		await create_timer(1.6).timeout
	await create_timer(4.5).timeout
	# PlaybackSpeed for a note is its Hz / (44100 / 64); sampled as that times a thousand.
	var want := PackedStringArray()
	var want_echo := PackedStringArray()
	for hz in [523.25, 659.25, 783.99, 1046.50, 1318.51, 1567.98, 2093.00]:
		want.append(str(int(round(hz / (44100.0 / 64.0) * 1000.0))))
		want_echo.append(str(int(round(hz / 2.0 / (44100.0 / 64.0) * 1000.0))))
	print("    lead: ", _said("LEAD "))
	print("    echo: ", _said("ECHO "))
	check(_said("READY ") == "true", "the 2A03 waveforms are here")
	var lead := _said("LEAD ").split(",")
	var echo := _said("ECHO ").split(",")
	check(_said("VOICES ") == "true|true", "both chime voices have a waveform")
	var runs := _runs(lead)
	var echoes := _runs(echo)
	check(runs.size() == 5 and ",".join(runs[0]) == ",".join(want), "at 5, the lead climbs C5 E5 G5 C6 E6 G6 C7")
	check(lead.size() > 1 and lead[lead.size() - 1] == "0", "and falls silent")
	check(echoes.size() == 5 and ",".join(echoes[0]) == ",".join(want_echo), "the echo plays them an octave down")
	check(echo.size() > 1 and echo[echo.size() - 1] == "0", "and falls silent too")
	for pair in [[1, -5, "on fire, a fourth below"], [2, 5, "10, a fourth above"], [3, 10, "15, a seventh above"], [4, 24, "40, two octaves up and no further"]]:
		var first := int(round(523.25 * pow(2.0, float(pair[1]) / 12.0) / (44100.0 / 64.0) * 1000.0))
		var top := int(round(2093.0 * pow(2.0, float(pair[1]) / 12.0) / (44100.0 / 64.0) * 1000.0))
		var run: PackedStringArray = runs[pair[0]] if runs.size() > pair[0] else PackedStringArray()
		check(run.size() == 7 and abs(int(run[0]) - first) <= 1 and abs(int(run[6]) - top) <= 1,
			"%s: %s" % [pair[2], ",".join(run)])
	check(_said("CLICKS ") == "0", "the banner showing and hiding plays no menu click: %s" % _said("CLICKS "))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## Each chime's notes, split at the silences between them.
func _runs(list: PackedStringArray) -> Array:
	var out := []
	var run := PackedStringArray()
	for v in list:
		if v == "0" or v == "":
			if run.size() > 0: out.append(run)
			run = PackedStringArray()
		else:
			run.append(v)
	if run.size() > 0: out.append(run)
	return out

## The notes played, without the silences before and after.
func _trim(list: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for v in list:
		if v != "0" and v != "": out.append(v)
	return out

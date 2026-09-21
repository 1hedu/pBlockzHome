# A joined player hears the trampoline on every bounce, not only the first.
#
#   godot --headless --path . -s res://tests/trampoline_net_test.gd
#
# A real client in its own process (chunk_peer.gd) drops its character onto one pad five times,
# the last two arriving fast sideways as a chained bounce does. Each pad has one Sound the
# server calls Play() on per bounce, and the client's engine times how long each play lasted.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")
const Arrive = preload("res://tests/Arrive.gd")
const PORT := 8822
const RIDES := 5
const RIDE_GAP := 4.0

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var kids: Array[int] = []
var report := ""
var t := 0.0
var phase := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _last(prefix: String) -> String:
	if not FileAccess.file_exists(report): return ""
	var lines := FileAccess.get_file_as_string(report).split("\n", false)
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with(prefix): return lines[i].substr(prefix.length())
	return ""

func _initialize() -> void:
	print("the trampoline, heard by a joined player")
	StandIns.stage("trampnet")
	report = OS.get_user_data_dir().path_join("trampoline_peer.txt")
	var chunk_file := OS.get_user_data_dir().path_join("trampoline_peer.luau")
	DirAccess.remove_absolute(report)
	var f := FileAccess.open(chunk_file, FileAccess.WRITE)
	# Dropped onto the pad from six studs, still and alive each time, so every ride is a landing.
	f.store_string("""
local Players = game:GetService("Players")
local map = workspace:WaitForChild("Map", 30)
local pad = map and map:FindFirstChild("TrampolineWestNorth", true)
if not pad then print("SEEN no pad") return end
local me = Players.LocalPlayer
local rides = %d
for i = 1, rides do
	local ch = me.Character or me.CharacterAdded:Wait()
	local root = ch:WaitForChild("HumanoidRootPart", 10)
	local hum = ch:WaitForChild("Humanoid", 10)
	if root and hum then
		hum.Health = hum.MaxHealth
		-- The last two come in fast, as a body does off the pad before: carried by SWING, thrown far.
		-- Low and not too quick, or the drift carries them past the pad without a landing.
		local fast = i > rides - 2
		root.CFrame = CFrame.new(pad.Position + Vector3.new(0, fast and 3 or 6, 0))
		root.AssemblyLinearVelocity = fast and Vector3.new(24, 0, 0) or Vector3.new(0, 0, 0)
		print("SEEN ride " .. i)
	end
	task.wait(%.1f)
end
print("SEEN rides done")
""" % [RIDES, RIDE_GAP])
	f.close()
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)
	# Trampoline.server.luau looks in PlaceAssets for SfxTrampoline, so the stand-in goes there.
	world.run_chunk("standins", StandIns.chunk("trampnet"))
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tests/chunk_peer.gd", "--",
		"--port=%d" % PORT, "--chunk=%s" % chunk_file, "--out=%s" % report, "--sound=TrampolineBounce"])
	if pid > 0: kids.append(pid)

func _process(delta: float) -> bool:
	t += delta
	# The fallback deadline is 30s to join and spawn, plus the rides themselves.
	if phase == 0 and (_last("SEEN ") == "rides done" or t > 30.0 + RIDES * RIDE_GAP):
		phase = 1
	elif phase == 1 and t > 0:
		phase = 2
		# 3s so the last play ends before its length is read.
		create_timer(3.0).timeout.connect(_finish)
	return false

func _finish() -> void:
	check(_last("SEEN ") != "no pad", "the joined client found the pad")
	check(_last("ride ") != "" or _last("SEEN ") == "rides done", "and rode it: %s" % _last("SEEN "))
	var told := _last("SOUNDPLAYS ").split(" ")
	var plays: PackedStringArray = told[1].split(",", false) if told.size() > 1 else PackedStringArray()
	check(plays.size() >= RIDES - 1, "its engine played the pad's Sound once per ride, not only the first: %d play(s) of %d rides" % [plays.size(), RIDES])
	var whole := 0
	var first := float(plays[0]) if plays.size() > 0 else 0.0
	for p in plays:
		if float(p) >= 0.25 and float(p) >= first * 0.6: whole += 1
	check(plays.size() > 0 and whole == plays.size(),
		"and every play was the whole clip, not a few milliseconds off the end of it: %s" % ",".join(plays))
	# A play reads "0.97@0.00/0dB/peak-21/far3"; far is its greatest distance from the ear, in studs.
	var near := 0
	var fars := PackedStringArray()
	for p in plays:
		var far := float(p.get_slice("far", 1)) if p.contains("far") else -1.0
		fars.append("%.0f" % far)
		if far >= 0.0 and far < 8.0: near += 1
	check(plays.size() > 0 and near == plays.size(),
		"and it stayed with the one thrown, fast launches included -- furthest from the ear, studs: %s" % ",".join(fars))
	for pid in kids: OS.kill(pid)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

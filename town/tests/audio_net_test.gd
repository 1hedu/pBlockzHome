# The Audio API across the wire: a chain a server script wires up is heard on a joined client.
#
#   godot --headless --path . -s res://tests/audio_net_test.gd
#
# A client that ignores what the server wires up is silent only to someone else, so the listener
# is a real client in its own process (chunk_peer.gd --voices), reporting its own engine's voices.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")
const Arrive = preload("res://tests/Arrive.gd")
const PORT := 8819

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
	print("the Audio API over the wire")
	StandIns.stage("audionet")
	report = OS.get_user_data_dir().path_join("audio_peer.txt")
	var chunk_file := OS.get_user_data_dir().path_join("audio_peer.luau")
	DirAccess.remove_absolute(report)
	var f := FileAccess.open(chunk_file, FileAccess.WRITE)
	f.store_string("print('SEEN joined')")
	f.close()
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tests/chunk_peer.gd", "--",
		"--port=%d" % PORT, "--chunk=%s" % chunk_file, "--out=%s" % report, "--voices=1"])
	if pid > 0: kids.append(pid)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 8.0:
		phase = 1
		world.run_chunk("build", """
local part = Instance.new("Part")
part.Name = "NetSpeaker" part.Anchored = true part.Position = Vector3.new(0, 60, 300) part.Parent = workspace
local player = Instance.new("AudioPlayer")
player.Asset = "user://preview/charge.wav" player.Looping = true
local filter = Instance.new("AudioFilter") filter.FilterType = Enum.AudioFilterType.Highpass12dB filter.Parent = player
local emitter = Instance.new("AudioEmitter") emitter.Parent = part
local a = Instance.new("Wire") a.SourceInstance = player a.TargetInstance = filter a.Parent = player
local b = Instance.new("Wire") b.SourceInstance = filter b.TargetInstance = emitter b.Parent = player
player.Parent = part
player:Play()
_G.netPlayer = player
""")
	elif phase == 1 and t > 14.0:
		phase = 2
		var seen := _last("VOICES ").split(" ")
		check(seen.size() == 3 and seen[0] == "1" and seen[1] == "1" and seen[2] == "1",
			"a joined client made the voice the server wired up, on its own bus, and it is playing: %s" % _last("VOICES "))
		world.run_chunk("stop", "_G.netPlayer:Stop()")
	elif phase == 2 and t > 18.0:
		phase = 3
		var seen := _last("VOICES ").split(" ")
		check(seen.size() == 3 and seen[0] == "1" and seen[1] == "0", "and when the server stops it, it stops there too: %s" % _last("VOICES "))
		world.run_chunk("gone", "_G.netPlayer.Parent:Destroy()")
	elif phase == 3 and t > 22.0:
		phase = 4
		var seen := _last("VOICES ").split(" ")
		check(seen.size() == 3 and seen[0] == "0" and seen[2] == "0", "and when it is destroyed the voice and its bus go: %s" % _last("VOICES "))
		for pid in kids: OS.kill(pid)
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

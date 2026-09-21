# A trampoline met by a real player across the wire.
#
#   godot --headless --path . -s res://tests/tramp_net_test.gd
#
# This process is the server; the arc is measured inside the client. Play Solo, as
# trampoline_test rides the pads, simulates the body on the machine that judges the touch, so
# it cannot see a launch velocity that fails to cross the wire.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld

## Every script error the server threw while this ran; _finish asserts it stayed empty.
var errors: Array[String] = []
var kids: Array[int] = []
var t := 0.0
var phase := 0
var report := ""

const PORT := 8817
const PEER := "Jumper"
# Background bots: how a body behaves over the wire depends on how busy the box is.
const LOAD := 8

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("a trampoline met across the wire")
	report = OS.get_user_data_dir().path_join("tramp.txt")
	DirAccess.remove_absolute(report)

	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		if String(line).begins_with("trampolines:"): print("    ", line))
	get_root().add_child(main)
	# Nothing here watches the intro, so players are let in as they join (tests/Arrive.gd).
	Arrive.now(world)

	for i in LOAD:
		var b := OS.create_process(OS.get_executable_path(),
			["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://tests/bot.gd", "--",
			"--name=Load%d" % i, "--port=%d" % PORT, "--every=1.3"])
		if b > 0: kids.append(b)
	var pid := OS.create_process(OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/tramp_peer.gd", "--",
		"--name=%s" % PEER, "--port=%d" % PORT, "--out=%s" % report])
	if pid > 0: kids.append(pid)

func _finish() -> void:
	for pid in kids: OS.kill(pid)
	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## One row per ride, as the client wrote it: "label|drop d|apex over the pad h|ended e".
func _rides() -> PackedStringArray:
	if not FileAccess.file_exists(report):
		return PackedStringArray()
	var blob := FileAccess.get_file_as_string(report).strip_edges()
	return PackedStringArray() if blob == "" else blob.split("\n")

func _apex(row: String) -> float:
	return float(row.substr(row.find("apex over the pad ") + 18).split("|")[0])

func _process(delta: float) -> bool:
	t += delta
	# 100s: the client connects, gets a body, then takes four rides with the pad's cooldown
	# between each.
	if phase == 0 and t > 100.0:
		phase = 1
		var rides := _rides()
		check(rides.size() >= 6, "the client jumped, then rode the pad four ways: %s" % str(rides))
		if rides.size() < 6:
			_finish()
			return false
		for row in rides:
			print("    ", row)

		# Row 1 is an ordinary jump, no pad involved: the height a real player gets over the wire.
		var jump := _apex(String(rides[1]))
		check(abs(jump - 6.4) < 0.8,
			"a plain jump over the wire is Roblox's own height: %.2f studs of a theoretical 6.37" % jump)

		var stood := _apex(String(rides[2]))
		var dropped := _apex(String(rides[3]))
		var stoodAgain := _apex(String(rides[4]))
		var far := _apex(String(rides[5]))

		check(stood > 20.0,
			"standing on it throws you about thirty studs up: %.1f" % stood)
		# RISE is a fixed apex whatever the approach, so arriving fast must not lower the arc.
		check(dropped > 20.0,
			"and LANDING on it throws you just as high: %.1f" % dropped)
		check(far > 20.0,
			"however hard you come down on it: %.1f" % far)
		check(stoodAgain > 20.0,
			"and it still works on the way back: %.1f" % stoodAgain)
		_finish()
	return false

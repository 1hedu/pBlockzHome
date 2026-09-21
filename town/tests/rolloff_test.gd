# Sound.RollOffMode: all four curves, measured.
#
#   godot --headless --path . -s res://tests/rolloff_test.gd
#
# Nothing has to be audible: what is checked is the gain the engine works out for a distance,
# read off the AudioStreamPlayer3D. Godot's inverse-distance is Roblox's Inverse exactly;
# Godot has no linear model, so the other three are worked out per frame.
#
#   Inverse         minDist / d                           Godot's own model
#   Linear          (maxDist - d) / (maxDist - minDist)
#   LinearSquare    that, squared
#   InverseTapered  the smaller of inverse and linear-square
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []
var lit := false

const LO := 10.0
const HI := 110.0
const AWAY := 60.0        # where the noise is put, in studs from the ear

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("how a sound fades with distance")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		said.append(line)
		if line.begins_with("intro:"): lit = true)
	get_root().add_child(main)
	_run()

## The world's camera, which is the ear.
##
## Viewport-checked, not the first current one: every ViewportFrame in the town has a camera
## current inside its own little world.
func _ear() -> Camera3D:
	var stack: Array[Node] = [get_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Camera3D and n.current and n.get_viewport() == get_root(): return n
		for c in n.get_children(): stack.append(c)
	return null

## The player node the test's Sound was given, by name.
func _player() -> AudioStreamPlayer3D:
	var stack: Array[Node] = [get_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AudioStreamPlayer3D and String(n.name) == "Noise": return n
		for c in n.get_children(): stack.append(c)
	return null

## Puts the noise at a point and asks its Sound for one of the four curves.
func _put(mode: String, at: Vector3) -> void:
	world.run_client_chunk("put", """
local ws = workspace
local part = ws:FindFirstChild("Speaker")
if not part then
	part = Instance.new("Part")
	part.Name = "Speaker"
	part.Anchored = true
	part.Size = Vector3.new(1, 1, 1)
	part.Parent = ws
	local s = Instance.new("Sound")
	s.Name = "Noise"
	s.Volume = 1
	s.RollOffMinDistance = %f
	s.RollOffMaxDistance = %f
	s.Parent = part
end
part.Position = Vector3.new(%f, %f, %f)
part:FindFirstChild("Noise").RollOffMode = Enum.RollOffMode.%s
""" % [LO, HI, at.x, at.y, at.z, mode])
	await create_timer(0.9).timeout

func _db_to_gain(db: float) -> float:
	return pow(10.0, db / 20.0)

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(2.0).timeout

	var ear := _ear()
	check(ear != null, "the scene has a camera to hear with")
	if ear == null:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	await _put("Inverse", ear.global_position + Vector3(AWAY, 0, 0))
	var a := _player()
	check(a != null, "the sound made itself a player")
	if a == null:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	check(a.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE,
		"Inverse is left to Godot, whose inverse-distance is the same curve")
	check(abs(a.unit_size - LO) < 0.01,
		"with RollOffMinDistance as its unit size: %.2f" % a.unit_size)
	check(abs(a.max_distance - HI) < 0.01,
		"and RollOffMaxDistance as its cutoff: %.2f" % a.max_distance)

	# The three Godot has no model for, measured as far gain over near rather than absolute:
	# the gain written is the curve times the Sound's Volume times its group's, and the town's
	# mixer is still ramping the music up.
	for mode in ["Linear", "LinearSquare", "InverseTapered"]:
		ear = _ear()
		await _put(mode, ear.global_position + Vector3(2, 0, 0))
		a = _player()
		check(a.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED,
			"%s turns Godot's own model off" % mode)
		var full := _db_to_gain(a.volume_db)
		ear = _ear()
		await _put(mode, ear.global_position + Vector3(AWAY, 0, 0))
		a = _player()
		var d: float = (a.global_position - ear.global_position).length()
		var got: float = _db_to_gain(a.volume_db) / max(full, 0.0001)
		# From the distance actually measured: the camera drifts while the character settles.
		var l: float = clamp((HI - d) / (HI - LO), 0.0, 1.0)
		var expect: float = l if mode == "Linear" else (l * l if mode == "LinearSquare" else min(LO / d, l * l))
		check(abs(got - expect) < 0.05,
			"%s at %.1f studs is %.3f of full, wanted %.3f" % [mode, d, got, expect])

	# The far end of every curve: silent past RollOffMaxDistance.
	ear = _ear()
	await _put("Linear", ear.global_position + Vector3(400, 0, 0))
	a = _player()
	check(_db_to_gain(a.volume_db) < 0.001,
		"past RollOffMaxDistance it is silent: %.5f" % _db_to_gain(a.volume_db))

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

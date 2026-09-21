# Shift halves WalkSpeed and letting it go gives it back, driven by real key events through the
# place's own controls (Controls.client). The stride needs no check of its own: the walk
# animation runs off how fast the body moves (animPhase in the host).
#
#   godot --headless --path . -s res://tests/shift_walk_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var t := 0.0
var step := 0
var said: Array[String] = []
var ok := 0
var bad := 0
var steps := []

func check(cond: bool, what: String) -> void:
	if cond: ok += 1
	else: bad += 1
	print("  %s  %s" % ["PASS" if cond else "FAIL", what])

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(func(_n, line): said.append(line))
	world.script_error.connect(func(n, e): print("  LUA ERROR [%s] %s" % [n, e]))
	root.add_child(main)
	# Nothing clicks through the intro here, so players are admitted as they join.
	Arrive.now(world)

func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	e.shift_pressed = down and code == KEY_SHIFT
	Input.parse_input_event(e)

func _home() -> void:
	world.run_chunk("home", "local r = game:GetService('Players'):GetPlayers()[1].Character.HumanoidRootPart r.CFrame = CFrame.new(40, r.Position.Y + 0.5, 0) r.AssemblyLinearVelocity = Vector3.zero")

func _see(tag: String) -> void:
	world.run_chunk("see", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
local at = ch.HumanoidRootPart.Position
print(("SEEN TAG x=%.2f z=%.2f clock=%.3f"):format(at.X, at.Z, os.clock()))
""".replace("TAG", tag))
	world.run_client_chunk("speed", """
local h = game:GetService("Players").LocalPlayer.Character.Humanoid
print(("SPEED TAG %.2f"):format(h.WalkSpeed))
""".replace("TAG", tag))

func _field(tag: String, key: String) -> float:
	for line in said:
		if line.begins_with("SEEN %s " % tag):
			for part in line.split(" "):
				if part.begins_with(key + "="): return float(part.substr(key.length() + 1))
	return 0.0

func _speed(tag: String) -> float:
	for line in said:
		if line.begins_with("SPEED %s " % tag): return float(line.split(" ")[2])
	return -1.0

## Studs a second between two snapshots.
func _rate(a: String, b: String) -> float:
	var d := Vector2(_field(b, "x") - _field(a, "x"), _field(b, "z") - _field(a, "z")).length()
	return d / max(_field(b, "clock") - _field(a, "clock"), 0.001)

func _process(delta: float) -> bool:
	t += delta
	if step == 0 and t > 10.0:
		step = 1; t = 0.0
		steps = [
			# Every stretch restarts on clear ground: walking into the fountain reads as a slow one.
			[0.0, func(): _home()],
			[1.0, func(): _key(KEY_W, true)],
			[0.4, func(): _see("walk0")],            # up to speed first
			[1.0, func(): _see("walk1")],
			[0.0, func(): _key(KEY_W, false); _home()],
			[0.6, func(): _key(KEY_SHIFT, true); _key(KEY_W, true)],
			[0.4, func(): _see("slow0")],
			[1.0, func(): _see("slow1")],
			[0.0, func(): _key(KEY_W, false); _home()],
			[0.6, func(): _key(KEY_SHIFT, false); _key(KEY_W, true)],
			[0.4, func(): _see("back0")],
			[1.0, func(): _see("back1")],
			[0.0, func(): _key(KEY_W, false)],
			[0.5, func(): _judge()],
		]
	elif step >= 1 and step <= steps.size():
		var s: Array = steps[step - 1]
		if t > float(s[0]):
			t = 0.0
			step += 1
			(s[1] as Callable).call()
	return false

func _judge() -> void:
	var walk := _rate("walk0", "walk1")
	var slow := _rate("slow0", "slow1")
	var back := _rate("back0", "back1")
	check(walk > 12.0, "W walks him at his WalkSpeed: %.1f studs a second" % walk)
	check(walk > 0.0 and abs(slow / walk - 0.5) < 0.12, "Shift + W walks him at half that: %.1f studs a second, %.0f%%" % [slow, 100.0 * slow / max(walk, 0.001)])
	check(abs(_speed("slow1") - _speed("walk1") * 0.5) < 0.01, "because WalkSpeed is halved while Shift is down: %.1f from %.1f" % [_speed("slow1"), _speed("walk1")])
	check(abs(back - walk) < walk * 0.15 and abs(_speed("back1") - _speed("walk1")) < 0.01,
		"and letting Shift go gives it back: %.1f studs a second, WalkSpeed %.1f" % [back, _speed("back1")])
	print("%d passed, %d failed" % [ok, bad])
	quit(0 if bad == 0 else 1)

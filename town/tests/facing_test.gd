# Camera and facing under a right-drag: right-drag turns both, Ctrl + right-drag turns the camera
# alone with A / D turning the body (WoW's left-drag), and Ctrl pressed mid-drag switches there and
# then. Run standing, then with W held: walking goes the way the camera looks, so a body facing its
# walk follows the camera unless something holds it.
#
#   godot --headless --path . -s res://tests/facing_test.gd
#
# Real input events. The heading judged is the SERVER's root, which is where a thrown orb goes.
extends SceneTree

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

func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	e.ctrl_pressed = down and code == KEY_CTRL
	Input.parse_input_event(e)

func _right(down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = down
	e.position = Vector2(640, 360)
	e.global_position = e.position
	Input.parse_input_event(e)

func _drag(dx: float) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(dx, 0)
	e.position = Vector2(640, 360)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(e)

## The camera's heading (client) and the body's heading as the server has it, in degrees.
func _see(tag: String) -> void:
	world.run_client_chunk("seecam", """
local v = workspace.CurrentCamera.CFrame.LookVector
print(("SEEN TAG camera=%.1f"):format(math.deg(math.atan2(-v.X, -v.Z))))
""".replace("TAG", tag))
	world.run_chunk("seebody", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
local v = ch.HumanoidRootPart.CFrame.LookVector
if not ch:GetAttribute("FacingTestBody") then ch:SetAttribute("FacingTestBody", os.clock()) end
local at = ch.HumanoidRootPart.Position
print(("SEEN TAG body=%.1f life=%.3f x=%.2f z=%.2f"):format(math.deg(math.atan2(-v.X, -v.Z)), ch:GetAttribute("FacingTestBody"), at.X, at.Z))
""".replace("TAG", tag))

func _field(tag: String, key: String) -> float:
	for line in said:
		if line.begins_with("SEEN %s " % tag) and line.find(key + "=") >= 0:
			return float(line.substr(line.find(key + "=") + key.length() + 1).split(" ")[0])
	return -1.0

func _apart(a: float, b: float) -> float:
	return abs(fposmod(b - a + 180.0, 360.0) - 180.0)

## One pass of drags, its snapshots tagged with `p`.
func _pass(p: String) -> Array:
	return [
		[0.3, func(): _see(p + "start")],
		# 200 pixels of drag is 57 degrees of camera.
		[0.3, func(): _right(true)],
		[0.2, func(): for i in 10: _drag(20)],
		[0.5, func(): _see(p + "held")],
		[0.3, func(): _right(false)],
		[0.5, func(): _see(p + "plain")],
		[0.5, func(): _key(KEY_CTRL, true)],
		[0.2, func(): _right(true)],
		[0.2, func(): for i in 10: _drag(20)],
		[0.3, func(): _see(p + "ctrl")],
		[0.2, func(): _right(false); _key(KEY_CTRL, false)],
		# One unbroken drag, with Ctrl pressed and released inside it.
		[0.5, func(): _right(true)],
		[0.2, func(): for i in 5: _drag(20)],
		[0.4, func(): _see(p + "mid1")],
		[0.2, func(): _key(KEY_CTRL, true)],
		[0.2, func(): for i in 10: _drag(20)],
		[0.4, func(): _see(p + "mid2")],
		[0.2, func(): _key(KEY_CTRL, false)],
		[0.4, func(): _see(p + "mid3")],
		[0.2, func(): _right(false)],
		[0.3, func(): _key(KEY_CTRL, true)],
		[0.2, func(): _right(true)],
		[0.3, func(): _see(p + "keys1")],
		[0.1, func(): _key(KEY_D, true)],
		[0.5, func(): _key(KEY_D, false)],
		[0.3, func(): _see(p + "keys2")],
		[0.2, func(): _right(false); _key(KEY_CTRL, false)],
	]

func _process(delta: float) -> bool:
	t += delta
	if step == 0 and t > 10.0:
		step = 1; t = 0.0
		steps = _pass("stand ")
		# WalkSpeed 1.5: at the default a pass walks him off the map, and the respawn hands the
		# drag a new body.
		steps.append([0.5, func():
			world.run_chunk("slow", "local ch = game:GetService('Players'):GetPlayers()[1].Character ch.Humanoid.WalkSpeed = 1.5 ch.HumanoidRootPart.CFrame = CFrame.new(0, ch.HumanoidRootPart.Position.Y, 30)")])
		steps.append([1.0, func(): _key(KEY_W, true)])
		steps.append_array(_pass("walk "))
		steps.append([0.2, func(): _key(KEY_W, false)])
		steps.append([0.5, func(): _judge()])
	elif step >= 1 and step <= steps.size():
		var s: Array = steps[step - 1]
		if t > float(s[0]):
			t = 0.0
			step += 1
			(s[1] as Callable).call()
	return false

func _judge_pass(p: String, how: String) -> void:
	var cam_turn := _apart(_field(p + "start", "camera"), _field(p + "plain", "camera"))
	var held := _apart(_field(p + "held", "camera"), _field(p + "held", "body"))
	check(cam_turn > 45.0 and held < 5.0,
		"%s, right-drag turns the camera (%.1f degrees) and the server has him facing where it looks (%.1f apart)" % [how, cam_turn, held])
	var cam_ctrl := _apart(_field(p + "plain", "camera"), _field(p + "ctrl", "camera"))
	var body_ctrl := _apart(_field(p + "plain", "body"), _field(p + "ctrl", "body"))
	check(cam_ctrl > 45.0 and body_ctrl < 3.0,
		"%s, Ctrl + right-drag turns the camera (%.1f) and holds the way he faces (%.1f)" % [how, cam_ctrl, body_ctrl])
	var mid1 := _apart(_field(p + "mid1", "camera"), _field(p + "mid1", "body"))
	var cam_mid := _apart(_field(p + "mid1", "camera"), _field(p + "mid2", "camera"))
	var body_mid := _apart(_field(p + "mid1", "body"), _field(p + "mid2", "body"))
	check(mid1 < 5.0 and cam_mid > 45.0 and body_mid < 3.0,
		"%s, touching Ctrl mid-drag stops him following at once: following %.1f apart, then camera %.1f, him %.1f" % [how, mid1, cam_mid, body_mid])
	var mid3 := _apart(_field(p + "mid3", "camera"), _field(p + "mid3", "body"))
	check(mid3 < 5.0, "%s, letting Ctrl go, still dragging, he turns back to the camera's look: %.1f apart" % [how, mid3])
	var turned := _apart(_field(p + "keys1", "body"), _field(p + "keys2", "body"))
	var cam_keys := _apart(_field(p + "keys1", "camera"), _field(p + "keys2", "camera"))
	# Half a turn a second for the half-second D is down is a quarter turn, less the frames the
	# press and the release take to land.
	check(turned > 45.0 and turned < 110.0 and cam_keys < 3.0,
		"%s, in a Ctrl + right-drag D turns him, half a turn a second: %.1f degrees for half a second of key, the camera %.1f" % [how, turned, cam_keys])

func _judge() -> void:
	_judge_pass("stand ", "standing")
	_judge_pass("walk ", "walking")
	# Steering with D while W walks. The walk-in-place this guards against only appears on a joined
	# client, so steer_net_test is the one that fails without the fix; this covers the Play Solo side.
	var steered := Vector2(_field("walk keys2", "x") - _field("walk keys1", "x"), _field("walk keys2", "z") - _field("walk keys1", "z")).length()
	check(steered > 0.6, "walking with W while D steers him in a Ctrl + right-drag, he goes somewhere: %.2f studs in 0.9s at 1.5 studs a second" % steered)
	# Nothing default is moving him: scripts/src/client/Controls.client.luau sets
	# StarterPlayer.DevComputerMovementMode to Scriptable, so W reaches the body only through it.
	var walked := Vector2(_field("walk keys2", "x") - _field("walk start", "x"), _field("walk keys2", "z") - _field("walk start", "z")).length()
	check(walked > 3.0, "and W walks him, the place's own controls doing the walking: %.1f studs over the pass" % walked)
	# One body for the whole pass: a respawn resets the right-drag in progress, which would leave
	# every walking check above judging a drag that no longer existed.
	check(_field("walk start", "life") == _field("walk keys2", "life") and _field("walk start", "life") > 0.0,
		"and he walked the whole pass on one body, no fall and respawn (%s against %s)" % [_field("walk start", "life"), _field("walk mid3", "life")])
	print("%d passed, %d failed" % [ok, bad])
	quit(0 if bad == 0 else 1)

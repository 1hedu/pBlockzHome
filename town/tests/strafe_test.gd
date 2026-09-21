# Running sideways in a right-drag, and swinging while you do.
#
#   godot --headless --path . -s res://tests/strafe_test.gd
#
# Driven by real input events: in a right-drag the body faces the way it runs, as Roblox and WoW
# do -- D right, A left, S backing up still facing ahead, standing facing the camera, and ahead
# for a swing's stroke. Headings read off the server, as facing_test does.
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
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(func(_n, line): said.append(line))
	world.script_error.connect(func(n, e): print("  LUA ERROR [%s] %s" % [n, e]))
	root.add_child(main)

func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func _button(which: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = which
	e.pressed = down
	e.position = Vector2(640, 360)
	e.global_position = e.position
	Input.parse_input_event(e)

## The camera's heading, and the body's heading and place as the server has them, in degrees.
func _see(tag: String) -> void:
	world.run_client_chunk("seecam", """
local v = workspace.CurrentCamera.CFrame.LookVector
print(("SEEN TAG camera=%.1f"):format(math.deg(math.atan2(-v.X, -v.Z))))
""".replace("TAG", tag))
	world.run_chunk("seebody", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
local v = ch.HumanoidRootPart.CFrame.LookVector
local at = ch.HumanoidRootPart.Position
print(("SEEN TAG body=%.1f x=%.2f z=%.2f swinging=%s"):format(math.deg(math.atan2(-v.X, -v.Z)), at.X, at.Z, tostring(ch:GetAttribute("Swinging"))))
""".replace("TAG", tag))

func _field(tag: String, key: String) -> float:
	for line in said:
		if line.begins_with("SEEN %s " % tag) and line.find(key + "=") >= 0:
			return float(line.substr(line.find(key + "=") + key.length() + 1).split(" ")[0])
	return INF

func _line(tag: String, key: String) -> String:
	for line in said:
		if line.begins_with("SEEN %s " % tag) and line.find(key + "=") >= 0:
			return line.substr(line.find(key + "=") + key.length() + 1).split(" ")[0]
	return ""

## Signed difference b - a, in -180..180.
func _turn(a: float, b: float) -> float:
	return fposmod(b - a + 180.0, 360.0) - 180.0

func _process(delta: float) -> bool:
	t += delta
	if step == 0 and t > 10.0:
		step = 1; t = 0.0
		steps = [
			# WalkSpeed 4, clear ground, and something in hand to swing. The steps before the
			# left-click leave the weapon time to draw: the server refuses a swing mid-draw.
			[0.2, func(): world.run_chunk("setup", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
ch.Humanoid.WalkSpeed = 4
ch.HumanoidRootPart.CFrame = CFrame.new(0, ch.HumanoidRootPart.Position.Y, 30)
local acc = Instance.new("Accessory")
acc.Name = "Spoonie"
local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Size = Vector3.new(0.3, 2.2, 0.3)
handle.Parent = acc
acc.Parent = ch
""")],
			[2.0, func(): _button(MOUSE_BUTTON_RIGHT, true)],
			[0.6, func(): _see("stand")],
			[0.2, func(): _key(KEY_D, true)],
			[0.8, func(): _see("right1")],
			[0.6, func(): _see("right2")],
			# A swing with D still down.
			[0.1, func(): _button(MOUSE_BUTTON_LEFT, true)],
			[0.06, func(): _button(MOUSE_BUTTON_LEFT, false)],
			[0.12, func(): _see("swing")],
			[0.2, func(): _key(KEY_D, false)],
			[1.2, func(): _key(KEY_A, true)],
			[0.8, func(): _see("left1")],
			[0.6, func(): _see("left2")],
			[0.1, func(): _key(KEY_A, false)],
			[0.5, func(): _key(KEY_S, true)],
			[0.8, func(): _see("back1")],
			[0.6, func(): _see("back2")],
			[0.1, func(): _key(KEY_S, false); _button(MOUSE_BUTTON_RIGHT, false)],
			[0.3, func(): _judge()],
		]
	elif step >= 1 and step <= steps.size():
		var s: Array = steps[step - 1]
		if t > float(s[0]):
			t = 0.0
			step += 1
			(s[1] as Callable).call()
	return false

func _judge() -> void:
	var cam := _field("stand", "camera")
	print("    camera %.1f; stand body %.1f; right %.1f; swing %.1f (swinging=%s); left %.1f; back %.1f" % [cam,
		_field("stand", "body"), _field("right2", "body"), _field("swing", "body"), _line("swing", "swinging"),
		_field("left2", "body"), _field("back2", "body")])
	check(abs(_turn(cam, _field("stand", "body"))) < 5.0, "in a right-drag, standing, he faces where the camera looks")
	# Headings are degrees anticlockwise from -Z seen from above, so running right is -90 off the camera.
	var ran_right := Vector2(_field("right2", "x") - _field("right1", "x"), _field("right2", "z") - _field("right1", "z"))
	var cam_right := Vector2(cos(deg_to_rad(cam)), -sin(deg_to_rad(cam)))
	check(ran_right.length() > 1.0 and ran_right.normalized().dot(cam_right) > 0.9,
		"D runs him right: %.2f studs, %.2f along the camera's right" % [ran_right.length(), ran_right.normalized().dot(cam_right)])
	check(abs(_turn(cam - 90.0, _field("right2", "body"))) < 12.0, "and he faces right while he runs, not ahead: %.1f off" % _turn(cam - 90.0, _field("right2", "body")))
	check(abs(_turn(cam, _field("swing", "body"))) < 12.0,
		"swinging while running right, he faces ahead for the stroke: %.1f off ahead" % _turn(cam, _field("swing", "body")))
	check(abs(_turn(cam + 90.0, _field("left2", "body"))) < 12.0, "A runs him left, facing left: %.1f off" % _turn(cam + 90.0, _field("left2", "body")))
	var backed := Vector2(_field("back2", "x") - _field("back1", "x"), _field("back2", "z") - _field("back1", "z"))
	var cam_ahead := Vector2(-sin(deg_to_rad(cam)), -cos(deg_to_rad(cam)))
	check(backed.length() > 1.0 and backed.normalized().dot(cam_ahead) < -0.9, "S backs him up: %.2f studs" % backed.length())
	check(abs(_turn(cam, _field("back2", "body"))) < 12.0, "still facing ahead: %.1f off" % _turn(cam, _field("back2", "body")))
	print("%d passed, %d failed" % [ok, bad])
	quit(0 if bad == 0 else 1)

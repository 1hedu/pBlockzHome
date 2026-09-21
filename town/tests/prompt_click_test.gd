# ProximityPrompt.ClickablePrompt, which Roblox defaults on: a click triggers the prompt, the
# same click does nothing once it is off, though its key still fires.
# Windowed: the click is a camera ray from a real pointer, which headless has neither of.
#
#   godot --path . -s res://tests/prompt_click_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []
var lit := false

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("clicking a proximity prompt")
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

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var at := String(line).find(prefix)
		if at >= 0:
			out.append(String(line).substr(at + prefix.length()).strip_edges())
	return out

func _click(at: Vector2) -> void:
	Input.warp_mouse(at)
	var m := InputEventMouseMotion.new()
	m.position = at; m.global_position = at
	Input.parse_input_event(m)
	await create_timer(0.25).timeout
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at; e.global_position = at
		Input.parse_input_event(e)
		await create_timer(0.15).timeout
	await create_timer(0.7).timeout

func _press_key() -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_E
		e.physical_keycode = KEY_E
		e.pressed = pressed
		Input.parse_input_event(e)
		await create_timer(0.2).timeout
	await create_timer(0.7).timeout

## Triggers so far, off the workspace attribute the prompt counts into, or -1 if nothing answered.
func _count() -> int:
	said.clear()
	world.run_chunk("count", """
print("TRIGGERS " .. tostring(workspace:GetAttribute("Triggers") or 0))
""")
	await create_timer(0.7).timeout
	var rows := _lines("TRIGGERS ")
	return int(String(rows[rows.size() - 1])) if rows.size() > 0 else -1

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(2.0).timeout
	DisplayServer.window_move_to_foreground()

	world.run_chunk("build", """
local ws = workspace
local Players = game:GetService("Players")
local char = Players:GetPlayers()[1].Character
local root = char:WaitForChild("HumanoidRootPart")
ws:SetAttribute("Triggers", 0)
local old = ws:FindFirstChild("Slab")
if old then old:Destroy() end
local slab = Instance.new("Part")
slab.Name = "Slab"
slab.Size = Vector3.new(14, 14, 1)
slab.Anchored = true
-- In front of the CHARACTER, not the camera: this is a server chunk and CurrentCamera is
-- the client's. Big and close, so it fills the middle of the shot whichever way the camera
-- is sitting over the shoulder; the exact pixel is asked of the client below.
slab.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 10 + Vector3.new(0, 2, 0),
	root.Position + Vector3.new(0, 2, 0))
slab.Parent = ws
local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Push"
prompt.ObjectText = "Slab"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.MaxActivationDistance = 40
prompt.RequiresLineOfSight = false
prompt.Parent = slab
prompt.Triggered:Connect(function()
	ws:SetAttribute("Triggers", (ws:GetAttribute("Triggers") or 0) + 1)
end)
print("BUILT at " .. tostring(slab.Position))
""")
	await create_timer(1.5).timeout

	# Only the client has CurrentCamera, so the viewport point is asked of it.
	said.clear()
	world.run_client_chunk("where", """
local ws = workspace
local cam = ws.CurrentCamera
local slab = ws:WaitForChild("Slab")
local at, on = cam:WorldToViewportPoint(slab.Position)
print(("SLAB %.0f %.0f %s"):format(at.X, at.Y, tostring(on)))
""")
	await create_timer(1.0).timeout
	var found := _lines("SLAB ")
	check(found.size() > 0 and String(found[0]).ends_with("true"),
		"the slab is on screen: %s" % str(found))
	if found.size() == 0:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	var bits: PackedStringArray = String(found[0]).split(" ")
	var middle := Vector2(float(bits[0]), float(bits[1]))

	# A warm-up click: the first press after the window comes forward is swallowed.
	await _click(middle)
	var base := await _count()

	await _click(middle)
	var clicked := await _count()
	check(clicked == base + 1,
		"clicking a prompt triggers it: %d -> %d" % [base, clicked])

	world.run_chunk("off", """
workspace.Slab.ProximityPrompt.ClickablePrompt = false
print("OFF")
""")
	await create_timer(0.8).timeout
	await _click(middle)
	var ignored := await _count()
	check(ignored == clicked,
		"with ClickablePrompt off the same click is ignored: %d -> %d" % [clicked, ignored])

	# The control for the check above: the prompt is still live, only its click is off.
	await _press_key()
	var keyed := await _count()
	check(keyed == ignored + 1,
		"but its key still works: %d -> %d" % [ignored, keyed])

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

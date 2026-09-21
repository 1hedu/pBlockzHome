# ClickDetector.CursorIcon: over the part the pointer becomes the detector's icon, off it the
# icon it had before. Read through Mouse.Icon, the property Roblox sets and a place reads back.
# Windowed, not headless: it needs a camera ray from a real pointer.
#
#   godot --path . -s res://tests/cursor_icon_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []
var lit := false

const WANT := "rbxasset://textures/GunCursor.png"

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the pointer over a click detector")
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

func _move(at: Vector2) -> void:
	Input.warp_mouse(at)
	var m := InputEventMouseMotion.new()
	m.position = at; m.global_position = at
	Input.parse_input_event(m)
	await create_timer(0.6).timeout

func _icon() -> String:
	said.clear()
	world.run_client_chunk("icon", """
local Players = game:GetService("Players")
print("ICON [" .. tostring(Players.LocalPlayer:GetMouse().Icon) .. "]")
""")
	await create_timer(0.7).timeout
	var rows := _lines("ICON ")
	return String(rows[rows.size() - 1]) if rows.size() > 0 else "?"

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(2.0).timeout
	DisplayServer.window_move_to_foreground()

	world.run_chunk("build", """
local ws = workspace
local Players = game:GetService("Players")
local root = Players:GetPlayers()[1].Character:WaitForChild("HumanoidRootPart")
local old = ws:FindFirstChild("Slab")
if old then old:Destroy() end
local slab = Instance.new("Part")
slab.Name = "Slab"
slab.Size = Vector3.new(14, 14, 1)
slab.Anchored = true
slab.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 10 + Vector3.new(0, 2, 0),
	root.Position + Vector3.new(0, 2, 0))
slab.Parent = ws
local cd = Instance.new("ClickDetector")
cd.MaxActivationDistance = 60
cd.CursorIcon = "%s"
cd.Parent = slab
cd.MouseHoverEnter:Connect(function() print("HOVER in") end)
cd.MouseHoverLeave:Connect(function() print("HOVER out") end)
print("BUILT")
""" % WANT)
	await create_timer(1.5).timeout

	said.clear()
	world.run_client_chunk("where", """
local ws = workspace
local at, on = ws.CurrentCamera:WorldToViewportPoint(ws:WaitForChild("Slab").Position)
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
	var on_slab := Vector2(float(bits[0]), float(bits[1]))

	# Off the slab first: the icon it must come back to is measured, not assumed.
	await _move(Vector2(40, 40))
	var before := await _icon()

	await _move(on_slab)
	var over := await _icon()
	check(over.find(WANT) >= 0, "over the detector the pointer is its icon: %s" % over)

	await _move(Vector2(40, 40))
	var after := await _icon()
	check(after == before, "and off it again the pointer is what it was: %s" % after)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

# The speed readout while you are driving, and VehicleSeat.HeadsUpDisplay switching it.
#
#   godot --headless --path . -s res://tests/vehicle_test.gd
#
# A GUI has no extent headless, so nothing here is about where the readout sits -- only that it
# exists, that HeadsUpDisplay turns it off and on, and that its number is the assembly's speed:
# a seat welded into a car has almost no velocity of its own to report.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the driving HUD")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	# Players are let in as they join, without the intro gate (tests/Arrive.gd).
	Arrive.now(world)
	_run()

## The readout, found by name.
##
## Callers read `visible`, not `is_visible_in_tree`: headless the core GUI layer has no viewport
## and is never visible in the tree, so that answers hidden whether the HUD is on or off.
## SubViewports are skipped -- the wardrobe keeps a preview world in one, and descending into it
## counts things twice.
func _hud() -> Control:
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SubViewport:
			continue
		if n is Control and String(n.name) == "VehicleHud":
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _speed() -> Label:
	var hud := _hud()
	return hud.get_node_or_null("Speed") as Label if hud != null else null

func _showing() -> bool:
	var hud := _hud()
	return hud != null and hud.visible

func _make(body: String, wait := 1.2) -> void:
	world.run_chunk("vehicle_probe", body)
	await create_timer(wait).timeout

func _run() -> void:
	await create_timer(3.0).timeout

	check(not _showing(), "nothing on screen while you are on your feet")

	# A parked car: a slab with a VehicleSeat welded on top, and a humanoid sat in it.
	await _make('''
local body = Instance.new("Part")
body.Name = "Chassis"
body.Size = Vector3.new(8, 1, 14)
body.Position = Vector3.new(0, 200, 0)
body.Anchored = true          -- parked, so a reading of nothing means nothing
body.Parent = workspace

local seat = Instance.new("VehicleSeat")
seat.Name = "Driver"
seat.Size = Vector3.new(4, 1, 4)
seat.Position = Vector3.new(0, 201, 0)
seat.Anchored = true
seat.Parent = workspace

local weld = Instance.new("WeldConstraint")
weld.Part0 = body
weld.Part1 = seat
weld.Parent = body

local plr = game:GetService("Players"):GetPlayers()[1]
local h = plr.Character:FindFirstChildOfClass("Humanoid")
seat:Sit(h)
''', 2.5)

	var label := _speed()
	check(label != null, "sitting in a vehicle seat puts a readout on screen")
	if label == null:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	check(_showing(), "and it is shown")
	check(label.text.ends_with("studs/s"), "saying a speed: %s" % label.text)
	check(label.text.begins_with("0 "), "which reads nothing while the car is parked: %s" % label.text)

	# Toggled while the parked seat is still under you: the falling seat below is past the
	# world's floor before a toggle could reach it.
	await _make('workspace:FindFirstChild("Driver").HeadsUpDisplay = false', 1.0)
	check(not _showing(), "HeadsUpDisplay = false takes it away, so a place can draw its own")
	await _make('workspace:FindFirstChild("Driver").HeadsUpDisplay = true', 1.0)
	check(_showing(), "and back on again")

	# The moving reading comes from a bare seat falling: a welded assembly with a driver pinned
	# into it is not simulated here (WINDOWED.md), so the car above stays where it is put.
	await _make('''
local seat = Instance.new("VehicleSeat")
seat.Name = "Loose"
seat.Size = Vector3.new(4, 1, 4)
seat.Position = Vector3.new(60, 300, 0)
seat.Parent = workspace
local plr = game:GetService("Players"):GetPlayers()[1]
seat:Sit(plr.Character:FindFirstChildOfClass("Humanoid"))
''', 2.0)
	var moving := _speed()
	var said := int(moving.text.split(" ")[0]) if moving != null else -1
	check(said > 20, "and a real number once the vehicle is moving: %s"
		% (moving.text if moving != null else "gone"))

	await _make('''
local plr = game:GetService("Players"):GetPlayers()[1]
plr.Character:FindFirstChildOfClass("Humanoid").Sit = false
''', 1.5)
	check(not _showing(), "getting out takes the readout with you")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

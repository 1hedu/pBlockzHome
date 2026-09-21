# A worn hat points up. As on Roblox, a worn Handle is placed by its attachment alone and its
# own Orientation is discarded, while sibling parts are placed relative to the Handle INCLUDING
# that orientation -- so a turned Handle cancels itself out and the accessory renders unturned.
#
#   godot --headless --path . -s res://tests/worn_test.gd
#
# Both shapes are built, an untuned Handle and a turned one, so the test still fails if worn
# placement stops working altogether.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("worn accessories")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	# Lets players in as they join instead of waiting out the intro (tests/Arrive.gd).
	Arrive.now(world)
	_run()

func _id(named: String) -> int:
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var at: int = stack.pop_back()
		for kid in world.get_child_ids(at):
			if world.get_instance(kid).name == named:
				return kid
			stack.append(kid)
	return 0

## Where a named part of a named accessory rides, in the body's own frame; INF if not worn.
func _at(accessory: String, part: String) -> Vector3:
	var acc := _id(accessory)
	if acc == 0:
		return Vector3.INF
	for kid in world.get_child_ids(acc):
		if world.get_instance(kid).name == part:
			return world.part_offset(kid).origin
	return Vector3.INF

## Builds a hat on the first player: a Handle at the head attachment and a cylinder above it.
## `turned` puts the 90-degree turn on the Handle itself; otherwise an invisible speck carries
## the attachment and the cylinder keeps its own turn -- the shape `accessory()` builds.
func _wear(name: String, turned: bool) -> void:
	var handle := ('''
local h = Instance.new("Part")
h.Name = "Handle"
h.Size = Vector3.new(0.16, 3.5, 3.5)
h.Orientation = Vector3.new(0, 0, 90)
''' if turned else '''
local h = Instance.new("Part")
h.Name = "Handle"
h.Size = Vector3.new(0.05, 0.05, 0.05)
h.Transparency = 1
''')
	world.run_chunk("worn_probe", '''
local ch = game:GetService("Players"):GetPlayers()[1].Character
local acc = Instance.new("Accessory")
acc.Name = "%s"
%s
h.CanCollide = false
h.Massless = true
h.Position = Vector3.new(0, 0.08, 0)
h.Parent = acc
local a = Instance.new("Attachment")
a.Name = "HatAttachment"
a.Position = Vector3.new(0, -0.08, 0)
a.Parent = h

-- The point of the hat, three studs up in worn space and stood on end by its own turn.
local tip = Instance.new("Part")
tip.Name = "Tip"
tip.Shape = Enum.PartType.Cylinder
tip.Size = Vector3.new(0.45, 0.5, 0.5)
tip.Orientation = Vector3.new(0, 0, 90)
tip.Position = Vector3.new(0, 3.3, 0)
tip.CanCollide = false
tip.Massless = true
tip.Parent = acc

acc.Parent = ch
''' % [name, handle])
	await create_timer(1.5).timeout

func _run() -> void:
	await create_timer(4.0).timeout
	check(_id("Head") != 0, "there is a head to put a hat on")

	# ---- an untuned Handle ---------------------------------------------------------------
	await _wear("GoodHat", false)
	var tip := _at("GoodHat", "Tip")
	check(tip != Vector3.INF, "the hat is worn")
	if tip == Vector3.INF:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	# 3.3 studs of hat over a head that rides about 1.5 above the root, so the tip clears 4.
	check(tip.y > 4.0, "its tip is above the head: y = %.2f" % tip.y)
	check(absf(tip.x) < 0.5 and absf(tip.z) < 0.5,
		"and over the middle of it, not off to one side: x = %.2f, z = %.2f" % [tip.x, tip.z])
	check(tip.y > absf(tip.x) * 4.0, "the hat points UP -- which is the whole of this test")

	# ---- a turned Handle, as the published Wizard Hat has ---------------------------------
	await _wear("BadHat", true)
	var bad := _at("BadHat", "Tip")
	check(bad != Vector3.INF, "the turned-Handle hat is worn too")
	if bad != Vector3.INF:
		check(absf(bad.x) > 2.0,
			"and lies on its side, as the published Wizard Hat does: x = %.2f, y = %.2f" % [bad.x, bad.y])
		check(bad.y < tip.y - 2.0,
			"its tip never gets above the head (%.2f against %.2f)" % [bad.y, tip.y])

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

# Un-anchoring a welded assembly at runtime lets it fall.
#
#   godot --headless --path . -s res://tests/unanchor_test.gd
#
# A welded assembly is one body, static or rigid by its root part's Anchored. The root is the
# anchored member if there is one and otherwise the biggest, so unanchoring the anchored part
# moves the root only when it was not also the biggest. Both shapes are checked.
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
	print("un-anchoring something that is welded together")
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

## Builds an anchored Chassis with a Seat welded on top at 300 studs, unanchors it, and returns
## how far it fell in 1.5s. Negative if the rig never reported.
func _try(tag: String, chassis: Vector3, seat: Vector3) -> float:
	said.clear()
	world.run_chunk("build", """
local ws = workspace
local old = ws:FindFirstChild("Rig")
if old then old:Destroy() end
local rig = Instance.new("Model")
rig.Name = "Rig"
rig.Parent = ws

local chassis = Instance.new("Part")
chassis.Name = "Chassis"
chassis.Size = Vector3.new(%f, %f, %f)
chassis.Position = Vector3.new(0, 300, 0)
chassis.Anchored = true
chassis.Parent = rig

local seat = Instance.new("Part")
seat.Name = "Seat"
seat.Size = Vector3.new(%f, %f, %f)
seat.Position = Vector3.new(0, 300 + %f, 0)
seat.Anchored = false
seat.Parent = rig

local weld = Instance.new("WeldConstraint")
weld.Part0 = chassis
weld.Part1 = seat
weld.Parent = chassis
print("BUILT")
""" % [chassis.x, chassis.y, chassis.z, seat.x, seat.y, seat.z, (chassis.y + seat.y) / 2.0])
	await create_timer(1.2).timeout

	world.run_chunk("drop", """
local ws = workspace
local rig = ws:FindFirstChild("Rig")
local chassis = rig:FindFirstChild("Chassis")
local was = chassis.Position.Y
chassis.Anchored = false
task.wait(1.5)
print(("FELL %.2f"):format(was - chassis.Position.Y))
""")
	await create_timer(3.0).timeout
	var rows := _lines("FELL ")
	return float(String(rows[rows.size() - 1])) if rows.size() > 0 else -1.0

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(2.0).timeout

	# The anchored part is the biggest, so it keeps the root and nothing forces a rebuild.
	var kept := await _try("keeps the root", Vector3(12, 2, 6), Vector3(2, 2, 2))
	check(kept > 5.0,
		"an assembly whose anchored part is the biggest falls when it is let go: %.2f studs"
		% kept)

	# The other way round: the anchored part is the smaller, so the root passes to the seat.
	var handed := await _try("hands it over", Vector3(2, 2, 2), Vector3(12, 2, 6))
	check(handed > 5.0,
		"and so does one whose anchored part is the smaller: %.2f studs" % handed)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

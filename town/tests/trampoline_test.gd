# The roof trampolines: they throw you across the town and not off it.
#
#   godot --headless --path . -s res://tests/trampoline_test.gd
#
# Three claims: a pad throws you; it throws you INWARD, since a pad turned round in the map
# file fires everyone into the void; and the distances vary over a run, which a constant throw
# would not while still passing the first two.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []
var lit := false

const EDGE := 70.0        # the Ground is 140 square, so the map is +/- this

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the trampolines on the roofs")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		said.append(line)
		if line.begins_with("intro:"): lit = true)
	get_root().add_child(main)
	# Nothing here watches the intro, so players are let in as they join (tests/Arrive.gd).
	Arrive.now(world)
	_run()

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var at := String(line).find(prefix)
		if at >= 0:
			out.append(String(line).substr(at + prefix.length()).strip_edges())
	return out

## Rides `pad` and returns "name|fromX|fromZ|toX|toZ|toY|apex above the pad", or "none" if the
## map has no such pad, or "" if nothing came back in time.
func _ride(pad: String) -> String:
	said.clear()
	# replace(), not %: the chunk carries Lua format specifiers that GDScript's % would eat.
	world.run_chunk("ride", ("""
local Players = game:GetService("Players")
local map = workspace:WaitForChild("Map")
local pad = map:FindFirstChild("PAD_NAME", true)
if not pad then print("RODE none") return end
local player = Players:GetPlayers()[1]
local root = player.Character:WaitForChild("HumanoidRootPart")

-- Dropped onto it from above, which is how a player meets one. Not planted on it: a
-- character placed at the pad's own height has its capsule inside the pad, and a launch out
-- of a solid is a launch the sweep cancels -- which looked exactly like the throw having no
-- height to it.
local padY = pad.Position.Y
-- Placed still, and alive. A teleport does not clear your velocity now that momentum is
-- carried, so without this each ride begins with whatever the LAST throw left in the body --
-- and the sideways gain turns that into a launch off the map, which is a real thing to be
-- able to do on purpose and not what a straight-on ride is meant to measure.
root.CFrame = CFrame.new(pad.Position + Vector3.new(0, 6, 0))
root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
local hum = player.Character:WaitForChild("Humanoid")
hum.Health = hum.MaxHealth
local from = root.Position

-- Long enough for the whole arc plus the fall at the end of it.
-- Sampled from the moment of the drop, not after it. Waiting for the launch before starting
-- to watch means the apex has already been and gone -- at this gravity it arrives half a
-- second in -- and what gets recorded is the highest point of the way DOWN.
local settled = 0
local last = root.Position
local peak = root.Position.Y
for _ = 1, 200 do
	task.wait(0.05)
	local now = root.Position
	if now.Y > peak then peak = now.Y end
	if (now - last).Magnitude < 0.3 then settled += 1 else settled = 0 end
	last = now
	-- Settled, and only once it has actually been thrown: it sits on the pad for a beat
	-- before the touch registers, and that is six quiet samples on its own.
	if settled >= 10 and peak > padY + 6 then break end
end
print(("RODE %s|%.1f|%.1f|%.1f|%.1f|%.1f|%.1f"):format(pad.Name,
	from.X, from.Z, root.Position.X, root.Position.Z, root.Position.Y, peak - padY))
""").replace("PAD_NAME", pad))
	# 16s: the arc plus the wait for the body to settle takes about ten.
	await create_timer(16.0).timeout
	var rows := _lines("RODE ")
	return String(rows[rows.size() - 1]) if rows.size() > 0 else ""

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(3.0).timeout

	var counted := _lines("trampolines: ")
	check(counted.size() > 0 and String(counted[0]).begins_with("8 "),
		"eight pads, two on each of the four roofs: %s" % str(counted))

	# One pad per corner, so a reversed pad cannot hide behind one that points the right way.
	var pads := {
		"TrampolineWestNorth": Vector3(1, 0, 0),     # the west shop throws you east
		"TrampolineEastSouth": Vector3(-1, 0, 0),
		"TrampolineHallWest": Vector3(0, 0, -1),     # the south hall throws you north
		"TrampolineBankEast": Vector3(0, 0, 1),
	}
	var reaches: Array[float] = []
	for name in pads:
		var told := await _ride(name)
		if told == "":
			check(false, "%s: the ride said nothing back in time" % name)
			continue
		if told == "none":
			check(false, "%s: no pad of that name in the map" % name)
			continue
		var b: PackedStringArray = told.split("|")
		var from := Vector2(float(b[1]), float(b[2]))
		var to := Vector2(float(b[3]), float(b[4]))
		var want: Vector3 = pads[name]
		var flat := Vector2(want.x, want.z)
		var went := (to - from)
		reaches.append(went.length())

		check(went.length() > 8.0,
			"%s throws you somewhere: %.0f studs" % [name, went.length()])
		check(went.normalized().dot(flat) > 0.7,
			"%s throws you INWARD, toward the middle: %s" % [name, str(to)])
		check(abs(to.x) < EDGE and abs(to.y) < EDGE,
			"%s leaves you on the map: %s" % [name, str(to)])
		check(float(b[5]) > -6.0,
			"%s and above the floor rather than under it: y %.1f" % [name, float(b[5])])
		# The apex is RISE whatever the distance, and PULL's launch speed is derived from it,
		# so an apex that is not thirty studs means PULL is wrong.
		check(abs(float(b[6]) - 30.0) < 6.0,
			"%s goes up about thirty studs, as they all do: %.0f" % [name, float(b[6])])

	# Four rides is a small sample: this asks only that the spread is not nought.
	if reaches.size() >= 3:
		var lo: float = reaches[0]
		var hi: float = reaches[0]
		for r in reaches:
			lo = min(lo, r)
			hi = max(hi, r)
		check(hi - lo > 10.0,
			"and not every throw is the same length: %.0f to %.0f studs" % [lo, hi])

	# The bed is a Part in the map file: a stretch that does nothing looks like one never wired.
	said.clear()
	world.run_chunk("flex", """
local Players = game:GetService("Players")
local map = workspace:WaitForChild("Map")
local pad = map:FindFirstChild("TrampolineWestNorth", true)
local bed = pad:FindFirstChild("TrampolineWestNorthBed")
local wasSize, wasAt = bed.Size, bed.Position
local char = Players:GetPlayers()[1].Character
local root = char:WaitForChild("HumanoidRootPart")
char:WaitForChild("Humanoid").Health = char.Humanoid.MaxHealth
root.CFrame = CFrame.new(pad.Position + Vector3.new(0, 6, 0))
root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
local small, far = bed.Size.X, 0
for _ = 1, 120 do
	task.wait()
	if bed.Size.X < small then small = bed.Size.X end
	local moved = (bed.Position - wasAt).Magnitude
	if moved > far then far = moved end
end
print(("FLEX shrank=%.2f moved=%.2f back=%s"):format(
	small / wasSize.X, far, tostring((bed.Size - wasSize).Magnitude < 0.01
		and (bed.Position - wasAt).Magnitude < 0.01)))
""")
	await create_timer(6.0).timeout
	var flex := _lines("FLEX ")
	check(flex.size() > 0 and String(flex[0]).find("back=true") >= 0,
		"the fabric ends up back where it started: %s" % str(flex))
	if flex.size() > 0:
		var f := String(flex[0])
		var shrank := float(f.substr(f.find("shrank=") + 7).split(" ")[0])
		var moved := float(f.substr(f.find("moved=") + 6).split(" ")[0])
		check(shrank < 0.75, "it shrinks toward its middle: down to %.0f%%" % (shrank * 100))
		# 0.425 studs is all there is between the sheet's face and the frame's before it buries.
		check(moved > 0.2, "and sinks back into its own face: %.2f studs" % moved)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

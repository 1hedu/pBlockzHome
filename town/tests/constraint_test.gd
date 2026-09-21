# Constraint properties, measured rather than looked at: per-axis force caps, reaction force,
# winch force, ball-socket friction and RotateP's BaseAngle. Each check drops a body, waits,
# and reads where it ended up.
#
#   godot --headless --path . -s res://tests/constraint_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("constraints")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, t): said.append(t))
	get_root().add_child(main)
	_run()

func _ask(body: String, wait := 1.2) -> Array[String]:
	said.clear()
	world.run_chunk("constraint_probe", body)
	await create_timer(wait).timeout
	return said.duplicate()

func _one(body: String, wait := 1.2) -> float:
	var out := await _ask(body, wait)
	for line in out:
		if line.begins_with("N "): return float(line.substr(2))
	return NAN

func _run() -> void:
	await create_timer(3.0).timeout

	# ---- AlignPosition.MaxAxesForce ------------------------------------------------------
	# Force up Y and none sideways: it holds its height and stays where it started sideways,
	# which is what a single magnitude cap cannot express.
	var drift := await _one('''
local anchor = Instance.new("Part")
anchor.Name = "Anchor" anchor.Anchored = true anchor.Size = Vector3.new(1, 1, 1)
anchor.Position = Vector3.new(200, 100, 0) anchor.Transparency = 1 anchor.Parent = workspace
local a0 = Instance.new("Attachment") a0.Parent = anchor

local body = Instance.new("Part")
body.Name = "Held" body.Size = Vector3.new(2, 2, 2)
body.Position = Vector3.new(210, 100, 0)     -- ten studs to the side of the goal
body.Parent = workspace
local a1 = Instance.new("Attachment") a1.Parent = body

local ap = Instance.new("AlignPosition")
ap.Attachment0 = a1
ap.Attachment1 = a0
ap.ForceLimitMode = Enum.ForceLimitMode.PerAxis
ap.ForceRelativeTo = Enum.ActuatorRelativeTo.World
ap.MaxAxesForce = Vector3.new(0, 1000000, 0) -- up and down only
ap.Responsiveness = 40
ap.Parent = body
task.wait(2.5)
print("N " .. tostring(body.Position.X) .. "|" .. tostring(body.Position.Y))
''', 4.0)
	var bits := []
	for line in said:
		if line.begins_with("N "): bits = line.substr(2).split("|")
	check(bits.size() == 2, "the held body reported where it got to")
	if bits.size() == 2:
		var x := float(bits[0])
		var y := float(bits[1])
		check(absf(x - 210.0) < 1.0,
			"a cap of zero sideways means it never moves sideways: %.2f (started at 210)" % x)
		check(absf(y - 100.0) < 2.0,
			"and a cap up the Y axis holds it against gravity: %.2f (goal 100)" % y)

	# ---- ReactionForceEnabled ------------------------------------------------------------
	# Both bodies loose: the equal-and-opposite lands on Attachment1's end, so the far body
	# is pulled in too.
	var moved := await _one('''
local function loose(name, x)
	local p = Instance.new("Part")
	p.Name = name p.Size = Vector3.new(2, 2, 2) p.Position = Vector3.new(300, 300, x)
	p.Parent = workspace
	local a = Instance.new("Attachment") a.Parent = p
	return p, a
end
local one, a1 = loose("Chaser", 0)
local two, a2 = loose("Chased", 20)
two.Anchored = false
local ap = Instance.new("AlignPosition")
ap.Attachment0 = a1
ap.Attachment1 = a2
ap.ReactionForceEnabled = true
ap.Responsiveness = 25
ap.MaxForce = 40000
ap.Parent = one
local from = two.Position.Z
task.wait(2.0)
print("N " .. tostring(math.abs(two.Position.Z - from)))
''', 3.5)
	check(moved > 0.5, "with ReactionForceEnabled the far end is pulled too: %.2f studs" % moved)

	var still := await _one('''
local function loose(name, x)
	local p = Instance.new("Part")
	p.Name = name p.Size = Vector3.new(2, 2, 2) p.Position = Vector3.new(400, 300, x)
	p.Parent = workspace
	local a = Instance.new("Attachment") a.Parent = p
	return p, a
end
local one, a1 = loose("Chaser2", 0)
local two, a2 = loose("Chased2", 20)
local ap = Instance.new("AlignPosition")
ap.Attachment0 = a1
ap.Attachment1 = a2
ap.ReactionForceEnabled = false
ap.Responsiveness = 25
ap.MaxForce = 40000
ap.Parent = one
local from = two.Position.Z
task.wait(2.0)
-- Only what the align did to it, not what gravity did: the Z axis alone.
print("N " .. tostring(math.abs(two.Position.Z - from)))
''', 3.5)
	# Relative, not an absolute threshold: two loose boxes nudge each other a little whatever
	# the constraint does.
	check(still < moved / 3.0,
		"and without it the far end is left alone: %.2f studs against %.2f" % [still, moved])

	# ---- RopeConstraint.WinchForce -------------------------------------------------------
	# The same rope, target and speed twice; only WinchForce differs.
	var hauled := await _one('''
local top = Instance.new("Part")
top.Name = "Gantry" top.Anchored = true top.Size = Vector3.new(2, 2, 2)
top.Position = Vector3.new(500, 200, 0) top.Parent = workspace
local a0 = Instance.new("Attachment") a0.Parent = top
local load = Instance.new("Part")
load.Name = "Load" load.Size = Vector3.new(6, 6, 6)
load.Position = Vector3.new(500, 180, 0) load.Parent = workspace
local a1 = Instance.new("Attachment") a1.Parent = load
local rope = Instance.new("RopeConstraint")
rope.Attachment0 = a0 rope.Attachment1 = a1
rope.Length = 20
rope.WinchEnabled = true
rope.WinchTarget = 2
rope.WinchSpeed = 8
rope.WinchForce = 5
rope.Parent = top
task.wait(3.0)
print("N " .. tostring(top.Position.Y - load.Position.Y))
''', 4.5)
	check(hauled > 10.0,
		"a winch with five newtons cannot lift a six-stud block: still %.1f studs down" % hauled)

	var lifted := await _one('''
local top = Instance.new("Part")
top.Name = "Gantry2" top.Anchored = true top.Size = Vector3.new(2, 2, 2)
top.Position = Vector3.new(600, 200, 0) top.Parent = workspace
local a0 = Instance.new("Attachment") a0.Parent = top
local load = Instance.new("Part")
load.Name = "Load2" load.Size = Vector3.new(6, 6, 6)
load.Position = Vector3.new(600, 180, 0) load.Parent = workspace
local a1 = Instance.new("Attachment") a1.Parent = load
local rope = Instance.new("RopeConstraint")
rope.Attachment0 = a0 rope.Attachment1 = a1
rope.Length = 20
rope.WinchEnabled = true
rope.WinchTarget = 2
rope.WinchSpeed = 8
rope.WinchForce = 500000
rope.Parent = top
task.wait(3.0)
print("N " .. tostring(top.Position.Y - load.Position.Y))
''', 4.5)
	check(lifted < 6.0, "and with enough force it comes all the way up: %.1f studs down" % lifted)

	# ---- BallSocketConstraint.MaxFrictionTorque ------------------------------------------
	# Two pendulums let go horizontal, compared by angular velocity rather than by how far
	# they fell: friction slows a joint, it does not hold a weight up, so both end hanging
	# down and only the free one is still swinging.
	await _one('''
local function pendulum(name, x, friction)
	local pin = Instance.new("Part")
	pin.Anchored = true pin.Size = Vector3.new(1, 1, 1)
	pin.Position = Vector3.new(x, 150, 0) pin.Parent = workspace
	local a0 = Instance.new("Attachment") a0.Parent = pin
	-- Lying along X, hung from the end nearest the pin: gravity has a full lever arm on it.
	local arm = Instance.new("Part")
	arm.Name = name arm.Size = Vector3.new(10, 1, 1)
	arm.Position = Vector3.new(x + 5, 150, 0) arm.Parent = workspace
	local a1 = Instance.new("Attachment") a1.Position = Vector3.new(-5, 0, 0) a1.Parent = arm
	local bs = Instance.new("BallSocketConstraint")
	bs.Attachment0 = a0 bs.Attachment1 = a1
	bs.MaxFrictionTorque = friction
	bs.Parent = pin
	return arm
end
local free = pendulum("FreeArm", 700, 0)
local stiff = pendulum("StiffArm", 760, 4000000)
task.wait(1.5)
print("N " .. tostring(free.AssemblyAngularVelocity.Magnitude) .. "|" .. tostring(stiff.AssemblyAngularVelocity.Magnitude))
''', 3.5)
	var spins := []
	for line in said:
		if line.begins_with("N "): spins = line.substr(2).split("|")
	check(spins.size() == 2, "both pendulums reported their spin")
	if spins.size() == 2:
		var loose_w := float(spins[0])
		var stiff_w := float(spins[1])
		check(loose_w > 1.0, "a frictionless joint is still swinging: %.2f rad/s" % loose_w)
		check(stiff_w < loose_w / 3.0,
			"and friction has all but stopped the other: %.2f rad/s against %.2f" % [stiff_w, loose_w])

	# ---- DynamicRotate.BaseAngle ---------------------------------------------------------
	# RotateP is the legacy servo: it turns to DesiredAngle, and BaseAngle is the zero that
	# angle is measured from, so moving the base swings the whole range on its own.
	var turned := await _one('''
local hinge = Instance.new("Part")
hinge.Name = "Post" hinge.Anchored = true hinge.Size = Vector3.new(1, 4, 1)
hinge.Position = Vector3.new(900, 100, 0) hinge.Parent = workspace
-- The legacy hinge turns about C0's Z, so the leaf hangs along X and swings up into Y.
local door = Instance.new("Part")
door.Name = "Leaf" door.Size = Vector3.new(6, 4, 1)
door.Position = Vector3.new(903, 100, 0) door.Parent = workspace
local j = Instance.new("RotateP")
j.Part0 = hinge
j.Part1 = door
j.C0 = CFrame.new(0, 0, 0)
j.C1 = CFrame.new(-3, 0, 0)
j.BaseAngle = math.pi / 2      -- a quarter turn of base
j.DesiredAngle = 0             -- and nothing asked for on top of it
j.MaxVelocity = 0.2
j.Parent = hinge
task.wait(3.0)
-- Turned a quarter about Z, the leaf swings from beside the post to above it.
print("N " .. tostring(door.Position.Y - 100))
''', 4.5)
	check(turned > 1.5,
		"a quarter turn of BaseAngle swings the leaf a quarter round with nothing asked for on top: %.2f studs up" % turned)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

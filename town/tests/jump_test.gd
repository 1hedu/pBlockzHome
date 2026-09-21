# The ordinary jump: how high, and how far.
#
#   godot --headless --path . -s res://tests/jump_test.gd
#
# JumpPower 50 against gravity 196.2 is Roblox's own pair; a full-control jump covers 8.2
# studs of ground. Height and distance are both measured, and so is what the air push has to
# leave alone: a trampoline throw steered against must still survive.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld

## Every script error the server threw while this ran; the last check asserts it is empty.
var errors: Array[String] = []
var said: Array[String] = []
var lit := false

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the ordinary jump, and what a throw does with it")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	# The default controls write moveDir every frame -- no keys down means a direction of
	# nought -- so they stomp a scripted Humanoid:Move and every distance reads zero.
	world.default_controls = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		said.append(line)
		if String(line).begins_with("intro:"): lit = true)
	get_root().add_child(main)
	_run()

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var i := String(line).find(prefix)
		if i >= 0:
			out.append(String(line).substr(i + prefix.length()).strip_edges())
	return out

func _num(row: String, after: String) -> float:
	return float(row.substr(row.find(after) + after.length()).split(" ")[0])

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(22.0).timeout

	said.clear()
	world.run_chunk("jump", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players:GetPlayers()[1]
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")
print(("SETUP jumpPower=%.1f gravity=%.1f walkSpeed=%.1f"):format(
	hum.JumpPower, workspace.Gravity, hum.WalkSpeed))

--- One jump, holding `dir` for the whole flight. Reports the apex and the ground covered.
---
--- Move is called every frame rather than once, which is what a control script does with a
--- key held -- MoveDirection is "until the next one" and the host reads it each step.
local function hop(dir)
	hum:Move(Vector3.new(0, 0, 0), false)
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	task.wait(0.7)
	local from = root.Position
	local floor = from.Y
	hum.Jump = true
	local peak, up = floor, false
	for _ = 1, 200 do
		RunService.Heartbeat:Wait()
		if dir.Magnitude > 0 then hum:Move(dir, false) end
		local y = root.Position.Y
		if y > peak then peak = y end
		-- Only start watching for the landing once they have actually left: the first frame
		-- is still on the floor, and a landing test that runs then ends the jump at nought.
		if y > floor + 0.5 then up = true end
		if up and y <= floor + 0.2 then break end
	end
	local to = root.Position
	hum:Move(Vector3.new(0, 0, 0), false)
	task.wait(0.3)
	return peak - floor, Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
end

local highStill, farStill = hop(Vector3.new(0, 0, 0))
print(("STILL apex %.2f studs, covered %.2f studs"):format(highStill, farStill))
local highHeld, farHeld = hop(Vector3.new(0, 0, -1))
print(("HELD apex %.2f studs, covered %.2f studs"):format(highHeld, farHeld))

-- A throw, steered against the whole way. Steering may TURN a throw but takes no speed out of
-- it, so leaning back into one must not brake it.
local function throw(steer)
	hum:Move(Vector3.new(0, 0, 0), false)
	root.CFrame = root.CFrame + Vector3.new(0, 3, 0)
	task.wait(0.4)
	local from = root.Position
	-- Up and along, about what a trampoline gives: 108 up is a thirty-stud arc.
	root.AssemblyLinearVelocity = Vector3.new(0, 108, -50)
	local floor = from.Y
	local up = false
	for _ = 1, 400 do
		RunService.Heartbeat:Wait()
		if steer.Magnitude > 0 then hum:Move(steer, false) end
		local y = root.Position.Y
		if y > floor + 2 then up = true end
		if up and y <= floor + 0.3 then break end
	end
	local to = root.Position
	hum:Move(Vector3.new(0, 0, 0), false)
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	task.wait(0.5)
	return Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
end

local free = throw(Vector3.new(0, 0, 0))
local against = throw(Vector3.new(0, 0, 1))
print(("THROW left alone %.1f studs, leaned against %.1f studs"):format(free, against))
""")
	await create_timer(30.0).timeout

	var setup := _lines("SETUP ")
	check(setup.size() > 0, "the character's own numbers were read: %s" % str(setup))
	if setup.size() > 0:
		var row := String(setup[0])
		check(abs(_num(row, "jumpPower=") - 50.0) < 0.01,
			"JumpPower is Roblox's 50: %s" % row)
		check(abs(_num(row, "gravity=") - 196.2) < 0.01, "against Roblox's gravity")

	var still := _lines("STILL ")
	check(still.size() > 0, "a jump from a standstill was measured: %s" % str(still))
	if still.size() > 0:
		var row := String(still[0])
		# v^2 / 2g = 50^2 / 392.4 = 6.37, plus a frame of overshoot at 60 Hz.
		check(abs(_num(row, "apex ") - 6.4) < 0.6,
			"and goes up about six and a third studs, as JumpPower says: %s" % row)
		check(_num(row, "covered ") < 0.5,
			"straight up when nothing is held: %s" % row)

	var held := _lines("HELD ")
	check(held.size() > 0, "and one with a direction held: %s" % str(held))
	if held.size() > 0 and still.size() > 0:
		var row := String(held[0])
		check(abs(_num(row, "apex ") - _num(String(still[0]), "apex ")) < 0.4,
			"the same height -- steering does not lift you: %s" % row)
		# 0.51 s in the air at 16 studs a second is 8.2.
		check(_num(row, "covered ") > 7.0,
			"and carries you the full walking speed the whole way: %s" % row)

	var thrown := _lines("THROW ")
	check(thrown.size() > 0, "a throw was measured both ways: %s" % str(thrown))
	if thrown.size() > 0:
		var row := String(thrown[0])
		var free := _num(row, "left alone ")
		var against := _num(row, "leaned against ")
		check(free > 30.0, "a throw goes a long way when left alone: %.1f studs" % free)
		# Steering may turn a throw; it may not take speed out of it.
		check(against > free * 0.55,
			"and leaning back against it does not cancel it: %.1f against %.1f" % [against, free])

	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

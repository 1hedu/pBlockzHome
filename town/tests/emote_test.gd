# /wave, /sit, /lay and /roll put the limbs where the emote says, signs included.
# Sampled off the limbs, not off playback state: an animation that poses nothing still plays.
#
#   godot --headless --path . -s res://tests/emote_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("emotes")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, t): said.append(t))
	get_root().add_child(main)
	# A character on join, skipping the town's nine-second arrival (tests/Arrive.gd).
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

## The drawn limb, in the body's own frame. Poses land on the mesh nodes every frame; the
## instance's `offset` is never written. SubViewports hold the wardrobe's preview doll.
func _limb(named: String) -> Transform3D:
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SubViewport:
			continue
		if n is CharacterBody3D:
			for c in n.get_children():
				if c is MeshInstance3D and String(c.name) == named:
					return (c as MeshInstance3D).transform
		for c in n.get_children():
			stack.append(c)
	return Transform3D()

## Types a line into RBXGeneral from the client, as the chat box does.
func _say(line: String, wait := 1.6) -> void:
	said.clear()
	world.run_client_chunk("emote_probe", '''
local TextChatService = game:GetService("TextChatService")
local general = TextChatService:WaitForChild("TextChannels"):WaitForChild("RBXGeneral")
general:SendAsync("%s")
''' % line)
	await create_timer(wait).timeout

func _run() -> void:
	await create_timer(4.0).timeout
	check(_id("Right Arm") != 0, "there is a body to move")
	if _id("Right Arm") == 0:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	var restArm := _limb("Right Arm")
	var restTorso := _limb("Torso")
	var restLeg := _limb("Right Leg")

	# ---- /wave ---------------------------------------------------------------------------
	# Sampled mid-wave: a finished wave reads the same as one that never started.
	await _say("/wave", 0.6)
	var waving := _limb("Right Arm")
	check(waving.origin.y > restArm.origin.y + 0.3,
		"a wave lifts the right arm: y %.2f from %.2f" % [waving.origin.y, restArm.origin.y])
	check(absf(_limb("Left Arm").origin.y - restArm.origin.y) < 0.4,
		"and leaves the other one alone, which is what naming one limb means")
	await create_timer(2.0).timeout
	check(absf(_limb("Right Arm").origin.y - restArm.origin.y) < 0.3,
		"and it comes back down on its own: a wave is a thing you do, not a thing you are")

	# ---- /sit ----------------------------------------------------------------------------
	await _say("/sit")
	var sitLeg := _limb("Right Leg")
	# -Z is forward: a leg swung about the hip lands in front of where it hung, and higher.
	check(sitLeg.origin.z < restLeg.origin.z - 0.8,
		"sitting puts the legs out in front: z %.2f from %.2f" % [sitLeg.origin.z, restLeg.origin.z])
	check(sitLeg.origin.y > restLeg.origin.y + 0.5, "and off the floor rather than through it")
	# A Pose is a delta in its own joint's frame and the two hips face opposite ways, so one
	# angle applied to both sends one leg forward and the other back.
	var sitLegL := _limb("Left Leg")
	check(sitLegL.origin.z < restLeg.origin.z - 0.8,
		"and the OTHER leg goes the same way, not the opposite one: z %.2f" % sitLegL.origin.z)
	# The drop is HipHeight, not the pose: posing alone leaves the body sitting in mid air.
	var hip := await _number('''
local h = game:GetService("Players"):GetPlayers()[1].Character:FindFirstChildOfClass("Humanoid")
print("N " .. tostring(h.HipHeight))
''')
	check(hip < -1.0, "and the body is lowered to the ground: HipHeight %.2f" % hip)

	# Sitting holds: a one-shot animation would look the same a moment after it was typed.
	await create_timer(2.5).timeout
	check(_limb("Right Leg").origin.z < restLeg.origin.z - 0.8,
		"and stays sat down, because sitting is a thing you are")

	# ---- standing up ----------------------------------------------------------------------
	# MoveDirection also stands you up, but it is rewritten every frame from client input, so
	# a write from here never lasts. Moving the root is the half a test can drive.
	world.run_chunk("emote_walk", '''
local ch = game:GetService("Players"):GetPlayers()[1].Character
local r = ch:FindFirstChild("HumanoidRootPart")
r.CFrame = r.CFrame + Vector3.new(8, 0, 0)
''')
	await create_timer(1.6).timeout
	check(absf(_limb("Right Leg").origin.z - restLeg.origin.z) < 0.5,
		"straying stands you up: z %.2f" % _limb("Right Leg").origin.z)
	var after := await _number('''
local h = game:GetService("Players"):GetPlayers()[1].Character:FindFirstChildOfClass("Humanoid")
print("N " .. tostring(h.HipHeight))
''')
	check(absf(after) < 0.01, "and gives you your height back: HipHeight %.2f" % after)

	# ---- /lay ----------------------------------------------------------------------------
	await create_timer(0.8).timeout
	await _say("/lay")
	var laid := _limb("Torso")
	# Head, arms and legs all hang off the Torso, so one rotation of it lays the body down.
	check(laid.basis.y.dot(Vector3.UP) < 0.3,
		"lying down turns the whole body over: torso up . world up = %.2f (was %.2f)"
		% [laid.basis.y.dot(Vector3.UP), restTorso.basis.y.dot(Vector3.UP)])
	# The head keeps pointing the way you faced, so the torso's up axis ends up along -Z.
	check(laid.basis.y.z < -0.9,
		"and lands you on your BACK, head the way you were facing: %.2f" % laid.basis.y.z)
	check(_limb("Head").origin.y < 0.9,
		"the head goes down with it rather than staying up on a stalk: y %.2f" % _limb("Head").origin.y)
	# A part's front is -Z, so face up means it points at the sky. Back and face down are one
	# rotation apart, and the up-axis check above passes either way.
	check(-laid.basis.z.y > 0.9,
		"and on your back rather than your face: chest . up = %.2f" % -laid.basis.z.y)

	# ---- /roll ------------------------------------------------------------------------------
	# /roll turns you over while lying; it does not lie you down.
	await _say("/roll")
	var over := _limb("Torso")
	check(-over.basis.z.y < -0.9,
		"rolling over puts you on your belly: chest . up = %.2f" % -over.basis.z.y)
	check(over.basis.y.z < -0.9,
		"with your head still the way it was, not swapped end for end: %.2f" % over.basis.y.z)
	await _say("/roll")
	check(-_limb("Torso").basis.z.y > 0.9, "and rolling again turns you back over")

	# Every held emote toggles: typing it again stands you up.
	await _say("/lay")
	check(_limb("Torso").basis.y.dot(Vector3.UP) > 0.9,
		"and typing it twice gets you back up: %.2f" % _limb("Torso").basis.y.dot(Vector3.UP))

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## Runs a chunk on the server and reads back the one number it printed.
func _number(body: String) -> float:
	said.clear()
	world.run_chunk("emote_read", body)
	await create_timer(0.8).timeout
	for line in said:
		if line.begins_with("N "): return float(line.substr(2))
	return NAN

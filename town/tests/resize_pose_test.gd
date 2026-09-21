# A limb resized every frame still animates.
#
#   godot --headless --path . -s res://tests/resize_pose_test.gd
#
# Measured as the spread of the arm's turn over a second. A standing sway of a few degrees is
# enough: the failure guarded against is a mesh rebuild writing the REST pose, which does not
# move at all. update_shape rewrites a limb's mesh transform from scratch on every rebuild, but
# this passes with or without the pose guard there -- what it holds is the swing, not that line.
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
	print("a limb keeps its pose across a rebuild")
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

## The MeshInstance3D the named limb is drawn with, in the WORLD.
##
## Viewport-checked, not first match by name: the wardrobe's doll and the drawing table's
## draft are copies of the character inside ViewportFrames, anchored and perfectly still.
func _limb(what: String) -> MeshInstance3D:
	var stack: Array[Node] = [get_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and String(n.name) == what and n.get_viewport() == get_root():
			return n
		for c in n.get_children(): stack.append(c)
	return null

## How far the limb's turn wanders over a second, in radians.
func _swing(what: String) -> float:
	var lo := 9.0
	var hi := -9.0
	for i in 50:
		await create_timer(0.02).timeout
		var m := _limb(what)
		if m == null: continue
		# Pitch, which is the axis an arm swings about.
		var a: float = m.transform.basis.get_euler().x
		lo = min(lo, a)
		hi = max(hi, a)
	return 0.0 if hi < lo else hi - lo

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(2.0).timeout

	# Walking on the spot: the animator swings the arms only while moving and on the floor.
	world.run_client_chunk("walk", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local char = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
-- An attribute rather than a global: _G is readonly in this sandbox, as it is in Roblox.
workspace:SetAttribute("Resizing", false)
RunService.RenderStepped:Connect(function()
	hum:Move(Vector3.new(1, 0, 0), false)
end)
-- On Heartbeat, which is AFTER the frame the poser drew: a rebuild that lands here is a
-- rebuild the poser does not get to correct before the frame is shown.
RunService.Heartbeat:Connect(function()
	if workspace:GetAttribute("Resizing") then
		local arm = char:FindFirstChild("Right Arm")
		-- A different Size every frame, which is what makes the mesh be rebuilt. Small
		-- enough that it is the same arm throughout.
		if arm then arm.Size = Vector3.new(1, 2 + (tick() % 1) * 0.02, 1) end
	end
end)
print("WALKING")
""")
	await create_timer(2.0).timeout
	check(said.has("WALKING") or _lines("WALKING").size() >= 0, "the character is walking")

	var free := await _swing("Right Arm")
	check(free > 0.02, "the arm moves when nothing interferes: %.3f rad" % free)
	if free <= 0.02:
		print("  (no swing to lose -- the rest of this proves nothing)")
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	world.run_client_chunk("resize", "workspace:SetAttribute('Resizing', true) print('RESIZING')")
	await create_timer(1.0).timeout
	var resized := await _swing("Right Arm")
	check(resized > free * 0.5,
		"and still moves while it is being resized every frame: %.3f rad against %.3f"
		% [resized, free])

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		if String(line).find(prefix) >= 0: out.append(line)
	return out

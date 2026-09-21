# A part parented into a ViewportFrame is built in that frame's own world and nowhere else,
# aims from the Camera set as CurrentCamera, and goes away with the frame.
#
#   godot --headless --path . -s res://tests/viewport_test.gd
extends SceneTree

var world: PulseBlockzWorld
var t := 0.0
var passed := 0
var failed := 0
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	print("== viewport frame")
	_run()

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS " + what)
	else:
		failed += 1
		printerr("  FAIL " + what)

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for kid in n.get_children():
		var hit := _find(kid, cls)
		if hit != null:
			return hit
	return null

## A ViewportFrame builds a SubViewport named Viewport holding a World and a Camera.
func _find_frame(n: Node) -> Node:
	if n is SubViewport and n.name == "Viewport" and n.get_node_or_null("World") != null:
		return n
	for kid in n.get_children():
		var hit := _find_frame(kid)
		if hit != null:
			return hit
	return null

func _find_named(n: Node, want: String) -> Node:
	if n.name == want:
		return n
	for kid in n.get_children():
		var hit := _find_named(kid, want)
		if hit != null:
			return hit
	return null

func _bodies_under(n: Node) -> int:
	var count := 0
	if n is StaticBody3D or n is RigidBody3D or n is CharacterBody3D:
		count += 1
	for kid in n.get_children():
		count += _bodies_under(kid)
	return count

func _run() -> void:
	for _i in 40:
		await process_frame

	var before := _bodies_under(world)
	world.run_client_chunk("frame", """
local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local screen = Instance.new("ScreenGui")
screen.Name = "DollTest"
screen.Parent = gui

local frame = Instance.new("ViewportFrame")
frame.Name = "Doll"
frame.Size = UDim2.new(0, 200, 0, 260)
frame.Position = UDim2.new(0, 20, 0, 20)
frame.Parent = screen

local part = Instance.new("Part")
part.Name = "InTheFrame"
part.Size = Vector3.new(2, 2, 2)
part.Anchored = true
part.Parent = frame
""")
	for _i in 40:
		await process_frame

	check(true, "a script can make a ViewportFrame at all")

	# Scoped to this test's panel: the wardrobe and the drawing table keep dolls in viewports
	# of their own, and a SurfaceGui has a SubViewport too.
	var mine := _find_named(world, "DollTest")
	check(mine != null, "the test's own panel is on screen")
	var vp: Node = null if mine == null else _find_frame(mine)
	check(vp != null, "the frame has a world of its own")
	if vp == null:
		done = true
		return
	check(vp.get_node_or_null("World") != null, "with a root to hang things from")
	check(vp.get_node_or_null("Camera") != null, "and a camera looking at it")

	var found := _find_named(world, "InTheFrame")
	print("       the part is at: %s" % [found.get_path() if found != null else "<not built at all>"])
	var inside := _bodies_under(vp)
	check(inside == 1, "the part inside it is built (%d)" % inside)
	var outside := _bodies_under(world) - _bodies_under(mine)
	check(outside == before, "and is not also in the town (%d before, %d outside now)" % [before, outside])

	# CurrentCamera replaces the frame's own framing: it looks from that Camera's CFrame, at its
	# FieldOfView.
	var cam: Camera3D = vp.get_node("Camera")
	var auto_origin := cam.global_transform.origin
	world.run_client_chunk("aim", """
local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local frame = gui.DollTest.Doll
local camera = Instance.new("Camera")
camera.FieldOfView = 25
camera.CFrame = CFrame.lookAt(Vector3.new(9, 1, 0), Vector3.new(0, 0, 0))
camera.Parent = frame
frame.CurrentCamera = camera
""")
	for _i in 30:
		await process_frame
	var o := cam.global_transform.origin
	var ahead := -cam.global_transform.basis.z
	check(o.distance_to(Vector3(9, 1, 0)) < 0.01 and ahead.dot((Vector3.ZERO - Vector3(9, 1, 0)).normalized()) > 0.999,
		"CurrentCamera: the frame looks from the Camera it names (%s, was %s)" % [o, auto_origin])
	check(absf(cam.fov - 25.0) < 0.01, "at its FieldOfView (%.1f)" % cam.fov)

	world.run_client_chunk("gone", """
local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local screen = gui:FindFirstChild("DollTest")
if screen then screen:Destroy() end
""")
	for _i in 40:
		await process_frame
	check(_find_named(world, "DollTest") == null, "closing the panel takes the little world with it")
	check(_bodies_under(world) == before, "and leaves nothing of the part behind")

	print("%d passed, %d failed" % [passed, failed])
	done = true

func _process(delta: float) -> bool:
	t += delta
	if done or t > 90.0:
		if not done: printerr("viewport test did not finish in %.0fs" % t)
		quit(1 if failed > 0 or not done else 0)
	return false

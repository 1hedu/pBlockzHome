# Roblox properties this engine declares. Each is checked for an EFFECT wherever one is
# observable; a check that only proves a written value reads back says so.
#
#   godot --headless --path . -s res://tests/parity_test.gd
extends SceneTree

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

## Cull modes in use across a world's parts. Walks the nodes because the flag lands only on
## the material; the script API has nothing to read back.
func _cull_modes(w: Node) -> Array:
	var found := []
	var stack: Array[Node] = [w]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var m = (n as MeshInstance3D).get_material_override()
			if m is BaseMaterial3D and not found.has(m.cull_mode):
				found.append(m.cull_mode)
		for c in n.get_children():
			stack.append(c)
	return found


func say(w: PulseBlockzWorld, into: Array, source: String) -> void:
	w.script_print.connect(func(_n, t): into.append(t))
	w.script_error.connect(func(n, e): into.append("ERROR %s %s" % [n, e]))
	w.run_chunk("t", source)

func _initialize() -> void:
	print("Roblox parity: properties nothing used to read")
	_run()

func _run() -> void:
	# ---- they exist and hold a value ------------------------------------------------
	var said := []
	var w := PulseBlockzWorld.new()
	w.mode = 1
	get_root().add_child(w)
	say(w, said, """
local h = Instance.new("Humanoid")
h.Parent = workspace
print("JumpHeight default " .. tostring(h.JumpHeight))
h.JumpHeight = 12.5    print("JumpHeight " .. tostring(h.JumpHeight))
print("UseJumpPower " .. tostring(h.UseJumpPower))
h.UseJumpPower = true print("UseJumpPower on " .. tostring(h.UseJumpPower))
local p = Instance.new("Part")
p.Parent = workspace
print("CanTouch " .. tostring(p.CanTouch))
p.CanTouch = false     print("CanTouch off " .. tostring(p.CanTouch))
""")
	await create_timer(1.0).timeout
	var s := "\n".join(said)
	check(s.find("JumpHeight default 7.2") >= 0, "Humanoid.JumpHeight defaults to Roblox's 7.2")
	check(s.find("JumpHeight 12.5") >= 0, "and holds a value")
	check(s.find("UseJumpPower false") >= 0, "Humanoid.UseJumpPower exists, and is false on a new Humanoid as on Roblox")
	check(s.find("UseJumpPower on true") >= 0, "and holds a value")
	check(s.find("CanTouch true") >= 0, "BasePart.CanTouch defaults true")
	check(s.find("CanTouch off false") >= 0, "and holds a value")

	# ---- and they DO something ------------------------------------------------------
	var heard := []
	var w2 := PulseBlockzWorld.new()
	w2.mode = 1
	get_root().add_child(w2)
	say(w2, heard, """
local ws = workspace
local floor = Instance.new("Part")
floor.Anchored = true floor.Size = Vector3.new(40, 1, 40)
floor.Position = Vector3.new(0, 0, 0) floor.Parent = ws

-- CanTouch silences the part it is set on, and only that part: the other side of the
-- same collision still hears it. Two counters, because "nothing happened" would also
-- pass if the parts simply never met.
local quiet = Instance.new("Part")
quiet.Name = "Quiet" quiet.Anchored = true quiet.CanTouch = false
quiet.Size = Vector3.new(8, 1, 8) quiet.Position = Vector3.new(0, 2, 0) quiet.Parent = ws
local faller = Instance.new("Part")
faller.Name = "Faller" faller.Size = Vector3.new(1, 1, 1)
faller.Position = Vector3.new(0, 8, 0) faller.Parent = ws
local q, f = 0, 0
quiet.Touched:Connect(function() q = q + 1 end)
faller.Touched:Connect(function() f = f + 1 end)
task.delay(3, function()
	print(("touch: silenced part heard %d, its partner heard %d"):format(q, f))
end)
""")
	# Real seconds, not frames: headless runs frames as fast as it can, so a frame count
	# elapses in well under the task.delay(3) above.
	await create_timer(5.0).timeout
	var h := "\n".join(heard)
	check(h.find("silenced part heard 0,") >= 0,
		"CanTouch false actually stops that part's Touched firing")
	check(h.find("its partner heard 0") < 0,
		"and the other side of the same collision still hears it")

	# ---- DoubleSided draws the back faces ------------------------------------------
	# The effect lands as a cull mode on the material, so that is what is read. On Roblox it
	# is the only fix for a mesh with reversed winding short of republishing the mesh.
	var w3 := PulseBlockzWorld.new()
	w3.mode = 1
	get_root().add_child(w3)
	say(w3, said, """
local a = Instance.new("Part")
a.Name = "Plain" a.Anchored = true a.Size = Vector3.new(2, 2, 2)
a.Position = Vector3.new(0, 0, 0) a.Parent = workspace
local b = Instance.new("MeshPart")
b.Name = "Sided" b.Anchored = true b.Size = Vector3.new(2, 2, 2)
b.Position = Vector3.new(6, 0, 0) b.DoubleSided = true b.Parent = workspace
print("DoubleSided reads back as " .. tostring(b.DoubleSided))
""")
	await create_timer(1.5).timeout
	var both := _cull_modes(w3)
	check(both.has(BaseMaterial3D.CULL_DISABLED),
		"MeshPart.DoubleSided turns culling off for that part")
	check(both.has(BaseMaterial3D.CULL_BACK),
		"and leaves an ordinary part culling its back faces")

	# ---- Interactable, and where a prompt sits -------------------------------------
	var w4 := PulseBlockzWorld.new()
	w4.mode = 0                                   # solo: GUI input is the client's to press
	get_root().add_child(w4)
	var seen := []
	say(w4, seen, """
local gui = Instance.new("ScreenGui")
gui.Parent = game:GetService("CoreGui")
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 200, 0, 200) panel.Parent = gui
local button = Instance.new("TextButton")
button.Size = UDim2.new(0, 100, 0, 40) button.Parent = panel
button.Activated:Connect(function() print("button fired") end)
print("Interactable defaults " .. tostring(button.Interactable))
-- Switching the PANEL off must silence the button under it, not just the panel.
panel.Interactable = false
print("panel off, button still says " .. tostring(button.Interactable))

local prompt = Instance.new("ProximityPrompt")
prompt.UIOffset = Vector2.new(0, 40)
print("UIOffset " .. tostring(prompt.UIOffset.X) .. "," .. tostring(prompt.UIOffset.Y))
""")
	await create_timer(1.0).timeout
	var g := "
".join(seen)
	check(g.find("Interactable defaults true") >= 0, "GuiObject.Interactable defaults true")
	check(g.find("panel off, button still says true") >= 0,
		"and a switched-off parent does not rewrite its children -- it silences them")
	check(g.find("UIOffset 0,40") >= 0, "ProximityPrompt.UIOffset holds a value")

	# The gate itself -- an Interactable=false object swallowing a click -- is not checked
	# here. It lives in GUI input dispatch, and headless has no window, so AbsoluteSize is
	# 0,0, nothing is hittable and every click misses: a swallowed-click check would pass
	# whether or not the gate exists. It belongs beside tests/bar_click_test.gd, windowed.

	# ---- AbsoluteRotation accumulates -----------------------------------------------
	# Read off the drawn node rather than summed by hand, so it agrees with the screen.
	var rot := []
	var w5 := PulseBlockzWorld.new()
	w5.mode = 0
	get_root().add_child(w5)
	say(w5, rot, """
local gui = Instance.new("ScreenGui")
gui.Parent = game:GetService("CoreGui")
local outer = Instance.new("Frame")
outer.Size = UDim2.new(0, 300, 0, 300) outer.Rotation = 30 outer.Parent = gui
local inner = Instance.new("Frame")
inner.Size = UDim2.new(0, 100, 0, 100) inner.Rotation = 15 inner.Parent = outer
task.delay(2, function()
	print(("rotation outer=%d inner=%d"):format(outer.AbsoluteRotation, inner.AbsoluteRotation))
end)
""")
	await create_timer(3.5).timeout
	# The value is not checked: headless lays out no GUI, so the transform it is read from is
	# identity whatever Rotation says. Listed in tests/WINDOWED.md.
	var r := "
".join(rot)
	check(r.find("rotation outer=") >= 0, "AbsoluteRotation is reported at all (its value needs a window)")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

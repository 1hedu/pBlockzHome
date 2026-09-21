# Where a worn accessory's parts land on the body. An accessory hangs from its Handle and
# every other part is welded relative to that Handle, so the placement is arithmetic.
#
#   node scripts/stage-preview.js crudespoon,pegs <dir>
#   godot --headless --path . -s res://tests/grip_test.gd -- <staged dir>
#
# accessory() renames the first part to Handle and the published Spoonie already has one, so
# the model on chain carries two and a weld's Part1 of "Handle" resolves by hash order.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var stage := ""
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("what a worn thing is holding on by")
	stage = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in (dir.get_files() if dir else PackedStringArray()):
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, t): said.append(t))
	get_root().add_child(main)
	# Nothing runs the intro here, so players are let in as they connect.
	Arrive.now(world)
	_run()

## Wears one staged item and returns the probe's "N <name> <value>" lines as a Dictionary.
## Found by the name the model gives itself, not the catalogue key: crudespoon is "Spoonie".
func _wear(key: String, probe: String) -> Dictionary:
	var json := FileAccess.get_file_as_string(stage.path_join("%s.json" % key))
	json = json.replace(stage.replace("\\", "/") + "/", "user://preview/")
	world.add_model("ReplicatedStorage/OnChain", key, json)
	said.clear()
	world.run_chunk("grip", WEAR % [_named(key), probe])
	await create_timer(1.4).timeout
	var out := {}
	for line in said:
		if line.begins_with("N "):
			var bits := line.substr(2).split(" ", true, 1)
			if bits.size() >= 2:
				out[bits[0]] = bits[1]
	return out

const WEAR := """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local src = rs:WaitForChild("OnChain", 2):FindFirstChild("%s")
local ch = Players:GetPlayers()[1].Character
local hum = ch:FindFirstChildOfClass("Humanoid")
-- One garment at a time, and the old one collected before it is destroyed: removing from the
-- list you are walking skips every other entry.
local old = {}
for _, d in ipairs(ch:GetChildren()) do
	if d:IsA("Accoutrement") then table.insert(old, d) end
end
for _, d in ipairs(old) do d:Destroy() end
local copy = src:Clone()
if copy:IsA("Accoutrement") then
	copy.Parent = ch
	hum:AddAccessory(copy)
else
	for _, c in ipairs(copy:GetChildren()) do
		if c:IsA("Accoutrement") then c.Parent = ch hum:AddAccessory(c) end
	end
	copy:Destroy()
end
task.wait(0.6)
local worn
for _, d in ipairs(ch:GetChildren()) do
	if d:IsA("Accoutrement") then worn = d end
end
local frame = ch:FindFirstChild("HumanoidRootPart").CFrame
%s
"""

## Each named part in the character's own frame: x right, y up, -z forward.
const WHERE := """
for _, name in ipairs({%s}) do
	local p = worn:FindFirstChild(name)
	if p then
		local at = frame:PointToObjectSpace(p.Position)
		print(("N %%s %%.3f %%.3f %%.3f"):format(name:lower(), at.X, at.Y, at.Z))
	else
		print("N " .. name:lower() .. " missing")
	end
end
"""

func _named(key: String) -> String:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(stage.path_join("manifest.json")))
	for row in (manifest if typeof(manifest) == TYPE_ARRAY else []):
		if typeof(row) == TYPE_DICTIONARY and String(row.get("key", "")) == key:
			return String(row.get("instance", key))
	return key

func _spot(d: Dictionary, name: String) -> Vector3:
	var bits := String(d.get(name, "")).split(" ")
	if bits.size() != 3:
		return Vector3(NAN, NAN, NAN)
	return Vector3(float(bits[0]), float(bits[1]), float(bits[2]))

func _run() -> void:
	await create_timer(4.0).timeout

	# ---- the Spoonie ---------------------------------------------------------------------
	var spoon := await _wear("crudespoon", """
local handles = 0
for _, d in ipairs(worn:GetDescendants()) do
	if d:IsA("BasePart") and d.Name == "Handle" then handles = handles + 1 end
end
print("N handles " .. tostring(handles))
local arm = ch:FindFirstChild("Right Arm")
print(("N reach %.3f"):format((worn:FindFirstChild("Handle").Position - arm.Position).Magnitude))
print(("N far %.3f"):format((worn:FindFirstChild("Bowl").Position - arm.Position).Magnitude))
""" + WHERE % '"Handle", "Stem", "Bowl", "Lip"')
	check(spoon.get("handles", "") == "1",
		"exactly one part is the Handle, where the published spoon has two: %s"
		% spoon.get("handles", "(nothing read)"))
	var butt := _spot(spoon, "handle")
	var bowl := _spot(spoon, "bowl")
	var stem := _spot(spoon, "stem")
	check(not is_nan(butt.x) and not is_nan(bowl.x), "it is on him and its parts are placed")
	if not is_nan(butt.x) and not is_nan(bowl.x):
		check(bowl.z < butt.z - 0.5,
			"the bowl is the far end, out in front of the fist: z %.2f against the butt's %.2f"
			% [bowl.z, butt.z])
		check(absf(bowl.x - butt.x) < 0.25,
			"in line with it rather than staggered sideways: x %.2f against %.2f"
			% [bowl.x, butt.x])
		check(stem.z < butt.z and stem.z > bowl.z,
			"and the stem is between the two, which is what a spoon is: z %.2f" % stem.z)
		check(butt.x > 0.3, "on his right, which is the hand it is gripped in: x %.2f" % butt.x)
	check(float(spoon.get("reach", "99")) < 1.6,
		"the butt is in the hand rather than floating off the body: %s studs from the arm"
		% spoon.get("reach", "?"))
	check(float(spoon.get("far", "99")) < 2.6,
		"and the bowl is a spoon's length from it: %s studs" % spoon.get("far", "?"))

	# ---- the pegs ------------------------------------------------------------------------------
	# All four jaws survive the Handle rename: JawLeftUpper is turned, so catalogue.js puts an
	# invisible Anchor first for the rename to take. The model on chain has no JawLeftUpper.
	var pegs := await _wear("pegs",
		WHERE % '"JawLeftUpper", "JawLeftLower", "JawRightUpper", "JawRightLower"')
	for jaw in ["jawleftupper", "jawleftlower", "jawrightupper", "jawrightlower"]:
		check(pegs.get(jaw, "missing") != "missing",
			"%s is on the model: %s" % [jaw, pegs.get(jaw, "missing")])
	var left := _spot(pegs, "jawleftupper")
	var right := _spot(pegs, "jawrightupper")
	if not is_nan(left.x) and not is_nan(right.x):
		check(left.x * right.x < 0,
			"the two are on opposite sides of him: x %.2f and %.2f" % [left.x, right.x])
		check(left.z < 0 and right.z < 0, "both on his front: z %.2f and %.2f" % [left.z, right.z])
		check(absf(left.y - right.y) < 0.2,
			"and level with each other: y %.2f and %.2f" % [left.y, right.y])

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

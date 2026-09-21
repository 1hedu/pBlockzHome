# The pets photographed in motion: summoned through Pets.summon as the wardrobe does, so the
# real follow code runs, with the character walked about for them to follow. The last two
# frames hold them still instead, which is where size reads.
#
#   node scripts/stage-preview.js roma,pup,steven <stage dir>
#   godot --path . -s res://tests/pets_shot.gd -- <stage dir> <shots dir>
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var shots := ""
var t := 0.0
var phase := 0
var glides := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0]
	shots = args[1] if args.size() > 1 else stage
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
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(shots)

## Puts a staged item into ReplicatedStorage. A model's own Name property wins over `key`, so
## these land as "White Roma", "Pup" and "Familiar".
func _template(key: String) -> void:
	var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
	# A staged path picks up the asset root and loads as nothing, drawing a MeshPart as its box.
	raw = raw.replace(stage.replace("\\", "/") + "/", "user://preview/")
	world.add_model("ReplicatedStorage", key, raw)

func _shoot(name: String) -> void:
	get_root().get_texture().get_image().save_png(shots.path_join(name + ".png"))
	print("  -> %s" % shots.path_join(name + ".png"))

## A point in front of the camera and off to one side: the character hides the view axis.
func _in_view(side: float, ahead: float) -> Vector3:
	var cam := get_root().get_camera_3d()
	if cam == null:
		return Vector3(0, 5, 0)
	var b := cam.global_transform.basis
	return cam.global_position - b.z * ahead + b.x * side + Vector3(0, 0.35, 0)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		_template("roma")
		_template("pup")
		_template("steven")
		# A corner of the town with room to drive a wide arc about.
		world.run_chunk("summon", """
local Pets = require(game:GetService("ServerScriptService").Pets)
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local ch = player and player.Character
if ch then ch:PivotTo(CFrame.new(-40, 4, 40)) end
task.wait(0.3)
Pets.summon(player, rs["White Roma"], "glide")
print("PETS roma summoned")
-- A long arc, so it has to lean into a turn rather than drive in a line.
task.spawn(function()
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	for i = 1, 60 do
		if not hum then break end
		local a = i * 0.3
		hum:MoveTo(Vector3.new(-40 + math.cos(a) * 15, 4, 40 + math.sin(a) * 15))
		task.wait(0.35)
	end
end)
""")
		t = 0.0
	elif phase == 1 and t > 2.2:
		glides += 1
		_shoot("roma-glide-%d" % glides)
		t = 0.0
		if glides == 4:
			phase = 2
	elif phase == 2 and t > 0.1:
		phase = 3
		t = 0.0
		# Both pets still, side by side and the same distance off: scale reads off a comparison,
		# not off one animal on its own.
		var a := _in_view(-0.75, 2.6)
		var b := _in_view(0.75, 2.6)
		world.run_chunk("pair", """
local Pets = require(game:GetService("ServerScriptService").Pets)
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
Pets.dismiss(player)
local hum = player.Character:FindFirstChildOfClass("Humanoid")
if hum then hum:MoveTo(player.Character:GetPivot().Position) end
local at = { Vector3.new(%f, %f, %f), Vector3.new(%f, %f, %f) }
for i, name in ipairs({"White Roma", "Pup"}) do
	local m = rs:FindFirstChild(name):Clone()
	m.Name = "Look" .. i
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			if not m.PrimaryPart then m.PrimaryPart = d end
		end
	end
	m.Parent = workspace
	m:PivotTo(CFrame.new(at[i], at[i] + Vector3.new(0.6, 0, 1)))
end
print("PETS pair placed")
""" % [a.x, a.y, a.z, b.x, b.y, b.z])
	elif phase == 3 and t > 2.5:
		_shoot("pets-pair")
		phase = 4
		t = 0.0
		var c := _in_view(0.0, 2.4)
		world.run_chunk("familiar", """
local rs = game:GetService("ReplicatedStorage")
for i = 1, 2 do
	local old = workspace:FindFirstChild("Look" .. i)
	if old then old:Destroy() end
end
local m = rs:FindFirstChild("Familiar"):Clone()
m.Name = "LookSteven"
for _, d in ipairs(m:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
		if not m.PrimaryPart then m.PrimaryPart = d end
	end
end
m.Parent = workspace
m:PivotTo(CFrame.new(%f, %f, %f))
print("PETS familiar placed")
""" % [c.x, c.y, c.z])
	elif phase == 4 and t > 3.5:
		_shoot("familiar-neck")
		quit(0)
	return false

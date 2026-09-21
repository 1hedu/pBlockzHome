# A close look at the car, from a camera that stays put.
#
#   node scripts/stage-preview.js roma,pup <stage dir>
#   godot --path . -s res://tests/roma_look.gd -- <stage dir> <shots dir>
#
# CameraType Scriptable hands the camera to the place's own script -- pulseblockz_world.cpp
# then skips its own camera update -- so the camera is nailed down here, the character parked
# out of shot, and the models put in front of the lens.
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var shots := ""
var t := 0.0
var phase := 0

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

func _template(key: String) -> void:
	var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
	raw = raw.replace(stage.replace("\\", "/") + "/", "user://preview/")
	world.add_model("ReplicatedStorage", key, raw)

func _shoot(name: String) -> void:
	get_root().get_texture().get_image().save_png(shots.path_join(name + ".png"))
	print("  -> %s" % shots.path_join(name + ".png"))

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		_template("roma")
		_template("pup")
		world.run_chunk("look", """
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local ch = player.Character
-- Out of shot, and stopped: a walking character drags the whole scene about.
ch:PivotTo(CFrame.new(-40, 4, 60))
local hum = ch:FindFirstChildOfClass("Humanoid")
if hum then hum:MoveTo(Vector3.new(-40, 4, 60)) end

local WHERE = Vector3.new(-40, 3.2, 40)
local function put(name, at, face)
	local m = rs:FindFirstChild(name):Clone()
	m.Name = "Look_" .. name
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			if not m.PrimaryPart then m.PrimaryPart = d end
		end
	end
	m.Parent = workspace
	m:PivotTo(CFrame.new(at, at + face))
	return m
end
-- Nose towards the camera and across it, so which end is which is not a matter of opinion.
put("White Roma", WHERE, Vector3.new(-0.6, 0, 1))
""")
		world.run_client_chunk("cam", """
local WHERE = Vector3.new(-40, 3.2, 40)
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 40
cam.CFrame = CFrame.new(WHERE + Vector3.new(-1.1, 0.55, 1.4), WHERE)
print("LOOK camera pinned at " .. tostring(cam.CFrame.Position))
""")
		t = 0.0
	elif phase == 1 and t > 2.5:
		_shoot("roma-close")
		phase = 2
		t = 0.0
		# From behind and above, where a wheel that is on upside down shows.
		world.run_client_chunk("look2", """
local WHERE = Vector3.new(-40, 3.2, 40)
local cam = workspace.CurrentCamera
cam.CFrame = CFrame.new(WHERE + Vector3.new(1.2, 0.8, -1.2), WHERE)
""")
	elif phase == 2 and t > 1.5:
		_shoot("roma-close-rear")
		phase = 3
		t = 0.0
		# Beside the dog, for size.
		world.run_chunk("look3", """
local rs = game:GetService("ReplicatedStorage")
local WHERE = Vector3.new(-40, 3.2, 40)
local pup = rs:FindFirstChild("Pup"):Clone()
pup.Name = "Look_Pup"
for _, d in ipairs(pup:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
		if not pup.PrimaryPart then pup.PrimaryPart = d end
	end
end
pup.Parent = workspace
local at = WHERE + Vector3.new(0, 0, -1.6)
pup:PivotTo(CFrame.new(at, at + Vector3.new(-0.6, 0, 1)))
""")
		world.run_client_chunk("cam3", """
local WHERE = Vector3.new(-40, 3.2, 40)
local cam = workspace.CurrentCamera
cam.FieldOfView = 45
cam.CFrame = CFrame.new(WHERE + Vector3.new(-2.2, 1.1, 1.4), WHERE + Vector3.new(0, 0, -0.8))
""")
	elif phase == 3 and t > 1.5:
		_shoot("roma-and-pup")
		quit(0)
	return false

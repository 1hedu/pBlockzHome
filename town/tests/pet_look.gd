# How big a pet is, photographed next to its owner for scale.
#
#   node scripts/stage-preview.js roma <dir>
#   godot --path . -s res://tests/pet_look.gd -- <staged dir> <shots dir> [key] [name]
#
# pet_shot.gd frames a model alone against the sky -- shape, not size -- and pets_shot.gd fires
# on a timer through the game's camera, which follows the character instead of standing where a
# comparison needs it. Two frames: the pet beside the character, then beside a third-scale copy.
extends SceneTree

var world: PulseBlockzWorld
var stage := ""
var shots := ""
var key := "roma"
var model := "White Roma"
var t := 0.0
var phase := 0
## Set when the place prints "intro:". Shooting on a timer instead photographs the loading card.
var lit := false

# Studs above the character: a stall stands in the quarter pets_shot.gd drives to, so this pair
# is lifted clear of the town and given a plate of its own rather than shot down there.
const HIGH := 80.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0]
	shots = args[1] if args.size() > 1 else stage
	key = args[2] if args.size() > 2 else key
	model = args[3] if args.size() > 3 else model
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in (dir.get_files() if dir else PackedStringArray()):
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.script_print.connect(func(_n, line):
		if line.begins_with("intro:"): lit = true
		elif line.begins_with("LOOK summoned at"): _aim(line))
	main.get_node("Wallet").auto_start = false
	# The title card covers the world for the first several seconds, which is when shots land.
	main.show_title = false
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(shots)

## Aims the camera once the place reports where the pair ended up. Written from a LocalScript
## with CameraType Scriptable, which is Roblox's "stop driving it": the host otherwise rewrites
## the Camera3D off the character every frame.
func _aim(line: String) -> void:
	var bits := line.split(" ")
	var at := Vector3(float(bits[3]), float(bits[4]), float(bits[5]))
	world.run_client_chunk("aim", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 40
cam.CFrame = CFrame.new(Vector3.new(%f, %f, %f), Vector3.new(%f, %f, %f))
""" % [at.x + 17, at.y + 1.5, at.z + 3.2, at.x, at.y - 1.2, at.z + 3.2])

func _shoot(name: String) -> void:
	get_root().get_texture().get_image().save_png(shots.path_join(name + ".png"))
	print("  -> %s" % shots.path_join(name + ".png"))

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and lit and t > 1.0:
		phase = 1
		var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
		# A staged path picks up the asset root and loads as nothing, and a MeshPart with no
		# mesh draws as its bounding box.
		raw = raw.replace(stage.replace("\\", "/") + "/", "user://preview/")
		world.add_model("ReplicatedStorage", key, raw)
		world.run_chunk("stand", """
local Pets = require(game:GetService("ServerScriptService").Pets)
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local ch = player.Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local at = ch:GetPivot().Position + Vector3.new(0, %f, 0)

-- Daylight. The town runs a clock and a preview taken at midnight is a preview of a dark
-- shape, which is nobody's idea of what the thing looks like.
game:GetService("Lighting").ClockTime = 13

local plate = Instance.new("Part")
plate.Name = "LookPlate"
plate.Anchored = true
plate.Size = Vector3.new(60, 2, 60)
plate.Position = at - Vector3.new(0, 4, 0)
plate.Material = Enum.Material.Concrete
plate.Color = Color3.fromRGB(150, 152, 150)
plate.Parent = workspace

-- Standing still and facing -Z, so the pet parks on +Z behind them and one camera off to
-- the side sees the pair at the same distance -- which is the only way a photograph says
-- anything true about how big one is next to the other. A pet still walking to its spot is
-- a pet photographed mid-stride, so it is given time to park.
hum.WalkSpeed = 0
ch:PivotTo(CFrame.new(at, at - Vector3.new(0, 0, 10)))
task.wait(0.4)
Pets.summon(player, rs:FindFirstChild("%s"), "glide")
print(("LOOK summoned at %%.1f %%.1f %%.1f"):format(at.X, at.Y, at.Z))
""" % [HIGH, model])
		t = 0.0
	elif phase == 1 and t > 4.0:
		phase = 2
		_shoot(key + "-beside-you")
		t = 0.0
		# A third-scale copy for the second frame, shrunk about the mean of its own parts.
		world.run_chunk("small", """
local rs = game:GetService("ReplicatedStorage")
local copy = rs:FindFirstChild("%s"):Clone()
copy.Name = "WasThisBig"
local mid = Vector3.new(0, 0, 0)
local n = 0
for _, d in ipairs(copy:GetDescendants()) do
	if d:IsA("BasePart") then mid = mid + d.Position n = n + 1 end
end
mid = n > 0 and mid / n or mid
for _, d in ipairs(copy:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Size = d.Size / 3
		d.Position = mid + (d.Position - mid) / 3
		d.Anchored = true
		d.CanCollide = false
		if not copy.PrimaryPart then copy.PrimaryPart = d end
	end
end
copy.Parent = workspace
-- Alongside the parked one and a little nearer the camera, so neither hides the other.
local player = game:GetService("Players"):GetPlayers()[1]
local at = player.Character:GetPivot().Position
copy:PivotTo(CFrame.new(at + Vector3.new(0, -2.4, 10.5)))
print("LOOK old size placed")
""" % [model])
	elif phase == 2 and t > 2.5:
		_shoot(key + "-old-and-new")
		quit(0)
	return false

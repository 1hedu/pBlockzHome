# The car in plain elevation: camera level with it, a long lens, one view per side.
#
#   godot --path . -s res://tests/roma_side.gd -- <stage dir> <shots dir>
#
# A roof and a floor pan look alike at 40 degrees a stud away; six studs out at 16 degrees,
# level and side on, which way up it is and which end is the nose both show.
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var shots := ""
var t := 0.0
var phase := 0
const VIEWS := [
	["side", 6.0, 0.0, 0.0],       # name, distance, height above the car, angle round it
	["front", 6.0, 0.0, 90.0],
	["above", 6.0, 5.0, 45.0],
]

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

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		for key in ["roma", "pup"]:
			var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
			world.add_model("ReplicatedStorage", key,
				raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("place", """
local rs = game:GetService("ReplicatedStorage")
local ch = game:GetService("Players"):GetPlayers()[1].Character
ch:PivotTo(CFrame.new(-40, 4, 70))
local hum = ch:FindFirstChildOfClass("Humanoid")
if hum then hum:MoveTo(Vector3.new(-40, 4, 70)) end
-- Its nose down +X, so a camera on -Z sees it broadside with the nose to the right.
local m = rs:FindFirstChild("White Roma"):Clone()
m.Name = "Look"
for _, d in ipairs(m:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
		if not m.PrimaryPart then m.PrimaryPart = d end
	end
end
m.Parent = workspace
m:PivotTo(CFrame.new(Vector3.new(-40, 3.2, 40), Vector3.new(-39, 3.2, 40)))
print("SIDE placed, pivot " .. tostring(m:GetPivot().Position))
""")
		t = 0.0
	elif phase >= 1 and phase <= VIEWS.size() and t > 1.6:
		var v: Array = VIEWS[phase - 1]
		if phase > 1:
			get_root().get_texture().get_image().save_png(shots.path_join("roma-%s.png" % VIEWS[phase - 2][0]))
			print("  -> roma-%s.png" % VIEWS[phase - 2][0])
		var a: float = deg_to_rad(float(v[3]))
		world.run_client_chunk("cam%d" % phase, """
local at = Vector3.new(-40, 3.2, 40)
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 16
cam.CFrame = CFrame.new(at + Vector3.new(%f, %f, %f), at)
""" % [sin(a) * float(v[1]), float(v[2]), -cos(a) * float(v[1])])
		phase += 1
		t = 0.0
	elif phase > VIEWS.size() and t > 1.6:
		get_root().get_texture().get_image().save_png(shots.path_join("roma-%s.png" % VIEWS[-1][0]))
		print("  -> roma-%s.png" % VIEWS[-1][0])
		quit(0)
	return false

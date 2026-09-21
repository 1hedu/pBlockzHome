# The arc of braziers, from a fixed camera above the town.
#
#   godot --path . -s res://tests/braziers_look.gd -- <shots dir>
extends SceneTree
var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	shots = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(shots)
	DirAccess.make_dir_recursive_absolute("user://preview")
	var w := FileAccess.open("user://preview/flame.png", FileAccess.WRITE)
	if w:
		w.store_buffer(FileAccess.get_file_as_bytes("res://../../../scripts/models/flame.png"))
		w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 5.0:
		phase = 1
		world.run_chunk("look", """
local rs = game:GetService("ReplicatedStorage")
local place = rs:FindFirstChild("PlaceAssets") or Instance.new("Folder")
place.Name = "PlaceAssets"
place.Parent = rs
if not place:FindFirstChild("FlameSprite") then
	local v = Instance.new("StringValue")
	v.Name = "FlameSprite"
	v.Value = "user://preview/flame.png"
	v.Parent = place
end
local map = workspace:FindFirstChild("Map")
local b = map and map:FindFirstChild("Brazier")
print("BRAZIER in the map: " .. tostring(b ~= nil))
if b then
	for _, d in ipairs(b:GetDescendants()) do
		print("BRAZIER   " .. d.Name .. "  " .. d.ClassName)
	end
end
local ch = game:GetService("Players"):GetPlayers()[1].Character
ch:PivotTo(CFrame.new(30, 4, -30))
local hum = ch:FindFirstChildOfClass("Humanoid")
if hum then hum:MoveTo(Vector3.new(30, 4, -30)) end
""")
		world.run_client_chunk("cam", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 55
local at = Vector3.new(40, 3.0, -42)
cam.CFrame = CFrame.new(Vector3.new(2, 26, -4), at)
""")
		t = 0.0
	elif phase == 1 and t > 4.0:
		get_root().get_texture().get_image().save_png(shots.path_join("arc.png"))
		print("  -> arc.png")
		quit(0)
	return false

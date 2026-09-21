# Do the props stand on their markers, and is the marker consumed?
#
#   godot --path . -s res://tests/marker_probe.gd -- <stage dir>
#
# The lookup falls back to a written-down corner, so "it built" proves nothing: the marker is
# moved where neither path would choose, so the tree's reported position names which path ran,
# and it is destroyed only on the path that used it.
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	stage = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in (dir.get_files() if dir else PackedStringArray()):
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	for f in ["rocket.obj", "rocket-colors.png", "tree.obj", "tree-colors.png"]:
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes("res://../../../scripts/models/".path_join(f)))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 1.0:
		phase = 1
		# The move has to land before anything is built; run after the build it proves nothing.
		world.run_chunk("move", """
local map = workspace:FindFirstChild("Map")
local spot = map and map:FindFirstChild("TreeSpot", true)
if spot then
	spot.CFrame = CFrame.new(-20, 0, 12) * CFrame.Angles(0, math.rad(90), 0)
	print("MARKER moved TreeSpot to -20, 0, 12")
else
	print("MARKER TreeSpot not in the map")
end
""")
		world.run_chunk("assets", """
local rs = game:GetService("ReplicatedStorage")
local place = rs:FindFirstChild("PlaceAssets") or Instance.new("Folder")
place.Name = "PlaceAssets"
place.Parent = rs
for name, file in pairs({ RocketMesh = "rocket.obj", RocketColors = "rocket-colors.png",
		TreeMesh = "tree.obj", TreeColors = "tree-colors.png" }) do
	if not place:FindFirstChild(name) then
		local v = Instance.new("StringValue")
		v.Name = name
		v.Value = "user://preview/" .. file
		v.Parent = place
	end
end
""")
		t = 0.0
	elif phase == 1 and t > 6.0:
		phase = 2
		world.run_chunk("check", """
local map = workspace:FindFirstChild("Map")
local tree = workspace:FindFirstChild("Tree")
local rocket = workspace:FindFirstChild("Rocket")
print("MARKER tree built: " .. tostring(tree ~= nil) .. ", rocket built: " .. tostring(rocket ~= nil))
if tree then
	local p = tree.Position
	print(("MARKER tree at %.1f, %.1f, %.1f  (moved marker said -20, ~9, 12)"):format(p.X, p.Y, p.Z))
end
print("MARKER TreeSpot left behind: " .. tostring((map and map:FindFirstChild("TreeSpot", true)) ~= nil))
print("MARKER RocketSpot left behind: " .. tostring((map and map:FindFirstChild("RocketSpot", true)) ~= nil))
""")
		t = 0.0
	elif phase == 2 and t > 2.5:
		quit(0)
	return false

# The tree, from a level camera, to check which way its faces point.
#
#   godot --path . -s res://tests/tree_look.gd -- <stage dir> <shots dir>
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0]
	shots = args[1]
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
	if phase == 0 and t > 5.0:
		phase = 1
		world.run_chunk("tree", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
ch:PivotTo(CFrame.new(46, 4, 80))
local hum = ch:FindFirstChildOfClass("Humanoid")
if hum then hum:MoveTo(Vector3.new(46, 4, 80)) end
local p = Instance.new("MeshPart")
p.Name = "Tree"
p.Size = Vector3.new(18.88, 18, 16.58)
p.Position = Vector3.new(46, 9, 46)
p.Orientation = Vector3.new(0, 20, 0)
p.MeshId = "user://preview/tree.obj"
p.TextureID = "user://preview/tree-colors.png"
p.Material = Enum.Material.SmoothPlastic
p.Anchored = true
p.Parent = workspace
print("TREE up, 18 studs")
""")
		world.run_client_chunk("cam", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 45
cam.CFrame = CFrame.new(Vector3.new(46, 9, 80), Vector3.new(46, 8, 46))
""")
		t = 0.0
	elif phase == 1 and t > 3.5:
		get_root().get_texture().get_image().save_png(shots.path_join("tree.png"))
		print("  -> tree.png")
		quit(0)
	return false

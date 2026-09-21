# The rocket, standing where it will stand.
#
#   godot --path . -s res://tests/rocket_shot.gd -- <shots dir>
#
# Built from scripts/models rather than off the chain, so it can be looked at before it costs
# anything. The camera follows the character, so where they stand is what is photographed.
extends SceneTree
var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://shots/rocket")
	DirAccess.make_dir_recursive_absolute("user://preview")
	for f in ["rocket.obj", "rocket-colors.png"]:
		var src := "res://../../../scripts/models/".path_join(f)
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(src))
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
		world.run_chunk("rocket", """
local part = Instance.new("MeshPart")
part.Name = "Rocket"
local SIZE = Vector3.new(4.04, 7.04, 2.635) * 3
part.Size = SIZE
part.Position = Vector3.new(46, SIZE.Y / 2, -46)
part.Orientation = Vector3.new(0, -25, 0)
part.MeshId = "user://preview/rocket.obj"
part.TextureID = "user://preview/rocket-colors.png"
part.Material = Enum.Material.SmoothPlastic
part.Anchored = true
part.Parent = workspace
-- Over to the corner, since the camera goes where the character goes.
-- Left where the game put them, so the shot shows whether the pad really did move.
local ch = game:GetService("Players"):GetPlayers()[1]
ch = ch and ch.Character
if ch then print("ROCKET stood at", ch:GetPivot().Position) end
print("ROCKET up")
""")
		t = 0.0
	elif phase == 1 and t > 3.5:
		get_root().get_texture().get_image().save_png(shots.path_join("rocket.png"))
		print("  -> %s" % shots.path_join("rocket.png"))
		phase = 2
		t = 0.0
		# Again from down the path, for the whole rocket against the town.
		world.run_chunk("back", """
local ch = game:GetService("Players"):GetPlayers()[1]
ch = ch and ch.Character
if ch then pcall(function() ch:PivotTo(CFrame.new(Vector3.new(16, 4, -16), Vector3.new(46, 10, -46))) end) end
""")
	elif phase == 2 and t > 2.5:
		get_root().get_texture().get_image().save_png(shots.path_join("rocket-far.png"))
		print("  -> %s" % shots.path_join("rocket-far.png"))
		quit(0)
	return false

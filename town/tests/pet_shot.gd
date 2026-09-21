# One pet model dropped straight into the world and photographed, particle effects included:
# render-pet.js draws the meshes and nothing else, so it cannot show an emitter, and shoot.gd
# wears an item on a character, whereas a pet is summoned beside one.
#
#   node scripts/stage-preview.js steven <dir>
#   godot --path . -s res://tests/pet_shot.gd -- <staged dir> <shots dir>
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
	_stage_files()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(shots)

## Copies the staged files into user://preview, where the engine can open them, as shoot.gd does.
func _stage_files() -> void:
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	if dir == null:
		printerr("cannot read ", stage)
		return
	for f in dir.get_files():
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		var manifest = JSON.parse_string(FileAccess.get_file_as_string(stage.path_join("manifest.json")))
		var key := String(manifest[0].key if typeof(manifest[0]) == TYPE_DICTIONARY else manifest[0])
		# A model's own Name property wins over the key and over the name add_model is given.
		var instance := String(manifest[0].get("instance", key)) if typeof(manifest[0]) == TYPE_DICTIONARY else key
		var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
		# Point every mesh and texture at the staged copy: a real path picks up the asset root
		# and loads as nothing, and a MeshPart with no mesh draws as its bounding box.
		raw = raw.replace(stage.replace("\\", "/") + "/", "user://preview/")
		world.add_model("Workspace", "PetLook", raw)
		# The host drives the camera every frame, so the model is moved into the view instead.
		var cam := get_root().get_camera_3d()
		var at := Vector3(0, 5, 0)
		if cam:
			# Up and to one side as well as forward: the character hides the view axis.
			var t3 := cam.global_transform
			at = cam.global_position - t3.basis.z * 4.0 + t3.basis.x * 1.5 + Vector3(0, 1.1, 0)
		world.run_chunk("place", """
local m = workspace:FindFirstChild("PetLook") or workspace:FindFirstChild("%s")
if m then
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	pcall(function() m:PivotTo(CFrame.new(%f, %f, %f)) end)
	print("PET placed " .. m.Name)
end
""" % [instance, at.x, at.y, at.z])
		t = 0.0
	elif phase == 1 and t > 3.0:
		get_root().get_texture().get_image().save_png(shots.path_join("pet.png"))
		print("  -> %s" % shots.path_join("pet.png"))
		quit(0)
	return false

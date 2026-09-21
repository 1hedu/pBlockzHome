# Shots of the Pup beside the character from four angles, a scriptable camera going round it.
# Windowed: the headless renderer draws nothing. A model's front faces -Z.
#
#   node scripts/stage-preview.js pup <dir>
#   godot --path . -s res://tests/pup_look.gd -- <staged dir> <shots dir>
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var stage := ""
var shots := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0]
	shots = args[1] if args.size() > 1 else stage
	DirAccess.make_dir_recursive_absolute(shots)
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in dir.get_files():
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
		w.close()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): if line.begins_with("PUP"): print(line))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _run() -> void:
	await create_timer(12.0).timeout
	var raw := FileAccess.get_file_as_string(stage.path_join("pup.json"))
	raw = raw.replace(stage.replace("\\", "/") + "/", "user://preview/")
	world.add_model("Workspace", "PupLook", raw)
	await create_timer(1.0).timeout
	for view in [["front", 0.0], ["three_quarter", 40.0], ["side", 90.0], ["back", 180.0]]:
		# Placed from the server: moving only the client's copy leaves the server's to fall.
		world.run_chunk("place", """
local m = workspace:FindFirstChild("Pup") or workspace:FindFirstChild("PupLook")
local player = game:GetService("Players"):GetPlayers()[1]
local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if not m or not root then print("PUP missing", m, root) return end
local ground = root.Position - Vector3.new(0, 3, 0)
-- Somewhere open: the spawn has a rocket beside it, which the first try put the dog inside.
local at
for _, off in ipairs({ Vector3.new(-8, 0, 0), Vector3.new(8, 0, 0), Vector3.new(0, 0, 8), Vector3.new(0, 0, -8), Vector3.new(-8, 0, 8), Vector3.new(8, 0, -8) }) do
	local p = ground + off
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { m, root.Parent }
	params.FilterType = Enum.RaycastFilterType.Exclude
	if #workspace:GetPartBoundsInBox(CFrame.new(p + Vector3.new(0, 4, 0)), Vector3.new(12, 7, 12), params) == 0 then at = p break end
end
at = at or ground + Vector3.new(-8, 0, 0)
for _, p in ipairs(m:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end
local body = m:FindFirstChildWhichIsA("BasePart", true)
m:PivotTo(CFrame.new(at + Vector3.new(0, body.Size.Y / 2, 0)))
workspace:SetAttribute("PupAt", at)
""")
		await create_timer(0.5).timeout
		world.run_client_chunk("look", """
local m = workspace:FindFirstChild("Pup") or workspace:FindFirstChild("PupLook")
local body = m and m:FindFirstChildWhichIsA("BasePart", true)
local at = workspace:GetAttribute("PupAt")
if not body or not at then print("PUP missing on the client") return end
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local a = math.rad(%f)
local focus = at + Vector3.new(0, 0.8, 0)
cam.CFrame = CFrame.lookAt(focus + Vector3.new(math.sin(a) * 4, 0.9, -math.cos(a) * 4), focus)
print(("PUP %%s size %%s at %%s body %%s mesh %%s cam %%s"):format("%s", tostring(body.Size), tostring(at), tostring(body.Position), tostring(body.MeshId), tostring(cam.CFrame.Position)))
""" % [view[1], view[0]])
		await create_timer(1.5).timeout
		get_root().get_texture().get_image().save_png(shots.path_join("pup_%s.png" % view[0]))
	print("  -> ", ProjectSettings.globalize_path(shots))
	quit(0)

# The Funmaster's name tag, photographed at three distances to see how it holds up.
#
#   godot --path . -s res://tests/npc_names_shot.gd -- <shots dir>
#
# Windowed: the headless renderer is a dummy and draws nothing.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var shots := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _run() -> void:
	await create_timer(15.0).timeout
	for d in [4.0, 10.0, 30.0]:
		world.run_client_chunk("look", """
local npc = workspace.Map:FindFirstChild("Funmaster")
local torso = npc and npc:FindFirstChild("Torso", true)
if not torso then return end
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(torso.Position + Vector3.new(0, 3, -%f), torso.Position + Vector3.new(0, 2.5, 0))
""" % d)
		await create_timer(1.5).timeout
		get_root().get_texture().get_image().save_png(shots.path_join("npc_name_%d.png" % int(d)))
	print("  -> ", ProjectSettings.globalize_path(shots))
	quit(0)

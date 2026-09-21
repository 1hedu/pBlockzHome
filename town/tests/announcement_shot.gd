# Photographs of an announcement: in chat, and in the Hall of Records' history.
#
#   (a dev chain running, with an announcement posted: node scripts/dev-chain.js announce ...)
#   PBLOCKZ_RPC_URL=http://127.0.0.1:8545 godot --path . -s res://tests/announcement_shot.gd -- <shots dir>
#
# Windowed: headless has a dummy renderer and draws nothing.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var shots := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _run() -> void:
	await create_timer(30.0).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("announcement_chat.png"))
	world.run_client_chunk("records", "game:GetService('ReplicatedStorage'):WaitForChild('RecordsRemote'):FireServer('announcements')")
	await create_timer(25.0).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("announcement_history.png"))
	print("  -> ", ProjectSettings.globalize_path(shots))
	quit(0)

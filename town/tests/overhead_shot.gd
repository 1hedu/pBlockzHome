# Another player's overhead name and hearts near and far: sized in studs, so big up close and
# small at distance. Camera at 6 and 30 studs; windowed client of the town on port 8800.
#
#   (tests/bots.ps1 running)
#   godot --path . -s res://tests/overhead_shot.gd -- <shots dir> [--bot=BFS 9000]
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var shots := ""
var bot := "BFS 9000"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 and not args[0].begins_with("--") else "user://shots"
	for a in args:
		if a.begins_with("--bot="): bot = a.substr(6)
	DirAccess.make_dir_recursive_absolute(shots)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	OS.set_environment("PBLOCKZ_PLAYER_KEY", PulseBlockzCrypto.keccak256_hex("pulseblockz overhead viewer"))
	OS.set_environment("PBLOCKZ_NO_DEV_KEY", "1")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 2
	world.server_address = "127.0.0.1"
	world.server_port = 8800
	world.player_name = "Viewer"
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): if line.begins_with("SHOT"): print(line))
	get_root().add_child(main)
	_run()

func _at(distance: float) -> void:
	world.run_client_chunk("cam", """
local Players = game:GetService("Players")
local target = Players:FindFirstChild("%s")
local head = target and target.Character and target.Character:FindFirstChild("Head")
if not head then print("SHOT no bot") return end
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
_G.shotConn = _G.shotConn or nil
if _G.shotConn then _G.shotConn:Disconnect() end
_G.shotConn = game:GetService("RunService").RenderStepped:Connect(function()
	local h = target.Character and target.Character:FindFirstChild("Head")
	if h then cam.CFrame = CFrame.lookAt(h.Position + Vector3.new(%f, 1.5, %f), h.Position + Vector3.new(0, 1.5, 0)) end
end)
print("SHOT looking at " .. target.Name)
""" % [bot, distance * 0.6, distance * 0.8])
	await create_timer(2.0).timeout

func _run() -> void:
	await create_timer(20.0).timeout
	await _at(6.0)
	get_root().get_texture().get_image().save_png(shots.path_join("overhead_near.png"))
	await _at(30.0)
	get_root().get_texture().get_image().save_png(shots.path_join("overhead_far.png"))
	print("  -> ", ProjectSettings.globalize_path(shots))
	quit(0)

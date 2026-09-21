# On-screen size of a bot's overhead board and an NPC's name tag at 6, 12, 20 and 35 studs:
# prints AbsoluteSize and TextBounds. Windowed client of the town on port 8800.
#
#   (tests/bots.ps1 running)
#   godot --path . -s res://tests/overhead_measure.gd
extends SceneTree

var world: PulseBlockzWorld

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	OS.set_environment("PBLOCKZ_PLAYER_KEY", PulseBlockzCrypto.keccak256_hex("pulseblockz overhead measure"))
	OS.set_environment("PBLOCKZ_NO_DEV_KEY", "1")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 2
	world.server_address = "127.0.0.1"
	world.server_port = 8800
	world.player_name = "Measurer"
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): if line.begins_with("MEASURE"): print(line))
	get_root().add_child(main)
	_run()

func _measure(distance: float) -> void:
	world.run_client_chunk("m", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer.PlayerGui
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local bot = Players:FindFirstChild("BFS 9000")
local head = bot and bot.Character and bot.Character:FindFirstChild("Head")
local npc = workspace.Map:FindFirstChild("Funmaster")
local tag = npc and npc:FindFirstChild("NameTag", true)
if head then
	cam.CFrame = CFrame.lookAt(head.Position + Vector3.new(0, 1, %f), head.Position)
	task.wait(0.5)
	local board = gui.Overhead:FindFirstChild("OverheadBFS 9000")
	local name = board and board:FindFirstChild("Name")
	print(("MEASURE bot %%d studs: board %%s name %%s bounds %%s"):format(%d, tostring(board and board.AbsoluteSize), tostring(name and name.AbsoluteSize), tostring(name and name.TextBounds)))
end
if tag and tag.Adornee or tag then
	local part = tag.Adornee or tag.Parent
	cam.CFrame = CFrame.lookAt(part.Position + Vector3.new(0, 2, %f), part.Position + Vector3.new(0, 2, 0))
	task.wait(0.5)
	local name = tag:FindFirstChild("Name")
	print(("MEASURE npc %%d studs: tag %%s name %%s bounds %%s"):format(%d, tostring(tag.AbsoluteSize), tostring(name and name.AbsoluteSize), tostring(name and name.TextBounds)))
end
""" % [distance, int(distance), distance, int(distance)])
	await create_timer(2.0).timeout

func _run() -> void:
	await create_timer(20.0).timeout
	for d in [6.0, 12.0, 20.0, 35.0]:
		await _measure(d)
	quit(0)

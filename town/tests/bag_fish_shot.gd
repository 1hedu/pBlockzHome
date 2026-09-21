# Photographs of the fish and the rod in the bag, the hand sockets and the action bar, each drawn
# from its model (shared/ModelPicture.luau) since the town's own things have no thumbnail.
#
#   godot --path . -s res://tests/bag_fish_shot.gd -- <shots dir>
#
# The rod arrives through Angling.giveRod, the same entry Funmaster.server.luau calls; only the
# catches stand in for the Fishing contract's answer. Windowed: headless has a dummy renderer and
# draws nothing.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const StandIns = preload("res://tests/StandIns.gd")

var world: PulseBlockzWorld
var shots := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	StandIns.stage("bag_fish_shot")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): if line.begins_with("SHOT"): print(line))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _run() -> void:
	await create_timer(9.0).timeout
	world.run_chunk("standins", StandIns.chunk("bag_fish_shot"))
	await create_timer(1.0).timeout
	world.run_chunk("give", """
local player = game:GetService("Players"):GetPlayers()[1]
if not player:GetAttribute("WalletAddress") or player:GetAttribute("WalletAddress") == "" then
	player:SetAttribute("WalletAddress", "0x00000000000000000000000000000000F15Ab0B0")
	task.wait(1)
end
local Angling = require(game:GetService("ServerScriptService").Angling)
print("SHOT rod " .. tostring(Angling.giveRod(player)))
Angling._setCatches(player, { [0] = 3, [1] = 1, [3] = 2, [4] = 5, [5] = 1, [6] = 2, [8] = 4, [9] = 1 })
""")
	await create_timer(2.0).timeout
	world.run_client_chunk("wear", """
local rs = game:GetService("ReplicatedStorage")
rs.WardrobeRemote:FireServer("wear", "Dysnomia Rod")
task.wait(0.8)
rs.WardrobeRemote:FireServer("wear", "Cyan Fish")
task.wait(0.8)
local gui = game:GetService("Players").LocalPlayer.PlayerGui
gui:WaitForChild("Wardrobe").Enabled = true
rs.WardrobeRemote:FireServer("list")
print("SHOT wardrobe open")
""")
	await create_timer(4.0).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("bag_fish.png"))
	print("  -> ", ProjectSettings.globalize_path(shots))
	quit(0)

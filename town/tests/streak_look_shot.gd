# Photographs a kill-streak banner beside the duel score, and the screen once it has gone.
# Windowed: the headless dummy renderer draws nothing. The announcement is sent by hand;
# streak_test is where a streak is earned.
#
#   godot --path . -s res://tests/streak_look_shot.gd -- <shots dir>
extends SceneTree

var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 10.0:
		phase = 1
		world.run_chunk("news", """
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local node = Instance.new("Configuration")
node.Name = "0xlook"
node:SetAttribute("Limit", 10)
node:SetAttribute("TeamA", player.Name)
node:SetAttribute("TeamB", "Carol")
node:SetAttribute("FragsA", 5)
node:SetAttribute("FragsB", 1)
node:SetAttribute("State", "live")
node.Parent = rs:WaitForChild("Duels")
player:SetAttribute("Duel", "0xlook")
rs.CombatNews:FireAllClients(player.Name .. " is on a 5 kill streak!")
""")
	elif phase == 1 and t > 11.0:
		phase = 2
		get_root().get_texture().get_image().save_png(shots.path_join("streak_banner.png"))
	elif phase == 2 and t > 16.0:
		phase = 3
		get_root().get_texture().get_image().save_png(shots.path_join("streak_gone.png"))
		print("  -> ", ProjectSettings.globalize_path(shots))
		quit(0)
	return false

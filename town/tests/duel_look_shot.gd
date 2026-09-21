# Screenshots of a ranked duel: the score panel, the town's chat line, and an arriving challenge.
#
#   godot --path . -s res://tests/duel_look_shot.gd -- <shots dir>
#
# Windowed, not headless: the dummy renderer draws nothing. duel_test covers the behaviour.
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
		world.run_chunk("duel", """
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local node = Instance.new("Configuration")
node.Name = "0xlook"
node:SetAttribute("Mode", "2v2")
node:SetAttribute("Limit", 10)
node:SetAttribute("TeamA", player.Name .. " & Bob")
node:SetAttribute("TeamB", "Carol & Dave")
node:SetAttribute("FragsA", 7)
node:SetAttribute("FragsB", 4)
node:SetAttribute("State", "live")
node.Parent = rs:WaitForChild("Duels")
player:SetAttribute("Duel", "0xlook")
rs.DuelRemote:FireClient(player, "announce", player.Name .. " got Carol. " .. player.Name .. " & Bob 7 - 4 Carol & Dave")
""")
	elif phase == 1 and t > 12.5:
		phase = 2
		get_root().get_texture().get_image().save_png(shots.path_join("duel_score.png"))
		world.run_chunk("invite", """
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
rs.FunRemote:FireClient(player, "open", { title = "Funmaster Mike  <Ranked Duel>", npc = "",
	greeting = "Carol & Dave challenge Bob & you to a ranked 2v2, first to 10 frags. Nobody else can touch you while it's on. You've a minute to say.",
	menu = { { id = "accept", arg = "x", label = "I'm in" }, { id = "decline", arg = "x", label = "No thanks" } } })
""")
	elif phase == 2 and t > 14.0:
		phase = 3
		get_root().get_texture().get_image().save_png(shots.path_join("duel_invite.png"))
		print("  -> ", ProjectSettings.globalize_path(shots))
		quit(0)
	return false

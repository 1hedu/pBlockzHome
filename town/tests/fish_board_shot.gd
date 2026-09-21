# Photographs of the space fishing leaderboard, before the Everliving Fish is found and after.
#
#   godot --path . -s res://tests/fish_board_shot.gd -- <shots dir>
#
# No Fishing contract is deployed: _board() fakes OwnWallet.request and sets Contracts.Fishing,
# which FishBoard.client.luau requires non-empty before it issues the read at all.
# Windowed: headless has a dummy renderer and draws nothing.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const StandIns = preload("res://tests/StandIns.gd")

var world: PulseBlockzWorld
var shots := ""
var said: Array[String] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	StandIns.stage("fish_board_shot")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line); if line.begins_with("BOARD"): print(line))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _board(discoverer: String) -> void:
	world.run_client_chunk("fake", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local OwnWallet = require(rs:WaitForChild("OwnWallet"))
local Contracts = require(rs:WaitForChild("Contracts"))
Contracts.Fishing = "0x000000000000000000000000000000000000F15B"
local me = Players.LocalPlayer:GetAttribute("WalletAddress") or "0x00000000000000000000000000000000000A11CE"
local anglers = { me, "0x7aB0000000000000000000000000000000001234", "0x9c11000000000000000000000000000000005678" }
local catches = {
	[me:lower()] = { 12, 3, 0, 7, 1, 0, 4, 0, 9, %s },
	[anglers[2]:lower()] = { 4, 8, 2, 7, 0, 5, 4, 1, 2, 0 },
	[anglers[3]:lower()] = { 1, 8, 6, 0, 3, 5, 0, 2, 11, 0 },
}
OwnWallet.request = function(req)
	task.wait(0.2)
	local out = {}
	for _, c in ipairs(req.calls or {}) do
		if c.fn == "discoverer()" then
			table.insert(out, { ok = true, words = { %s } })
		elseif c.fn == "anglerCount()" then
			table.insert(out, { ok = true, words = { #anglers } })
		elseif c.fn == "anglers(uint256)" then
			table.insert(out, { ok = true, words = { anglers[c.args[1] + 1] } })
		elseif c.fn == "caughtOf(address)" then
			table.insert(out, { ok = true, words = catches[tostring(c.args[1]):lower()] })
		end
	end
	return { ok = true, results = out }
end
print("BOARD faked for " .. me)
""" % ["1" if discoverer != "" else "0", "me" if discoverer != "" else "\"0x0000000000000000000000000000000000000000\""])
	await create_timer(0.5).timeout
	# The chat and the bar sit over the board's top row.
	world.run_client_chunk("quiet", """
for _, s in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if s:IsA("ScreenGui") and s.Name ~= "FishBoard" then s.Enabled = false end
end
""")
	world.run_chunk("open", """
local player = game:GetService("Players"):GetPlayers()[1]
game:GetService("ReplicatedStorage").FunRemote:FireClient(player, "fishboard")
""")

func _run() -> void:
	await create_timer(9.0).timeout
	world.run_chunk("standins", StandIns.chunk("fish_board_shot"))
	await create_timer(1.0).timeout
	await _board("")
	await create_timer(3.0).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("fish_board_unfound.png"))
	world.run_client_chunk("shut", "game:GetService('Players').LocalPlayer.PlayerGui.FishBoard.Enabled = false")
	await create_timer(0.5).timeout
	await _board("me")
	await create_timer(3.0).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("fish_board_found.png"))
	print("  -> ", ProjectSettings.globalize_path(shots))
	quit(0)

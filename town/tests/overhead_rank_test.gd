# A place on the ranked duel leaderboard shows after the name over a player's head: "Runner #2".
# A real client (chunk_peer.gd, "Viewer") reads the board over the bot Runner while the server
# puts a stranger and Runner on the DuelKills store and refreshes the ranks.
#
#   godot --headless --path . -s res://tests/overhead_rank_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const PORT := 8822

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var kids: Array[int] = []
var report := ""
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _last_report(prefix: String) -> String:
	if not FileAccess.file_exists(report): return ""
	var lines := FileAccess.get_file_as_string(report).split("\n", false)
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with(prefix): return lines[i].substr(prefix.length())
	return ""

func _last_said(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

const VIEWER := """
local Players = game:GetService("Players")
local me = Players.LocalPlayer
while true do
	task.wait(0.5)
	local screen = me.PlayerGui:FindFirstChild("Overhead")
	local board = screen and screen:FindFirstChild("OverheadRunner")
	local name = board and board:FindFirstChild("Name")
	if name then print("SEEN RANK NAME " .. name.Text) end
end
"""

func _initialize() -> void:
	print("rank after the name")
	report = OS.get_user_data_dir().path_join("rank_viewer.txt")
	DirAccess.remove_absolute(report)
	var chunk := OS.get_user_data_dir().path_join("rank_viewer.luau")
	var f := FileAccess.open(chunk, FileAccess.WRITE)
	f.store_string(VIEWER)
	f.close()
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	Arrive.now(world)
	for spec in [["tests/chunk_peer.gd", ["--chunk=%s" % chunk, "--out=%s" % report, "--name=Viewer"]],
				 ["tests/bot.gd", ["--name=Runner", "--every=999"]]]:
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://" + spec[0], "--", "--port=%d" % PORT]
		args.append_array(spec[1])
		var pid := OS.create_process(OS.get_executable_path(), args)
		if pid > 0: kids.append(pid)
	_run()

func _run() -> void:
	# Pin the two near each other so Runner's board is on the Viewer's screen.
	await create_timer(4.0).timeout
	world.run_chunk("places", """
local Players = game:GetService("Players")
local SPOTS = { Viewer = Vector3.new(25, 0, 40), Runner = Vector3.new(25, 0, 52) }
game:GetService("RunService").Heartbeat:Connect(function()
	for _, p in ipairs(Players:GetPlayers()) do
		local spot = SPOTS[p.Name]
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if spot and root then
			root.CFrame = CFrame.new(Vector3.new(spot.X, root.Position.Y, spot.Z))
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end)
""")
	var t := 0.0
	while t < 60.0 and _last_report("RANK NAME ") == "":
		await create_timer(1.0).timeout
		t += 1.0
	check(_last_report("RANK NAME ") == "Runner", "not on the board, the name is just the name: %s" % _last_report("RANK NAME "))

	world.run_chunk("board", """
local Players = game:GetService("Players")
local Duels = require(game:GetService("ServerScriptService"):FindFirstChild("Duels", true))
local Ledger = require(game:GetService("ServerScriptService"):FindFirstChild("Ledger", true))
local runner = Players:FindFirstChild("Runner")
local address = runner and Ledger.addressOf(runner)
print("RANKED address " .. tostring(address))
if not address then return end
local function top()
	local rows = {}
	for _, row in ipairs(Duels.leaderboard(10)) do table.insert(rows, row.name .. "=" .. row.kills) end
	return table.concat(rows, ",")
end
print("RANKED before " .. top())
local board = game:GetService("DataStoreService"):GetOrderedDataStore("DuelKills")
board:SetAsync("0x00000000000000000000000000000000000000aa", 9)
board:SetAsync(address:lower(), 4)
Duels.refreshRanks()
print("RANKED after " .. top())
print("RANKED attribute " .. tostring(runner:GetAttribute("Rank")))
""")
	t = 0.0
	while t < 20.0 and not _last_report("RANK NAME ").contains("#"):
		await create_timer(1.0).timeout
		t += 1.0
	check(_last_said("RANKED before ") == "Founder=0", "before anybody has fought, the town's owner is #1 with no kills: %s" % _last_said("RANKED before "))
	check(_last_said("RANKED after ").ends_with(",Founder=0"),
		"and the first kills put them below: %s" % _last_said("RANKED after "))
	check(_last_said("RANKED attribute ") == "2", "the server gives Runner its place: %s (address %s)" % [_last_said("RANKED attribute "), _last_said("RANKED address ")])
	check(_last_report("RANK NAME ") == "Runner #2", "and everyone sees it after the name: %s" % _last_report("RANK NAME "))

	for pid in kids: OS.kill(pid)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

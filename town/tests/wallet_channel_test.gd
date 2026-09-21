# Ledger.askPlayer reaches the named player's own wallet and no other machine; a player with
# no key is refused, and the server's own channel signs for nobody.
#
#   godot --headless --path . -s res://tests/wallet_channel_test.gd
#
# A server with no key and three client processes: Alice and Bob keyed, Guest not. Alice's
# write is expected to fail on chain -- a fresh key has no gas -- so what is checked is whose
# wallet tried.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const PORT := 8823

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var kids: Array[int] = []
var heard: Array[String] = []
var t := 0.0
var phase := 0
var keys := {}
var addrs := {}
var reports := {}

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _said(prefix: String) -> String:
	for i in range(heard.size() - 1, -1, -1):
		if heard[i].begins_with(prefix): return heard[i].substr(prefix.length())
	return ""

func _file(who: String) -> String:
	return FileAccess.get_file_as_string(reports[who]) if FileAccess.file_exists(reports[who]) else ""

func _spawn(who: String, key: String) -> void:
	var before := {"PBLOCKZ_PLAYER_KEY": OS.get_environment("PBLOCKZ_PLAYER_KEY"), "PBLOCKZ_NO_DEV_KEY": OS.get_environment("PBLOCKZ_NO_DEV_KEY")}
	OS.set_environment("PBLOCKZ_PLAYER_KEY", key)
	OS.set_environment("PBLOCKZ_NO_DEV_KEY", "1")
	reports[who] = OS.get_user_data_dir().path_join("channel_%s.txt" % who)
	DirAccess.remove_absolute(reports[who])
	var chunk := OS.get_user_data_dir().path_join("channel_peer.luau")
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/chunk_peer.gd", "--", "--port=%d" % PORT, "--chunk=%s" % chunk, "--out=%s" % reports[who],
		"--name=%s" % who, "--noconfirm=1"])
	if pid > 0: kids.append(pid)
	for k in before:
		if before[k] == "": OS.unset_environment(k)
		else: OS.set_environment(k, before[k])

func _initialize() -> void:
	print("a desk asks a player's own wallet")
	var chunk := OS.get_user_data_dir().path_join("channel_peer.luau")
	var f := FileAccess.open(chunk, FileAccess.WRITE)
	f.store_string("""
local chain = game:GetService("ReplicatedStorage"):WaitForChild("Chain", 60)
chain:GetAttributeChangedSignal("AskWallet"):Connect(function()
	local raw = chain:GetAttribute("AskWallet")
	if raw and raw ~= "[]" then print("SEEN ASK " .. raw) end
end)
""")
	f.close()
	for who in ["Alice", "Bob"]:
		keys[who] = PulseBlockzCrypto.keccak256_hex("pulseblockz channel test " + who)
		addrs[who] = PulseBlockzCrypto.address_from_key(keys[who])
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(func(_n, line): heard.append(line))
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)
	_spawn("Alice", keys["Alice"])
	_spawn("Bob", keys["Bob"])
	_spawn("Guest", "")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 25.0:
		phase = 1
		world.run_chunk("ask", """
local Players = game:GetService("Players")
local Ledger = require(game:GetService("ServerScriptService").Ledger)
local Contracts = require(game:GetService("ReplicatedStorage").Contracts)
local function show(tag, a) print(tag .. " " .. (a and (tostring(a.ok) .. "|" .. tostring(a.address) .. "|" .. tostring(a.message)) or "nil")) end
task.spawn(function() show("WHO_ALICE", Ledger.askPlayer(Players.Alice, { action = "who" }, 30)) end)
task.spawn(function() show("WHO_BOB", Ledger.askPlayer(Players.Bob, { action = "who" }, 30)) end)
task.spawn(function() show("GUEST", Ledger.askPlayer(Players.Guest, { action = "who" }, 30)) end)
task.spawn(function()
	show("WRITE_ALICE", Ledger.askPlayer(Players.Alice, { action = "write", to = Contracts.Duelling, fn = "setFighting(bool)", args = { true }, note = "test" }, 60))
end)
task.spawn(function()
	show("SERVER_WRITE", Ledger.request({ action = "write", to = Contracts.Duelling, fn = "setFighting(bool)", args = { true } }, 30))
end)
""")
	elif phase == 1 and (t > 95.0 or (_said("WRITE_ALICE ") != "" and _said("WHO_ALICE ") != "" and _said("SERVER_WRITE ") != "")):
		phase = 2
		for tag in ["WHO_ALICE ", "WHO_BOB ", "GUEST ", "WRITE_ALICE ", "SERVER_WRITE "]: print("    ", tag, _said(tag))
		check(_said("WHO_ALICE ").begins_with("true|%s" % addrs["Alice"]), "asked of Alice, Alice's own wallet answers: %s" % _said("WHO_ALICE "))
		check(_said("WHO_BOB ").begins_with("true|%s" % addrs["Bob"]), "asked of Bob, Bob's: %s" % _said("WHO_BOB "))
		check(_said("GUEST ").begins_with("false|nil|You haven't a wallet"), "a guest has no wallet to ask: %s" % _said("GUEST "))
		check(_file("Alice").contains("setFighting") and not _file("Bob").contains("setFighting") and not _file("Guest").contains("setFighting"),
			"a write asked of Alice reaches Alice's machine and nobody else's")
		var w := _said("WRITE_ALICE ")
		check(w != "" and w != "nil", "and her own wallet answers it: %s" % w)
		check(_said("SERVER_WRITE ").begins_with("false|nil|The town doesn't sign"), "the server's own channel signs for nobody: %s" % _said("SERVER_WRITE "))
		for pid in kids: OS.kill(pid)
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

# Two players at one teller: each is read back their own address, the Guest is told they have no
# wallet, and a wallet half naming somebody else's address is rejected.
#
#   godot --headless --path . -s res://tests/per_player_test.gd
#
# Needs the network: the wallets and the town read from the game's contracts. The keys are
# derived here and hold nothing, so every check is about whose row it is -- the address read
# back, the forged gas refused -- and never about a balance. Ledger.data's "ok" is that row
# finished loading: the catalogue, the holdings the town read for that address, and the
# player's own wallet half.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const PORT := 8824

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

## The last line the teller said to `who` beginning with `start`, from that peer's report file.
func _told(who: String, start: String) -> String:
	var lines := _file(who).split("\n")
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with("SAY " + start): return lines[i]
	return ""

func _spawn(who: String, key: String) -> void:
	var before := {"PBLOCKZ_PLAYER_KEY": OS.get_environment("PBLOCKZ_PLAYER_KEY"), "PBLOCKZ_NO_DEV_KEY": OS.get_environment("PBLOCKZ_NO_DEV_KEY")}
	OS.set_environment("PBLOCKZ_PLAYER_KEY", key)
	OS.set_environment("PBLOCKZ_NO_DEV_KEY", "1")
	reports[who] = OS.get_user_data_dir().path_join("per_player_%s.txt" % who)
	DirAccess.remove_absolute(reports[who])
	var chunk := OS.get_user_data_dir().path_join("per_player_peer.luau")
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/chunk_peer.gd", "--", "--port=%d" % PORT, "--chunk=%s" % chunk, "--out=%s" % reports[who],
		"--name=%s" % who, "--reads=1"])
	if pid > 0: kids.append(pid)
	for k in before:
		if before[k] == "": OS.unset_environment(k)
		else: OS.set_environment(k, before[k])

func _initialize() -> void:
	print("each player is told about their own wallet")
	for who in ["Alice", "Bob"]:
		keys[who] = PulseBlockzCrypto.keccak256_hex("pulseblockz per player test " + who)
		addrs[who] = PulseBlockzCrypto.address_from_key(keys[who])
	var f := FileAccess.open(OS.get_user_data_dir().path_join("per_player_peer.luau"), FileAccess.WRITE)
	f.store_string("""
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local me = Players.LocalPlayer
local bank = rs:WaitForChild("BankRemote", 60)
bank.OnClientEvent:Connect(function(kind, payload)
	if kind == "say" and type(payload) == "table" and payload.lines then
		print("SEEN SAY " .. table.concat(payload.lines, " | "))
	end
end)
task.spawn(function()
	for _ = 1, 100 do
		bank:FireServer("receive")
		task.wait(3)
	end
end)
-- The forgery: a wallet half naming somebody else's address, sent as though it were ours.
rs:GetAttributeChangedSignal("ForgeFor"):Connect(function()
	local victim = rs:GetAttribute("ForgeFor")
	if me.Name ~= "Bob" or type(victim) ~= "string" then return end
	rs:WaitForChild("MineRemote"):FireServer(game:GetService("HttpService"):JSONEncode({
		address = victim, gas = "999999999", gas_wei = "999999999000000000000000000", can_buy = true, tokens = {},
	}))
	print("SEEN FORGED")
end)
""")
	f.close()
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

## Prints "<tag>_<name> status|address|gas|holdings-read" for Alice and Bob, from the server.
func _pictures(tag: String) -> void:
	world.run_chunk("pictures", """
local Players = game:GetService("Players")
local Ledger = require(game:GetService("ServerScriptService").Ledger)
for _, name in ipairs({ "Alice", "Bob" }) do
	local p = Players:FindFirstChild(name)
	local d = p and Ledger.data(p)
	local line = d and table.concat({ tostring(d.status), tostring(d.address), tostring(d.gas), tostring(Ledger.holdings(p) ~= nil) }, "|") or "nil"
	print("%s_" .. name .. " " .. line)
end
""" % tag)

func _done() -> bool:
	return _told("Alice", "This is you").contains(addrs["Alice"]) and _told("Bob", "This is you").contains(addrs["Bob"]) \
		and _told("Guest", "You haven't signed in") != ""

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and (_done() or t > 240.0):
		phase = 1
		print("    answered after %.0fs" % t)
		_pictures("PIC")
	elif phase == 1 and _said("PIC_Bob ") != "":
		phase = 2
		world.run_chunk("forge", """game:GetService("ReplicatedStorage"):SetAttribute("ForgeFor", "%s")""" % addrs["Alice"])
		t = 0.0
	elif phase == 2 and t > 6.0:
		phase = 3
		_pictures("AFTER")
	elif phase == 3 and _said("AFTER_Bob ") != "":
		phase = 4
		var a := _told("Alice", "This is you")
		var b := _told("Bob", "This is you")
		print("    Alice was told: ", a.substr(0, 120))
		print("    Bob was told:   ", b.substr(0, 120))
		print("    Guest was told: ", _told("Guest", "You haven't").substr(0, 120))
		for tag in ["PIC_Alice ", "PIC_Bob ", "AFTER_Alice ", "AFTER_Bob "]: print("    ", tag, _said(tag))
		check(a.contains(addrs["Alice"]) and not a.contains(addrs["Bob"]), "Alice asks who she is, and is read back her own address")
		check(b.contains(addrs["Bob"]) and not b.contains(addrs["Alice"]), "Bob asks, and is read back his")
		check(_told("Guest", "You haven't signed in") != "" and not _file("Guest").contains("This is you"),
			"the guest is told there is no wallet of theirs to read, not shown anybody else's")
		check(_said("PIC_Alice ").begins_with("ok|%s|" % addrs["Alice"]) and _said("PIC_Alice ").ends_with("|true"),
			"the server's picture of Alice is hers, finished, with her holdings read: %s" % _said("PIC_Alice "))
		check(_said("PIC_Bob ").begins_with("ok|%s|" % addrs["Bob"]) and _said("PIC_Bob ").ends_with("|true"),
			"and of Bob, his: %s" % _said("PIC_Bob "))
		check(_file("Bob").contains("FORGED"), "Bob sent a wallet half naming Alice's address")
		check(_said("AFTER_Bob ") == _said("PIC_Bob "),
			"and Bob's picture did not take it -- still his own wallet's word: %s" % _said("AFTER_Bob "))
		check(not _said("AFTER_Alice ").contains("999999999") and _said("AFTER_Alice ") == _said("PIC_Alice "),
			"nor did Alice's change: %s" % _said("AFTER_Alice "))
		for pid in kids: OS.kill(pid)
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

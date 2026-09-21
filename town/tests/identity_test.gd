# A player is their wallet: sign-in at the door.
#
#   godot --headless --path . -s res://tests/identity_test.gd
#
# A server and five clients: two with a wallet key, one with none, two forging. A wallet signs
# the server's nonce on the client's own machine; the server holds no key and only recovers the
# signer. Alice reports what her machine sees, so addresses are checked over the wire as well.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const PORT := 8822

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var kids: Array[int] = []
var heard: Array[String] = []
var t := 0.0
var phase := 0
var keys := {}
var addrs := {}
var alice_report := ""
var forger_report := ""
var relay_report := ""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _said(prefix: String) -> String:
	for i in range(heard.size() - 1, -1, -1):
		if heard[i].begins_with(prefix): return heard[i].substr(prefix.length())
	return ""

func _file_last(path: String, prefix: String) -> String:
	if not FileAccess.file_exists(path): return ""
	var lines := FileAccess.get_file_as_string(path).split("\n", false)
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with(prefix): return lines[i].substr(prefix.length())
	return ""

func _spawn(script: String, args: Array, env: Dictionary) -> void:
	# The child inherits this process's environment: set for the spawn, restored after.
	var before := {}
	for k in env:
		before[k] = OS.get_environment(k)
		OS.set_environment(k, env[k])
	var full := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://" + script, "--", "--port=%d" % PORT]
	full.append_array(args)
	var pid := OS.create_process(OS.get_executable_path(), full)
	if pid > 0: kids.append(pid)
	for k in before:
		if before[k] == "": OS.unset_environment(k)
		else: OS.set_environment(k, before[k])

func _initialize() -> void:
	print("sign-in: a player is their wallet")
	for who in ["Alice", "Bob"]:
		keys[who] = PulseBlockzCrypto.keccak256_hex("pulseblockz identity test " + who)
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

	alice_report = OS.get_user_data_dir().path_join("identity_alice.txt")
	forger_report = OS.get_user_data_dir().path_join("identity_forger.txt")
	relay_report = OS.get_user_data_dir().path_join("identity_relay.txt")
	if FileAccess.file_exists(relay_report): DirAccess.remove_absolute(relay_report)
	DirAccess.remove_absolute(alice_report)
	DirAccess.remove_absolute(forger_report)
	var chunk := OS.get_user_data_dir().path_join("identity_alice.luau")
	var f := FileAccess.open(chunk, FileAccess.WRITE)
	f.store_string("""
local Players = game:GetService("Players")
while true do
	task.wait(0.5)
	local seen = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(seen, p.Name .. "=" .. tostring(p:GetAttribute("WalletAddress")))
	end
	table.sort(seen)
	print("SEEN ADDRS " .. table.concat(seen, " "))
end
""")
	f.close()
	_spawn("tests/chunk_peer.gd", ["--chunk=%s" % chunk, "--out=%s" % alice_report, "--name=Alice"],
		{"PBLOCKZ_PLAYER_KEY": keys["Alice"], "PBLOCKZ_NO_DEV_KEY": "1"})
	_spawn("tests/chunk_peer.gd", ["--chunk=%s" % chunk, "--out=%s" % OS.get_user_data_dir().path_join("identity_bob.txt"), "--name=Bob"],
		{"PBLOCKZ_PLAYER_KEY": keys["Bob"], "PBLOCKZ_NO_DEV_KEY": "1"})
	_spawn("tests/chunk_peer.gd", ["--chunk=%s" % chunk, "--out=%s" % OS.get_user_data_dir().path_join("identity_guest.txt"), "--name=Guest"],
		{"PBLOCKZ_PLAYER_KEY": "", "PBLOCKZ_NO_DEV_KEY": "1"})
	_spawn("tests/identity_forger.gd", ["--claim=%s" % addrs["Alice"], "--key=%s" % keys["Bob"], "--out=%s" % forger_report],
		{"PBLOCKZ_PLAYER_KEY": "", "PBLOCKZ_NO_DEV_KEY": "1"})
	_spawn("tests/identity_forger.gd", ["--name=Relayed", "--for=evil.example:%d" % PORT, "--key=%s" % keys["Bob"], "--out=%s" % relay_report],
		{"PBLOCKZ_PLAYER_KEY": "", "PBLOCKZ_NO_DEV_KEY": "1"})

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 25.0:
		phase = 1
		world.run_chunk("read", """
local Players = game:GetService("Players")
local seen = {}
for _, name in ipairs({ "Alice", "Bob", "Guest", "Forger", "Relayed" }) do
	local p = Players:FindFirstChild(name)
	table.insert(seen, name .. "=" .. (p and tostring(p:GetAttribute("WalletAddress")) or "absent"))
end
print("SERVER " .. table.concat(seen, " "))
""")
	elif phase == 1 and t > 26.5:
		phase = 2
		var server := _said("SERVER ")
		print("    server sees: ", server)
		print("    Alice's machine sees: ", _file_last(alice_report, "ADDRS "))
		print("    forger: ", FileAccess.get_file_as_string(forger_report).replace("\n", " | ") if FileAccess.file_exists(forger_report) else "(nothing)")
		check(server.contains("Alice=%s" % addrs["Alice"]), "Alice's own wallet signed her in as her address")
		check(server.contains("Bob=%s" % addrs["Bob"]) and addrs["Alice"] != addrs["Bob"], "Bob as his, a different one: two players are two wallets")
		check(server.contains("Guest=nil"), "a player with no key joins as a guest, with no address")
		check(server.contains("Forger=absent") and FileAccess.file_exists(forger_report)
			and FileAccess.get_file_as_string(forger_report).contains("DISCONNECTED"),
			"one who signs with one key and claims another's address is refused at the door")
		check(server.contains("Relayed=absent") and FileAccess.file_exists(relay_report)
			and FileAccess.get_file_as_string(relay_report).contains("DISCONNECTED"),
			"a sign-in signed for another server's name is refused, even with an honest signature: %s" % [FileAccess.get_file_as_string(relay_report).replace("\n", " | ") if FileAccess.file_exists(relay_report) else "(nothing)"])
		var theirs := _file_last(alice_report, "ADDRS ")
		check(theirs.contains("Alice=%s" % addrs["Alice"]) and theirs.contains("Bob=%s" % addrs["Bob"]) and theirs.contains("Guest=nil"),
			"and every player's machine sees the same addresses: %s" % theirs)
		for pid in kids: OS.kill(pid)
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

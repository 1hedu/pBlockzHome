# Two players with the same name are two players.
#
#   godot --headless --path . -s res://tests/identity_twins_test.gd
#
# The stock client's name is a constant (Main.tscn: "Founder"), so two people who never changed
# it arrive with the same name. The Welcome names the Player the server made for this client,
# and the client becomes that one rather than whichever Player is called that.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const Peer = preload("res://tests/Peer.gd")
const PORT := 8826

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var peers := []
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

func _file_last(path: String, prefix: String) -> String:
	if not FileAccess.file_exists(path): return ""
	var lines := FileAccess.get_file_as_string(path).split("\n", false)
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with(prefix): return lines[i].substr(prefix.length())
	return ""

func _initialize() -> void:
	print("twins: two players with the same name are two players")
	for who in ["A", "B"]:
		keys[who] = PulseBlockzCrypto.keccak256_hex("pulseblockz twins test " + who)
		addrs[who] = PulseBlockzCrypto.address_from_key(keys[who])
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(func(_n, line): heard.append(line))
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)

	var chunk := OS.get_user_data_dir().path_join("twins.luau")
	var f := FileAccess.open(chunk, FileAccess.WRITE)
	f.store_string("""
local Players = game:GetService("Players")
while true do
	task.wait(0.5)
	local me = Players.LocalPlayer
	local gui = me and me:FindFirstChildOfClass("PlayerGui")
	local count = #Players:GetPlayers()
	print(("SEEN ME %s uid=%s addr=%s gui=%s players=%d"):format(me and me.Name or "nil",
		me and tostring(me.UserId) or "nil", me and tostring(me:GetAttribute("WalletAddress")) or "nil",
		gui and "yes" or "no", count))
end
""")
	f.close()
	for who in ["A", "B"]:
		reports[who] = OS.get_user_data_dir().path_join("twins_%s.txt" % who)
		DirAccess.remove_absolute(reports[who])
		peers.append(Peer.spawn("res://tests/chunk_peer.gd",
			["--port=%d" % PORT, "--chunk=%s" % chunk, "--out=%s" % reports[who]],
			{ "key": keys[who], "name": "Founder", "reads": false }))

func _server_players() -> void:
	world.run_chunk("read", """
local Players = game:GetService("Players")
local seen = {}
for _, p in ipairs(Players:GetPlayers()) do
	table.insert(seen, p.Name .. "/" .. tostring(p.UserId) .. "/" .. tostring(p:GetAttribute("WalletAddress")))
end
table.sort(seen)
print("SERVER " .. #seen .. " " .. table.concat(seen, " "))
""")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 20.0:
		phase = 1
		_server_players()
	elif phase == 1 and t > 21.5:
		phase = 2
		var server := _said("SERVER ")
		var a := _file_last(reports["A"], "ME ")
		var b := _file_last(reports["B"], "ME ")
		print("    server: ", server)
		print("    A: ", a)
		print("    B: ", b)
		check(server.begins_with("2 "), "the server has two Players called Founder")
		check(a.contains("addr=%s" % addrs["A"]) and a.contains("gui=yes"), "A's LocalPlayer carries A's address and has a PlayerGui")
		check(b.contains("addr=%s" % addrs["B"]) and b.contains("gui=yes"), "B's LocalPlayer carries B's address and has a PlayerGui")
		var ua := a.get_slice("uid=", 1).get_slice(" ", 0)
		var ub := b.get_slice("uid=", 1).get_slice(" ", 0)
		check(ua != "" and ua != ub, "and they are different Players (UserId %s vs %s)" % [ua, ub])
		check(a.contains("players=2") and b.contains("players=2"), "each machine sees both")
		Peer.stop(peers[1])
		t = 0.0
	# B is killed, not asked to leave, so the server only learns of it on connection timeout:
	# a few seconds idle, longer under load. Polled once a second for up to thirty.
	elif phase == 2 and t > 5.0:
		phase = 3
		t = 0.0
		_server_players()
	elif phase == 3 and t > 1.0 and not _said("SERVER ").begins_with("1 ") and t < 30.0 and int(t) != int(t - delta):
		_server_players()
	# The drop reaches A a report later than the server, so A is waited for separately.
	elif phase == 3 and (_said("SERVER ").begins_with("1 ") or t >= 30.0):
		phase = 35
		t = 0.0
	elif phase == 35 and (_file_last(reports["A"], "ME ").contains("players=1") or t >= 10.0):
		phase = 4
		var server := _said("SERVER ")
		var a := _file_last(reports["A"], "ME ")
		print("    after B left, server: ", server, "  A: ", a)
		check(server.begins_with("1 ") and server.contains(addrs["A"]), "B leaving removed B's Player, not A's")
		check(a.contains("addr=%s" % addrs["A"]) and a.contains("players=1"), "A is still A")
		for p in peers: Peer.stop(p)
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

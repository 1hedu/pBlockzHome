# A ranked duel, start to finish, with three real players.
#
#   node scripts/dev-chain.js --block-time 2        (in another shell, and leave it running)
#   PBLOCKZ_RPC_URL=http://127.0.0.1:8545 godot --headless --path . -s res://tests/duel_test.gd
#
# A keyless server and three peer clients with their own wallets.
# It needs the dev chain's own DuelRecords, because the town checks every signature it is handed
# against the contract (signerOf) before keeping it: a stand-in address has them all refused.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const TypedData = preload("res://host/TypedData.gd")
const PORT := 8825

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var kids := {}
var heard: Array[String] = []
var t := 0.0
var phase := 0
var at := 0.0
var keys := {}
var addrs := {}
var reports := {}
var carol_heard_duel := false

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _said(prefix: String) -> String:
	for i in range(heard.size() - 1, -1, -1):
		if heard[i].begins_with(prefix): return heard[i].substr(prefix.length())
	return ""

func _file(who: String) -> String:
	return FileAccess.get_file_as_string(reports[who]) if FileAccess.file_exists(reports[who]) else ""

func _line(who: String, start: String) -> String:
	var lines := _file(who).split("\n")
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with(start): return lines[i]
	return ""

func _with(who: String, needle: String) -> String:
	var lines := _file(who).split("
")
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].contains(needle): return lines[i]
	return ""

func _spawn(who: String) -> void:
	var before := {"PBLOCKZ_PLAYER_KEY": OS.get_environment("PBLOCKZ_PLAYER_KEY"), "PBLOCKZ_NO_DEV_KEY": OS.get_environment("PBLOCKZ_NO_DEV_KEY")}
	OS.set_environment("PBLOCKZ_PLAYER_KEY", keys[who])
	OS.set_environment("PBLOCKZ_NO_DEV_KEY", "1")
	reports[who] = OS.get_user_data_dir().path_join("duel_%s.txt" % who)
	DirAccess.remove_absolute(reports[who])
	var chunk := OS.get_user_data_dir().path_join("duel_peer.luau")
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/chunk_peer.gd", "--", "--port=%d" % PORT, "--chunk=%s" % chunk, "--out=%s" % reports[who],
		"--name=%s" % who, "--noconfirm=1"])
	if pid > 0: kids[who] = pid
	for k in before:
		if before[k] == "": OS.unset_environment(k)
		else: OS.set_environment(k, before[k])

func _initialize() -> void:
	print("a ranked duel")
	var state = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://../../../.dev-chain.json")))
	duel_records = String(state.get("DuelRecords", "")) if typeof(state) == TYPE_DICTIONARY else ""
	if OS.get_environment("PBLOCKZ_RPC_URL") == "" or duel_records == "":
		printerr("  FAIL needs the dev chain: node scripts/dev-chain.js, and PBLOCKZ_RPC_URL set to it")
		print("0 passed, 1 failed")
		quit(1)
		return
	# Fresh addresses every run: a leaderboard left over from a previous run is not what this run did.
	var run := str(Time.get_unix_time_from_system()) + str(randi())
	for who in ["Alice", "Bob", "Carol"]:
		keys[who] = PulseBlockzCrypto.keccak256_hex("pulseblockz duel test %s %s" % [who, run])
		addrs[who] = PulseBlockzCrypto.address_from_key(keys[who])
	var f := FileAccess.open(OS.get_user_data_dir().path_join("duel_peer.luau"), FileAccess.WRITE)
	f.store_string("""
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local me = Players.LocalPlayer
local fun = rs:WaitForChild("FunRemote", 60)
fun.OnClientEvent:Connect(function(kind, p)
	if type(p) ~= "table" then return end
	if kind == "open" then
		print("SEEN OPEN " .. tostring(p.greeting))
		for _, m in ipairs(p.menu or {}) do
			if m.id == "accept" then task.wait(0.5) fun:FireServer("accept", m.arg) end
		end
	elseif kind == "say" then
		print("SEEN SAY " .. table.concat(p.lines or {}, " | "))
	end
end)
rs:WaitForChild("DuelRemote", 60).OnClientEvent:Connect(function(kind, text)
	print("SEEN ANNOUNCE " .. tostring(text))
end)
local chain = rs:WaitForChild("Chain", 60)
chain:GetAttributeChangedSignal("AskWallet"):Connect(function()
	local raw = chain:GetAttribute("AskWallet")
	if raw and raw ~= "[]" then print("SEEN ASK " .. raw) end
end)
rs:GetAttributeChangedSignal("TestChallenge"):Connect(function()
	if me.Name ~= "Alice" then return end
	fun:FireServer("ranked") task.wait(0.4)
	fun:FireServer("mode", "1v1") task.wait(0.4)
	fun:FireServer("foe", "Bob") task.wait(0.4)
	fun:FireServer("challenge", nil, "2")
end)
rs:GetAttributeChangedSignal("TestAgree"):Connect(function()
	if me.Name == "Carol" then fun:FireServer("agree", rs:GetAttribute("TestAgree")) end
end)
rs:GetAttributeChangedSignal("TestOnChain"):Connect(function()
	if me.Name == "Alice" then fun:FireServer("onchain", rs:GetAttribute("TestOnChain")) end
end)
task.spawn(function()
	local gui = me:WaitForChild("PlayerGui", 60)
	while true do
		task.wait(0.5)
		local s = gui and gui:FindFirstChild("DuelScore")
		if s and s.Enabled then
			local t = {}
			for _, d in ipairs(s:GetDescendants()) do
				if d:IsA("TextLabel") and d.Name ~= "Shadow" and d.Text ~= "" then table.insert(t, d.Text) end
			end
			print("SEEN SCORE " .. table.concat(t, " / "))
		end
	end
end)
""")
	f.close()
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	# In memory: the default is user://datastores.json, the record a real server keeps.
	world.data_store_path = ""
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(func(_n, line): heard.append(line))
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)
	for who in ["Alice", "Bob", "Carol"]:
		_spawn(who)

const HEAD := """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Health = require(game:GetService("ServerScriptService").Health)
local Duels = require(game:GetService("ServerScriptService").Duels)
local Ledger = require(game:GetService("ServerScriptService").Ledger)
local Alice, Bob, Carol = Players:FindFirstChild("Alice"), Players:FindFirstChild("Bob"), Players:FindFirstChild("Carol")
local function bare(p)
	local ff = p and p.Character and p.Character:FindFirstChildOfClass("ForceField")
	if ff then ff:Destroy() end
end
"""

func _run(name: String, body: String) -> void:
	world.run_chunk(name, HEAD + body.replace("DUEL_RECORDS", duel_records))

## The dev chain's DuelRecords address, out of the .dev-chain.json scripts/dev-chain.js writes.
var duel_records := ""

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if t > 3.0 and int(t * 2) != int((t - delta) * 2):
				_run("signed", """
local n = 0
for _, p in ipairs({ Alice, Bob, Carol }) do if p and Ledger.addressOf(p) then n += 1 end end
print("SIGNED " .. n)
""")
			if _said("SIGNED ") == "3" or t > 90.0:
				phase = 1; at = t
				# What is checked from here on is who is asked to sign what, not whether a transaction lands.
				_run("go", """
require(rs.Contracts).DuelRecords = "DUEL_RECORDS"
rs:SetAttribute("TestChallenge", os.clock())
""")
		1:
			if t - at > 6.0:
				phase = 2; at = t
				_run("sides", """
local a, ta = Health.sideOf(Alice)
local b, tb = Health.sideOf(Bob)
print("SIDES " .. tostring(ta) .. "|" .. tostring(tb) .. "|" .. tostring(a ~= nil and a == b) .. "|" .. tostring(Health.sideOf(Carol)))
""")
		2:
			if t - at > 3.0:
				phase = 3; at = t
				# bare() first: a fresh body's spawn ForceField would absorb the blow.
				_run("rules", """
bare(Alice) bare(Bob) bare(Carol)
print("RULES " .. table.concat({
	tostring(Health.hit(Alice, Carol, 1, 0)),
	tostring(Health.hit(Carol, Alice, 1, 0)),
	tostring(Health.heal(Bob, Carol, 1)),
	tostring(Health.hit(Bob, Alice, 1, 0)),
}, "|"))
""")
		3:
			if t - at > 2.0:
				phase = 4; at = t
				_run("frag1", """
bare(Bob)
print("FRAG1 " .. tostring(Health.hit(Bob, Alice, 1000, 0)))
""")
		4:
			if t - at > 5.0:
				phase = 5; at = t
				_run("frag2", """
bare(Bob) bare(Alice)
print("FRAG2 " .. tostring(Health.hit(Bob, Alice, 1000, 0)))
""")
		5:
			# Polled: both wallets are asked to agree, answer, and each signature is read back
			# against the contract before it is kept.
			if t - at > 8.0 and int(t * 0.5) != int((t - delta) * 0.5):
				_run("agreed", "local r = Duels.recent(Alice)[1] print('AGREED ' .. tostring(r ~= nil and Duels.agreedByBoth(r)))")
			if (t - at > 8.0 and _said("AGREED ") == "true") or t - at > 60.0:
				phase = 6; at = t
				carol_heard_duel = _file("Carol").contains("ANNOUNCE Alice")
				_run("after", """
local r = Duels.recent(Alice)[1]
print("AFTER " .. tostring(Health.sideOf(Alice)) .. "|" .. tostring(Health.mayHurt(Carol, Alice)))
print("RESULT " .. (r and HttpService:JSONEncode(r) or "nil"))
print("TYPED " .. HttpService:JSONEncode(Duels.typed(r)))
print("SIGS " .. HttpService:JSONEncode(r.signatures or {}))
print("BOTH " .. tostring(Duels.agreedByBoth(r)))
local rows = {}
for _, row in ipairs(Duels.leaderboard(50)) do table.insert(rows, row.address .. "=" .. row.kills .. "k" .. row.wins .. "/" .. row.losses) end
print("BOARD " .. table.concat(rows, ","))
-- As though the contract had not been deployed after all.
require(rs.Contracts).DuelRecords = ""
if r then rs:SetAttribute("TestOnChain", r.id) end
""")
		6:
			if t - at > 4.0:
				phase = 7; at = t
				_run("contract", """
require(rs.Contracts).DuelRecords = "DUEL_RECORDS"
rs:SetAttribute("TestOnChain", Duels.recent(Alice)[1].id .. " ")
""")
		7:
			if _with("Alice", "record(bytes32") != "" or t - at > 60.0:
				phase = 8; at = t
				_run("second", """
local c = Duels.challenge({ Alice }, { Carol }, 3)
if c then Duels.accept(c, Carol) end
print("SECOND " .. tostring(c ~= nil))
""")
		8:
			if t - at > 3.0:
				phase = 9; at = t
				OS.kill(kids["Carol"])
		9:
			# Carol is gone, so Bob -- the one signed-in bystander -- is asked to witness instead.
			if t - at > 8.0:
				phase = 95; at = t
				_run("forfeit", """
local r = Duels.recent(Alice)[1]
print("FORFEIT " .. (r and (tostring(r.forfeit) .. "|" .. tostring(r.winner) .. "|" .. r.mode) or "nil"))
print("FORFEIT_ID " .. (r and r.id or ""))
print("WALKED " .. tostring(r and Duels.signedBy(r, Ledger.addressOf(Alice))) .. "|" .. tostring(r and Duels.agreedByBoth(r)))
print("WITNESSED " .. tostring(r and Duels.witnessed(r)) .. "|" .. HttpService:JSONEncode(r and r.witnessesAsked or {}))
print("WSIGS " .. HttpService:JSONEncode(r and r.witnesses or {}))
if r then rs:SetAttribute("TestOnChain", r.id .. "  ") end
""")
		95:
			if _with("Alice", "recordWitnessed(") != "" or t - at > 30.0:
				phase = 10; at = t
				# Carol back, on the same key and so the same address.
				_spawn("Carol")
		10:
			if t - at > 3.0 and int(t * 2) != int((t - delta) * 2):
				_run("back", """
local c = Players:FindFirstChild("Carol")
print("BACK " .. tostring(c ~= nil and Ledger.addressOf(c) ~= nil))
""")
			if _said("BACK ") == "true" or t - at > 60.0:
				phase = 11; at = t
				_run("agree_later", """rs:SetAttribute("TestAgree", "%s")""" % _said("FORFEIT_ID "))
		11:
			if t - at > 8.0:
				phase = 12; at = t
				_run("later", """
local r = Duels.result("%s")
print("LATER " .. tostring(r and Duels.signedBy(r, Ledger.addressOf(Carol))) .. "|" .. tostring(r and Duels.agreedByBoth(r)))
""" % _said("FORFEIT_ID "))
		12:
			if t - at > 2.0:
				phase = 13
				_verdict()
	return false

func _verdict() -> void:
	var bob_open := _line("Bob", "OPEN ")
	print("    Bob was shown: ", bob_open.substr(0, 110))
	check(bob_open.contains("Alice challenges you to a ranked 1v1") and bob_open.contains("first to 2"),
		"Bob is asked on his own screen, by name, with the limit")
	check(_said("SIDES ").begins_with("A|B|true|nil"), "once he says yes they are on opposite sides of one duel, and Carol on neither: %s" % _said("SIDES "))
	var rules := _said("RULES ").split("|")
	print("    rules: ", _said("RULES "))
	check(rules.size() == 4 and rules[0] == "false", "Carol cannot hurt Alice")
	check(rules.size() == 4 and rules[1] == "false", "Alice cannot hurt Carol")
	check(rules.size() == 4 and rules[2] == "false", "Carol cannot mend Bob")
	check(rules.size() == 4 and rules[3] == "true", "Alice can hurt Bob")
	var score := _file("Alice")
	check(score.contains("SCORE Alice  0 - 0  Bob / First to 2") or score.contains("SCORE First to 2 / Alice  0 - 0  Bob"),
		"Alice's screen shows the score and the limit")
	check(score.contains("Alice  1 - 0  Bob"), "and follows it")
	check(_said("FRAG1 ") == "true" and _said("FRAG2 ") == "true", "two killing blows landed")
	check(_file("Bob").contains("ANNOUNCE Alice win, 2 - 0"), "Bob is told who won: %s" % _line("Bob", "ANNOUNCE").substr(0, 90))
	check(_file("Alice").contains("ANNOUNCE Alice got Bob"), "Alice hears each frag")
	check(not carol_heard_duel, "and Carol, who was not in it, hears none of it")
	check(_said("AFTER ").begins_with("nil|true"), "afterwards the sides are gone and the open town's rules are back: %s" % _said("AFTER "))

	var r = JSON.parse_string(_said("RESULT "))
	check(typeof(r) == TYPE_DICTIONARY and int(r.fragsA) == 2 and int(r.fragsB) == 0 and int(r.winner) == 1 and not r.forfeit
		and int(r.teamA[0].kills) == 2 and int(r.teamB[0].kills) == 0,
		"the result is on the town's record: %s" % _said("RESULT ").substr(0, 120))
	if typeof(r) == TYPE_DICTIONARY:
		check(String(r.teamA[0].address).to_lower() == String(addrs["Alice"]).to_lower()
			and String(r.teamB[0].address).to_lower() == String(addrs["Bob"]).to_lower(), "under the addresses they signed in with")
	var board := _said("BOARD ")
	print("    board: ", board)
	check(board.begins_with(String(addrs["Alice"]).to_lower() + "=2k1/0") and board.contains(String(addrs["Bob"]).to_lower() + "=0k0/1"),
		"the leaderboard ranks by kills: Alice's two first, and Bob on it with none")

	check(_with("Alice", "sign_typed").contains("PulseBlockz Duels") and _with("Bob", "sign_typed").contains("PulseBlockz Duels"),
		"the moment it ends, both Alice's and Bob's wallets are asked to agree to the result")
	var sigs = JSON.parse_string(_said("SIGS "))
	var typed = JSON.parse_string(_said("TYPED "))
	var d: Dictionary = TypedData.digest(typed) if typeof(typed) == TYPE_DICTIONARY else {}
	for who in ["Alice", "Bob"]:
		var one := String((sigs as Dictionary).get(String(addrs[who]).to_lower(), "")) if typeof(sigs) == TYPE_DICTIONARY else ""
		check(one.length() == 132 and d.get("ok", false) and PulseBlockzCrypto.recover_address(d.digest, one) == addrs[who],
			"%s's signature is kept, and it is %s's, over exactly that result" % [who, who])
	check(_said("BOTH ") == "true", "so both sides have agreed")
	check(_file("Bob").contains("ANNOUNCE Both sides have agreed"), "and they are told so")

	check(_file("Alice").contains("isn't on chain yet"), "putting it on chain with no contract says so")
	var sig := String((sigs as Dictionary).get(String(addrs["Bob"]).to_lower(), "")) if typeof(sigs) == TYPE_DICTIONARY else ""
	var alice_ask := _with("Alice", "record(bytes32")
	check(alice_ask.contains("record(bytes32,address[],address[],uint16[],uint16[],uint16,uint8,uint64,bytes)") and sig != "" and alice_ask.contains(sig.substr(2, 20)),
		"with one, Alice's own wallet is asked to send it, carrying Bob's kept signature")
	var bob_asks := {}
	for line in _file("Bob").split("\n"):
		if line.contains("sign_typed") and not line.contains("Witness a ranked duel"):
			var at_n := line.find("\"n\":")
			if at_n >= 0: bob_asks[line.substr(at_n, 12)] = true
	check(bob_asks.size() == 1, "and Bob is not asked a second time: he already agreed (%d asks)" % bob_asks.size())

	check(_said("SECOND ") == "true", "a second duel starts, Alice against Carol")
	check(_said("FORFEIT ") == "true|1|1v1", "Carol walks out, and it goes down as Alice's win by forfeit: %s" % _said("FORFEIT "))
	check(_said("WALKED ") == "true|false", "Alice agrees to it; Carol, gone, has not: %s" % _said("WALKED "))
	var bob_witness := _with("Bob", "Witness a ranked duel")
	check(bob_witness.contains("sign_typed") and bob_witness.contains("Alice beat Carol"),
		"so Bob, signed in and not in it, is asked to witness it")
	check(_said("WITNESSED ") == "true|[\"%s\"]" % String(addrs["Bob"]).to_lower(),
		"he signs, and one of one is a majority: it is witnessed: %s" % _said("WITNESSED "))
	var wsigs = JSON.parse_string(_said("WSIGS "))
	var wsig := String((wsigs as Dictionary).get(String(addrs["Bob"]).to_lower(), "")) if typeof(wsigs) == TYPE_DICTIONARY else ""
	var alice_witnessed := _with("Alice", "recordWitnessed(")
	check(alice_witnessed.contains("recordWitnessed(bytes32,address[],address[],uint16[],uint16[],uint16,uint8,uint64,bytes[])")
		and wsig != "" and alice_witnessed.contains(wsig.substr(2, 20)),
		"and with Carol away, putting it on chain asks Alice to send it as witnessed, carrying Bob's witness signature")
	check(_said("LATER ") == "true|true", "Carol comes back later and agrees to it at the Funmaster, and now both sides have: %s" % _said("LATER "))
	for who in kids: OS.kill(kids[who])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

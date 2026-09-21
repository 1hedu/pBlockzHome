# Funmaster Mike hands out the fishing rod: who gets one, where it is kept, and how it is worn.
#
#   godot --headless --path . -s res://tests/fishing_rod_test.gd
#
# Play Solo, the DataStore in memory.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const ADDRESS := "0x00000000000000000000000000000000F15Ab0B0"

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the fishing rod")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _heard_any(needle: String) -> bool:
	for line in said:
		if line.contains(needle): return true
	return false

func _said(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

const SERVER_HEAD := """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local sss = game:GetService("ServerScriptService")
local player = Players:GetPlayers()[1]
local Angling = require(sss.Angling)
"""

func _server(body: String) -> void:
	world.run_chunk("rod", SERVER_HEAD + body)

func _client(body: String) -> void:
	world.run_client_chunk("rodc", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
""" + body)

func _ask(action: String) -> void:
	said.clear()
	_client("rs:WaitForChild(\"FunRemote\"):FireServer(\"%s\")" % action)
	await create_timer(1.0).timeout

func _items() -> String:
	said.clear()
	_client("rs:WaitForChild(\"WardrobeRemote\"):FireServer(\"list\")")
	await create_timer(1.0).timeout
	return _said("ITEMS ")

func _wear(model: String) -> String:
	_client("rs:WaitForChild(\"WardrobeRemote\"):FireServer(\"wear\", \"%s\")" % model)
	await create_timer(1.2).timeout
	said.clear()
	_server("""
local ch = player.Character
local acc = ch and ch:FindFirstChild("%s")
local grip = acc and acc:FindFirstChild("Handle") and acc.Handle:FindFirstChildOfClass("Attachment")
print("WORN " .. tostring(acc ~= nil and acc:IsA("Accessory")) .. " " .. (grip and grip.Name or "-"))
""" % model)
	await create_timer(0.4).timeout
	return _said("WORN ")

func _run() -> void:
	await create_timer(10.0).timeout
	_client("""
rs:WaitForChild("FunRemote").OnClientEvent:Connect(function(kind, p)
	if kind == "say" then
		local ids = {}
		for _, m in ipairs(p.menu or {}) do table.insert(ids, m.id .. "=" .. m.label) end
		print("SAY " .. table.concat(p.lines or {}, " ") .. " || " .. table.concat(ids, ","))
	else
		print("FUN " .. tostring(kind))
	end
end)
rs:WaitForChild("Notify").OnClientEvent:Connect(function(card)
	print("NOTIFY " .. tostring(card.Title) .. " | " .. tostring(card.Text))
end)
rs:WaitForChild("WardrobeRemote").OnClientEvent:Connect(function(kind, items)
	if kind ~= "items" then return end
	local names = {}
	for _, it in ipairs(items) do table.insert(names, it.name) end
	print("ITEMS " .. table.concat(names, ","))
end)
""")
	await create_timer(0.5).timeout

	# Play Solo signs in with the dev key, so sign out to be a guest.
	_server("player:SetAttribute(\"WalletAddress\", \"\")")
	await create_timer(0.8).timeout
	await _ask("fishing")
	var guest := _said("SAY ")
	check(guest.contains("Sign in") and guest.contains("fishing=Space Fishing?") and not guest.contains("fishboard"),
		"a guest is told to sign in and keeps the question (%s)" % guest)
	check(not (await _items()).contains("Dysnomia Rod"), "and has no rod")

	_server("player:SetAttribute(\"WalletAddress\", \"%s\")" % ADDRESS)
	# The chime stays quiet for a spell after signing in: what arrives inside it is not newly received.
	await create_timer(9.0).timeout
	await _ask("fishing")
	var given := _said("SAY ")
	check(given.contains("Turn the other cheek kinda guy? Here you go, the space fishing is excellent right now. Just throw a cast anywhere off the edge of the map."),
		"signed in, he says his line (%s)" % given)
	check(given.contains("fishboard=Space Fishing Leaderboard") and not given.contains("Space Fishing?"),
		"and the question has become the leaderboard")
	check(_said("NOTIFY ") == "Dysnomia Rod | You got a Dysnomia Rod from Funmaster Mike.", "and a notification says you got it (%s)" % _said("NOTIFY "))
	var chimed := _heard_any("itemchime: item")
	check((await _items()).contains("Dysnomia Rod"), "the rod is in the bag")
	check(chimed, "and the chime plays for getting it")
	check((await _wear("Dysnomia Rod")) == "true RightGripAttachment", "and goes in the hand")

	said.clear()
	_server("""
local store = game:GetService("DataStoreService"):GetDataStore("Fishing")
print("STORED " .. tostring(store:GetAsync("rod/%s")))
""" % ADDRESS.to_lower())
	await create_timer(0.6).timeout
	check(_said("STORED ") == "true", "written down against the address, lowercased")

	_server("player:SetAttribute(\"WalletAddress\", \"\")")
	await create_timer(0.8).timeout
	said.clear()
	_server("print(\"GUESTROD \" .. tostring(Angling.hasRod(player)))")
	await create_timer(0.4).timeout
	var forgot := _said("GUESTROD ")
	_server("player:SetAttribute(\"WalletAddress\", \"%s\")" % ADDRESS)
	# Past the chime's quiet spell again.
	await create_timer(9.0).timeout
	said.clear()
	_server("print(\"BACKROD \" .. tostring(Angling.hasRod(player)))")
	await create_timer(0.4).timeout
	check(forgot == "false" and _said("BACKROD ") == "true", "signed out it is not held; signed in again it is (%s)" % forgot)

	await _ask("fishboard")
	check(said.has("FUN close") and said.has("FUN fishboard") and _said("SAY ") == "",
		"the leaderboard button closes his window and opens the board")

	# Clearing Contracts.Fishing stops a dev chain's ContractsDev entry reading over the stood-in catches.
	said.clear()
	_server("require(rs.Contracts).Fishing = '' Angling._setCatches(player, { [0] = 2, [9] = 1 })")
	await create_timer(0.8).timeout
	check(_heard_any("itemchime: everliving"), "catching the Everliving Fish chimes, the higher one")
	var items := await _items()
	check(items.contains("Red Fish") and items.contains("Everliving Fish") and not items.contains("Blue Fish"),
		"fish the contract counts are in the bag, and no others (%s)" % items)
	check((await _wear("Everliving Fish")) == "true LeftGripAttachment", "and go in the off hand")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

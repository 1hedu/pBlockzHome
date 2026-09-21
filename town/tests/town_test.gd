# Proves each town desk answers from one player's wallet picture, that a purchase or a send
# is asked of that player's own wallet and never the server's, and that a question asked
# mid-fetch degrades and then updates. PAYLOAD stubs the chain, so the run is offline.
#
#   godot --headless --path . -s res://tests/town_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var passed := 0
var failed := 0
var said: Array[String] = []

const PAYLOAD := {
	"address": "0x9E53d6dE1b989ed13aEE38645F3F3462Ca0Cff09",
	"network": "PulseChain testnet v4",
	"registry": "0xbD540C22F9FA1f070D0b85d8325baE809c3db40B",
	"marketplace": "0x9f1A5C5d8328C863EDcDef8416745391A3Ef2968",
	"can_buy": true,
	"gas": "0.2994",
	"tokens": [],
	"items": [{"id": 5, "qty": "2", "uri": "pblockz://e923299888/hat", "name": "Top Hat",
		"kind": "accessory", "slot": "head", "model": "TopHat", "thumb": "user://thumbs/e923299888.png"},
		# Two accessories in the head slot, so wearing one has to take the other off.
		{"id": 9, "qty": "1", "uri": "pblockz://aa11bb22/wig", "name": "Wig",
			"kind": "accessory", "slot": "head", "model": "Wig", "thumb": ""}],
	"listings": [
		{"id": 5, "name": "Top Hat", "owned": true},
		{"id": 7, "name": "Leather Duck", "owned": false,
			"uri": "pblockz://c0ffee1234/duck", "thumb": "pblockz://c0ffee1234/duck-thumb?mime=image%2Fpng",
			"tier": 0, "tier_name": "Common", "locked": false},
		{"id": 12, "name": "Rainbow Rolex", "owned": false,
			"tier": 6, "tier_name": "Shark", "locked": true},
	],
	"holder": {"tier": 0, "name": "Common", "next": "Uncommon", "needed": "10"},
	"history": [{"hash": "0xc378b7f7f5716f8bb808104afe2a782349cf4a34e02062d8dfae11f6b92db2d9",
		"block": "25323800", "ok": true, "gas": "72692", "selector": "0x9f1d0f59"}],
	"explorer": "scan.v4.testnet.pulsechain.com",
	"chain": {"block": "22574321", "base_fee": "7", "txs": "42", "chain_id": "943",
		"assetstore": "0x0f9D08e13BE2345856026615d05F7251F07efAfA",
		"inventory": "0xd7291C4780E16d06e28d5Efd6B54275c6697C2B7"},
	# The real PulseX deployment on testnet v4, not placeholders: a swap signs to these.
	"pulsex": {"probe": "1000", "router": "0xDaE9dd3d1A52CfCe9d5F2fAC7fDe164D500E50f7",
		"factory": "0xFf0538782D122d3112F75dc7121F61562261c0f7",
		"chain_id": 943, "site": "app.pulsex.com",
		"tokens": [
			{"symbol": "PLS", "address": "", "decimals": 18, "name": "Pulse"},
			{"symbol": "PLSX", "address": "0x8a810ea8B121d08342E9e7696f4a9915cBE494B7", "decimals": 18, "name": "PulseX"},
			{"symbol": "HEX", "address": "0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39", "decimals": 8, "name": "HEX"},
			{"symbol": "MYCOIN", "address": "0x1111111111111111111111111111111111111111", "decimals": 18, "name": "Pasted In", "custom": true}],
		"quotes": [{"symbol": "HEX", "out": "3.735295", "pair": "0x19BB45a727", "liquidity": "4217937546"},
			{"symbol": "PLSX", "out": "1197.536153", "pair": "0x149B2C629e", "liquidity": "77098701426"}]},
}

## True when a single WARDROBE line holds both; the whole transcript would match two
## states that never coexisted.
func _line_with(a: String, b: String) -> bool:
	for line in said:
		if line.begins_with("WARDROBE ") and line.contains(a) and line.contains(b):
			return true
	return false

func check(ok: bool, what: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print(("  PASS " if ok else "  FAIL ") + what)

## Shaped as Chain.server.luau hands it to Ledger.setCatalogue.
func _catalogue() -> Dictionary:
	return {"status": "ok", "registry": PAYLOAD.registry, "marketplace": PAYLOAD.marketplace,
		"inventory": PAYLOAD.chain.inventory, "assetstore": PAYLOAD.chain.assetstore,
		"listings": PAYLOAD.listings,
		# Six holder rungs in wei: 0, 10, 100, 1k, 10k, 100k PLS.
		"ladder": ["0", "10000000000000000000", "100000000000000000000", "1000000000000000000000",
			"10000000000000000000000", "100000000000000000000000"]}

## What the player's own wallet publishes: PAYLOAD minus everything the town reads itself.
func _mine() -> Dictionary:
	var m: Dictionary = PAYLOAD.duplicate(true)
	for k in ["items", "listings", "holder", "registry", "marketplace"]:
		m.erase(k)
	m["status"] = "ok"
	return m

func _said_server_write() -> bool:
	for line in said:
		if line.begins_with("SERVER-REQUEST") and line.contains("\"action\":\"write\""):
			return true
	return false

func _initialize() -> void:
	# The test decides who the player is; a key sitting on the machine would decide instead.
	OS.set_environment("PBLOCKZ_NO_DEV_KEY", "1")
	OS.unset_environment("PBLOCKZ_PLAYER_KEY")
	# Main.tscn wires World, ScriptSync and Wallet together, so the real scene goes in whole
	# rather than a hand-built world, as tests/play_solo_test.gd does. Wallet polling has to be
	# off before it enters the tree, or the test hits the network.
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.data_store_path = ""
	root.add_child(main)
	# Force a character in now: the intro only lifts after the phase that moves the root.
	Arrive.now(world)
	world.script_print.connect(func(n, txt):
		said.append(txt)
		print("    [%s] %s" % [n, txt]))
	world.script_error.connect(func(n, e): print("    ERROR [%s] %s" % [n, e]))
	print("== town")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 1.0:
		phase = 1
		world.run_chunk("signed_in", """
local player = game:GetService("Players"):GetPlayers()[1]
if player then player:SetAttribute("WalletAddress", "%s") end
""" % PAYLOAD.address)
	elif phase == 1 and t > 1.6:
		phase = 2
		# Asked before the town read lands, so the reply has to degrade and then update itself.
		world.run_client_chunk("early", """
local rs = game:GetService("ReplicatedStorage")
local remote = rs:WaitForChild("BankRemote", 5)
remote.OnClientEvent:Connect(function(kind, payload)
    if kind == "open" then print("EARLY-OPEN " .. payload.greeting)
    elseif kind == "update" then print("UPDATE " .. payload.greeting)
    else print("EARLY-SAY " .. table.concat(payload.lines, " | ")) end
end)
remote:FireServer("balance")
""")
	elif phase == 2 and t > 2.2:
		phase = 3
		# The town's read lands; the Chain "Wallet" attribute is what Wallet.gd publishes.
		world.run_chunk("town_read", """
local HttpService = game:GetService("HttpService")
local Ledger = require(game:GetService("ServerScriptService").Ledger)
local player = game:GetService("Players"):GetPlayers()[1]
Ledger.setCatalogue(HttpService:JSONDecode([==[%s]==]))
Ledger.setHoldings(player, HttpService:JSONDecode([==[%s]==]), "%s")
""" % [JSON.stringify(_catalogue()), JSON.stringify(PAYLOAD.items), PAYLOAD.address])
		world.run_client_chunk("chain_publish", """
local c = game:GetService("ReplicatedStorage"):WaitForChild("Chain", 5)
c:SetAttribute("Wallet", [==[%s]==])
""" % JSON.stringify(_mine()))
	elif phase == 3 and t > 3.2:
		phase = 4
		world.run_client_chunk("probe", """
local rs = game:GetService("ReplicatedStorage")
local bank = rs:WaitForChild("BankRemote", 5)
local shop = rs:WaitForChild("ShopRemote", 5)
-- What the desks ask of this player's own wallet, as it arrives on this machine.
local chain = rs:WaitForChild("Chain", 5)
chain:GetAttributeChangedSignal("AskWallet"):Connect(function()
    local raw = chain:GetAttribute("AskWallet")
    if raw and raw ~= "[]" then print("ASKED " .. raw) end
end)
local function listen(who, remote)
    remote.OnClientEvent:Connect(function(kind, payload)
        if kind == "open" then
            print(who .. "-OPEN " .. payload.greeting)
        elseif payload.lines then
            local labels = {}
            for _, entry in ipairs(payload.menu or {}) do table.insert(labels, entry.label) end
            print(who .. "-SAY " .. table.concat(payload.lines, " | ")
                .. " ||thumb=" .. tostring(payload.thumb)
                .. " ||menu=" .. table.concat(labels, " / "))
        end
    end)
end
listen("BANK", bank)
listen("SHOP", shop)
shop.OnClientEvent:Connect(function(kind, payload)
    if kind ~= "shelf" then return end
    local parts = {}
    for _, it in ipairs(payload.items) do
        table.insert(parts, ("%s|%s"):format(it.name,
            it.owned and "owned" or (it.locked and ("locked:" .. tostring(it.tier_name)) or "buy")))
    end
    print("SHELF holder=" .. tostring((payload.holder or {}).name)
        .. " cards=" .. #payload.items .. " || " .. table.concat(parts, " / "))
end)
task.spawn(function()
    for _, id in ipairs({"balance", "items", "about"}) do
        bank:FireServer(id)
        task.wait(0.12)
    end
    for _, id in ipairs({"shop", "how"}) do
        shop:FireServer(id)
        task.wait(0.12)
    end
    shop:FireServer("buy", 7)
    task.wait(0.2)
end)
""")
	elif phase == 4 and t > 5.4:
		phase = 5
		# The server's own request channel, which the buy must have left empty.
		world.run_chunk("read_request", """
local c = game:GetService("ServerStorage"):FindFirstChild("Chain")
print("SERVER-REQUEST " .. tostring(c and c:GetAttribute("Request")))
""")
	elif phase == 5 and t > 6.0:
		phase = 6
		world.run_client_chunk("wardrobe", """
local rs = game:GetService("ReplicatedStorage")
local remote = rs:WaitForChild("WardrobeRemote", 5)
remote.OnClientEvent:Connect(function(kind, items)
    local parts = {}
    for _, item in ipairs(items) do
        table.insert(parts, ("%s:%s:%s"):format(item.name, item.slot or "?", item.worn and "on" or "off"))
    end
    print("WARDROBE " .. (#parts == 0 and "(empty)" or table.concat(parts, " ")))
end)
task.spawn(function()
    remote:FireServer("list")
    task.wait(0.2)
    remote:FireServer("wear", "Wig")           -- same slot: the hat must come off
    task.wait(0.2)
    remote:FireServer("remove", "Wig")
    task.wait(0.2)
    remote:FireServer("wear", "CrownJewels")   -- not ours; must be refused
    task.wait(0.2)
    remote:FireServer("wear", "TopHat")
    task.wait(0.2)
end)
""")
	elif phase == 6 and t > 7.6:
		phase = 7
		# The teller's position is looked up, not hard-coded: the bank moves around the map.
		# FireClient "open" reproduces the ProximityPrompt path rather than skipping it:
		# Bank.server.luau fires that same event from Ledger.onTalk("Teller", ...).
		world.run_chunk("stand_at_teller", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local player = Players:GetPlayers()[1]
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local map = workspace:FindFirstChild("Map")
local teller = map and map:FindFirstChild("Teller")
local torso = teller and teller:FindFirstChild("Torso")
if root and torso then root.Position = torso.Position + Vector3.new(0, 0, 4) end
rs.BankRemote:FireClient(player, "open",
    { title = "Rivet  <Wallet Services>", npc = "Teller", greeting = "Morning.", menu = {} })
""")
	elif phase == 7 and t > 8.4:
		phase = 8
		world.run_client_chunk("dialog_near", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
print("DIALOG-NEAR " .. tostring(gui:WaitForChild("TownDialog").Enabled))
""")
	elif phase == 8 and t > 9.0:
		phase = 9
		# The origin is 57 studs from the teller, well past CLOSE_DISTANCE (16, Dialog.client.luau).
		world.run_chunk("walk_away", """
local Players = game:GetService("Players")
local player = Players:GetPlayers()[1]
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if root then root.Position = Vector3.new(0, 4, 0) end
""")
	elif phase == 9 and t > 10.2:
		phase = 10
		world.run_client_chunk("dialog_far", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
print("DIALOG-FAR " .. tostring(gui:WaitForChild("TownDialog").Enabled))
""")
	elif phase == 10 and t > 11.4:
		phase = 11
		world.run_client_chunk("counters", """
local rs = game:GetService("ReplicatedStorage")
local bank = rs:WaitForChild("BankRemote", 5)
local trade = rs:WaitForChild("TradeRemote", 5)
local records = rs:WaitForChild("RecordsRemote", 5)
local function listen(who, remote)
    remote.OnClientEvent:Connect(function(kind, payload)
        if kind ~= "say" then return end
        local labels = {}
        for _, entry in ipairs(payload.menu or {}) do table.insert(labels, entry.label) end
        print(who .. "-SAY " .. table.concat(payload.lines, " | ")
            .. " ||input=" .. tostring(payload.input and (payload.input.placeholder or "yes") or "none")
            .. " ||menu=" .. table.concat(labels, " / "))
    end)
end
listen("RECORDS", records)
listen("BANK2", bank)
-- The trading house is a swap panel now, not a conversation: it sends the market over
-- and the panel prices a trade against it.
trade.OnClientEvent:Connect(function(kind, payload)
    if kind ~= "market" then return end
    if payload.loading then print("TRADE-MARKET loading") return end
    local syms, custom = {}, "none"
    for _, t in ipairs(payload.tokens or {}) do
        table.insert(syms, t.symbol)
        if t.custom then custom = t.symbol end
    end
    local depth = ""
    for sym, d in pairs(payload.depth or {}) do
        depth = depth .. (" %s=%s/%s"):format(sym, d.out, d.liquidity)
    end
    print(("TRADE-MARKET chain=%s router=%s site=%s tokens=%s custom=%s depth=%s"):format(
        tostring(payload.chain_id), tostring(payload.router), tostring(payload.site),
        table.concat(syms, ","), custom, depth))
end)
task.spawn(function()
    for _, id in ipairs({"chain", "account", "history", "contracts", "verify"}) do
        records:FireServer(id)
        task.wait(0.1)
    end
    -- The trading house has no menu any more: you open it and it hands over the market.
    trade:FireServer("open")
    task.wait(0.3)
    -- The bank's send form: ask, refuse a bad address, take a good one, then send.
    bank:FireServer("receive")
    task.wait(0.1)
    bank:FireServer("ask_send")
    task.wait(0.1)
    bank:FireServer("send_to", nil, "not-an-address")
    task.wait(0.1)
    bank:FireServer("send_to", nil, "0x1111111111111111111111111111111111111111")
    task.wait(0.1)
    bank:FireServer("send", nil, "5")
    task.wait(0.2)
end)
""")
	elif phase == 11 and t > 13.8:
		phase = 12
		world.run_chunk("read_last", """
local c = game:GetService("ServerStorage"):FindFirstChild("Chain")
print("SERVER-REQUEST " .. tostring(c and c:GetAttribute("Request")))
""")
	elif phase == 12 and t > 14.6:
		phase = 13
		var all := " ".join(said)
		# ---- the bank: wallet only
		check(all.contains("holds 0.2994 PLS"), "the teller reports the wallet's PLS")
		check(not all.contains("mUSD") and not all.contains("mWPLS"), "and no mock tokens anywhere in the town")
		check(all.contains("Top Hat") and all.contains("(#5)"), "lists the owned item by the name its on-chain metadata gives it")
		# A uri, not a path: a server file path names nothing on a joined client.
		check(all.contains("thumb=pblockz://c0ffee1234/duck-thumb"), "hands the client a picture to draw beside the answer, by uri")
		check(all.contains("PulseChain testnet v4"), "explains where the data came from")
		check(all.contains("your") and all.contains("wallet shows you the transaction first"), "and that your own wallet shows and signs the transaction, said in character")
		check(not all.contains("BANK-SAY On sale"), "the teller no longer runs the shop")
		# ---- the shop: the shelf
		check(all.contains("SHELF ") and all.contains("cards=3"), "the shopkeeper hands the shelf over as cards, one per thing")
		check(all.contains("Leather Duck|buy"), "each card carrying its name and what you can do")
		check(all.contains("Top Hat|owned"), "marking what you already have rather than offering it again")
		check(all.contains("SHELF holder=Common"), "and saying which rung you are on")
		# ---- the ladder
		check(all.contains("locked:Legendary"), "a card out of reach says what it wants")
		check(all.count("Top Hat|") == 1, "one card per thing")
		check(all.contains("things on the shelf"), "and the dialog points you at the shelf rather than listing it")
		
		
		# ---- the hall of records: your transactions, read from the explorer's API
		check(all.contains("25323800") and all.contains("REVERTED") == false, "the archivist lists your recent transactions")
		check(all.contains("scan.v4.testnet.pulsechain.com"), "and says they came from the explorer's own API")
		check(all.contains("Take Engram 25323800"), "and offers to let you carry one")
		# ---- buying is a request, not an action
		# The request names the contract, function and arguments, so the client needs no vocabulary of its own.
		check(all.contains("ASKED") and all.contains("\"action\":\"write\""),
			"taking something is asked of the player's own wallet, on their own machine")
		check(not _said_server_write(), "and never of the server, which signs for nobody")
		check(all.contains("add(bytes32,uint8)"), "naming the call rather than a word the client knows")
		check(all.contains("0xc0ffee1234"), "and the item, which is the hash of its own metadata")
		check(all.contains("Your wallet shows you what you"), "and the shopkeeper says who actually signs, in character")
		# ---- the wardrobe
		check(all.contains("WARDROBE Top Hat:head:on"), "the wardrobe lists what you own, worn by default")
		check(all.contains("Top Hat:head:off"), "and takes it off when you ask")
		check(_line_with("Top Hat:head:on", "Wig:head:off"),
			"only one thing per slot goes on by itself, not everything you own")
		check(_line_with("Top Hat:head:off", "Wig:head:on"),
			"and wearing the other hat takes the first one off")
		check(all.count("WARDROBE") >= 4, "a request for something you do not own still gets an answer")
		check(not all.contains("CrownJewels"), "but wearing something you do not own is refused")
		# ---- the window closes itself
		check(all.contains("DIALOG-NEAR true"), "the dialog is open while you are standing at the NPC")
		check(all.contains("DIALOG-FAR false"), "and closes itself when you walk away, rather than following you home")
		# ---- the hall of records: the chain itself
		check(all.contains("22574321"), "the archivist reads the block height off the chain data")
		check(all.contains("7 wei") and all.contains("Base fee"), "and the base fee, not the node's inflated suggestion")
		check(all.contains("an owner, an admin key, or a pause switch"), "and says the contracts have nobody in charge")
		check(all.contains("scan.v4.testnet.pulsechain.com"), "and points you at the explorer to check it yourself")
		# ---- the trading house
		check(all.contains("3.735295") and all.contains("1197.536153"), "the trader reads real PulseX quotes")
		check(all.contains("0xDaE9dd3d") or all.contains("0xdae9dd3d"), "through PulseX's own router, and says which")
		check(all.contains("app.pulsex.com"), "and points at PulseX rather than standing in for it")
		# 943 is PulseChain testnet v4, where PulseX is deployed; 369 is mainnet.
		check(all.contains("chain=943"), "and quotes the chain the swap actually settles on")
		check(not all.contains("chain=369"), "not mainnet, which it could never have traded against")
		check(all.contains("4217937546") and all.contains("77098701426"),
			"showing pool depth, because a price with nothing behind it quotes anything")
		check(all.contains("custom=MYCOIN"),
			"and carrying a token pasted in by address, so the list is not somebody else's")
		# ---- the bank's wallet services
		check(all.contains("BANK2-SAY This is you"), "the teller reads your address back")
		check(all.contains("isn't an address"), "refuses something that is not an address")
		check(all.contains("input=0x0000"), "and asks for one in the box")
		check(all.contains("0x1111...1111"), "takes a good one and asks how much")
		# AskWallet carries OwnWallet.luau's whole ordered list of outstanding numbered requests,
		# so each ASKED line reprints a growing array and the send is the last entry in it.
		check(all.contains("ASKED") and all.contains("Send 5 PLS"),
			"and sending is asked of the player's own wallet to confirm")
		check(all.contains("\"to\":\"0x1111111111111111111111111111111111111111\"") and all.contains("\"value\":\"5\""),
			"a plain PLS transfer to the address that was typed")
		check(not all.contains("transfer(address,uint256)"), "not a token's transfer call")
		# ---- degrading
		check(all.contains("Still reading the ledger"), "a question asked mid-fetch says so, rather than claiming the line is down")
		check(all.contains("UPDATE") and all.contains("I can see your account"), "and the open window fills itself in when the data lands, with no second visit")
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed else 0)
	return false

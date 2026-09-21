-- What the desks need to read the chain and to ask a player's wallet, in one place.
--
-- Scripts do not talk to the chain themselves. The server's host (Wallet.gd) answers the server's
-- READS through attributes on ReplicatedStorage.Chain; it holds no key and signs nothing. Everything
-- a player's wallet does is asked of that player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Ledger = {}
local resultHandlers = {}   -- see Ledger.onResult and Ledger.askFor

-- The server's channel to its host, in ServerStorage: what the server asks its host and what
-- comes back is the server's business, and ServerStorage does not replicate. It lived in
-- ReplicatedStorage, where every request and every answer -- the whole catalogue, each
-- player's holdings, the documents behind them -- went to every client, on every write, as
-- attributes on a node those clients also made a local copy of. (A client's own wallet still
-- talks to that client's scripts through ReplicatedStorage.Chain on that machine: OwnWallet.luau.)
local ServerStorage = game:GetService("ServerStorage")
function Ledger.node()
	local chain = ServerStorage:FindFirstChild("Chain")
	if not chain then
		chain = Instance.new("Configuration")
		chain.Name = "Chain"
		chain.Parent = ServerStorage
	end
	return chain
end

-- ---- what a desk knows about a player ------------------------------------------------------
-- A player is their wallet, and every desk in the square talks to one player at a time. So what a
-- desk reads is that player's picture of the world, put together from three halves:
--
--   the catalogue   what exists and what it costs -- the town's game state, the same for everyone,
--                   read once by the server (Chain.server.luau)
--   their holdings  what their address owns, read by the server from the game's own contracts
--                   (Registry, Inventory), because what somebody wears and swings is what the
--                   server has to judge -- and what their models are, mounted so they can be worn
--   their wallet    balances, tokens, history, pools: read by the player's OWN machine, from their
--                   own wallet, and handed to the desks to show them (Mine.client.luau). Shown,
--                   never believed: nothing is decided off it, and the chain checks every write.
--
-- Treat what comes back as read-only: it is one shared table per player, remade when a half moves.

local Units = require(ReplicatedStorage:WaitForChild("Units"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))

local catalogue = nil         -- { status, registry, marketplace, donations, inventory, assetstore, listings, ladder, ids }
local holdings = {}           -- player -> { items, address, at }
local mine = {}               -- player -> the wallet half their own machine last reported
local views = {}              -- player -> { key, doc }
local revision = 0
local changedHandlers = {}

local function bump(player)
	revision += 1
	for _, fn in ipairs(changedHandlers) do task.spawn(fn, player) end
end

--- Says something a player's picture is made of has changed, for what the town holds for them
--- itself -- a rod Funmaster Mike gave them, fish the Fishing contract counts -- so the wardrobe
--- and the desks look again, the same as when their holdings land.
function Ledger.changed(player)
	bump(player)
end

function Ledger.setCatalogue(doc)
	catalogue = doc
	bump(nil)
end

function Ledger.catalogue()
	return catalogue
end

function Ledger.setHoldings(player, items, address)
	holdings[player] = { items = items, address = address, at = os.clock() }
	bump(player)
end

function Ledger.holdings(player)
	local h = holdings[player]
	return h and h.items or nil
end

--- Calls fn(player) whenever something a player's picture is made of changes -- nil for the
--- catalogue, which is everyone's.
function Ledger.onChanged(fn)
	table.insert(changedHandlers, fn)
end

-- Their own machine's half. Size-capped and shape-checked, and only kept while it is about the
-- wallet they signed in with: a key changed on the title screen is a different wallet, and its
-- balances beside this player's items would be a picture of nobody.
-- Notifications for one player: the server says what, and their client shows it with
-- StarterGui:SetCore("SendNotification") -- see Notify.client.luau.
local notify = Instance.new("RemoteEvent")
notify.Name = "Notify"
notify.Parent = ReplicatedStorage

local mineRemote = Instance.new("RemoteEvent")
mineRemote.Name = "MineRemote"
mineRemote.Parent = ReplicatedStorage
mineRemote.OnServerEvent:Connect(function(player, raw)
	if type(raw) ~= "string" or #raw > 400000 then return end
	local ok, doc = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(doc) ~= "table" then return end
	-- Signed in as one address and reporting another: not theirs, so it does not replace what
	-- their own wallet last said. Before sign-in it is kept, and checked against the address
	-- whenever a desk reads it (Ledger.data).
	local address = Ledger.addressOf(player)
	if address and (type(doc.address) ~= "string" or doc.address:lower() ~= address:lower()) then return end
	mine[player] = doc
	bump(player)
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	holdings[player], mine[player], views[player] = nil, nil, nil
end)

--- Which rung a player stands on, and which listings that puts out of reach. Advisory: it decides
--- what the shelf bothers to offer. The RULE is Inventory.add, which checks the balance on chain.
local function rank(view)
	local rung = catalogue and catalogue.ladder
	if type(rung) ~= "table" or #rung == 0 then return end
	-- Below the first edge is not the first rung, and this used to say it was. The bottom rung
	-- costs 5 PLS, so somebody holding less stands on nothing -- but the tier started at 0 and
	-- only ever went up, which made "holding nothing" and "standing on Common" the same number.
	-- Everything at Common then read as unlocked, the shelf drew "Take it" on all of it, and
	-- Inventory.add refused it on chain (NotBigEnough) after the wallet had been signed and the
	-- gas spent. -1 is off the ladder: every rung is above it, so everything locks.
	local tier = -1
	local held = tostring(view.gas_wei or "0")
	for i, edge in ipairs(rung) do
		if not Units.lessThan(held, tostring(edge)) then tier = i - 1 end
	end
	view.holder = {
		tier = tier,
		-- Empty rather than a rung's name: whoever draws this has to say something else, and a
		-- name clamped to "Common" is exactly the lie this is fixing.
		name = tier >= 0 and Theme.rarityName(tier) or "",
		next = tier + 1 < #rung and Theme.rarityName(tier + 1) or "",
		needed = tier + 1 < #rung and Units.format(tostring(rung[tier + 2]), 18, 0) or "",
	}
	for _, l in ipairs(view.listings or {}) do
		local need = math.clamp(l.tier or 0, 0, math.max(#rung - 1, 0))
		l.tier = need
		l.tier_name = Theme.rarityName(need)
		l.locked = need > tier
	end
end

--- The picture a desk has of `player`: their wallet, their holdings, and the catalogue, as one
--- table in the shape every desk has always read (d.address, d.tokens, d.items, d.listings, ...).
--- Nil while nothing at all is known yet; `status = "loading"` while a half is still coming.
function Ledger.data(player)
	if not player then return nil end
	local address = Ledger.addressOf(player)
	local h = holdings[player]
	local m = mine[player]
	if m and address and type(m.address) == "string" and m.address:lower() ~= address:lower() then m = nil end
	local key = ("%d|%s"):format(revision, tostring(address))
	local cached = views[player]
	if cached and cached.key == key then return cached.doc end

	local view = {}
	-- Their wallet's half first, then the town's facts over it: a client does not get to say
	-- where the registry is.
	for k, v in pairs(m or {}) do view[k] = v end
	view.address = address or view.address
	view.signed_in = address ~= nil
	view.can_buy = address ~= nil and m ~= nil and m.can_buy == true
	view.tokens = view.tokens or {}
	local cat = catalogue or {}
	view.registry = cat.registry
	view.marketplace = cat.marketplace
	view.donations = cat.donations
	view.assetstore = cat.assetstore or view.assetstore
	view.chain = table.clone(type(view.chain) == "table" and view.chain or {})
	view.chain.inventory = cat.inventory
	view.chain.assetstore = cat.assetstore
	view.items = h and h.items or {}
	-- By the bytes as well as by the id. A listing's id is a Registry number; the same thing in
	-- somebody's bag, taken off that shelf, is an Inventory record named by the content hash of
	-- its document (Shop.server.luau), so its id is a bytes32 that no Registry number can equal.
	-- The uri of that document is what both carry, and the hash in it is the one name the two
	-- id spaces share.
	local owned, ownedBytes = {}, {}
	for _, item in ipairs(view.items) do
		if item.id then owned[item.id] = true end
		local hash = tostring(item.uri or ""):match("^pblockz://(%x+)")
		if hash then ownedBytes[hash:lower()] = true end
	end
	view.listings = {}
	for _, l in ipairs(cat.listings or {}) do
		local one = table.clone(l)
		local hash = tostring(l.uri or ""):match("^pblockz://(%x+)")
		one.owned = owned[l.id] == true or (hash ~= nil and ownedBytes[hash:lower()] == true)
		table.insert(view.listings, one)
	end
	rank(view)
	if not catalogue or (address and not h) or (address and not m) then
		view.status = "loading"
	else
		view.status = "ok"
	end
	views[player] = { key = key, doc = view }
	return view
end

--- Calls fn(player, d) once per player, the first time their picture stops loading -- so a desk
--- that opened on "give me a moment" can put the real greeting up without being asked again.
local readyHandlers = {}
local ready = {}   -- player -> their picture has loaded this session

function Ledger.onReady(fn)
	table.insert(readyHandlers, fn)
end

Ledger.onChanged(function(who)
	local list = who and { who } or game:GetService("Players"):GetPlayers()
	for _, player in ipairs(list) do
		if not ready[player] and player.Parent then
			local d = Ledger.data(player)
			if d and not Ledger.loading(d) then
				ready[player] = true
				for _, fn in ipairs(readyHandlers) do task.spawn(fn, player, d) end
			end
		end
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player) ready[player] = nil end)

--- A player with no wallet signed in: a guest. They can look around; there is nothing of theirs
--- to read and nothing to sign with.
function Ledger.guest(d)
	return d ~= nil and not d.signed_in
end

function Ledger.noWallet()
	return {
		"No wallet signed in, so there's nothing of yours for me to read.",
		"Sign in at the title screen and come back.",
	}
end

-- Three states, and the difference matters: nothing published yet, a fetch in flight,
-- or real data. Saying "the line is down" while it is merely loading is how you get
-- someone to walk away from a working bank.
function Ledger.loading(d)
	return d ~= nil and d.status == "loading"
end

function Ledger.notYet(d)
	if Ledger.loading(d) then
		return { "Still reading the ledger. I'll speak up the moment it lands." }
	end
	return { "The line's still down. Nothing I can tell you." }
end

function Ledger.short(addr)
	if type(addr) ~= "string" or #addr < 12 then return tostring(addr) end
	return addr:sub(1, 6) .. "..." .. addr:sub(-4)
end

function Ledger.nameOf(entry, fallbackId)
	if entry and type(entry.name) == "string" and entry.name ~= "" then return entry.name end
	return "#" .. tostring(fallbackId)
end

-- ---- asking the host to do something -------------------------------------------
-- No script here can sign a transaction or reach the network. What it can do is write
-- down what was asked for; the host reads it, decides, and writes back the outcome.
--
-- Requests are numbered so a reply finds the person who asked. The counter lives on
-- the Chain node rather than in this module, so two NPCs asking at once cannot both
-- call theirs number one whatever `require` does about caching.
--
-- ---- why this is a queue and not one attribute ----------------------------------
-- It WAS one attribute. Every asker wrote the whole request into `Request` and the host
-- polled that one slot four times a second. Twenty-six places in this town ask -- the
-- teller, the shelf, the wardrobe, the tailor, the archivist -- and one of them, the
-- Chain publisher, asks on a loop forever: a batched read, then a batched fetch, then
-- again. So the slot was almost never yours for long.
--
-- Two ways to lose a request, and both were happening:
--
--   * Somebody else writes the slot before the host's next poll. Yours is simply gone.
--     Nothing errors, nothing warns; the asker waits out its whole timeout and gets nil.
--   * The host is busy signing (`_buying`), so it skips polling entirely -- and every
--     request written during those seconds lands in a slot nobody is looking at.
--
-- That is what "Take Engram said Asking... and never asked" was. The `store` went into
-- the slot, the publisher's next read went in on top of it, and the button sat there
-- politely for two minutes waiting on a request the host never saw.
--
-- So: a LIST of everything still outstanding. Nobody overwrites anybody, the host drains
-- whatever it finds whenever it next looks, and a request stops being outstanding when
-- its answer comes back -- which the single watcher below notices for everyone at once.
--
-- ---- both channels, not one ------------------------------------------------------
-- There are two: the wallet's, and the scan's. They are separate on purpose, so a page
-- being fetched cannot be lost behind a purchase and a purchase cannot be lost behind a
-- page.
--
-- The queue above was written for the wallet's, and the scan's was left exactly as it had
-- always been: one slot, polled five times a second, in front of a fetch that takes
-- seconds. Two people reading the explorer at once lost each other's pages, and so did one
-- person pressing Open on somebody's Engram -- that is "put the window up" and "go to this
-- page", written back to back. The same defect, one attribute over.
--
-- So it is one implementation used twice, and there is nowhere left for a third copy of
-- this bug to live.

-- How long an unanswered request stays in the list. Longer than the longest patience any
-- caller uses, because dropping one that is still being waited on would be a second way to
-- lose it. A host that is simply not there must not grow this without bound either.
local FORGET = 180

--- One request channel: a counter, a queue of what is still outstanding, and the answers.
local function channel(seqAttr, requestAttr, resultAttr)
	local self = {}
	local outstanding = {}   -- n -> the request, still unanswered
	local order = {}         -- the ns, oldest first, so the host drains in the order asked
	local watching = false

	local function flush()
		local out = {}
		for _, n in ipairs(order) do
			local r = outstanding[n]
			if r then table.insert(out, r) end
		end
		Ledger.node():SetAttribute(requestAttr, HttpService:JSONEncode(out))
	end

	local function settle(n)
		if outstanding[n] == nil then return end
		outstanding[n] = nil
		for i, m in ipairs(order) do
			if m == n then table.remove(order, i) break end
		end
		flush()
	end

	-- Wired on the first ask. Every reply on this channel passes through here whoever it
	-- was for, which is what lets the list shrink without each caller having to remember
	-- to say it is done.
	local function watchOnce(chain)
		if watching then return end
		watching = true
		chain:GetAttributeChangedSignal(resultAttr):Connect(function()
			local raw = chain:GetAttribute(resultAttr)
			if type(raw) ~= "string" or raw == "" then return end
			local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
			if ok and type(res) == "table" and res.n then settle(res.n) end
		end)
	end

	function self.ask(request)
		local chain = Ledger.node()
		local n = (chain:GetAttribute(seqAttr) or 0) + 1
		chain:SetAttribute(seqAttr, n)
		request.n = n
		watchOnce(chain)
		outstanding[n] = request
		table.insert(order, n)
		flush()
		task.delay(FORGET, function() settle(n) end)
		return n
	end

	function self.onResult(handler)
		local chain = Ledger.node()
		chain:GetAttributeChangedSignal(resultAttr):Connect(function()
			local raw = chain:GetAttribute(resultAttr)
			if type(raw) ~= "string" or raw == "" then return end
			local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
			if ok and type(res) == "table" and res.n then handler(res.n, res) end
		end)
	end

	-- Yields until the answer with this number arrives, or the timeout runs out.
	function self.await(request, timeout)
		local want = self.ask(request)
		local chain = Ledger.node()
		local answer = nil
		local conn
		conn = chain:GetAttributeChangedSignal(resultAttr):Connect(function()
			local raw = chain:GetAttribute(resultAttr)
			if type(raw) ~= "string" or raw == "" then return end
			local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
			if ok and type(res) == "table" and res.n == want then answer = res end
		end)
		local waited = 0
		local limit = timeout or 20
		while answer == nil and waited < limit do
			waited += task.wait(0.1)
		end
		conn:Disconnect()
		return answer
	end

	return self
end

-- The wallet's channel: reads, writes, stores, fetches, who.
local wallet = channel("Seq", "Request", "Result")

function Ledger.ask(request) return wallet.ask(request) end

-- Calls `handler(n, result)` for every outcome written back -- the server's own reads, and what a
-- player's wallet answered to Ledger.askFor. Each NPC ignores the numbers that are not its own.
function Ledger.onResult(handler)
	table.insert(resultHandlers, handler)
	return wallet.onResult(handler)
end

--- Ask, and wait here for the answer.
---
--- Ledger.ask is fire-and-forget with a number, and every desk that wanted the reply grew
--- its own `waiting[n] = player` table to catch it later. That is the right shape when the
--- answer has to go back to a particular person -- but not for a script that simply wants
--- to know something before it carries on, which is what read and who are for.
---
--- Yields, so only call it from a thread that may. Returns nil if nothing comes back
--- inside `timeout`, which is a real outcome rather than an error: the host may have no
--- key, no network, or no interest.
function Ledger.request(request, timeout) return wallet.await(request, timeout) end

-- ---- asking a player's own wallet ------------------------------------------------------
-- The channel above is the server's own host, and the server holds no key: it READS. Anything a
-- player's wallet has to do -- sign, pay, send, publish -- is asked of that player: their machine
-- gets the request (WalletBridge.client.luau), their own wallet puts it in front of them, and the
-- answer comes back here. Nobody else's machine sees it, and nobody else's wallet can answer it.

local playerRemote = nil
local playerSeq = 0
local playerWaiting = {}   -- n -> { player, answer }

local function walletRemote()
	if playerRemote then return playerRemote end
	playerRemote = ReplicatedStorage:FindFirstChild("WalletRemote")
	if not playerRemote then
		playerRemote = Instance.new("RemoteEvent")
		playerRemote.Name = "WalletRemote"
		playerRemote.Parent = ReplicatedStorage
	end
	playerRemote.OnServerEvent:Connect(function(player, n, answer)
		local waiting = playerWaiting[n]
		-- Only the player it was asked of can answer it.
		if not waiting or waiting.player ~= player then return end
		waiting.answer = type(answer) == "table" and answer or { ok = false, message = "An answer that made no sense." }
	end)
	return playerRemote
end

--- The address a player signed in with, or nil for a guest.
function Ledger.addressOf(player)
	local a = player and player:GetAttribute("WalletAddress")
	return type(a) == "string" and a ~= "" and a or nil
end

--- Asks `player`'s own wallet to do `request`, and waits for what came of it. Yields; nil if
--- nothing came back inside `timeout` (they walked off, or the prompt is still up).
function Ledger.askPlayer(player, request, timeout)
	local remote = walletRemote()
	if not Ledger.addressOf(player) then
		return { ok = false, message = "You haven't a wallet signed in, so there's nothing to sign with." }
	end
	playerSeq += 1
	local n = playerSeq
	local waiting = { player = player }
	playerWaiting[n] = waiting
	remote:FireClient(player, n, request)
	local waited = 0
	local limit = timeout or 300
	while waiting.answer == nil and waited < limit and player.Parent do
		waited += task.wait(0.1)
	end
	playerWaiting[n] = nil
	return waiting.answer
end

-- Made as the server starts, so a client's bridge finds it.
walletRemote()


--- Asks `player`'s own wallet without waiting, like Ledger.ask: returns a number, and the answer
--- arrives through Ledger.onResult with that number -- so a desk that matched writes to players by
--- number keeps doing exactly that, with the write now going to the player's wallet instead of the
--- town's (which has none). Numbers from here never collide with the server channel's.
local forSeq = 1000000000

function Ledger.askFor(player, request)
	forSeq += 1
	local n = forSeq
	task.spawn(function()
		local answer = Ledger.askPlayer(player, request) or { ok = false, message = "Your wallet didn't answer." }
		answer.n = n
		if answer.ok and (request.action == "write" or request.action == "store" or request.action == "swap"
			or request.action == "add_liquidity" or request.action == "remove_liquidity") then
			for _, fn in ipairs(Ledger._wroteHandlers) do task.spawn(fn, player) end
		end
		for _, fn in ipairs(resultHandlers) do task.spawn(fn, n, answer) end
	end)
	return n
end

--- Asks `player`'s own wallet and waits, like Ledger.request.
function Ledger.requestFor(player, request, timeout)
	local answer = Ledger.askPlayer(player, request, timeout)
	if answer and answer.ok and (request.action == "write" or request.action == "store") then
		for _, fn in ipairs(Ledger._wroteHandlers) do task.spawn(fn, player) end
	end
	return answer
end

--- Calls fn(player) after a player's own wallet has changed something on chain, so what the
--- server knows of their holdings can be read again.
Ledger._wroteHandlers = {}
function Ledger.onPlayerWrote(fn)
	table.insert(Ledger._wroteHandlers, fn)
end

-- ---- asking the scan ------------------------------------------------------------------
-- Not from here any more. A page of the block explorer is read by the client that wants to
-- look at it: shared/Scan.luau writes an `Ask` channel and that machine's own Scan.gd
-- answers it. A server has no business fetching somebody else's browsing, and on a hosted
-- town it would be the operator's bandwidth and the operator's address in the logs.

-- Wires an NPC's ProximityPrompt to a handler once the map has mounted.
function Ledger.onTalk(modelName, handler)
	task.spawn(function()
		local map = workspace:WaitForChild("Map", 10)
		local npc = map and map:WaitForChild(modelName, 10)
		local torso = npc and npc:WaitForChild("Torso", 10)
		local prompt = torso and torso:WaitForChild("Talk", 10)
		if not prompt then
			warn(("%s: no prompt found; the counter is unattended"):format(modelName))
			return
		end
		prompt.Triggered:Connect(handler)
		print(("%s is on the desk"):format(modelName))
	end)
end

return Ledger

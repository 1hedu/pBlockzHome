-- Ranked duels: one against one or two against two, first team to a number of frags.
--
-- ---- what is sealed --------------------------------------------------------------------------
-- Nobody outside a duel can touch anybody in it, or mend them, and nobody in it can touch anybody
-- outside it. Health.mayHurt holds that rule; this puts people on their sides and takes them off.
--
-- ---- where a result lives --------------------------------------------------------------------
-- Here, on the server, in DataStores -- the town's record of the fights it judged, which is the
-- only thing that saw them. A result goes on chain only if somebody wants it there, and only
-- with both sides: one player sends it and pays for it, and it carries a signature from somebody
-- on the other team (contracts/DuelRecords.sol). The server hands over the numbers; it signs
-- nothing and sends nothing. Everything a wallet does here is asked of that player's wallet.
--
-- ---- what ranks ------------------------------------------------------------------------------
-- Kills. A win in a match to one and a win in a match to twenty-five are not the same thing, so
-- wins cannot be compared across matches; a kill is a kill in every one of them. Each player's own
-- kills are counted -- in a two against two, the team's frags are its two players' kills added up
-- -- and the leaderboard is those, summed over every ranked duel. Wins and losses are kept beside
-- them for reading, not for ranking.
--
-- Everybody in a ranked duel has to be signed in: a result is about addresses, and a guest has
-- none to be ranked under.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")

local Ledger = require(script.Parent.Ledger)
local Health = require(script.Parent.Health)
local Contracts = require(ReplicatedStorage:WaitForChild("Contracts"))

local Duels = {}

Duels.MIN_LIMIT = 1
Duels.MAX_LIMIT = 25
Duels.ANSWER_SECONDS = 60      -- how long a challenge waits for everybody to say yes
Duels.SIGN_SECONDS = 120       -- how long the other side has to sign a result
Duels.WITNESS_SECONDS = 60     -- how long a bystander has to witness one
Duels.RECENT = 20              -- results kept per player for "my duels"

-- ---- storage -------------------------------------------------------------------------------
local stores = {}
local function store(name, ordered)
	local key = (ordered and "o:" or "") .. name
	if stores[key] then return stores[key] end
	local ok, got = pcall(function()
		return ordered and DataStoreService:GetOrderedDataStore(name) or DataStoreService:GetDataStore(name)
	end)
	stores[key] = ok and got or nil
	return stores[key]
end

local function keyOf(address) return tostring(address):lower() end

--- Where a result is kept. A DataStore key is at most fifty characters and an id is a bytes32 --
--- sixty-six with its 0x -- so the key is its first half, which is a whole random GUID and as
--- unique as the id is.
local function resultKey(id) return "duel/" .. tostring(id):sub(3, 34) end

local function load(name, key)
	local s = store(name)
	if not s then return nil end
	local ok, got = pcall(function() return s:GetAsync(key) end)
	return ok and got or nil
end

local function save(name, key, value)
	local s = store(name)
	if not s then return false end
	return (pcall(function() s:SetAsync(key, value) end))
end

local function update(name, key, fn)
	local s = store(name)
	if not s then return nil end
	local ok, got = pcall(function() return s:UpdateAsync(key, fn) end)
	return ok and got or nil
end

-- ---- what is replicated --------------------------------------------------------------------
-- A Configuration per duel under ReplicatedStorage.Duels, so every client can draw the score
-- without being sent it: who is on each side, the frags, the limit, and whether it is live.
local folder = ReplicatedStorage:FindFirstChild("Duels") or Instance.new("Folder")
folder.Name = "Duels"
folder.Parent = ReplicatedStorage

local remote = ReplicatedStorage:FindFirstChild("DuelRemote") or Instance.new("RemoteEvent")
remote.Name = "DuelRemote"
remote.Parent = ReplicatedStorage

--- A line in the chat for these players, from the town rather than from anybody.
function Duels.announce(players, text)
	for _, p in ipairs(players) do
		if p and p.Parent then remote:FireClient(p, "announce", text) end
	end
end

local pending = {}   -- id -> challenge
local live = {}      -- id -> duel
local busy = {}      -- player -> id of the challenge or duel they are in

local function newId()
	return "0x" .. HttpService:GenerateGUID(false):gsub("-", ""):lower()
		.. HttpService:GenerateGUID(false):gsub("-", ""):lower()
end

local function names(list)
	local out = {}
	for _, p in ipairs(list) do table.insert(out, p.Name) end
	return table.concat(out, " & ")
end

local function everyone(d)
	local out = {}
	for _, p in ipairs(d.teamA) do table.insert(out, p) end
	for _, p in ipairs(d.teamB) do table.insert(out, p) end
	return out
end

local function publish(d)
	local node = folder:FindFirstChild(d.id)
	if not node then
		node = Instance.new("Configuration")
		node.Name = d.id
		node.Parent = folder
	end
	node:SetAttribute("Mode", d.mode)
	node:SetAttribute("Limit", d.limit)
	node:SetAttribute("TeamA", names(d.teamA))
	node:SetAttribute("TeamB", names(d.teamB))
	node:SetAttribute("FragsA", d.fragsA or 0)
	node:SetAttribute("FragsB", d.fragsB or 0)
	node:SetAttribute("State", d.state)
end

--- Who may be asked into a ranked duel right now: signed in, here, and not already in one.
function Duels.free(player)
	return player ~= nil and player.Parent ~= nil and Ledger.addressOf(player) ~= nil and busy[player] == nil
end

function Duels.busyWith(player)
	return busy[player] and (live[busy[player]] or pending[busy[player]]) or nil
end

-- ---- challenging ---------------------------------------------------------------------------

--- Starts a challenge. `teamA` includes the challenger, first. Returns the challenge, or nil and
--- the reason it could not be made.
function Duels.challenge(teamA, teamB, limit)
	limit = math.floor(tonumber(limit) or 0)
	if limit < Duels.MIN_LIMIT or limit > Duels.MAX_LIMIT then
		return nil, ("First to anything from %d to %d."):format(Duels.MIN_LIMIT, Duels.MAX_LIMIT)
	end
	local size = #teamA
	if size < 1 or size > 2 or #teamB ~= size then return nil, "It's one against one, or two against two." end
	local seen = {}
	for _, p in ipairs(teamA) do
		if seen[p] then return nil, "Somebody's down twice." end
		seen[p] = true
	end
	for _, p in ipairs(teamB) do
		if seen[p] then return nil, "Somebody's down on both sides." end
		seen[p] = true
	end
	for p in pairs(seen) do
		if not Ledger.addressOf(p) then return nil, ("%s hasn't signed in with a wallet, so there's nothing to rank."):format(p.Name) end
		if not Duels.free(p) then return nil, ("%s is already in a duel."):format(p.Name) end
	end
	local c = {
		id = newId(), mode = ("%dv%d"):format(size, size), limit = limit,
		teamA = teamA, teamB = teamB, host = teamA[1], accepted = { [teamA[1]] = true },
		state = "pending", at = os.clock(),
	}
	pending[c.id] = c
	for p in pairs(seen) do busy[p] = c.id end
	publish(c)
	task.delay(Duels.ANSWER_SECONDS, function()
		if pending[c.id] == c then Duels.cancel(c, "Nobody answered in time, so it's off.") end
	end)
	return c
end

function Duels.pending(id) return pending[id] end

local function release(c)
	for _, p in ipairs(everyone(c)) do
		if busy[p] == c.id then busy[p] = nil end
	end
	local node = folder:FindFirstChild(c.id)
	if node then node:Destroy() end
end

function Duels.cancel(c, why)
	if pending[c.id] ~= c then return end
	pending[c.id] = nil
	release(c)
	Duels.announce(everyone(c), why)
end

local start

--- A yes from one of the challenged. Once everybody has said yes, it starts.
function Duels.accept(c, player)
	if pending[c.id] ~= c or busy[player] ~= c.id then return false end
	c.accepted[player] = true
	for _, p in ipairs(everyone(c)) do
		if not c.accepted[p] then return true end
	end
	start(c)
	return true
end

function Duels.decline(c, player)
	if pending[c.id] ~= c or busy[player] ~= c.id then return false end
	Duels.cancel(c, ("%s turned it down."):format(player.Name))
	return true
end

-- ---- fighting ------------------------------------------------------------------------------

start = function(c)
	pending[c.id] = nil
	-- Addresses remembered while everybody is here, so somebody who leaves mid-duel is still on
	-- the record under the address they fought as.
	c.addresses = {}
	for _, p in ipairs(everyone(c)) do c.addresses[p] = Ledger.addressOf(p) end
	c.state = "live"
	c.fragsA, c.fragsB = 0, 0
	c.kills = {}   -- player -> kills in this duel
	c.startedAt = os.time()
	live[c.id] = c
	for _, p in ipairs(c.teamA) do Health.setSide(p, c.id, "A") end
	for _, p in ipairs(c.teamB) do Health.setSide(p, c.id, "B") end
	for _, p in ipairs(everyone(c)) do p:SetAttribute("Duel", c.id) end
	publish(c)
	Duels.announce(everyone(c), ("Ranked duel: %s against %s, first to %d. Nobody else can touch you."):format(
		names(c.teamA), names(c.teamB), c.limit))
	-- Everybody starts even: a fresh body with full hearts, at a spawn, behind its ForceField.
	for _, p in ipairs(everyone(c)) do
		task.spawn(function() pcall(function() p:LoadCharacterAsync() end) end)
	end
end

local finish

Health.onKill(function(victim, killer)
	if not killer then return end
	local id, team = Health.sideOf(killer)
	local d = id and live[id]
	if not d then return end
	local vid = Health.sideOf(victim)
	if vid ~= id then return end
	if team == "A" then d.fragsA += 1 else d.fragsB += 1 end
	d.kills[killer] = (d.kills[killer] or 0) + 1
	publish(d)
	Duels.announce(everyone(d), ("%s got %s. %s %d - %d %s"):format(killer.Name, victim.Name,
		names(d.teamA), d.fragsA, d.fragsB, names(d.teamB)))
	if d.fragsA >= d.limit then finish(d, 1, false)
	elseif d.fragsB >= d.limit then finish(d, 2, false) end
end)

--- The result as it is kept and as it goes on chain.
local function resultOf(d, winner, forfeit)
	local function side(list)
		local out = {}
		for _, p in ipairs(list) do
			table.insert(out, { address = Ledger.addressOf(p) or d.addresses[p], name = p.Name, kills = d.kills[p] or 0 })
		end
		return out
	end
	return {
		id = d.id, mode = d.mode, limit = d.limit,
		teamA = side(d.teamA), teamB = side(d.teamB),
		fragsA = d.fragsA, fragsB = d.fragsB, winner = winner, forfeit = forfeit == true,
		endedAt = os.time(), signatures = {},
	}
end

local function remember(r)
	save("Duels", resultKey(r.id), r)
	local function each(side, won)
		for _, one in ipairs(side) do
			local key = keyOf(one.address)
			update("Duels", "by/" .. key, function(old)
				local list = type(old) == "table" and old or {}
				table.insert(list, 1, r.id)
				while #list > Duels.RECENT do table.remove(list) end
				return list
			end)
			update("Duels", "stats/" .. key, function(old)
				local s = type(old) == "table" and old or {}
				s.name = one.name
				s.kills = (tonumber(s.kills) or 0) + (one.kills or 0)
				s.wins = (tonumber(s.wins) or 0) + (won and 1 or 0)
				s.losses = (tonumber(s.losses) or 0) + (won and 0 or 1)
				return s
			end)
			-- The ranking itself. Incremented by nothing too, so somebody who has fought and not
			-- yet killed anybody is on the board rather than missing from it.
			local ranks = store("DuelKills", true)
			if ranks then
				pcall(function() ranks:IncrementAsync(key, one.kills or 0) end)
			end
		end
	end
	each(r.teamA, r.winner == 1)
	each(r.teamB, r.winner == 2)
end

finish = function(d, winner, forfeit, why)
	if live[d.id] ~= d then return end
	live[d.id] = nil
	d.state = "over"
	publish(d)
	local r = resultOf(d, winner, forfeit)
	for _, p in ipairs(everyone(d)) do
		if p.Parent then
			Health.setSide(p, nil)
			p:SetAttribute("Duel", nil)
		end
		busy[p] = nil
	end
	task.delay(8, function()
		local node = folder:FindFirstChild(d.id)
		if node then node:Destroy() end
	end)
	local winners = winner == 1 and d.teamA or d.teamB
	Duels.announce(everyone(d), ("%s%s win, %d - %d. It's on the town's record."):format(
		why and (why .. " ") or "", names(winners), r.fragsA, r.fragsB))
	task.spawn(function()
		remember(r)
		Duels.refreshRanks()
		Duels.askEveryone(r)
	end)
	return r
end

--- Walking out, or asking to stop: the other side wins it as it stands.
function Duels.forfeit(player, why)
	local id = busy[player]
	if not id then return false end
	local c = pending[id]
	if c then
		Duels.cancel(c, ("%s pulled out."):format(player.Name))
		return true
	end
	local d = live[id]
	if not d then return false end
	local _, team = Health.sideOf(player)
	finish(d, team == "A" and 2 or 1, true, why or ("%s gave it up."):format(player.Name))
	return true
end

Players.PlayerRemoving:Connect(function(player)
	if busy[player] then Duels.forfeit(player, ("%s left."):format(player.Name)) end
end)

-- ---- the record ----------------------------------------------------------------------------

function Duels.result(id)
	return load("Duels", resultKey(id))
end

--- A player's recent results, newest first.
function Duels.recent(player)
	local address = Ledger.addressOf(player)
	if not address then return {} end
	local ids = load("Duels", "by/" .. keyOf(address))
	local out = {}
	for _, id in ipairs(type(ids) == "table" and ids or {}) do
		local r = Duels.result(id)
		if type(r) == "table" then table.insert(out, r) end
	end
	return out
end

--- The top of the town's leaderboard: { name, address, kills, wins, losses }, most kills first.
function Duels.leaderboard(count)
	local ranks = store("DuelKills", true)
	if not ranks then return {} end
	local ok, pages = pcall(function() return ranks:GetSortedAsync(false, count or 10) end)
	if not ok or not pages then return {} end
	local out = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		local s = load("Duels", "stats/" .. entry.key) or {}
		table.insert(out, { address = entry.key, name = s.name or Ledger.short(entry.key),
			kills = tonumber(entry.value) or 0, wins = tonumber(s.wins) or 0, losses = tonumber(s.losses) or 0 })
	end
	return out
end

--- Each player's place on the leaderboard, as their "Rank" attribute: 1 for the most kills, nil for
--- somebody who has never fought a ranked duel. Every client draws it after the name over their
--- head. Set after every result and whenever somebody signs in, since a place moves when anybody's
--- kills do. Yields.
function Duels.refreshRanks()
	local ranks = store("DuelKills", true)
	if not ranks then return end
	local ok, pages = pcall(function() return ranks:GetSortedAsync(false, 100) end)
	if not ok or not pages then return end
	local place, n = {}, 0
	while true do
		for _, entry in ipairs(pages:GetCurrentPage()) do
			n += 1
			place[keyOf(entry.key)] = n
		end
		if pages.IsFinished or n >= 1000 then break end
		if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local address = Ledger.addressOf(p)
		p:SetAttribute("Rank", address and place[keyOf(address)] or nil)
	end
end

local function watchRank(player)
	player:GetAttributeChangedSignal("WalletAddress"):Connect(function() task.spawn(Duels.refreshRanks) end)
	if Ledger.addressOf(player) then task.spawn(Duels.refreshRanks) end
end
-- The town's owner starts the ranked board at the top with nothing: their own account (the one
-- Donations names, and the first announcement), at 0 kills and no matches, named as they play.
-- Written once, only while they are not on the board at all -- any real duel of theirs, and anybody
-- else's first kill, puts the board back to what was actually fought.
Duels.FOUNDER = { address = Contracts.Donations, name = "Founder" }
task.spawn(function()
	local founder = Duels.FOUNDER.address
	local ranks = founder and founder ~= "" and store("DuelKills", true)
	if not ranks then return end
	local key = keyOf(founder)
	local ok, have = pcall(function() return ranks:GetAsync(key) end)
	if not ok or have ~= nil then return end
	pcall(function() ranks:SetAsync(key, 0) end)
	update("Duels", "stats/" .. key, function(old)
		local s = type(old) == "table" and old or {}
		s.name = s.name or Duels.FOUNDER.name
		s.kills, s.wins, s.losses = tonumber(s.kills) or 0, tonumber(s.wins) or 0, tonumber(s.losses) or 0
		return s
	end)
	Duels.refreshRanks()
end)

Players.PlayerAdded:Connect(watchRank)
for _, p in ipairs(Players:GetPlayers()) do watchRank(p) end

--- Which team an address fought on in a result: 1, 2, or nil.
function Duels.teamOf(r, address)
	local key = keyOf(address)
	for _, one in ipairs(r.teamA or {}) do if keyOf(one.address) == key then return 1 end end
	for _, one in ipairs(r.teamB or {}) do if keyOf(one.address) == key then return 2 end end
	return nil
end

local function addresses(side)
	local out = {}
	for _, one in ipairs(side) do table.insert(out, one.address) end
	return out
end

local function killsOf(side)
	local out = {}
	for _, one in ipairs(side) do table.insert(out, one.kills or 0) end
	return out
end

--- What the other side signs: EIP-712 over the result, for DuelRecords on this chain.
function Duels.typed(r)
	return {
	-- The name below is not this project's name: the deployed DuelRecords has that string in its
	-- bytecode and checks every signature against it. See contracts/DuelRecords.sol.
		domain = { name = "PulseBlockz Duels", version = "1", chainId = Contracts.ChainId,
			verifyingContract = Contracts.DuelRecords },
		primaryType = "Result",
		types = { Result = {
			{ name = "id", type = "bytes32" }, { name = "teamA", type = "address[]" },
			{ name = "teamB", type = "address[]" }, { name = "killsA", type = "uint16[]" },
			{ name = "killsB", type = "uint16[]" }, { name = "limit", type = "uint16" },
			{ name = "winner", type = "uint8" }, { name = "endedAt", type = "uint64" },
		} },
		message = { id = r.id, teamA = addresses(r.teamA), teamB = addresses(r.teamB),
			killsA = killsOf(r.teamA), killsB = killsOf(r.teamB), limit = r.limit, winner = r.winner, endedAt = r.endedAt },
	}
end

--- The transaction that records it, as the sender's wallet is asked to send it.
function Duels.recordCall(r, signature)
	return {
		action = "write", to = Contracts.DuelRecords,
		fn = "record(bytes32,address[],address[],uint16[],uint16[],uint16,uint8,uint64,bytes)",
		args = { r.id, addresses(r.teamA), addresses(r.teamB), killsOf(r.teamA), killsOf(r.teamB), r.limit, r.winner, r.endedAt, signature },
		note = ("Put %s %d - %d %s on chain"):format(r.teamA[1] and r.teamA[1].name or "?", r.fragsA, r.fragsB,
			r.teamB[1] and r.teamB[1].name or "?"),
	}
end

--- Keeps a signature against a result, so one given once can be used by anybody on the sending
--- side later. Only a signature the wallet said came from somebody on the other side of `from`.
function Duels.keepSignature(id, signer, signature)
	return update("Duels", resultKey(id), function(old)
		if type(old) ~= "table" then return nil end
		old.signatures = type(old.signatures) == "table" and old.signatures or {}
		old.signatures[keyOf(signer)] = signature
		return old
	end)
end

--- Whether `signature` really is `address`'s over `r`, asked of DuelRecords itself.
---
--- A signature comes back from a player's own machine, and that machine can say anything: one kept
--- without checking marks a result agreed that nobody agreed to, and the winner who sends it pays
--- for a transaction that can only revert. The contract recovers the signer in a read, so the town
--- checks with no key of its own. Yields.
function Duels.signedFor(r, address, signature)
	if type(signature) ~= "string" or not signature:match("^0x%x+$") or not address then return false end
	local answer = Ledger.request({ action = "read", to = Contracts.DuelRecords,
		fn = "signerOf(bytes32,address[],address[],uint16[],uint16[],uint16,uint8,uint64,bytes)",
		args = { r.id, addresses(r.teamA), addresses(r.teamB), killsOf(r.teamA), killsOf(r.teamB), r.limit, r.winner, r.endedAt, signature },
		returns = { "address" } })
	local who = answer and answer.ok and answer.words and answer.words[1]
	return type(who) == "string" and keyOf(who) == keyOf(address)
end

--- Whether the chain has `id`, agreed (`recorded`) or witnessed (`witnessedOf`). The town's record only
--- says "on chain" once the chain does -- not on a machine's word that its transaction went. Yields.
function Duels.onChain(id, witnessed)
	local answer = Ledger.request(witnessed
		and { action = "read", to = Contracts.DuelRecords, fn = "witnessedOf(bytes32)", args = { id }, returns = { "bytes32" } }
		or { action = "read", to = Contracts.DuelRecords, fn = "recorded(bytes32)", args = { id }, returns = { "bool" } })
	local word = answer and answer.ok and answer.words and answer.words[1]
	if witnessed then return type(word) == "string" and word:gsub("^0x", ""):match("[1-9a-fA-F]") ~= nil end
	return word == true
end

function Duels.markRecorded(id, hash)
	return update("Duels", resultKey(id), function(old)
		if type(old) ~= "table" then return nil end
		old.onChain = hash or true
		return old
	end)
end

-- ---- agreeing to it ------------------------------------------------------------------------
-- The moment a duel ends, everybody in it is asked to sign the result: free, nothing sent, just
-- their own wallet saying "that is what happened". Each signature is kept on the town's record.
-- Anybody who waved it off, walked out, or was not there can agree to it later, at the Funmaster.
-- Once somebody from each side has signed, any of them can put it on chain and pay for it.

--- Whether `address` has signed `r`.
function Duels.signedBy(r, address)
	local sigs = type(r) == "table" and type(r.signatures) == "table" and r.signatures or {}
	local sig = address and sigs[keyOf(address)]
	return type(sig) == "string" and sig ~= ""
end

--- Whether each side has at least one signature -- enough to put it on chain.
function Duels.agreedByBoth(r)
	local function any(side)
		for _, one in ipairs(side or {}) do
			if Duels.signedBy(r, one.address) then return true end
		end
		return false
	end
	return any(r.teamA) and any(r.teamB)
end

--- Asks `player`, who fought in `r`, to sign it. Keeps the signature if their wallet gives one, as
--- theirs -- the address their wallet signed as, which must be the address they fought as. Yields.
function Duels.agree(player, r, note)
	if not Contracts.DuelRecords or Contracts.DuelRecords == "" then
		return { ok = false, message = "The duel record contract isn't on chain yet, so there's nothing to sign against." }
	end
	local address = Ledger.addressOf(player)
	if not address or not Duels.teamOf(r, address) then
		return { ok = false, message = "You weren't in that one." }
	end
	if Duels.signedBy(r, address) then
		return { ok = true, signature = r.signatures[keyOf(address)], message = "You've already agreed to it." }
	end
	local answer = Ledger.requestFor(player, {
		action = "sign_typed", typed = Duels.typed(r),
		note = note or "Sign to agree this is how the duel went. It costs nothing and sends nothing.",
	}, Duels.SIGN_SECONDS)
	if answer and answer.ok and type(answer.signature) == "string"
		and type(answer.address) == "string" and keyOf(answer.address) == keyOf(address) then
		if not Duels.signedFor(r, address, answer.signature) then
			return { ok = false, message = "That signature isn't yours for this result, so it isn't kept." }
		end
		Duels.keepSignature(r.id, answer.address, answer.signature)
		r.signatures = type(r.signatures) == "table" and r.signatures or {}
		r.signatures[keyOf(address)] = answer.signature
		return { ok = true, signature = answer.signature, message = "Agreed." }
	end
	return { ok = false, message = tostring(answer and answer.message or "no answer") }
end

--- Asks everybody in `r` who is here, all at once, and says how it went once they have answered.
function Duels.askEveryone(r)
	if not Contracts.DuelRecords or Contracts.DuelRecords == "" then return end
	local asked, answered = {}, 0
	for _, side in ipairs({ r.teamA, r.teamB }) do
		for _, one in ipairs(side) do
			for _, p in ipairs(Players:GetPlayers()) do
				local a = Ledger.addressOf(p)
				if a and keyOf(a) == keyOf(one.address) then table.insert(asked, p) end
			end
		end
	end
	if #asked == 0 then return end
	Duels.announce(asked, "Sign to agree to the result -- it's free. Anybody who doesn't can agree to it later at the Funmaster.")
	for _, p in ipairs(asked) do
		task.spawn(function()
			local answer = Duels.agree(p, r)
			answered += 1
			Duels.announce(asked, answer.ok and ("%s agreed to the result."):format(p.Name)
				or ("%s hasn't agreed to it yet."):format(p.Name))
			if answered == #asked then
				local fresh = Duels.result(r.id) or r
				if Duels.agreedByBoth(fresh) then
					Duels.announce(asked, "Both sides have agreed. Any of you can put it on chain from the Funmaster.")
				else
					Duels.announce(asked, "Not both sides have agreed. It can be agreed to later at the Funmaster -- and everybody else here is being asked to witness it.")
					Duels.askWitnesses(fresh, asked)
				end
			end
		end)
	end
end

-- ---- witnesses --------------------------------------------------------------------------------
-- When a side will not agree -- they waved it off, walked out, or were not there to ask -- everybody
-- else signed in here is asked to witness it: the same result, signed by somebody who was not in
-- it. More than half of the people asked is a witnessed result, and a witnessed result can go on
-- chain too, marked as witnessed and counted apart (DuelRecords.recordWitnessed), because the chain
-- cannot tell a bystander from a spare wallet and the town that asked them can.

--- Whether more than half of the bystanders asked about `r` signed it.
function Duels.witnessed(r)
	if type(r) ~= "table" or type(r.witnessesAsked) ~= "table" or #r.witnessesAsked == 0 then return false end
	local signed = 0
	for _, address in ipairs(r.witnessesAsked) do
		local sig = type(r.witnesses) == "table" and r.witnesses[keyOf(address)]
		if type(sig) == "string" and sig ~= "" then signed += 1 end
	end
	return signed * 2 > #r.witnessesAsked
end

function Duels.witnessSignatures(r)
	local out = {}
	for _, address in ipairs(type(r.witnessesAsked) == "table" and r.witnessesAsked or {}) do
		local sig = type(r.witnesses) == "table" and r.witnesses[keyOf(address)]
		if type(sig) == "string" and sig ~= "" then table.insert(out, sig) end
	end
	return out
end

--- Asks every signed-in player who was not in `r` to witness it, and tells `told` how it went.
function Duels.askWitnesses(r, told)
	if not Contracts.DuelRecords or Contracts.DuelRecords == "" then return end
	local bystanders, addresses = {}, {}
	for _, p in ipairs(Players:GetPlayers()) do
		local a = Ledger.addressOf(p)
		if a and not Duels.teamOf(r, a) then
			table.insert(bystanders, p)
			table.insert(addresses, keyOf(a))
		end
	end
	if #bystanders == 0 then
		Duels.announce(told, "Nobody else is here to witness it.")
		return
	end
	update("Duels", resultKey(r.id), function(old)
		if type(old) ~= "table" then return nil end
		old.witnessesAsked = addresses
		old.witnesses = type(old.witnesses) == "table" and old.witnesses or {}
		return old
	end)
	local function who(side)
		local n = {}
		for _, one in ipairs(side) do table.insert(n, one.name) end
		return table.concat(n, " & ")
	end
	local winners = r.winner == 1 and r.teamA or r.teamB
	local losers = r.winner == 1 and r.teamB or r.teamA
	local answered = 0
	for _, p in ipairs(bystanders) do
		task.spawn(function()
			local answer = Ledger.requestFor(p, {
				action = "sign_typed", typed = Duels.typed(r),
				note = ("Witness a ranked duel: %s beat %s, %d - %d. One side hasn't agreed to it. If that's how it went, sign to witness it -- it's free."):format(
					who(winners), who(losers), r.winner == 1 and r.fragsA or r.fragsB, r.winner == 1 and r.fragsB or r.fragsA),
			}, Duels.WITNESS_SECONDS)
			local address = Ledger.addressOf(p)
			if answer and answer.ok and type(answer.signature) == "string" and address
				and type(answer.address) == "string" and keyOf(answer.address) == keyOf(address)
				and Duels.signedFor(r, address, answer.signature) then
				update("Duels", resultKey(r.id), function(old)
					if type(old) ~= "table" then return nil end
					old.witnesses = type(old.witnesses) == "table" and old.witnesses or {}
					old.witnesses[keyOf(address)] = answer.signature
					return old
				end)
			end
			answered += 1
			if answered == #bystanders then
				local fresh = Duels.result(r.id) or r
				local signed = #Duels.witnessSignatures(fresh)
				Duels.announce(told, Duels.witnessed(fresh)
					and ("Witnessed by %d of %d. It can go on chain as witnessed from the Funmaster."):format(signed, #bystanders)
					or ("Only %d of %d witnessed it, which isn't enough."):format(signed, #bystanders))
			end
		end)
	end
end

--- The transaction that records a witnessed result.
function Duels.recordWitnessedCall(r)
	return {
		action = "write", to = Contracts.DuelRecords,
		fn = "recordWitnessed(bytes32,address[],address[],uint16[],uint16[],uint16,uint8,uint64,bytes[])",
		args = { r.id, addresses(r.teamA), addresses(r.teamB), killsOf(r.teamA), killsOf(r.teamB), r.limit, r.winner, r.endedAt,
			Duels.witnessSignatures(r) },
		note = ("Put %s %d - %d %s on chain, as witnessed"):format(r.teamA[1] and r.teamA[1].name or "?", r.fragsA, r.fragsB,
			r.teamB[1] and r.teamB[1].name or "?"),
	}
end

--- Puts a result on chain, for `player`, who fought in it.
---
--- One signature from the other side is all it takes, and one already given is used again.
--- Otherwise somebody from the other side who is here is asked -- the first who says yes. Then
--- `player`'s own wallet sends it, and pays. Returns { ok, message }; yields throughout.
function Duels.putOnChain(player, id, say)
	say = say or function() end
	if not Contracts.DuelRecords or Contracts.DuelRecords == "" then
		return { ok = false, message = "The duel record contract isn't on chain yet, so there's nowhere to put it." }
	end
	local address = Ledger.addressOf(player)
	local r = Duels.result(id)
	if type(r) ~= "table" then return { ok = false, message = "I can't find that duel." } end
	local mine = address and Duels.teamOf(r, address)
	if not mine then return { ok = false, message = "You weren't in that one, so it isn't yours to send." } end

	if Duels.onChain(r.id) then
		Duels.markRecorded(r.id)
		return { ok = true, message = "That one's already on chain." }
	end

	local other = mine == 1 and r.teamB or r.teamA
	local signature = nil
	for _, one in ipairs(other) do
		local sig = type(r.signatures) == "table" and r.signatures[keyOf(one.address)]
		if type(sig) == "string" and sig ~= "" then signature = sig break end
	end
	if not signature then
		local asked = {}
		for _, one in ipairs(other) do
			for _, p in ipairs(Players:GetPlayers()) do
				local a = Ledger.addressOf(p)
				if a and keyOf(a) == keyOf(one.address) then table.insert(asked, p) end
			end
		end
		if #asked == 0 and not Duels.witnessed(r) then
			return { ok = false, message = "Nobody from the other side is here to sign for it, and it wasn't witnessed." }
		end
		if #asked > 0 then say(("Asking %s to sign for it."):format(names(asked))) end
		for _, p in ipairs(asked) do
			local answer = Duels.agree(p, r, ("%s wants to put your duel on chain. Signing says the result is right; it costs you nothing, and %s pays to send it."):format(
				player.Name, player.Name))
			if answer and answer.ok then
				signature = answer.signature
				break
			end
			say(("%s didn't sign: %s"):format(p.Name, tostring(answer and answer.message or "no answer")))
		end
		if not signature and not Duels.witnessed(r) then
			return { ok = false, message = "Nobody from the other side signed, so it stays on the town's record." }
		end
	end
	if not signature then
		if r.witnessedOnChain then
			return { ok = true, message = "It's already on chain as witnessed. It goes on as agreed once the other side agrees." }
		end
		say("The other side hasn't agreed, but it was witnessed. It goes on chain marked as witnessed.")
		local sent = Ledger.requestFor(player, Duels.recordWitnessedCall(r), Duels.SIGN_SECONDS)
		if sent and sent.ok and Duels.onChain(r.id, true) then
			update("Duels", resultKey(r.id), function(old)
				if type(old) ~= "table" then return nil end
				old.witnessedOnChain = sent.hash or true
				return old
			end)
			return { ok = true, message = "It's on chain, as witnessed. " .. tostring(sent.message or "") }
		end
		return { ok = false, message = "It didn't go: " .. tostring(sent and sent.message or "no answer") }
	end

	say("Signed. Your wallet will show you the transaction.")
	local sent = Ledger.requestFor(player, Duels.recordCall(r, signature), Duels.SIGN_SECONDS)
	if sent and sent.ok and Duels.onChain(r.id) then
		Duels.markRecorded(r.id, sent.hash)
		return { ok = true, message = "It's on chain. " .. tostring(sent.message or "") }
	end
	return { ok = false, message = "It didn't go: " .. tostring(sent and sent.message or "no answer") }
end

return Duels

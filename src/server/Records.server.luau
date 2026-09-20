-- Unger, in the Hall of Records. What a block explorer's front page says, read aloud.
--
-- Everything here is public: the height of the chain, what gas costs, how many
-- transactions this account has ever sent, and the addresses of every contract the
-- town touches. None of it needs a key, and none of it is this town's to keep -- the
-- same numbers are on scan.pulsechain.com, which is the point she keeps making.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ledger = require(script.Parent.Ledger)
local Engrams = require(script.Parent.Engrams)
local Contracts = require(game:GetService("ReplicatedStorage"):WaitForChild("Contracts"))

local remote = Instance.new("RemoteEvent")
remote.Name = "RecordsRemote"
remote.Parent = ReplicatedStorage

local EXPLORER = "scan.v4.testnet.pulsechain.com"

-- The scan first: it is the thing most people came to her for, and the menu scrolls past
-- five, so anything below that is a thing you have to go looking for.
local MENU = {
	{ id = "scan", label = "Open the scan" },
	{ id = "announcements", label = "Announcement History" },
	{ id = "chain", label = "How's the chain doing?" },
	{ id = "account", label = "What's on record for me?" },
	{ id = "history", label = "Show me what I've done" },
	{ id = "contracts", label = "Which contracts does this town use?" },
	{ id = "verify", label = "Can I check any of this myself?" },
}


-- ---- the explorer page ---------------------------------------------------------------
-- Unger still talks, but the numbers go to a page rather than into her mouth. Reading a
-- table of contract addresses aloud, one line at a time, was always the wrong shape:
-- an explorer is a thing you scan with your eyes and paste out of.
local board = Instance.new("RemoteEvent")
board.Name = "ExplorerRemote"
board.Parent = ReplicatedStorage

local reading = {}      -- players with the page open, so it refreshes where they stand

local function page(d)
	if not d or Ledger.loading(d) then
		return { loading = true, host = EXPLORER }
	end
	local c = d.chain or {}
	local txs = {}
	for _, tx in ipairs(d.history or {}) do
		table.insert(txs, {
			hash = tx.hash or "",
			block = tostring(tx.block or ""),
			ok = tx.ok == true,
		})
	end
	return {
		loading = false,
		host = EXPLORER,
		network = d.network or "",
		chain_id = tostring(c.chain_id or ""),
		block = tostring(c.block or ""),
		base_fee = tostring(c.base_fee or ""),
		address = d.address or "",
		gas = d.gas or "",
		txs_ever = tostring(c.txs or ""),
		items = #(d.items or {}),
		txs = txs,
		contracts = {
			{ name = "Registry", address = d.registry or "" },
			{ name = "Marketplace", address = d.marketplace or "" },
			{ name = "Asset store", address = c.assetstore or "" },
			{ name = "Inventory", address = c.inventory or "" },
		},
	}
end

local function showPage(player)
	reading[player] = true
	board:FireClient(player, "page", page(Ledger.data(player)))
end

-- ---- navigating the scan --------------------------------------------------------------
-- The panel asks for a page by the name the explorer's own URLs use -- block, tx,
-- address, tokens -- and the host goes and reads it. Nothing in this script touches the
-- network: it writes down what was asked for and waits to be answered, which is the only
-- way anything inside this sandbox reaches outside it.
local VIEWS = { home = true, blocks = true, block = true, txs = true, tx = true,
	address = true, tokens = true, token = true, search = true }

-- Pages are not this script's business any more.
--
-- The client asks its own client for them -- shared/Scan.luau, answered by Scan.gd on the
-- machine doing the reading. Reading an explorer needs no key and signs nothing, so there
-- was never a reason for the town's server to fetch it, and on a hosted town there is every
-- reason not to: one operator fetching every page every visitor opens, on their bandwidth,
-- with their address in somebody else's logs.
--
-- What is left here is what a server is actually for: putting the window up when you ask Unger
-- for it, and cutting an Engram, which is a fact about YOU rather than a page.

board.OnServerEvent:Connect(function(player, action, view, id)
	if action == "open" then
		showPage(player)
	elseif action == "close" then
		reading[player] = nil
	elseif action == "keep" then
		-- Take the page you are standing on. What you get is a note of where it is, not
		-- a picture of it: showing it later goes and reads the page again.
		-- Every way out of here says something. These were three bare `return`s, and a
		-- refusal nobody is told about is indistinguishable from a town that has stopped
		-- answering -- which is exactly how it looked from the other end: a button that
		-- said "Asking..." and then nothing, forever.
		if not VIEWS[view] or view == "home" then
			board:FireClient(player, "note", "That's not a page I can cut anything from.")
			return
		end
		id = type(id) == "string" and id or ""
		if #id > 66 or id:match("[^%w]") then
			board:FireClient(player, "note", "That page's name isn't one I'd put on a badge.")
			return
		end
		-- Immediate, free, and nothing signed.
		--
		-- This was three transactions: store the badge, store a note about it, record in the
		-- Inventory contract that you hold it -- two documents and a signature for what is,
		-- at the end of the day, a link. It also wrote "this account opened this page in
		-- this block" into a permanent public record, which is nobody's idea of a feature.
		-- An Engram lives as long as you are here now, like a candle or a bruise.
		local name, blurb = Engrams.describe(view, id)
		local one, already = Engrams.take(player, view, id, name, blurb)
		if not one then
			board:FireClient(player, "note", already or "I couldn't cut that one.")
			return
		end
		board:FireClient(player, "note", already
			or ("\"%s\" is yours. Press I to carry it."):format(one.name))
	end
end)

local function greeting(d)
	if not d then
		return "The archive's offline - I can't read the chain right now. Try me in a moment."
	elseif Ledger.loading(d) then
		return "One moment, I'm pulling the latest block - this window fills itself in."
	elseif Ledger.guest(d) then
		return "Hall of Records. No wallet signed in, so nothing on record for you."
	end
	local c = d.chain
	if not c then
		return "Welcome to the Hall of Records. I can see the chain but not the headers just now."
	end
	return ("Hall of Records. Chain %s."):format(c.chain_id or "?")
end

local answers = {}

--- The chain's height and base fee right now. The wallet publishes them only alongside a real
--- change, so the copy in `d.chain` can be minutes old; this reads them when asked, and falls back
--- to that copy if the read does not answer inside `patience`.
local function liveHead(c, patience)
	local answer = Ledger.request({ action = "read", calls = {
		{ to = Contracts.Multicall3, fn = "getBlockNumber()", args = {}, returns = { "uint256" } },
		{ to = Contracts.Multicall3, fn = "getBasefee()", args = {}, returns = { "uint256" } },
	} }, patience)
	local results = answer and answer.ok and answer.results
	local function word(i, fallback)
		local one = type(results) == "table" and results[i]
		if type(one) ~= "table" or not one.ok or type(one.words) ~= "table" or one.words[1] == nil then return fallback end
		return tostring(one.words[1])
	end
	local live = type(results) == "table"
	return word(1, c.block), word(2, c.base_fee), live
end

-- What each player was last told, so a live head that lands late replaces the answer it
-- belongs to and not whatever they have moved on to.
local lastAnswer = {}

local function chainLines(d, c, height, baseFee, live)
	return {
		("Network:    %s"):format(d.network or "?"),
		("Chain id:   %s"):format(c.chain_id or "?"),
		("Height:     block %s%s"):format(height or "?", live and "" or "   (a moment ago; asking the node)"),
		("Base fee:   %s wei"):format(baseFee or "?"),
		"",
		"The base fee is what a transaction burns. Ask the node what to pay and it",
		"says thousands of gwei; paying that costs about fifty PLS a transaction.",
	}
end

function answers.chain(d, player)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	local c = d.chain
	if not c then return { "I can't read the headers just now." } end
	-- Answered now with the last known head, and again when the live one lands. Two seconds
	-- was the most the window would wait, and a read queued behind the town's own start-up
	-- reads takes longer than that, so the archivist mostly read out the stale copy and said
	-- nothing about it.
	local height, baseFee, live = liveHead(c, 1.5)
	if not live and player then
		task.spawn(function()
			local h2, f2, live2 = liveHead(c, 30)
			if live2 and lastAnswer[player] == "chain" and player.Parent then
				remote:FireClient(player, "say", { lines = chainLines(d, c, h2, f2, true), menu = MENU, thumb = "" })
			end
		end)
	end
	return chainLines(d, c, height, baseFee, live)
end

function answers.account(d)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if Ledger.guest(d) then return Ledger.noWallet() end
	local c = d.chain or {}
	local lines = {
		("Address: %s"):format(d.address or "?"),
		("Transactions ever sent: %s"):format(c.txs or "?"),
		("Balance: %s PLS"):format(d.gas or "?"),
		("Items from the registry: %d"):format(#(d.items or {})),
	}
	table.insert(lines, "")
	table.insert(lines, "Read from the chain each time. Nothing of it is stored here.")
	return lines
end

function answers.contracts(d)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	local c = d.chain or {}
	local out = {
		"Everything this town runs on, by address:",
		("  Registry       %s"):format(d.registry or "?"),
		("  Marketplace    %s"):format(d.marketplace or "?"),
		("  Asset store    %s"):format(c.assetstore or "?"),
		("  Inventory      %s"):format(c.inventory or "?"),
	}
	local function add(label, address)
		if address and address ~= "" then table.insert(out, ("  %s %s"):format(label, address)) end
	end
	add("Duelling      ", Contracts.Duelling)
	add("Duel records  ", Contracts.DuelRecords)
	add("Fishing       ", Contracts.Fishing)
	add("Announcements ", Contracts.Announcements)
	table.insert(out, "")
	table.insert(out, "No owner, no admin key, no pause switch on any of them, except")
	table.insert(out, "Announcements: the town's owner can post and pin. Nothing else.")
	return out
end

function answers.verify(d)
	return {
		("Everything is on %s. Paste any of those addresses in for the same"):format(EXPLORER),
		"numbers I just read you, and every transaction that made them.",
		"",
		"An asset's id is the hash of its own bytes. If what comes back doesn't",
		"hash to what was asked for, the client throws it away.",
	}
end

-- ---- keepsakes -------------------------------------------------------------------
-- A transaction you can pick up and carry. Unger's whole argument is that the record is
-- public and permanent; handing you one to hold makes the point better than saying it.
function answers.history(d)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if Ledger.guest(d) then return Ledger.noWallet() end
	local history = d.history or {}
	if #history == 0 then
		return {
			"Nothing on record for you yet, or the explorer isn't answering.",
			"",
			("Read from %s, the explorer's API rather than the node: a node has the"):format(d.explorer or "the explorer"),
			"latest block, not what you did last week.",
		}
	end
	local lines = { ("Your last %d transaction%s:"):format(#history, #history == 1 and "" or "s") }
	local menu = {}
	for _, tx in ipairs(history) do
		table.insert(lines, ("  block %s  %s  %s"):format(tostring(tx.block), tx.ok and "ok " or "REVERTED", Ledger.short(tx.hash)))
		table.insert(menu, { id = "keep", arg = tx.hash, label = ("Take Engram %s"):format(tostring(tx.block)) })
	end
	table.insert(lines, "")
	table.insert(lines, ("Straight off %s. Take an Engram and it's in your bag."):format(d.explorer or "the explorer"))
	for _, entry in ipairs(MENU) do table.insert(menu, entry) end
	return lines, menu
end

--- Opens the explorer. She keeps talking; the page is a second window, asked for.
-- Opens the scan and shuts this window behind it. The third value is what says so: her
-- dialog has nothing left to tell you once the thing you asked for is on screen, and two
-- windows for one keypress is the whole reason the scan came off the greeting.
function answers.scan(d, player)
	if player then showPage(player) end
	return nil, nil, true
end

function answers.keep(d, player, hash)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if Ledger.guest(d) then return Ledger.noWallet() end
	if type(hash) ~= "string" or #hash ~= 66 then
		return { "I didn't catch which one." }
	end
	-- The row you are looking at. It already carries the block and whether it succeeded,
	-- read from the explorer -- so taking an Engram of it asks nothing further of the chain.
	local row = nil
	for _, tx in ipairs(d.history or {}) do
		if tx.hash == hash then row = tx end
	end
	if not row then
		return { "That one's not on your list any more. Ask me again for what you've done." }
	end
	local name, blurb = Engrams.describe("tx", row.hash)
	local one, already = Engrams.take(player, "tx", row.hash, name, blurb)
	if not one then
		return { already or "I couldn't cut that one." }
	end
	if already then
		return { already }
	end
	return {
		("\"%s\" is yours. Press I to carry it."):format(one.name),
		"",
		"It costs nothing and it signs nothing. An Engram is a link -- where that",
		"transaction is, not a copy of it -- and showing it goes and reads the chain",
		"again, which is why nobody can make one say something the chain doesn't.",
		"",
		"It's yours while you're here. Where you've been looking isn't the sort of",
		"thing this town writes down forever, and nobody asked it to.",
	}
end

-- Their page follows their picture: a new block, a new transaction of theirs, the catalogue.
Ledger.onChanged(function(who)
	for player in pairs(reading) do
		if player.Parent and (who == nil or who == player) then showPage(player) end
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player) reading[player] = nil lastAnswer[player] = nil end)

Ledger.onTalk("Archivist", function(player)
	-- Her window, and not the explorer as well. Two panels at once for one keypress is
	-- one too many; the scan is a thing you ask for, from her menu.
	remote:FireClient(player, "open", { title = "Unger  <Hall of Records>", npc = "Archivist", greeting = greeting(Ledger.data(player)), menu = MENU })
end)

-- Every announcement the town's owner has made. Read off the Announcements contract by the player's
-- own machine (Announcements.client.luau); she only opens the book.
function answers.announcements(_d, player)
	remote:FireClient(player, "announcements")
	return nil, nil, true
end

remote.OnServerEvent:Connect(function(player, action, arg)
	if type(action) ~= "string" then return end
	local fn = answers[action]
	if not fn then return end
	lastAnswer[player] = action
	local ok, lines, menu, shut = pcall(fn, Ledger.data(player), player, arg)
	if not ok then
		warn("records: " .. tostring(lines))
		lines = { "Something went wrong on my side. Sorry." }
		menu = nil
		shut = false
	end
	-- An answer may say that it has opened something of its own, in which case her window
	-- goes rather than sitting behind it with nothing to say.
	if shut then
		remote:FireClient(player, "close")
		return
	end
	remote:FireClient(player, "say", { lines = lines, menu = menu or MENU, thumb = "" })
end)

Ledger.onReady(function(player, d)
	remote:FireClient(player, "update", { greeting = greeting(d), menu = MENU })
end)

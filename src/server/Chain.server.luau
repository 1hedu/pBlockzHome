-- What this town reads off the chain, and hands to its own desks.
--
-- Every counter in the square -- the teller, the shelf, the wardrobe, the archivist, the
-- screener -- reads `Ledger.data(player)`: that one player's picture of the world. This builds
-- the two halves of it that are the town's game state:
--
--   the catalogue      what is registered, what is for sale and at what price, the ladder --
--                      the same for everybody, read once and again when idle
--   each player's      what their signed-in address holds in the game's own contracts (the
--   holdings           Registry and the Inventory) and the models it is made of, mounted so they
--                      can be worn. The server reads these to JUDGE -- what somebody may wear and
--                      swing -- and never on anybody's behalf: no key, no writes.
--
-- The third half, a player's balances and history, is read by their own machine from their own
-- wallet (Mine.client.luau), and only ever shown back to them.
--
-- ---- why this is the town's and not the client's ---------------------------------------
-- All of this used to live in demo2/Wallet.gd: four hundred lines of client that knew what
-- a shelf was, what an inventory was, and what a holdings ladder was. That made this town's
-- feature list part of the program you run, which is exactly backwards -- a different place
-- could neither change it nor have its own, and the client got to decide which places could
-- exist.
--
-- The line is the same one that put the PNG encoder here and left the decoder there:
-- deciding WHAT to ask for is the place's, going and getting it is the client's. So this
-- script says which contracts, which functions and which ids; `read` makes the calls and
-- `fetch` gets the bytes; and neither of them knows that any of it is a hat.
--
-- ---- how it talks to the chain ---------------------------------------------------------
-- It cannot. No script here can reach the network -- HttpService's request methods are off
-- in the sandbox, and the runtime has no socket to give one. What it can do is write down
-- what it wants; the host reads that, decides, and writes the answer back.
--
-- Both verbs take a list, and that is not a convenience. Forty items and forty-odd listings
-- asked one at a time, each polled at a tenth of a second, is minutes of waiting and a
-- hammered request channel; asked together they are three round trips. Anything added here
-- should join an existing batch rather than become one more call of its own.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Ledger = require(script.Parent.Ledger)
local Contracts = require(ReplicatedStorage:WaitForChild("Contracts"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))

-- How long to wait on one batch. Ledger.request's default of twenty seconds is sized for a
-- single call; a hundred-odd of them across three round trips on a public node is not, and
-- giving up early publishes a short list as though it were the whole one -- which is how
-- things you own blink out of your bags.
local PATIENCE = 90

-- How much of the registry to look at, counting back from the newest id. Zero is all of it,
-- and all of it is the right answer here.
--
-- This had a window once, and it cost a working shop twice. Seven new items moved nextId
-- from 32 to 39, the window slid to 15..38, and the five items below it -- the top hat,
-- Louis, the Rolex, the copper trousers, the cane -- vanished from the shelf AND from their
-- owner's inventory in the same breath, because one scan decides both. Nothing had been
-- lost; this had simply stopped looking that far back. The registry is tens of items and
-- each costs two calls inside a batch, so it is read whole.
local SCAN_IDS = 0

-- Calls per round of the registry scan. Forty-eight, because past that this node stops
-- answering -- and a batch that did not answer looks exactly like a chain with nothing on
-- it, so the cost of guessing high is things quietly missing from the shelf.
--
-- It is tempting to go higher: the host spreads a batch over five parallel lanes, so a
-- round is one round trip however many calls are in it, and forty-eight is only ten a lane.
-- That was tried. Putting the one balanceOfBatch call in the same round as the forty-nine
-- tokensFor calls -- fifty calls, still ten a lane -- took the scan from 11.6s to 37.1s and
-- lost six listings, twice, reproducibly. Whatever the node is doing there, it is not what
-- the arithmetic says it should. Measure before raising this.
local CALLS_PER_ROUND = 48

-- How often to read the catalogue again when nothing has happened: another creator registering
-- an asset, or a price changing. A player's own writes re-read their holdings on their own.
local IDLE_SECONDS = 60
-- How old a player's holdings may get before they are read again unasked. Anything they do in
-- the town reads them at once (Ledger.onPlayerWrote); this is for what happens to their address
-- elsewhere, and five minutes is soon enough to notice a transfer from another window.
local HOLDINGS_SECONDS = 300

-- How long to wait before trying again when the catalogue read did not answer at all: the node
-- is down, or there is no network. Soon enough that the shelf fills in when it comes back, and
-- not so soon that a town with no network does nothing but ask.
local RETRY_SECONDS = 15

-- ---- talking to the host ---------------------------------------------------------------

--- One batched read. Returns the list of results, or nil if the host did not answer --
--- which is a real outcome and not an error: there may be no key, no network, or no node.
---
--- nil and empty are different answers, and that difference is the whole reason this
--- returns nil rather than an empty table. A read that failed must never be published as a
--- chain with nothing on it.
local function readMany(calls)
	if #calls == 0 then return {} end
	local answer = Ledger.request({ action = "read", calls = calls }, PATIENCE)
	if not answer or not answer.ok or type(answer.results) ~= "table" then return nil end
	return answer.results
end

--- The words of one result, or nil. Every caller handles a slot that failed on its own --
--- one bad row does not fail a batch, by design -- so this is the only place that reaches
--- into the shape.
local function wordsOf(results, i)
	local one = results and results[i]
	if type(one) ~= "table" or not one.ok or type(one.words) ~= "table" then return nil end
	return one.words
end

local function firstWord(results, i, fallback)
	local w = wordsOf(results, i)
	if not w or w[1] == nil then return fallback end
	return w[1]
end

--- Documents, by uri, fetched together. `as` says what to get back: "text" for the JSON
--- metadata, "file" for a picture the game can point an ImageLabel at, "model" for
--- something it can clone onto a character.
local function fetchMany(uris, as)
	if #uris == 0 then return {} end
	local answer = Ledger.request({ action = "fetch", uris = uris, as = as }, PATIENCE)
	if not answer or not answer.ok or type(answer.results) ~= "table" then return nil end
	return answer.results
end

-- ---- the catalogue ---------------------------------------------------------------------

--- Which ids exist.
---
--- Nothing here asks the Marketplace. The shelf used to be "whatever has a price", which made a
--- mock token's price the index of a shop where nothing is bought: taking a thing is holding
--- enough tPLS, and the price was never read by anything but this list.
local function scanRegistry()
	local size = readMany({
		{ to = Contracts.Registry, fn = "nextId()", args = {}, returns = { "uint256" } },
	})
	if not size then return nil end
	local nextId = tonumber(firstWord(size, 1, "0")) or 0
	if nextId <= 1 then return { ids = {} } end

	local lowest = 1
	if SCAN_IDS > 0 then lowest = math.max(1, nextId - SCAN_IDS) end

	local ids = {}
	for id = nextId - 1, lowest, -1 do table.insert(ids, id) end
	return { ids = ids }
end

--- Which of `ids` one address holds, and how many.
---
--- The Registry is an ERC1155 and ERC1155 has balanceOfBatch for exactly this, so the whole
--- registry's holdings are a single eth_call rather than one per id -- and alone in its round,
--- because sharing one with the listings measured three times slower and lost rows (see
--- CALLS_PER_ROUND).
local function balancesOf(ids, address)
	if #ids == 0 then return {} end
	local who = table.create(#ids)
	for _ = 1, #ids do table.insert(who, address) end
	local balances = readMany({
		{ to = Contracts.Registry, fn = "balanceOfBatch(address[],uint256[])",
		  args = { who, ids }, returns = { "uint256[]" } },
	})
	if not balances then return nil end
	local held = (wordsOf(balances, 1) or {})[1]
	if type(held) ~= "table" then return nil end
	local owned = {}
	for k, id in ipairs(ids) do
		local qty = tostring(held[k] or "0")
		if qty ~= "0" and qty ~= "" then
			table.insert(owned, { id = id, qty = qty })
		end
	end
	return owned
end

--- The uri of every id asked about, kept between rounds.
---
--- An asset's uri is set when it is minted and names its bytes by their own hash, so it can
--- never point at anything else. Asking for it again is a call with no possible new answer in
--- it, and until now every one of them went out again every single round -- one per item,
--- forever, on a loop that runs at least once a minute.
---
--- What is NOT in here is everything that can actually move: balances and who owns what. Those
--- are read whole every round, which is the entire point of reading at all.
local uriMemo = {}

-- ---- and kept between visits ------------------------------------------------------------
-- An id's uri is the slowest thing in the read that also changes the least. On a cold start
-- it is one call per thing you own or that is on sale -- about fifty of them, ten seconds --
-- and the answer is nearly always the one it gave last time.
--
-- So it is written down. DataStoreService is where a Roblox game keeps exactly this, and it
-- survives leaving. What it is NOT is trusted: setUri can change an id's uri right up until
-- the asset is frozen, so the cache is used to answer the FIRST read of a session and then
-- checked against the chain in the background. If anything moved, the memo is corrected and
-- the town publishes again a moment later. Fast and wrong for three seconds beats correct
-- and ten seconds late, as long as it cannot stay wrong.
local DataStoreService = game:GetService("DataStoreService")
local URI_STORE, URI_KEY = "chain", "uris"
local uriStore = nil
local uriDirty = false

local function uriBook()
	if uriStore then return uriStore end
	local ok, got = pcall(function() return DataStoreService:GetDataStore(URI_STORE) end)
	uriStore = ok and got or nil
	return uriStore
end

local function loadUris()
	local book = uriBook()
	if not book then return end
	local ok, got = pcall(function() return book:GetAsync(URI_KEY) end)
	if not ok or type(got) ~= "table" then return end
	for key, uri in pairs(got) do
		local id = tonumber(key)
		if id and type(uri) == "string" and uri ~= "" then uriMemo[id] = uri end
	end
end

local function saveUris()
	if not uriDirty then return end
	uriDirty = false
	local book = uriBook()
	if not book then return end
	-- Keyed by the id as a STRING: a table with number keys does not survive a round trip
	-- through JSON as the same shape, and an id that comes back as "7" is an id that never
	-- matches 7 again.
	local out = {}
	for id, uri in pairs(uriMemo) do out[tostring(id)] = uri end
	pcall(function() book:SetAsync(URI_KEY, out) end)
end

loadUris()

local function detailsFor(uriWanted)
	local uriIds, seenId = {}, {}
	for _, id in ipairs(uriWanted) do
		if not seenId[id] and not uriMemo[id] then
			seenId[id] = true; table.insert(uriIds, id)
		end
	end
	if #uriIds == 0 then return { uriOf = uriMemo } end

	local calls = {}
	for _, one in ipairs(uriIds) do
		table.insert(calls, { to = Contracts.Registry, fn = "uri(uint256)",
			args = { one }, returns = { "string" } })
	end
	local r = readMany(calls)
	if not r then return nil end

	-- Only what was asked for this round goes into the memo; everything else is already in
	-- it. An empty uri is not remembered -- that is a call that failed, not an asset
	-- without bytes, and remembering it would make one bad round permanent.
	for k, one in ipairs(uriIds) do
		local got = tostring(firstWord(r, k, ""))
		if got ~= "" and uriMemo[one] ~= got then uriMemo[one] = got uriDirty = true end
	end
	return { uriOf = uriMemo }
end

-- ---- the inventory ---------------------------------------------------------------------

-- Which blob in the store holds a given hash. Settled when the bytes land, so asked once.
local blobMemo = {}
-- Which uri a carried document came back as, by its hash. Its text is in `described`.
local carriedUri = {}

--- What the Inventory contract says you carry. Separate from the registry on purpose: this
--- is the record that survives the shop, and an id here folds in the rung it was claimed
--- at, so it is not fetchable on its own. dataOf is what turns it back into the hash of the
--- bytes the thing is actually made of.
local function readInventory(address)
	local page = readMany({
		{ to = Contracts.Inventory, fn = "inventoryOf(address,uint256,uint256)",
			args = { address, 0, 128 }, returns = { "bytes32[]", "bytes32[]", "bytes32[]" } },
	})
	if not page then return nil end
	local w = wordsOf(page, 1)
	if not w then return {} end
	local ids, counts, datas = w[1] or {}, w[2] or {}, w[3] or {}

	local ZERO = "0x" .. string.rep("0", 64)
	local wanted = {}
	for i, id in ipairs(ids) do
		local n = tostring(counts[i] or "")
		local held = n:gsub("^0x", ""):gsub("^0+", "") ~= ""
		local data = datas[i]
		if held and data and data ~= ZERO then
			table.insert(wanted, { id = id, hash = data })
		end
	end
	if #wanted == 0 then return {} end

	-- A hash on its own is not fetchable: blobOf says which blob in the store holds those
	-- bytes, and the client composes the uri out of the two.
	--
	-- Asked once per hash and then remembered. Bytes are stored under the hash OF those
	-- bytes, so which blob holds them is settled the moment they land and cannot move. This
	-- was forty calls a round, every round, all of them with the same answer as last time.
	local calls, asking = {}, {}
	for _, one in ipairs(wanted) do
		if not blobMemo[one.hash] then
			table.insert(asking, one.hash)
			table.insert(calls, { to = Contracts.AssetStore, fn = "blobOf(bytes32)",
				args = { one.hash }, returns = { "uint256" } })
		end
	end
	if #calls > 0 then
		local r = readMany(calls)
		if not r then return nil end
		for i, hash in ipairs(asking) do
			local blob = tonumber(firstWord(r, i, "0")) or 0
			-- Zero is "not in this store", which a later round could still change -- a blob
			-- can be written after the record of it. Only a real answer is kept.
			if blob > 0 then blobMemo[hash] = blob end
		end
	end
	local out = {}
	for _, one in ipairs(wanted) do
		local blob = blobMemo[one.hash]
		-- Recorded, but its bytes are not in this store. Nothing to draw, so nothing to say.
		if blob then
			table.insert(out, { id = one.id, qty = "1", source = "inventory",
				hash = one.hash, blob = blob })
		end
	end
	return out
end

-- ---- what a thing is -------------------------------------------------------------------

-- Metadata documents, by uri, read once and kept.
--
-- They are content-addressed, so what a uri names cannot change. Fetching the same sixty
-- documents every minute is work with no possible new answer in it, and it lands on the
-- thread the music is generated on.
local described = {}

local function describe(entries)
	-- Everything not already known, in one warming. This is the difference between a shelf
	-- that fills in and a shelf you wait two minutes for.
	local missing = {}
	for _, e in ipairs(entries) do
		if e.uri and e.uri ~= "" and not described[e.uri] then missing[e.uri] = true end
	end
	local list = {}
	for uri in pairs(missing) do table.insert(list, uri) end
	if #list > 0 then
		local docs = fetchMany(list, "text")
		if docs then
			for i, uri in ipairs(list) do
				local one = docs[i]
				if type(one) == "table" and one.ok and type(one.text) == "string" then
					local ok, doc = pcall(function() return HttpService:JSONDecode(one.text) end)
					if ok and type(doc) == "table" then described[uri] = doc end
				end
			end
		end
	end

	for _, e in ipairs(entries) do
		local doc = described[e.uri or ""]
		if doc then
			e.name = tostring(doc.name or "")
			e.kind = tostring(doc.kind or "")
			-- Which body slot it occupies. Metadata written before slots existed comes back
			-- "", and the wardrobe treats that as belonging to no slot -- the pre-slot
			-- behaviour rather than a crash. The model itself also says, and the client
			-- reads it off the attachment when it mounts one.
			e.slot = tostring(doc.slot or "")
			-- The rung it is claimed at, as its MAKER published it. This used to be derived
			-- from the item's price, which meant the shelf gated on spending while the
			-- chain gated on holdings -- two ladders for one question, and the item's own
			-- metadata had no say in either.
			e.tier = tonumber(doc.tier) or 0
			if doc.tier_pls ~= nil then e.tier_pls = tonumber(doc.tier_pls) end
			-- An outfit is a record rather than a thing: no model, and what matters about
			-- it is the list inside. Stamped, so the newest one wins.
			if e.kind == "outfit" then
				e.worn = doc.worn or {}
				e.at = tonumber(doc.at) or 0
			end
		end
	end
end

--- Pictures and models, for the things that need them.
---
--- A picture is worth a round trip for anything on a card. A MODEL is only worth one for
--- something you actually hold -- the shop shows a name and a picture, and pulling down
--- forty models to browse a shelf is what made the first read of a full shop take two
--- minutes.
-- What a picture and a model came back as, by uri. Same reason as the metadata beside them:
-- a uri names bytes by their own hash, so fetching one twice is asking a question that has
-- already been answered. The host keeps its own copy on disk, so the second fetch cost no
-- network -- but it was still a round trip out of the sandbox and a model mounted again,
-- once per item, every round, forever.
local modelOf = {}

--- What a document says an asset is, as something the town can point at.
---
--- A document names its picture and its model by content hash and stops there -- that is
--- what the thing IS, and which chain, store and blob hold a copy this month is not. The
--- client fills the rest in (AssetStore.blobOf says where, the blob says what kind), so all
--- that is needed here is to say that these characters are a content id and not a caption:
--- an ImageLabel is handed the string and looks for a scheme in it.
---
--- Anything already carrying one is passed through, which is what a model stored before
--- this looks like.
local function asset(ref)
	local text = tostring(ref or "")
	if text == "" or text:find("://", 1, true) then return text end
	return "pblockz://" .. (text:gsub("^0x", ""))
end

local function dress(entries, wantModels)
	local models, modelOwner = {}, {}
	for _, e in ipairs(entries) do
		local doc = described[e.uri or ""]
		if doc then
			-- The picture goes out as the uri that names it, and each client fetches its own copy
			-- (shared/Pictures.luau). It used to be fetched here and sent as this machine's file
			-- path, which a joined client could only draw if the same file happened to be in its
			-- own folder already.
			e.thumb = asset(doc.thumbnail)
			local model = asset(doc.model)
			if wantModels and model ~= "" then
				local had = modelOf[model]
				if had then
					e.model = had.name
					if (e.slot or "") == "" and had.slot then e.slot = had.slot end
				else
					table.insert(models, model)
					modelOwner[#models] = e
				end
			end
		end
	end
	if #models > 0 then
		local got = fetchMany(models, "model")
		for i, e in pairs(modelOwner) do
			local one = got and got[i]
			if type(one) == "table" and one.ok and one.name then
				e.model = one.name
				-- The model says which limb it follows even when the metadata does not, and
				-- the client reads that off the single Attachment in its Handle. This is
				-- why something published before slots existed still lands in a socket you
				-- can click.
				if (e.slot or "") == "" and one.slot then e.slot = one.slot end
				modelOf[models[i]] = { name = one.name, slot = one.slot }
			end
		end
	end
end

-- ---- the ladder ------------------------------------------------------------------------

-- Read once: the rungs are fixed at construction and nobody can move them. Where a player stands
-- on it is worked out against their own balance, in Ledger.data.
local ladder = nil

local function rungs()
	if ladder then return ladder end
	local r = readMany({
		{ to = Contracts.Inventory, fn = "ladder()", args = {}, returns = { "uint256[]" } },
	})
	local w = wordsOf(r, 1)
	if w and type(w[1]) == "table" and #w[1] > 0 then ladder = w[1] end
	return ladder
end

-- How long each leg of a read took, so "the town takes ages to fill in" can be answered
-- with a number instead of a guess. Printed once per read, not per call: this is a handful
-- of round trips, and which one of them is the slow one is the whole question.
local legs = {}
local function leg(name, fn, ...)
	local at = os.clock()
	local a, b = fn(...)
	table.insert(legs, ("%s %.1fs"):format(name, os.clock() - at))
	return a, b
end

-- ---- the catalogue ---------------------------------------------------------------------

local catalogueIds = nil   -- the registry's ids as of the last good read, which holdings are read against

local function readCatalogue()
	legs = {}
	local scan = leg("registry", scanRegistry)
	if not scan then return nil end
	local details = leg("details", detailsFor, scan.ids)
	if not details then return nil end

	-- The shelf is every registered thing whose own metadata puts it on a rung of the ladder.
	-- A rung is what taking it is gated on, so a thing without one has no way off the shelf --
	-- the demo hats from before the ladder, and the ipfs:// entries from the first deploy that
	-- have nothing here to read at all.
	local candidates = {}
	for _, id in ipairs(scan.ids) do
		local uri = details.uriOf[id] or ""
		if uri:match("^pblockz://") then table.insert(candidates, { id = id, uri = uri }) end
	end
	leg("describe", describe, candidates)
	local listings = {}
	for _, e in ipairs(candidates) do
		local doc = described[e.uri]
		if doc and doc.tier ~= nil then table.insert(listings, e) end
	end
	leg("pictures", dress, listings, false)
	catalogueIds = scan.ids
	return {
		status = "ok",
		registry = Contracts.Registry,
		marketplace = Contracts.Marketplace,
		donations = Contracts.Donations,
		inventory = Contracts.Inventory,
		assetstore = Contracts.AssetStore,
		listings = listings,
		ladder = leg("ladder", rungs),
	}
end

-- ---- one player's holdings -------------------------------------------------------------

--- What `address` holds in the game's contracts, described and with its models mounted. Nil when
--- a read did not answer, which keeps what was known rather than emptying anybody's bag.
local function readHoldings(address)
	if not catalogueIds then return nil end
	local items = {}
	local owned = balancesOf(catalogueIds, address)
	if not owned then return nil end
	local wantUri = {}
	for _, item in ipairs(owned) do table.insert(wantUri, item.id) end
	local details = detailsFor(wantUri)
	if not details then return nil end
	for _, item in ipairs(owned) do
		item.uri = details.uriOf[item.id] or ""
		table.insert(items, item)
	end

	-- The Inventory contract's half of what they carry. Its ids are hashes rather than registry
	-- numbers, so the host is handed the parts and composes the uri: a uri is its addressing
	-- scheme, and a second spelling of it here is a second thing to get wrong.
	local carried = readInventory(address)
	if carried then
		-- Only the documents not already read. Each is named by its own hash, so one read is the
		-- only read it will ever need; fetching all of them again every minute was three disk
		-- reads and a hash check apiece, and a reply with every one of their texts in it.
		local parts, whose = {}, {}
		for i, one in ipairs(carried) do
			local key = tostring(one.hash):lower()
			local uri = carriedUri[key]
			if not (uri and described[uri]) then
				table.insert(parts, { hash = one.hash, store = Contracts.AssetStore,
					blob = one.blob, mime = "application/json" })
				whose[#parts] = i
			end
		end
		local made = #parts > 0 and fetchMany(parts, "text") or nil
		for k, i in pairs(whose) do
			local got = made and made[k]
			if type(got) == "table" and got.uri then
				-- Already read, so describe() will not ask for it a second time.
				if got.ok and type(got.text) == "string" then
					local ok, doc = pcall(function() return HttpService:JSONDecode(got.text) end)
					if ok and type(doc) == "table" then described[got.uri] = doc end
				end
				carriedUri[tostring(carried[i].hash):lower()] = got.uri
			end
		end
		for _, one in ipairs(carried) do
			one.uri = carriedUri[tostring(one.hash):lower()]
			one.hash, one.blob = nil, nil
			table.insert(items, one)
		end
	end

	-- Models for everything they hold: what they hold is what they may wear.
	describe(items)
	-- And the name of the rung beside its number, the way a listing carries one (Ledger.data's
	-- rank). The bag and the shelf card are the same thing seen twice, and a tooltip with the
	-- colour of a rung but not its word is the shelf's sentence with the noun taken out.
	-- Nothing is named for a rung it has not got: an item with no metadata read has no tier.
	for _, item in ipairs(items) do
		if item.tier then item.tier_name = Theme.rarityName(item.tier) end
	end
	dress(items, true)
	return items
end

-- ---- publishing ------------------------------------------------------------------------

--- Checks every remembered uri against the chain, once a session.
---
--- The cache answers the first read so the town fills in fast; this is the other half of
--- that bargain. It costs the same ten seconds the cache saved, but it spends them with
--- your bag already on screen rather than with you standing in an empty square -- and if
--- setUri has moved something, the memo is corrected and the town reads again.
local checkedUris = false

local function verifyUris()
	if checkedUris then return false end
	local ids = {}
	for id in pairs(uriMemo) do table.insert(ids, id) end
	table.sort(ids)
	if #ids == 0 then return false end
	local moved = false
	local at = 1
	while at <= #ids do
		local slice, calls = {}, {}
		while at <= #ids and #slice < CALLS_PER_ROUND do
			table.insert(slice, ids[at])
			table.insert(calls, { to = Contracts.Registry, fn = "uri(uint256)",
				args = { ids[at] }, returns = { "string" } })
			at += 1
		end
		local r = readMany(calls)
		-- A round that did not answer leaves the memo alone. An unanswered call is not an
		-- asset with no uri, and treating it as one would empty a bag over a dropped packet.
		-- And it is not the end of checking: this used to mark the check done on the way
		-- out, so one dropped round meant a town that served last week's names and models
		-- until somebody restarted it -- twice, after a catalogue publish, with the restart
		-- changing nothing because the memo is written down.
		if not r then
			warn("Chain: could not check the remembered uris against the chain; trying again next round")
			return moved
		end
		for k, id in ipairs(slice) do
			local got = tostring(firstWord(r, k, ""))
			if got ~= "" and got ~= uriMemo[id] then
				uriMemo[id] = got
				uriDirty = true
				moved = true
			end
		end
	end
	checkedUris = true
	print(moved and "Chain: a remembered uri had moved; reading again" or "Chain: the remembered uris still hold")
	return moved
end

-- Only when there is news: every desk with a panel open redraws on a change.
local lastCatalogue = nil
local lastHoldings = {}   -- player -> encoded
local lastRead = {}       -- player -> when their holdings were last read

local function publishCatalogue()
	local ok, doc = pcall(readCatalogue)
	if not ok then
		warn(("Chain: the catalogue read threw -- %s"):format(tostring(doc)))
		return false
	end
	if not doc then return false end
	local encoded = HttpService:JSONEncode(doc)
	local changed = encoded ~= lastCatalogue
	if changed then
		lastCatalogue = encoded
		Ledger.setCatalogue(doc)
		print(("Chain: %d listing(s) in the catalogue"):format(#doc.listings))
		print("Chain: " .. table.concat(legs, ", "))
	end
	return true, changed
end

local function publishHoldings(player)
	local address = Ledger.addressOf(player)
	if not address or not player.Parent then return end
	local at = os.clock()
	local ok, items = pcall(readHoldings, address)
	if not ok then
		warn(("Chain: %s's holdings read threw -- %s"):format(player.Name, tostring(items)))
		return
	end
	-- Signed out, or signed in as somebody else, while this was reading: not theirs any more.
	if not items or not player.Parent or Ledger.addressOf(player) ~= address then return end
	lastRead[player] = os.clock()
	local encoded = HttpService:JSONEncode(items)
	if encoded == lastHoldings[player] and Ledger.holdings(player) then return end
	lastHoldings[player] = encoded
	Ledger.setHoldings(player, items, address)
	print(("Chain: %d item(s) for %s (%s), %.1fs"):format(#items, player.Name, Ledger.short(address), os.clock() - at))
end

-- One reader, and flags for news.
--
-- Not a handler that reads: two of those overlap, and a read that takes a minute is a minute
-- in which somebody signs in twice. The first attempt at this had the handler and the timer
-- both calling a re-entrancy guard, which turned into a loop that never yielded and got the
-- script killed on its time budget. So: one thread does the reading, and anything with news
-- puts a name on the list. A change that lands mid-read is the next thing this loop does.
local Players = game:GetService("Players")
local wanted = {}        -- player -> read their holdings next
local order = {}

local function want(player)
	if not Ledger.addressOf(player) or wanted[player] then return end
	wanted[player] = true
	table.insert(order, player)
end

local function watch(player)
	player:GetAttributeChangedSignal("WalletAddress"):Connect(function()
		lastHoldings[player] = nil
		want(player)
	end)
	want(player)
end
Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerRemoving:Connect(function(player)
	wanted[player], lastHoldings[player], lastRead[player] = nil, nil, nil
end)

-- What a player's own wallet just changed: read it again now, and once more a little later,
-- because the node that answers the read may not have the block that the write landed in yet.
Ledger.onPlayerWrote(function(player)
	want(player)
	task.delay(8, function() if player.Parent then want(player) end end)
end)

task.spawn(function()
	local sinceCatalogue = math.huge
	while true do
		if sinceCatalogue >= (catalogueIds and IDLE_SECONDS or RETRY_SECONDS) then
			local ok, changed = publishCatalogue()
			if ok then
				saveUris()
				if verifyUris() then
					local _, again = publishCatalogue()
					changed = changed or again
					saveUris()
				end
				-- Holdings are read against the registry, so a registry that grew means every
				-- player's holdings again. One that did not means only the ones gone stale:
				-- every player every minute, one after another and seconds each, was most of
				-- what this server spent its time on, for pictures that had not changed.
				for _, player in ipairs(Players:GetPlayers()) do
					if changed or (os.clock() - (lastRead[player] or 0)) >= HOLDINGS_SECONDS then want(player) end
				end
			end
			sinceCatalogue = 0
		end
		while #order > 0 and catalogueIds do
			local player = table.remove(order, 1)
			wanted[player] = nil
			publishHoldings(player)
			saveUris()
		end
		local waited = 0
		while #order == 0 and waited < 1 do
			waited += task.wait(0.25)
		end
		sinceCatalogue += waited
	end
end)

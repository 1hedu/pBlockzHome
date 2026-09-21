-- Kara, the tailor. Draw a cape and it goes on the chain as yours.
--
-- Nothing Kara sells is a token. The drawing becomes a picture, the picture becomes a
-- cape, and both go on chain as plain data; what records that you own one is a
-- mapping of address to content hash in contracts/Inventory.sol. There is no id to
-- mint, no registry, and nobody whose permission you need -- an item's identity is
-- the hash of its own bytes, so anyone can fetch them and check.
--
-- As ever, this script cannot sign anything or reach the network. It collects the
-- drawing and asks the player's own wallet, which shows them each step and pays for it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ledger = require(script.Parent.Ledger)
local Contracts = require(game:GetService("ReplicatedStorage"):WaitForChild("Contracts"))
local HttpService = game:GetService("HttpService")
local Png = require(ReplicatedStorage:WaitForChild("Png"))
local Paint = require(ReplicatedStorage:WaitForChild("Paint"))
local Cape = require(ReplicatedStorage:WaitForChild("Cape"))


local remote = Instance.new("RemoteEvent")
remote.Name = "TailorRemote"
remote.Parent = ReplicatedStorage

local MENU = {
	{ id = "paint", label = "I'd like to draw one" },
	{ id = "mine", label = "What have I made?" },
	{ id = "ask_give", label = "Give one to someone" },
	{ id = "how", label = "How does this work?" },
}

local waiting = {}      -- request number -> player
local giving = {}       -- player -> the item hash they picked

local function greeting(d)
	if not d then
		return "Evening. My line to the chain is down, so I can't publish anything just now."
	elseif Ledger.loading(d) then
		return "Evening. One moment while I read what you've got - this fills itself in."
	elseif Ledger.guest(d) then
		return "Evening. Blank capes, and a table to draw on - sign in with a wallet and what you make goes on the chain as yours."
	end
	return "Evening. Blank capes, and a table to draw on. What you make goes on the chain as data - not a token, and nobody has to approve it."
end

-- What you hold in the Inventory contract that did not come off Finch's shelf: what was drawn at a
-- table like this one, by you or by somebody who gave it to you. Taking a thing off the shelf is an
-- Inventory record too, so the shelf's own hashes are left out.
local function made(d)
	local shelf = {}
	for _, l in ipairs((d or {}).listings or {}) do
		local uri = tostring(l.uri or "")
		local hash = uri:match("^pblockz://(%x+)")
		if hash then shelf[hash:lower()] = true end
	end
	local out = {}
	for _, item in ipairs((d or {}).items or {}) do
		-- Matched on the item's uri: the hash an item was read with is cleared before it is
		-- published (Chain.server.luau, readHoldings), and the uri is what it carries here.
		local hash = tostring(item.uri or ""):match("^pblockz://(%x+)")
		if item.source == "inventory" and not (hash and shelf[hash:lower()]) then table.insert(out, item) end
	end
	return out
end

local answers = {}

-- Putting a drawing on the chain.
--
-- Four things go up and each one's hash is an argument to the next: the drawing, the model
-- that names the drawing, a picture for the shelf, and a description naming the model and
-- the picture. Then one call records that you hold it. That chain is exactly why `store` is
-- a verb of its own -- the place cannot say in advance what call it wants, because it does
-- not know the hashes until the earlier ones land.
--
-- Every step can fail and each says which one did. "It didn't work" after five signatures,
-- with no clue whether the drawing or the record was the problem, is the kind of answer
-- that makes people stop trying.
local function publish(player, indices, name, palette, words)
	local title = name:gsub("^%s+", ""):gsub("%s+$", "")
	if title == "" then title = "Hand-drawn Cape" end
	title = title:sub(1, 40)

	local function say(...)
		remote:FireClient(player, "say", { lines = { ... }, menu = MENU, thumb = "" })
	end

	local parts = Cape.parts(indices, title, palette, words)

	-- 1. the drawing itself, which the cape wears as a decal
	local emblem = Ledger.requestFor(player, {
		action = "store", bytes = Png.base64(parts.emblem), mime = "image/png",
		note = ("The drawing for \"%s\""):format(title),
	}, 120)
	if not emblem or not emblem.ok then
		say("The picture didn't store: " .. tostring(emblem and emblem.message or "no answer"))
		return
	end

	-- 2. the cape, which names the drawing
	local model = Ledger.requestFor(player, {
		action = "store",
		bytes = Png.base64(HttpService:JSONEncode(parts.model("pblockz://" .. emblem.hash:gsub("^0x", "")))),
		mime = "application/json", note = ("The cape \"%s\""):format(title),
	}, 120)
	if not model or not model.ok then
		say("The cape didn't store: " .. tostring(model and model.message or "no answer"))
		return
	end

	-- 3. a picture of it for the shelf
	local thumb = Ledger.requestFor(player, {
		action = "store", bytes = Png.base64(parts.thumb), mime = "image/png",
		note = ("The shelf picture for \"%s\""):format(title),
	}, 120)
	if not thumb or not thumb.ok then
		say("The picture of it didn't store: " .. tostring(thumb and thumb.message or "no answer"))
		return
	end

	-- 4. what it is, naming the two above. This one's hash IS the item's identity.
	local described = Ledger.requestFor(player, {
		action = "store",
		bytes = Png.base64(HttpService:JSONEncode({
			name = title, kind = "accessory", slot = "back",
			blurb = "Drawn at the tailor's, on chain.",
			license = "CC0-1.0", source = "the tailor",
			-- By hash, not by uri. A hash says which bytes; a uri also says which chain,
			-- store and blob happen to hold them this month, and writing that down here
			-- would mean rewriting every cape anyone ever drew the day it changed. The
			-- client asks the store where they are (AssetStore.blobOf) and what they are
			-- (the blob carries its own mime), so nothing is lost by leaving it out.
			model = model.hash, thumbnail = thumb.hash,
		})),
		mime = "application/json", note = ("What \"%s\" is"):format(title),
	}, 120)
	if not described or not described.ok then
		say("The description didn't store: " .. tostring(described and described.message or "no answer"))
		return
	end

	-- 5. the record. keep takes the content hash, which is the whole identity. keep, not add:
	-- add is the ladder's gate for taking things off a shelf, and a thing you drew yourself is
	-- not taken from anyone. Recording it used to need five PLS in the wallet.
	local recorded = Ledger.requestFor(player, {
		action = "write", to = Contracts.Inventory,
		fn = "keep(bytes32)", args = { described.hash },
		note = ("Record that \"%s\" is yours"):format(title),
	}, 120)
	if not recorded or not recorded.ok then
		say("It's on the chain but the record didn't take: "
			.. tostring(recorded and recorded.message or "no answer"))
		return
	end
	say(("\"%s\" is yours. Press I to put it on."):format(title))
end

function answers.paint(d, player)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if not d.can_buy then
		return { "I can't publish for you: you've no wallet signed in that can sign." }
	end
	-- The panel is drawn by the client; all this does is open it, and tell it what it is
	-- drawing with. The grid and the palette used to arrive in the wallet's payload, which
	-- meant a place could only offer painting if its client happened to carry a palette --
	-- and only ever that one. They are the place's now, in shared/Paint.luau, so both halves
	-- read the same list and a cape looks like the drawing.
	remote:FireClient(player, "paint", { w = Paint.W, h = Paint.H, palette = Paint.PALETTE })
	return {
		"There's the table. Draw whatever you like.",
		"",
		"Left mouse paints, and the colour you pick is on the left. Give it a name",
		"and press Publish when you're happy with it.",
		"",
		"Try it on as often as you like - that costs nothing and touches no chain.",
		"",
		"Publishing is five transactions: the drawing, the cape, a picture of it, its",
		"description, and the record that you have one.",
	}
end

function answers.mine(d)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if Ledger.guest(d) then return Ledger.noWallet() end
	local items = made(d)
	if #items == 0 then
		return {
			"Nothing yet. Draw one and it'll be here.",
			"",
			"What you make is recorded against your address in the inventory contract:",
			"a note that says you have one, which anybody can read. Only you can give",
			"yours away.",
		}
	end
	local lines = { ("%d thing%s drawn at a table like mine - yours, or given to you:"):format(#items, #items == 1 and "" or "s") }
	for _, item in ipairs(items) do
		table.insert(lines, ("  %s  x%s"):format(item.name or "(unnamed)", tostring(item.qty)))
		table.insert(lines, ("     %s"):format(Ledger.short(item.id)))
	end
	table.insert(lines, "")
	table.insert(lines, "That long number is the hash of the thing's own data and the rung it was")
	table.insert(lines, "claimed at. There's no registry to look it up in.")
	return lines
end

function answers.how(d)
	return {
		"Your drawing gets stored on the chain as a picture, and a cape that wears",
		"it gets stored beside it. An asset's name is the hash of those bytes, so if",
		"what comes back doesn't hash to what you asked for, your client throws it",
		"away.",
		"",
		"Owning it is a mapping of address to hash, in a contract with no owner and",
		"no admin. Not an NFT: nothing to mint, nothing to list.",
		"",
		"Anyone who knows the hash can write down that they have one too.",
	}
end

function answers.ask_give(d, player)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	local items = made(d)
	if #items == 0 then
		return { "You haven't got anything of mine to give away yet." }
	end
	local menu = {}
	for _, item in ipairs(items) do
		table.insert(menu, { id = "pick_give", arg = item.id, label = ("Give: %s"):format(item.name or Ledger.short(item.id)) })
	end
	for _, entry in ipairs(MENU) do table.insert(menu, entry) end
	return { "Which one?" }, menu
end

function answers.pick_give(d, player, hash)
	giving[player] = hash
	return {
		"Right. Who's it going to?",
		"",
		"Type their address below. Yours goes down by one and theirs goes up; the",
		"chain won't let me do it any other way.",
	}, { { id = "give", label = "Hand it over" }, table.unpack(MENU) },
	{ placeholder = "0x0000000000000000000000000000000000000000" }
end

function answers.give(d, player, _arg, typed)
	if not d or not d.can_buy then return { "You've no wallet signed in that can sign." } end
	local item = giving[player]
	if not item then return { "I've lost track of which one. Start again?" } end
	local to = type(typed) == "string" and typed:gsub("%s", "") or ""
	if #to ~= 42 or to:sub(1, 2) ~= "0x" then
		return { "That isn't an address." }, { { id = "give", label = "Try again" }, table.unpack(MENU) },
			{ placeholder = "0x...", text = to }
	end
	giving[player] = nil
	waiting[Ledger.askFor(player, {
		action = "write",
		to = Contracts.Inventory,
		fn = "give(address,bytes32,uint32)",
		args = { to, item, 1 },
		note = ("Hand it to %s. Yours goes down, theirs goes up."):format(Ledger.short(to)),
	})] = player
	return { ("Handing it to %s. Your wallet will ask you first."):format(Ledger.short(to)) }
end

-- The client sends the finished drawing here; this only forwards it.
remote.OnServerEvent:Connect(function(player, action, arg, typed, extra, words)
	if action == "publish" then
		-- `arg` is the pixels, `typed` the name, `extra` the palette as mixed at the table, `words`
		-- the line of text on it. None of it is trusted: each is checked here before anything is
		-- drawn, and what is drawn is drawn here -- the table's own picture is never used.
		if type(arg) ~= "string" then return end
		local ok, why = Paint.check(arg)
		local palette = nil
		if ok then
			palette, why = Paint.parsePalette(extra)
			ok = palette ~= nil
		end
		local cleanWords = nil
		if ok and words ~= nil then
			cleanWords, why = Paint.checkText(words)
			if why then ok = false end
		end
		if not ok then
			remote:FireClient(player, "say", { lines = { why }, menu = MENU, thumb = "" })
			return
		end
		remote:FireClient(player, "say", {
			lines = { "Off it goes. Five transactions - I'll shout when it's done." },
			menu = MENU, thumb = "",
		})
		task.spawn(publish, player, arg, tostring(typed or ""), palette, cleanWords)
		return
	end
	if type(action) ~= "string" then return end
	local fn = answers[action]
	if not fn then return end
	local d = Ledger.data(player)
	local ok, lines, menu, input = pcall(fn, d, player, arg, typed)
	if not ok then
		warn("tailor: " .. tostring(lines))
		lines = { "Something went wrong on my side. Sorry." }
		menu, input = nil, nil
	end
	remote:FireClient(player, "say", { lines = lines, menu = menu or MENU, thumb = "", input = input })
end)

-- Trying one on does not come through here at all. The drawing table holds the drawing and
-- the cape's shape is in Cape.luau, so the draft is built where it is looked at -- see
-- Cape.preview. It used to ask the host to render one; the host stopped being able to when
-- the tailor moved into the town, and the button went quiet.

Ledger.onResult(function(n, res)
	local player = waiting[n]
	waiting[n] = nil
	if not player or not player.Parent then return end
	remote:FireClient(player, "say", { lines = { tostring(res.message or "Done.") }, menu = MENU, thumb = "" })
end)


Ledger.onTalk("Tailor", function(player)
	remote:FireClient(player, "open", { title = "Kara  <Tailor>", npc = "Tailor", greeting = greeting(Ledger.data(player)), menu = MENU })
end)

Ledger.onReady(function(player, d)
	remote:FireClient(player, "update", { greeting = greeting(d), menu = MENU })
end)

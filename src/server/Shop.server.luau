-- Finch, who runs the stall on the west side of the square. Everything on the shelf is
-- registered on chain by whoever made it; Finch sets no prices and takes no cut.
--
-- Nothing is bought. What gates the shelf is what you HOLD -- the rung of the ladder in
-- contracts/Inventory.sol, checked by the chain against msg.sender.balance -- so taking a
-- thing costs you nothing but the gas to record it, and spending your holdings tomorrow
-- drops you back down a rung. That is the whole point of measuring holdings instead of
-- spend, and it is why there is no till here.
--
-- The prices are still published and the marketplace still works. This counter does not use
-- either.
--
-- This script cannot sign a transaction and has no key to sign one with. Taking something asks
-- the player's OWN wallet (Ledger.askFor): their machine shows them what is about to be signed,
-- they confirm it or don't, and they pay the gas. A script asking to spend your money is just a
-- request until your wallet agrees.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Ledger = require(script.Parent.Ledger)
local Contracts = require(game:GetService("ReplicatedStorage"):WaitForChild("Contracts"))
local Handouts = require(script.Parent.Handouts)

local remote = Instance.new("RemoteEvent")
remote.Name = "ShopRemote"
remote.Parent = ReplicatedStorage

local MENU = {
	{ id = "shop", label = "What have you got?" },
	{ id = "how", label = "How does taking things work?" },
}

-- What is on the shelf, deduped, and nothing whose metadata never resolved: without a name
-- there is nothing to put on a card.
local function shelfOf(d)
	local items = {}
	local seen = {}
	for _, l in ipairs((d and d.listings) or {}) do
		local named = l.name ~= nil and l.name ~= ""
		if named and not seen[l.id] then
			seen[l.id] = true
			table.insert(items, {
				id = l.id, name = Ledger.nameOf(l, l.id),
				thumb = l.thumb or "", owned = l.owned == true, locked = l.locked == true,
				tier_name = l.tier_name, tier = l.tier or 0, tier_pls = l.tier_pls,
				slot = l.slot or "",
				can_buy = d.can_buy == true,
			})
		end
	end
	-- Rarity first, commonest at the top, then by name within a rung -- so the colours of one
	-- thing sit together, and the order is the same every visit.
	table.sort(items, function(a, b)
		if a.tier ~= b.tier then return a.tier < b.tier end
		local an, bn = tostring(a.name):lower(), tostring(b.name):lower()
		if an ~= bn then return an < bn end
		return tostring(a.id) < tostring(b.id)
	end)
	return items
end

local function greeting(d)
	if not d then
		return "Afternoon. My ledger line's down, so I can't read the shelf just now - try me in a minute."
	elseif Ledger.loading(d) then
		return "Afternoon. Give me a second to read the shelf - this window fills itself in."
	end
	if Ledger.guest(d) then
		return "Afternoon. Have a look by all means - you'll need a wallet signed in to take anything."
	end
	local n = #shelfOf(d)
	return ("Afternoon. %d thing%s on the shelf, all of it registered on %s by whoever made it.")
		:format(n, n == 1 and "" or "s", d.network or "chain")
end

local answers = {}

-- The shelf goes to the grid panel, not into the dialog as text. Everything here has
-- a picture published beside it and a list of names throws that away.
function answers.shop(d, player)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	local items = shelfOf(d)
	if #items == 0 then
		return { "Shelf's empty right now." }
	end
	remote:FireClient(player, "shelf", {
		items = items, holder = d.holder or {}, gas = d.gas or "",
	})
	local holder = d.holder or {}
	return {
		("%d things on the shelf - have a look."):format(#items),
		"",
		"Registered on chain by whoever made it, pictures and all.",
		"",
		(holder.name ~= nil and holder.name ~= "")
			and ("You're standing on %s. Anything at that rung or under is yours for the taking -"):format(holder.name)
			or ("You're not on the ladder yet. Hold %s PLS and %s opens up -"):format(
				holder.needed ~= nil and holder.needed ~= "" and holder.needed or "5",
				holder.next ~= nil and holder.next ~= "" and holder.next or "the bottom rung"),
		"nothing to pay but the gas.",
	}
end

function answers.how(d)
	local holder = (d and d.holder) or {}
	return {
		"Nothing here costs anything. Every thing sits on a rung of the ladder, and",
		"if you're holding enough to stand on that rung, you can have it.",
		"",
		"Holding, not spending: nothing is taken off you and nothing is locked.",
		"Spend it tomorrow and you drop a rung, and what's above goes out of reach.",
		"",
		(holder.next ~= nil and holder.next ~= "")
			and ("Next rung up is %s, at %s PLS."):format(holder.next, holder.needed or "?")
			or ((holder.name ~= nil and holder.name ~= "") and "You're at the top of the ladder."
				or "I can't read the ladder just now."),
		"",
		"Your wallet shows you what you're about to take. You pay the gas, and",
		"the chain checks your balance itself, right then.",
	}
end


local waiting = {}      -- request number -> player

function answers.buy(d, player, id)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if type(id) ~= "number" then
		return { "I didn't catch which one you wanted." }
	end

	-- The candles come off Finch's own counter rather than the chain. They are spent the moment
	-- they land, and a signature for a fact that is true for four seconds is a fight lost --
	-- so the holding is one bit on the server. One at a time, which is the whole rule: use it
	-- and walk back.
	local name = nil
	for _, l in ipairs(d.listings or {}) do
		if l.id == id then name = Ledger.nameOf(l, l.id) break end
	end
	if name and Handouts.serves(name) then
		if Handouts.give(player, name) then
			-- The wardrobe reads Handouts on every sync, so it is enough to poke it.
			ReplicatedStorage:WaitForChild("WardrobeRemote"):FireClient(player, "note",
				("%s - on the house."):format(name))
			return {
				("There you go - one %s."):format(name),
				"",
				"Nothing signed and nothing to pay. Use it and come back; I'll have another.",
			}
		end
		return {
			("You've already got a %s."):format(name),
			"",
			"One at a time. Spend that one and I'll hand you the next.",
		}
	end

	-- `can_buy` is "there is a key loaded", which is what signing anything needs -- taking a
	-- free thing still writes a record and still costs gas. A candle signs nothing, so it is past
	-- this only for everything else.
	if not d.can_buy then
		return { "I can't record it for you: you've no wallet signed in that can sign." }
	end

	-- An item IS the hash of its own metadata, and that hash is already sitting in the
	-- pblockz:// uri on the listing -- so there is nothing to look up and nothing to trust.
	-- Pulling it out is a substring; the wallet does the hashing that makes the call.
	local listing = nil
	for _, l in ipairs(d.listings or {}) do
		if l.id == id then listing = l break end
	end
	-- Either spelling of the scheme: the name changed, and every uri written before it did is
	-- still on chain saying the old one.
	local uri = tostring(listing and listing.uri or "")
	local hash = uri:match("^pblockz://(%x+)")
	if not hash then
		return { "I can't tell what that one is made of. Try another." }
	end
	waiting[Ledger.askFor(player, {
		action = "write",
		to = Contracts.Inventory,
		fn = "add(bytes32,uint8)",
		args = { "0x" .. hash, listing.tier or 0 },
		note = ("Take %s off the shelf"):format(name or ("#" .. tostring(id))),
	})] = player
	return {
		("Right you are - %s."):format(name or ("#" .. tostring(id))),
		"",
		"Your wallet will show you the transaction. I'll speak up when it lands.",
	}
end

-- What their wallet made of it.
Ledger.onResult(function(n, res)
	local player = waiting[n]
	waiting[n] = nil
	if not player or not player.Parent then return end
	local lines = { tostring(res.message or "Done.") }
	if res.ok then
		table.insert(lines, "")
		table.insert(lines, "Press I to put it on.")
	end
	remote:FireClient(player, "say", { lines = lines, menu = MENU, thumb = "" })
end)

-- ---- the stall -------------------------------------------------------------------
Ledger.onTalk("Shopkeeper", function(player)
	remote:FireClient(player, "open", { title = "Finch  <Shop>", npc = "Shopkeeper", greeting = greeting(Ledger.data(player)), menu = MENU })
end)

remote.OnServerEvent:Connect(function(player, action, arg)
	if type(action) ~= "string" then return end
	local fn = answers[action]
	if not fn then return end
	local d = Ledger.data(player)
	local ok, lines, menu = pcall(fn, d, player, arg)
	if not ok then
		warn("shop: " .. tostring(lines))
		lines = { "Something went wrong on my side. Sorry." }
		menu = nil
	end
	local thumb = ""
	if action == "buy" and d and d.listings then
		for _, l in ipairs(d.listings) do
			if l.id == arg and l.thumb and l.thumb ~= "" then thumb = l.thumb break end
		end
	end
	remote:FireClient(player, "say", { lines = lines, menu = menu or MENU, thumb = thumb })
end)

Ledger.onReady(function(player, d)
	remote:FireClient(player, "update", { greeting = greeting(d), menu = MENU })
end)

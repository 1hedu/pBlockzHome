-- Engrams: links you can hold.
--
-- ---- what one is -------------------------------------------------------------------------
-- At the end of the day it is a link. A view and an id -- "block 24913201", "the account
-- 0xdAC1..." -- and the badge is how you store one, carry it to somebody and show them.
-- They can equip it, show it, throw it away. The link is always the Engram.
--
-- ---- why none of this is on chain --------------------------------------------------------
-- It used to be three transactions: store the badge, store a note describing it, record in
-- the Inventory contract that you hold it. Two documents and a signature, for a string.
--
-- Worse than wasteful -- wrong. Minting it writes "this account opened this page in this
-- block" into a permanent public record. That is chat traffic. Nobody wants where they
-- looked and what they showed a friend kept forever, and there is no version of that anyone
-- asked for. Showing somebody a page is a thing you say, and things you say in this town are
-- the server's: combat, positions, who is on fire, who is carrying a candle.
--
-- So an Engram lives as long as you are here, and goes when you go. Same rule as the
-- candles (Handouts.luau), same reason: the one thing that could not sensibly be on chain is
-- the only thing that moved off it.
--
-- The BADGE is still a model the town makes -- see Engram.luau, and Made.server.luau, which
-- builds it once and puts it where the wardrobe looks. What is here is the holding.
local Players = game:GetService("Players")

local Engrams = {}

-- How many you can carry at once. Not a rule about scarcity: each one is a wardrobe entry
-- and a tile in your bag, and a hundred identical badges is a bag nobody can read. Taking
-- another when you are full swaps out the oldest, which is what a pocket does.
local CARRY = 12

local held = {}      -- player -> list of engrams, oldest first
local nextId = 0

--- The badge every Engram wears. One template, and the wardrobe is keyed by model name, so
--- each engram gets its own name off the same template -- see `source` in Wardrobe.
Engrams.MODEL = "Engram"

--- Is this a model name that belongs to an Engram rather than to the chain.
function Engrams.isBadge(modelName)
	local name = tostring(modelName)
	return name == Engrams.MODEL or name:sub(1, #Engrams.MODEL + 1) == Engrams.MODEL .. "#"
end

--- What this player is carrying, in the shape the wardrobe wants -- the same shape an item
--- off the chain arrives in, so nothing downstream has to know the difference.
function Engrams.owned(player)
	local out = {}
	for _, one in ipairs(held[player] or {}) do
		table.insert(out, {
			id = one.id,
			qty = 1,
			model = one.model,
			name = one.name,
			thumb = "",
			slot = "offhand",
			kind = "accessory",
			tier = 0,
			tier_name = "",
			engram = true,
			-- The link, carried on the item itself. Showing one goes and reads the page
			-- again rather than repeating anything remembered here: an Engram holds the
			-- address of a claim, never the claim.
			view = one.view,
			page = one.page,
			blurb = one.blurb,
		})
	end
	return out
end

--- One of them, by the id the client named or by the model it is wearing.
function Engrams.find(player, key)
	local want = tostring(key)
	for _, one in ipairs(held[player] or {}) do
		if one.id == want or one.model == want then return one end
	end
	return nil
end

--- What to call an Engram of a page, and what it says it remembers.
---
--- Only the views that name ONE thing. "The latest transactions" is a different list every
--- ten seconds, so an Engram of it would go on claiming to be a page that has since changed
--- out from under it -- the one thing an Engram must never do.
local NAMED = {
	transaction = function(id) return ("Engram %s"):format(id:sub(1, 10)), ("Transaction %s."):format(id:sub(1, 12)) end,
	tx = function(id) return ("Engram %s"):format(id:sub(1, 10)), ("Transaction %s."):format(id:sub(1, 12)) end,
	block = function(id) return ("Engram block %s"):format(id), ("Block %s."):format(id) end,
	address = function(id) return ("Engram %s"):format(id:sub(1, 8)), ("The account %s."):format(id) end,
	token = function(id) return ("Engram %s"):format(id:sub(1, 8)), ("The token at %s."):format(id) end,
}

--- The name and the one-line description for a page, or nil if it is not one thing.
function Engrams.describe(view, page)
	local name = NAMED[tostring(view)]
	if not name then return nil, nil end
	return name(tostring(page or ""))
end

--- Cuts one. Returns the engram, or nil and a line saying why not.
---
--- Taking the same page twice gives you back the one you already have. Two identical badges
--- is not a thing anybody wanted and it is the obvious result of pressing a button twice.
function Engrams.take(player, view, page, name, blurb)
	if type(view) ~= "string" or view == "" or not NAMED[view] then
		return nil, "There's nothing on that page worth cutting -- it'd be different by morning."
	end
	page = tostring(page or "")
	if page == "" then return nil, "That page doesn't name anything." end
	for _, one in ipairs(held[player] or {}) do
		if one.view == view and one.page == page then
			return one, ("You're already carrying that one -- \"%s\"."):format(one.name)
		end
	end
	held[player] = held[player] or {}
	nextId += 1
	local one = {
		id = "engram:" .. tostring(nextId),
		model = ("%s#%d"):format(Engrams.MODEL, nextId),
		name = tostring(name or "Engram"),
		blurb = tostring(blurb or ""),
		view = view,
		page = page,
	}
	table.insert(held[player], one)
	-- Full: the oldest goes, which is the only rule a pocket has ever had.
	while #held[player] > CARRY do
		table.remove(held[player], 1)
	end
	return one, nil
end

--- Throws one away. Nothing is undone by this and nothing was spent on it.
function Engrams.drop(player, key)
	local want = tostring(key)
	for i, one in ipairs(held[player] or {}) do
		if one.id == want or one.model == want then
			table.remove(held[player], i)
			return one
		end
	end
	return nil
end

--- Hands one to somebody standing next to you. They get their own; yours stays.
---
--- A link is not a thing there can only be one of, and pretending otherwise would mean
--- losing yours to show it to two people.
function Engrams.give(player, key, target)
	local one = Engrams.find(player, key)
	if not one then return nil end
	return (Engrams.take(target, one.view, one.page, one.name, one.blurb))
end

Players.PlayerRemoving:Connect(function(player)
	held[player] = nil
end)

return Engrams

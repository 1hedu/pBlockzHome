-- What is on your action bar, square by square.
--
-- Ten squares, each holding the name of a thing you own or nothing at all. Not an order over
-- your inventory: a layout, with gaps, which is what a bar is. You put things on it and you
-- take them off.
--
-- ---- where it is kept --------------------------------------------------------------------
-- DataStoreService, which is where a Roblox game keeps exactly this, and it survives leaving.
-- Not the chain, for the candle's reason: which square you keep your torch in is not a fact
-- anybody else has to agree with, and paying a signature to move a hat one square along would
-- be absurd. What you own is on chain. Where you put it is yours.
--
-- ---- and what a bar looks like before you have touched it ---------------------------------
-- Full. An untouched bar is your first ten things in the order the chain handed them over,
-- because a bar you have to set up before it is any use is a worse bar than one that already
-- works -- and somebody who never drags anything never has to know this exists. The moment
-- you DO arrange it, that is the layout, gaps and all, and nothing fills it in behind you.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Bar = {}

Bar.SLOTS = 10

local STORE = "bar"
local KEY = "layout"

local layout = {}       -- player -> { [1..SLOTS] = model name }, or nil for untouched
local store = nil

local function open()
	if store then return store end
	-- pcall, because a DataStore is allowed to be unavailable and a town that will not start
	-- without one is a town that will not start.
	local ok, got = pcall(function() return DataStoreService:GetDataStore(STORE) end)
	store = ok and got or nil
	return store
end

--- Which key a player's layout lives under: their address, because a player is their wallet.
--- Two people can arrive with the same name (the stock client's is a constant), and a bar keyed
--- by name was one of them finding the other's squares. A guest has no address and nothing
--- kept: their layout lasts the visit.
local function keyFor(player)
	local address = player:GetAttribute("WalletAddress")
	if type(address) ~= "string" or address == "" then return nil end
	return ("%s/%s"):format(KEY, address:lower())
end

--- Stored as a list of ten, with "" for an empty square, because a table with holes in it
--- does not survive a round trip through JSON as the same shape.
local function packed(slots)
	local out = {}
	for i = 1, Bar.SLOTS do out[i] = slots[i] or "" end
	return out
end

local function unpacked(list)
	local out = {}
	for i = 1, Bar.SLOTS do
		local name = list[i]
		if type(name) == "string" and name ~= "" then out[i] = name end
	end
	return out
end

local function load(player)
	local s = open()
	local key = keyFor(player)
	if not s or not key then return end
	local ok, got = pcall(function() return s:GetAsync(key) end)
	if ok and type(got) == "table" then
		layout[player] = unpacked(got)
	end
end

--- The layout this player arranged, or nil if they never have.
function Bar.of(player)
	return layout[player]
end

--- Puts a list of ten names in the squares, keeping only strings and only one of each.
---
--- Trusting nothing: the client sends this, so a name repeated, a name that is not a string
--- or a list longer than the bar is cleaned up rather than believed. What it cannot do is
--- claim you own something -- the bar draws each square from what the chain says you have, so
--- a made-up name is a square that draws as empty.
function Bar.set(player, list)
	if type(list) ~= "table" then return false end
	local seen, slots = {}, {}
	for i = 1, Bar.SLOTS do
		local name = list[i]
		if type(name) == "string" and name ~= "" and not seen[name] then
			seen[name] = true
			slots[i] = name
		end
	end
	layout[player] = slots
	local s = open()
	local key = keyFor(player)
	if s and key then
		pcall(function() s:SetAsync(key, packed(slots)) end)
	end
	return true
end

--- Forgets a layout entirely, so the bar goes back to being untouched.
---
--- Different from arranging ten empty squares, which is a layout and is kept: somebody who
--- clears their bar on purpose should find it clear next time. This is for putting things
--- back -- a test that drags things off the bar is writing to the DataStore of whoever is
--- signed in, and without this it leaves them with an empty bar in the real game. Which is
--- exactly what happened.
function Bar.forget(player)
	layout[player] = nil
	local s = open()
	local key = keyFor(player)
	if s and key then
		pcall(function() s:RemoveAsync(key) end)
	end
end

--- What the bar should show: the layout if there is one, otherwise the first ten things.
---
--- Names only. The panel already has the whole inventory and can look up an icon, what rung
--- it is, and whether it is on you -- so this says where things go and nothing else.
function Bar.showing(player, items)
	local slots = layout[player]
	if slots then return packed(slots) end
	local out = {}
	for i = 1, Bar.SLOTS do
		out[i] = items[i] and items[i].model or ""
	end
	return out
end

-- Their address lands after they arrive (the door asks their wallet to sign), so the layout
-- is read when it does, and again should they sign in as somebody else.
local function watch(player)
	player:GetAttributeChangedSignal("WalletAddress"):Connect(function()
		layout[player] = nil
		load(player)
	end)
	load(player)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(player) layout[player] = nil end)

-- Whoever is already here when this loads, which is everybody on a listen server: PlayerAdded
-- has been and gone by the time a script in ServerScriptService runs.
task.spawn(function()
	for _, player in ipairs(Players:GetPlayers()) do watch(player) end
end)

return Bar

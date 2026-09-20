-- Space fishing: who has a rod, and which fish they can hold.
--
-- ---- the rod -----------------------------------------------------------------------------
-- Funmaster Mike hands it over. Not a thing you buy and not a thing on chain: there is nothing to
-- own about it that anybody else has to agree with, the same as where your bar squares are. So
-- the town writes down that he gave you one, in a DataStore against the address you signed in
-- with, and it is still yours next time. A guest has no address to write it under, and nothing to
-- cast with either -- a cast is a transaction from your own wallet.
--
-- ---- the fish ----------------------------------------------------------------------------
-- The Fishing contract's to say (contracts/Fishing.sol). Every catch is counted against the
-- angler on chain, and the town reads those counts for your address the way it reads anything
-- else it has to judge by: a fish you hold is a fish the contract says you caught. The models are
-- the town's own (shared/Fish.luau, built into ReplicatedStorage.Made).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ledger = require(script.Parent.Ledger)
local Contracts = require(ReplicatedStorage:WaitForChild("Contracts"))
local Fish = require(ReplicatedStorage:WaitForChild("Fish"))

local Angling = {}

local STORE = "Fishing"

local rods = {}       -- player -> true once the rod is known to be theirs
local catches = {}    -- player -> { [species] = count }, off the chain
local store = nil

local function open()
	if store then return store end
	local ok, got = pcall(function() return DataStoreService:GetDataStore(STORE) end)
	store = ok and got or nil
	return store
end

--- Which key a rod lives under. Lowercased, because an address is one address however it is
--- capitalised, and under fifty characters, which is as long as a DataStore key may be.
local function rodKey(address)
	return "rod/" .. address:lower()
end

--- Whether Funmaster Mike has given this player a rod.
function Angling.hasRod(player)
	return rods[player] == true
end

--- Gives this player a rod. True if they now have one; false and a reason if they cannot.
function Angling.giveRod(player)
	local address = Ledger.addressOf(player)
	if not address then return false, "guest" end
	if rods[player] then return true end
	rods[player] = true
	local s = open()
	if s then
		pcall(function() s:SetAsync(rodKey(address), true) end)
	end
	Ledger.changed(player)
	return true
end

local function loadRod(player)
	local address = Ledger.addressOf(player)
	if not address then
		rods[player] = nil
		return
	end
	local s = open()
	if not s then return end
	local ok, got = pcall(function() return s:GetAsync(rodKey(address)) end)
	-- Still the same address: a sign-in that changed while the store answered is somebody else.
	if ok and got == true and Ledger.addressOf(player) == address and player.Parent then
		rods[player] = true
		Ledger.changed(player)
	end
end

--- Reads this player's catches off the Fishing contract. Nothing to read before it is deployed.
function Angling.readCatches(player)
	local address = Ledger.addressOf(player)
	if not address or Contracts.Fishing == nil or Contracts.Fishing == "" then return end
	local returns = {}
	for i = 1, 10 do returns[i] = "uint32" end
	local answer = Ledger.request({
		action = "read",
		to = Contracts.Fishing,
		fn = "caughtOf(address)",
		args = { address },
		returns = returns,
	})
	if not answer or not answer.ok or type(answer.words) ~= "table" then return end
	-- "0x": nothing at that address on the node being asked -- no contract there, which is not the
	-- same as a contract saying they have caught nothing.
	if type(answer.data) ~= "string" or #answer.data < 2 + 64 * 10 then return end
	if Ledger.addressOf(player) ~= address or not player.Parent then return end
	local counts = {}
	for species = 0, Fish.EVERLIVING do
		counts[species] = tonumber(answer.words[species + 1]) or 0
	end
	catches[player] = counts
	Ledger.changed(player)
end

--- How many of a species this player has caught, as the town last read it.
function Angling.caught(player, species)
	local counts = catches[player]
	return counts and counts[species] or 0
end

--- Stands in for the chain's answer. For tests, and nothing else.
function Angling._setCatches(player, counts)
	catches[player] = counts
	Ledger.changed(player)
end

--- The Everliving Fish's picture, once the place's assets have it; "" draws the name instead.
local function everlivingThumb()
	local assets = ReplicatedStorage:FindFirstChild("PlaceAssets")
	local v = assets and assets:FindFirstChild("EverlivingFishThumb")
	return v and v.Value or ""
end

--- What this player is carrying from fishing, in the shape the wardrobe wants.
function Angling.owned(player)
	local out = {}
	if rods[player] then
		table.insert(out, { id = "fishing:rod", qty = 1, model = Fish.ROD, name = Fish.ROD, thumb = "",
			slot = "mainhand", kind = "accessory", tier = 0, tier_name = "" })
	end
	local counts = catches[player]
	if counts then
		for species = 0, Fish.EVERLIVING do
			local n = counts[species] or 0
			if n > 0 then
				local name = Fish.nameOf(species)
				table.insert(out, { id = "fishing:" .. species, qty = n, model = name, name = name,
					thumb = species == Fish.EVERLIVING and everlivingThumb() or "",
					slot = "offhand", kind = "accessory", tier = 0, tier_name = "",
					blurb = species == Fish.EVERLIVING and "ROMANS VI:IV" or "" })
			end
		end
	end
	return out
end

local function watch(player)
	player:GetAttributeChangedSignal("WalletAddress"):Connect(function()
		rods[player], catches[player] = nil, nil
		task.spawn(loadRod, player)
		task.spawn(Angling.readCatches, player)
	end)
	if Ledger.addressOf(player) then
		task.spawn(loadRod, player)
		task.spawn(Angling.readCatches, player)
	end
end

Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(watch, player) end
Players.PlayerRemoving:Connect(function(player)
	rods[player], catches[player] = nil, nil
end)

return Angling

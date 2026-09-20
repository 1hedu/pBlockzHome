-- Things the server hands out, one at a time.
--
-- The candles. Everything else in the town you own on chain: Inventory records that you hold
-- a thing, and holding it is a fact about you that survives the server, the session and this
-- whole project. A candle is not like that. It is spent the moment it lands, and recording
-- that on chain means a signature in the middle of a fight -- which is a fight lost, however
-- it is arranged -- for a fact that is true for about four seconds.
--
-- So a candle is one bit: have you got one. Finch gives you one if you have not, using it takes
-- it away, and you walk back across the square for another. Nothing is signed, nothing is
-- burned, and the only thing that had to move off chain is the one thing that could not
-- sensibly be on it.
--
-- The MODEL is still on chain, like every other asset -- the mesh, the thumbnail, the
-- metadata, all of it addressed by content hash. What is here is the holding, not the thing.
--
-- Session-lived on purpose. Leave and you have no candle, which is the same rule everyone
-- else is playing by and is one walk across the square to fix.
local Players = game:GetService("Players")

local Handouts = {}

-- What the server serves rather than the chain. By the name the item publishes itself under,
-- because that is what the wardrobe, the shop and the weapon all know it by.
Handouts.SERVED = {
	["Red Candle"] = true,
	["Green Candle"] = true,
}

local held = {}      -- player -> { [name] = true }

function Handouts.serves(name)
	return Handouts.SERVED[tostring(name)] == true
end

function Handouts.has(player, name)
	local mine = held[player]
	return mine ~= nil and mine[tostring(name)] == true
end

--- Hands one over. False if they already have one, which is the whole rule.
function Handouts.give(player, name)
	if not Handouts.serves(name) then return false end
	if Handouts.has(player, name) then return false end
	held[player] = held[player] or {}
	held[player][tostring(name)] = true
	return true
end

--- Takes it back, because it has been used.
function Handouts.take(player, name)
	local mine = held[player]
	if not mine then return false end
	local had = mine[tostring(name)] == true
	mine[tostring(name)] = nil
	return had
end

--- Everything this player is carrying, as the wardrobe wants to see it: the same shape an
--- item off the chain arrives in, so nothing downstream has to know the difference.
function Handouts.owned(player)
	local out = {}
	for name in pairs(held[player] or {}) do
		table.insert(out, {
			id = "served:" .. name,
			qty = 1,
			model = name,
			name = name,
			thumb = "",
			slot = "mainhand",
			kind = "accessory",
			tier = 0,
			tier_name = "",
			served = true,
		})
	end
	return out
end

Players.PlayerRemoving:Connect(function(player)
	held[player] = nil
end)

return Handouts

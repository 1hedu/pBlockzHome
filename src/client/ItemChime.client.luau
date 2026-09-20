-- The chime when something comes into your bag: a fish on the line, a rod from Funmaster Mike, a
-- candle from Finch, a hat you bought. Higher for the Everliving Fish.
--
-- Heard off the bag itself rather than off each thing that can put something in it. The wardrobe
-- sends this machine the whole list whenever it changes (Wardrobe.server.luau); anything on it that
-- was not there last time, or there are more of, came in. One way in covers every way in, including
-- ones nobody has written yet.
--
-- Not while the list is still arriving. Signing in fills the bag from the chain all at once, and none
-- of that is receiving anything: so the first few seconds after arriving or signing in are only
-- looked at, and so is the moment the chain's half of the list lands.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Chime = require(ReplicatedStorage:WaitForChild("Chime"))
local Fish = require(ReplicatedStorage:WaitForChild("Fish"))

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("WardrobeRemote")

--- How long after arriving or signing in before it counts.
local SETTLE = 8
--- How much higher the Everliving Fish's chime is.
local EVERLIVING_UP = 12

local had = nil            -- model -> qty, as last seen
local settledFrom = os.clock() + SETTLE
local wasLoading = nil

player:GetAttributeChangedSignal("WalletAddress"):Connect(function()
	had = nil
	settledFrom = os.clock() + SETTLE
end)

remote.OnClientEvent:Connect(function(kind, items, _standing, _slots, loading)
	if kind ~= "items" or type(items) ~= "table" then return end
	local now = {}
	for _, item in ipairs(items) do
		if type(item.model) == "string" then now[item.model] = (now[item.model] or 0) + (tonumber(item.qty) or 1) end
	end
	-- The chain's half landing is the list catching up, not anything arriving.
	local landed = wasLoading == true and loading ~= true
	wasLoading = loading == true
	local counting = had ~= nil and os.clock() >= settledFrom and not landed
	local came, everliving = false, false
	if counting then
		for model, qty in pairs(now) do
			if qty > (had[model] or 0) then
				came = true
				if model == Fish.EVERLIVING_NAME then everliving = true end
			end
		end
	end
	had = now
	if came then
		Chime.play(everliving and EVERLIVING_UP or 0)
		print(("itemchime: %s"):format(everliving and "everliving" or "item"))
	end
end)

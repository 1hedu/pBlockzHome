-- Lighting a torch somebody is carrying.
--
-- The item itself is published with an unlit emitter and a `Flame` attribute saying which
-- fire it burns, for the same two reasons a brazier in the map is: a particle's Texture is a
-- published asset that no pblockz:// URI in a model resolves on its own, and a fire of several
-- colours is several emitters, which one authored model cannot be. Flames.luau settles both,
-- and this only has to notice that a torch has appeared.
--
-- Every torch, not just the local player's. An accessory worn by anyone is an instance in
-- everyone's world, so watching Workspace for one catches the torch in a stranger's hand as
-- readily as the one in yours -- and a fight where only your own weapon is alight would look
-- broken from both sides.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flames = require(ReplicatedStorage:WaitForChild("Flames"))

local lit = {}     -- accessories already seen, so a re-parent does not light one twice

local sprite = nil

local function light(thing)
	if not thing:IsA("Accoutrement") or lit[thing] then return end
	if thing:GetAttribute("Flame") == nil then return end
	lit[thing] = true
	Flames.lightModel(thing, sprite)
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("PlaceAssets", 180)
	local v = folder and folder:WaitForChild("FlameSprite", 180)
	sprite = v and v.Value ~= "" and v.Value or nil

	-- What is already worn, then everything that turns up afterwards. Both, because a torch
	-- can be equipped long before the place assets arrive or long after.
	for _, d in ipairs(workspace:GetDescendants()) do
		light(d)
	end
	workspace.DescendantAdded:Connect(light)
end)

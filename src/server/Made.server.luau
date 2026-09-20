-- Models the town makes for itself.
--
-- Everything you can wear here comes out of ReplicatedStorage.OnChain: the host fetches it,
-- verifies the bytes against the hash that names them, and mounts it. That is right for
-- everything somebody owns -- the hat, the cape, Louis, the spoon.
--
-- The Engram badge is not one of those. It is not owned, it is not bought and it is not
-- minted; it is the shape a link takes so you can hold one. There is nothing for the chain
-- to say about it, so it is built here, once, out of the same description the host would
-- have mounted -- and put where the wardrobe already looks.
--
-- One template. Every Engram wears it under its own name (see Engrams.luau), and the
-- wardrobe's `source` falls back past the "#" to find it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engram = require(ReplicatedStorage:WaitForChild("Engram"))
local Engrams = require(script.Parent.Engrams)

local made = ReplicatedStorage:FindFirstChild("Made")
if not made then
	made = Instance.new("Folder")
	made.Name = "Made"
	made.Parent = ReplicatedStorage
end

-- The fish and the rod: who has caught what is the Fishing contract's to say, and a fish is
-- primitives, so there is nothing about the models themselves to publish. See shared/Fish.luau.
-- First, because they wait on nothing.
local Fish = require(ReplicatedStorage:WaitForChild("Fish"))
for _, model in ipairs(Fish.buildAll()) do
	model.Parent = made
end

-- The badge wears the PulseBlockz gradient once the place's pictures are in, which is moments after
-- the town starts. Waited for, briefly; a place without them gets the plain glass badge.
local assets = ReplicatedStorage:WaitForChild("PlaceAssets", 30)
if assets then
	assets:WaitForChild("EngramBadge", 15)
	assets:WaitForChild("PulseGradient", 15)
end
local badge = Engram.build(Engrams.MODEL, Engram.look())
badge.Name = Engrams.MODEL
badge.Parent = made

print(("made: %s, %d part(s)"):format(badge.Name, (function()
	local n = 0
	for _, d in ipairs(badge:GetDescendants()) do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end)()))

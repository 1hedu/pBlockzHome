-- The braziers around the square: where they stand, and getting them lit.
--
-- The brazier itself is map geometry and needs nothing from anywhere. Two things cannot live
-- in the map with it. A particle's Texture is a published asset, and a pblockz:// URI written
-- into a .model.json is never resolved -- so the sprite is handed over here once the place
-- assets land, the same way the rocket and the tree are given their meshes.
--
-- And the colours, which are Flames' business rather than this file's: a brazier says which
-- fire it burns with a `Flame` attribute and nothing else. That is why a second brazier in
-- another colour is one word in the map and no new art at all -- the sprite is drawn white
-- and a ParticleEmitter's Color multiplies through it, so one picture serves every palette
-- there is and any you add.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flames = require(ReplicatedStorage:WaitForChild("Flames"))
local Ranks = require(ReplicatedStorage:WaitForChild("Ranks"))

-- How much taller the busiest token's fire stands than the quietest one's, in studs.
--
-- Five ranks, evenly spaced, so the bottom one is exactly the flame every brazier used to
-- have and the top one is fourteen studs above it. Even spacing is the whole point: two
-- tokens a few per cent apart must not look the same, and one an order of magnitude ahead
-- must not go off the top of the screen.
--
-- Fourteen and not five. Five studs on a flame that already reaches eight is a sixty per cent
-- stretch, which is plain when two braziers are side by side and invisible from across the
-- square -- and across the square is where you read it from. At fourteen the top of the
-- ladder is nearly three times the bottom and the rungs are three and a half studs apart,
-- which is a step you can see without anything to compare it against.
--
-- A tongue's height is its speed times how long it lives, more or less -- Drag and the upward
-- Acceleration bend it, but not enough to matter at this size -- so lifetime is what is
-- scaled. Speed is left alone, because a faster fire is a different fire and a taller one is
-- the same fire reaching further.
local TALLER = 14.0
-- What the authored flame already reaches, measured off its own numbers: about six studs a
-- second for about seven tenths of a second, plus what the acceleration adds.
local BASE_REACH = 7.8

--- The lifetime multiplier that makes a fire `share` of the way up the ladder.
local function stretch(share)
	return (BASE_REACH + TALLER * share) / BASE_REACH
end

--- And how much wider its tongues are.
---
--- A tall fire made of the same thin tongues reads as a longer thread rather than a bigger
--- fire: height alone stretches the silhouette without changing what it is. Half again at the
--- top is enough to make the difference one of size, and little enough that the biggest is
--- still a fire in a bowl rather than a bonfire the bowl is standing in.
local WIDER = 0.5
local function widen(share)
	return 1 + WIDER * share
end

-- Where they stand.
--
-- One brazier is authored in the map, in the corner of the square that had nothing in it. The
-- rest are clones of it laid along a circle whose centre is off towards the fountain, so the
-- crescent hugs the corner and its opening faces the water. Nine and a third studs apart,
-- which leaves about a stud and a half of daylight between two cages.
local HOME = Vector3.new(46, 0, -46)
local MIDDLE = 3
local ARC = {
	{ "pulse",  30.40, -55.86 },
	{ "pulsex", 38.81, -51.89 },
	{ "hex",    46.00, -46.01 },
	{ "inc",    51.57, -38.55 },
	{ "provex", 55.17, -29.96 },
}

local function moveTo(model, x, z)
	local d = Vector3.new(x, 0, z) - HOME
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Position = p.Position + d
		end
	end
end

task.spawn(function()
	local map = workspace:WaitForChild("Map", 60)
	if not map then
		warn("brazier: no map")
		return
	end

	-- The arc first, so everything below sees every brazier there is.
	local fires = {}
	local template = map:WaitForChild("Brazier", 30)
	if template then
		for i, spot in ipairs(ARC) do
			local m = template
			if i ~= MIDDLE then
				m = template:Clone()
				m.Name = "Brazier" .. i
				moveTo(m, spot[2], spot[3])
				m.Parent = map
			end
			m:SetAttribute("Flame", spot[1])
			table.insert(fires, m)
		end
	end

	-- The heights, before and regardless of anything arriving off a chain.
	--
	-- Ahead of the sprite on purpose. How tall a fire stands says which token is busiest and
	-- how fast its torch burns; the picture the tongues are drawn with is what they look like.
	-- Waiting on the second to do the first meant a slow fetch left every brazier the same
	-- height -- and on a client with no place assets at all, silently wrong forever.
	--
	-- The authored lifetimes are kept and multiplied rather than overwritten, so retuning a
	-- flame in the map still means something and this only stretches whatever is there.
	local authored = {}
	local function remember(d)
		if authored[d] == nil then
			authored[d] = { life = d.Lifetime, size = d.Size }
		end
	end
	for _, model in ipairs(fires) do
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("ParticleEmitter") and d.Name == "Flame" then remember(d) end
		end
	end

	Ranks.watch(function()
		local ranks = Ranks.all()
		for _, model in ipairs(fires) do
			local share = Ranks.share(ranks[tostring(model:GetAttribute("Flame"))] or Ranks.LAST)
			local tall, wide = stretch(share), widen(share)
			for d, was in pairs(authored) do
				if d:IsDescendantOf(model) and d.Parent then
					d.Lifetime = NumberRange.new(was.life.Min * tall, was.life.Max * tall)
					local kp = {}
					for _, k in ipairs(was.size.Keypoints) do
						table.insert(kp, NumberSequenceKeypoint.new(k.Time, k.Value * wide))
					end
					d.Size = NumberSequence.new(kp)
				end
			end
		end
	end)

	-- And then the colours and the picture, once the place assets land. Cloning an emitter
	-- per colour copies the lifetime it has by then, which is why this comes second.
	local folder = ReplicatedStorage:WaitForChild("PlaceAssets", 180)
	local sprite = folder and folder:WaitForChild("FlameSprite", 180)
	local lit = 0
	for _, model in ipairs(map:GetDescendants()) do
		lit += Flames.lightModel(model, sprite and sprite.Value or nil)
	end
	-- The clones are new emitters and the height watcher has never seen them, so they are
	-- added to it and it is run again.
	for _, model in ipairs(fires) do
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("ParticleEmitter") and d.Name == "Flame" then remember(d) end
		end
	end
	print(("brazier: %d fire(s) lit"):format(lit))
end)

-- /wave, /sit and /lay, the way an MMO means them.
--
-- Typed as chat commands, which is what TextChatCommand is for: the alias is registered
-- once, the engine matches the word and fires Triggered on both halves, and the text never
-- becomes a message. So `/sit` sits you down and does not also say "/sit" to the square.
--
-- ---- why the server ---------------------------------------------------------------------
-- Because everybody has to see it. An animation played on the client that typed it is an
-- animation nobody else in the square knows about. The command fires on both halves and this
-- is the half that acts.
--
-- ---- held and unheld --------------------------------------------------------------------
-- A wave is a thing you do; sitting is a thing you are. So a wave plays through and ends by
-- itself, and sitting and lying hold until you move -- which is what every MMO does, and it
-- is the only sensible answer to "how do I stand up": you walk.
--
-- Holding one is two things, not one. The POSE says what the body is doing; HipHeight says
-- where the body is. Pose the legs forward without dropping the body and the character sits
-- in mid air with its feet through the floor.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Emotes = require(ReplicatedStorage:WaitForChild("Emotes"))

-- The sequences, built once and shared. An Animation names one by the path it sits at, so
-- they need a home in the tree rather than a local.
-- NOT "Emotes". `src/shared/Emotes.luau` is already ReplicatedStorage.Emotes, and a folder
-- of the same name under the same parent makes two children called Emotes -- FindFirstChild
-- then hands back the ModuleScript, which has no animations in it. The sequences load, the
-- track plays, and the body does nothing.
local shelf = Instance.new("Folder")
shelf.Name = "EmoteAnimations"
shelf.Parent = ReplicatedStorage

-- The Animations go in a folder of their own, NOT beside the sequences. An AnimationId is a
-- path, and a path finds one child by name -- so a KeyframeSequence called "sit" and an
-- Animation called "sit" under the same parent is a coin flip over which one gets loaded,
-- and the Animation has no keyframes in it. The track plays and the body does nothing.
local pointers = Instance.new("Folder")
pointers.Name = "Anims"
pointers.Parent = shelf

local anims = {}
for name, def in pairs(Emotes.DEFS) do
	local seq = Emotes.sequence(name, { loop = def.loop, priority = Enum.AnimationPriority.Action }, def.frames)
	seq.Parent = shelf
	local anim = Instance.new("Animation")
	anim.Name = name
	anim.AnimationId = "ReplicatedStorage.EmoteAnimations." .. name
	anim.Parent = pointers
	anims[name] = anim
end

--- Which limbs an emote poses, whichever way it is played.
---
--- Every emote has to give back exactly what it took, and this is the list of what that is.
--- Stopping a track does NOT clear the Transform it wrote, so the last pose stays on the
--- joint -- which is a body still half lying down while it walks around.
local function limbsOf(name)
	local out = {}
	local def = Emotes.DEFS[name]
	for _, frame in ipairs((def and def.frames) or {}) do
		for limb in pairs(frame.pose) do out[limb] = true end
	end
	return out
end

-- Bumped every time an emote starts or stops, so a clear scheduled by one cannot land on
-- the next.
local generation = {}

-- What each player is holding, so it can be taken off them again: the track, and the
-- HipHeight they had before it dropped them.
local held = {}

local function release(player: Player)
	local h = held[player]
	if not h then return end
	held[player] = nil
	if h.character and h.character.Parent then h.character:SetAttribute("Emote", nil) end
	if h.track then
		local ok = pcall(function() h.track:Stop(0.25) end)
		if not ok then end
		-- And then put the joints back. Stopping a track fades it out of the blend; it does
		-- not clear the Transform it has been writing, so the last frame of the animation
		-- stays on every joint it touched. Standing up out of /lay left the body carrying a
		-- quarter of the pose it had just been in -- crooked, and it stayed that way.
		--
		-- After the fade rather than during it, or the fade writes over this on its way out.
		--
		-- Guarded by a count, because this lands a third of a second later and you can be in
		-- another pose by then: /roll is a release and a play back to back, and without this
		-- the clear from the first one wipes joints the second one had just written. Which
		-- is the crooked man who had been lying down and rolling over.
		local character = player.Character
		local touched = h.touched or {}
		generation[player] = (generation[player] or 0) + 1
		local mine = generation[player]
		task.delay(0.3, function()
			if generation[player] ~= mine then return end
			if not character or not character.Parent then return end
			for _, m in ipairs(character:GetDescendants()) do
				if m:IsA("Motor6D") and m.Part1 and touched[m.Part1.Name] then
					m.Transform = CFrame.new()
				end
			end
		end)
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and h.hipHeight then humanoid.HipHeight = h.hipHeight end
end

local function play(player: Player, name: string)
	local def = Emotes.DEFS[name]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not def or not animator or humanoid.Health <= 0 then return end

	-- One at a time, and typing the one you are already doing stands you up -- which is how
	-- every one of these works everywhere else.
	local already = held[player]
	release(player)
	if already and already.name == name then return end
	-- AFTER the release, not before. Release schedules a clear a third of a second out and
	-- stamps it with the count as it stands then -- so the bump that invalidates it has to
	-- come later than that, or the stamp still matches and the clear lands on the pose that
	-- replaced it. /roll is a release and a play back to back, which is how this was found.
	generation[player] = (generation[player] or 0) + 1

	local track = animator:LoadAnimation(anims[name])
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = def.loop == true
	track:Play(0.2)

	if def.loop then
		local was = humanoid.HipHeight
		local root = character:FindFirstChild("HumanoidRootPart")
		held[player] = { name = name, track = track, hipHeight = was, character = character,
			at = root and root.Position, touched = limbsOf(name) }
		-- Said on the body, for anything that cares what somebody is doing rather than how it
		-- looks: lying face up in the fountain is a thing the Everliving Fish answers to.
		character:SetAttribute("Emote", name)
		-- Negative, and not clamped at zero. HipHeight raises the body off the floor, so
		-- lowering it below zero is what puts somebody ON the floor -- clamping it at zero
		-- left the sit pose hanging in mid air with its feet through the ground.
		if def.hold > 0 then humanoid.HipHeight = was - def.hold end
	end
end

-- ---- standing up -------------------------------------------------------------------------
-- Walking is how you stand up, so this watches for two things.
--
-- MoveDirection is the intent, and it stands you up the instant you press a key. But it
-- cannot be the only signal: the world writes that field every frame from the client's own
-- input, so a Humanoid:Move from a script is stamped back to zero before the next look --
-- meaning an NPC or a script that walks you somewhere would leave you sitting as you slid
-- across the square.
--
-- So also: have you actually GONE anywhere. Horizontal only, because sitting drops the body
-- by a couple of studs on purpose and that is not walking. A knock-back far enough to move
-- you a few studs standing you up is right rather than wrong -- it is what being knocked over
-- ought to do.
local STRAYED = 3.0

task.spawn(function()
	while true do
		task.wait(0.1)
		for player, h in pairs(held) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not humanoid or not root or humanoid.Health <= 0 then
				held[player] = nil
			else
				local from = h.at or root.Position
				local dx, dz = root.Position.X - from.X, root.Position.Z - from.Z
				if humanoid.MoveDirection.Magnitude > 0.1 or math.sqrt(dx * dx + dz * dz) > STRAYED then
					release(player)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player) held[player] = nil end)

-- ---- the commands --------------------------------------------------------------------------
local commands = TextChatService:WaitForChild("TextChatCommands")
for name, def in pairs(Emotes.DEFS) do
	-- A hidden one is a pose something else switches you into, not a word you type. `belly`
	-- is the only one: /roll turns you over, and /belly would be a way to get face down on
	-- the grass without lying down first, which is not a thing.
	if def.hidden then continue end
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = name
	cmd.PrimaryAlias = "/" .. name
	cmd.Parent = commands
	cmd.Triggered:Connect(function(source)
		-- Triggered hands over the TextSource the line came from; the player is what it
		-- names. On the client half this fires too and does nothing, because there is no
		-- Animator there that anybody else can see.
		local player = source and Players:GetPlayerByUserId(source.UserId)
		if player then play(player, name) end
	end)
end

-- ---- rolling over --------------------------------------------------------------------------
-- Only while you are lying there. It is the one emote that is not a thing you start from
-- standing: you lie down, and then you turn over. Typed while upright it says so rather than
-- quietly doing nothing, because a command that answers is how anybody learns what it is for.
local roll = Instance.new("TextChatCommand")
roll.Name = "roll"
roll.PrimaryAlias = "/roll"
roll.Parent = commands
roll.Triggered:Connect(function(source)
	local player = source and Players:GetPlayerByUserId(source.UserId)
	if not player then return end
	local h = held[player]
	if not h or (h.name ~= "lay" and h.name ~= "belly") then return end
	play(player, h.name == "lay" and "belly" or "lay")
end)

-- A second name for lying down, because half the people who want it will type the other one.
local lieDown = Instance.new("TextChatCommand")
lieDown.Name = "lieAlias"
lieDown.PrimaryAlias = "/lie"
lieDown.Parent = commands
lieDown.Triggered:Connect(function(source)
	local player = source and Players:GetPlayerByUserId(source.UserId)
	if player then play(player, "lay") end
end)

print(("emotes: %s"):format(table.concat({ "/wave", "/sit", "/lay", "/roll" }, " ")))

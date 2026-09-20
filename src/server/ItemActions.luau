-- What a thing DOES, as against what wearing it does.
--
-- The bag has two gestures now. Right-click puts something on or takes it off, which is what
-- clicking an item in a bag means nearly everywhere. That leaves left-click, and left-click
-- asks the thing to do its trick.
--
-- Almost nothing has one. That is the honest default and it is not a gap: a hat is a hat, and
-- a left-click on it does nothing rather than doing something invented to fill the gesture in.
-- The table below is the whole list.
--
-- ---- why the server ----------------------------------------------------------------------
-- A trick only you can hear is not worth doing. The Familiar's is a noise, and the point of a
-- noise is the person next to you hearing it -- so it is played on a Sound in the world, from
-- the pet, rather than on the clicker's own machine. Everyone nearby hears it; nobody across
-- the square does, because it fades with distance like every other sound in a world.
--
-- ---- and why it is rationed --------------------------------------------------------------
-- Anything one player can make everybody else hear is something one player can make everybody
-- else hear five times a second. The cooldown is longer than the longer of the two clips, so
-- the most anybody can do with it is talk steadily rather than machine-gun the square.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Pets = require(script.Parent.Pets)

local ItemActions = {}

-- His two lines, said in turn. The names are the place assets they arrive as.
local VOICES = { "SfxFamiliar1", "SfxFamiliar2" }

-- How often he will speak, in seconds. The longer clip is 0.64s.
local COOL = 1.0

-- How far it carries. Close by: the people you are standing with, not the square.
local NEAR = 8              -- full volume out to here
local FAR = 55              -- and nothing at all past here

local said = {}             -- player -> which line is next
local spoke = {}            -- player -> when they last did

--- The published clip behind a name, or "" before the host has fetched it.
local function clip(name)
	local folder = ReplicatedStorage:FindFirstChild("PlaceAssets")
	local value = folder and folder:FindFirstChild(name)
	return (value and value.Value) or ""
end

--- The Familiar says one of his two things, out of his own head, where he is standing.
---
--- The reverb is the first effect this town has hung on anything. It is a child of the Sound,
--- which is where Roblox puts one, and the engine gives a Sound with effects a bus of its own
--- rather than mixing them per voice -- so it costs nothing until somebody asks for it.
local function speak(player)
	local head = Pets.speaker(player)
	if not head then
		return "He has to be out before he can say anything."
	end
	local which = said[player] or 1
	local asset = clip(VOICES[which])
	if asset == "" then
		return "He has lost his voice -- the town never fetched it."
	end
	said[player] = which == 1 and 2 or 1

	local sound = Instance.new("Sound")
	sound.Name = "FamiliarVoice"
	sound.SoundId = asset
	sound.Volume = 1
	-- Out of the pet and no further than the next few people. RollOffMinDistance is where it
	-- starts to fade and RollOffMaxDistance is where it has gone entirely.
	sound.RollOffMinDistance = NEAR
	sound.RollOffMaxDistance = FAR
	sound.Parent = head

	local room = Instance.new("ReverbSoundEffect")
	-- A long tail on a short bark, which is the joke. Diffusion below 1 lets some of the
	-- room's edges through rather than smearing the lot into a wash.
	room.DecayTime = 3
	room.Diffusion = 0.85
	room.DryLevel = 0
	room.WetLevel = -4
	room.Parent = sound

	sound:Play()
	-- By the clock, not by Ended: a Sound that has only just been made reports finishing
	-- before it is audible, and hanging Destroy off that signal plays it exactly once per
	-- session. Six seconds is longer than the clip plus the tail the reverb adds to it.
	Debris:AddItem(sound, 6)
	return nil
end

-- The list. Keyed by the model name the chain knows the thing by.
local DOES = {
	Familiar = { label = "Speak", run = speak },
}

--- What this item does when it is clicked, or nil if it does nothing.
---
--- The client asks so it knows whether a left-click is worth anything: a tile that does
--- nothing should not click at you as though it had.
function ItemActions.of(item)
	local does = item and DOES[item.model]
	return does and does.label or nil
end

--- Do it. Returns a line to show the player, or nil when there is nothing to say.
function ItemActions.run(player, item)
	local does = item and DOES[item.model]
	if not does then return nil end
	local now = os.clock()
	if now - (spoke[player] or -1) < COOL then return nil end
	spoke[player] = now
	return does.run(player)
end

Players.PlayerRemoving:Connect(function(player)
	said[player] = nil
	spoke[player] = nil
end)

return ItemActions

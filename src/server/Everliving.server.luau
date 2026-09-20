-- The Everliving Fish: lie down face up in the fountain holding it, and stand up whole.
--
-- Romans 6:4. Down into the water, and up again. Face up only: /lay puts you on your back, /roll
-- turns you over, and lying face down in a fountain is a different thing altogether. The fish has
-- to be in your hand as you step INTO the water -- taking it out once you are already in does
-- nothing until you step out and come back in carrying it -- and still in your hand while you lie
-- there. The healing is on the way back up: the moment you stand, every heart you had lost is back.
--
-- Read off the body, the way the fight reads a weapon: an Accoutrement named "Everliving Fish" is
-- the fish, and the character's "Emote" attribute (Emotes.server.luau) is what you are doing.
local Players = game:GetService("Players")

local Health = require(script.Parent.Health)

local FISH = "Everliving Fish"
local ABOVE = 3.5         -- studs over the water's surface a lying body can be and still be in it
local LOOK = 0.2          -- seconds between looks

--- The fountain's water, when the map has one.
local function water()
	local map = workspace:FindFirstChild("Map")
	local fountain = map and map:FindFirstChild("Fountain")
	return fountain and fountain:FindFirstChild("Water")
end

local function holdingFish(character)
	local fish = character:FindFirstChild(FISH)
	return fish ~= nil and fish:IsA("Accoutrement")
end

--- Whether a point is in the fountain: over the water, and not far above it.
local function inWater(pos, part)
	local local_ = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size / 2
	return math.abs(local_.X) <= half.X and math.abs(local_.Z) <= half.Z
		and local_.Y <= half.Y + ABOVE and local_.Y >= -half.Y - 2
end

local blessed = {}        -- character -> has lain face up in the water with the fish in hand
local inside = {}         -- character -> in the fountain, and whether the fish came in with them

local function risen(character)
	blessed[character] = nil
	local player = Players:GetPlayerFromCharacter(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not player or not hum or hum.Health <= 0 then return end
	if hum.Health < hum.MaxHealth then
		Health.heal(player, player, hum.MaxHealth)
	end
	print(("everliving: %s rose from the water, %d of %d"):format(player.Name, hum.Health, hum.MaxHealth))
end

local function watch(character)
	-- Standing up is the Emote going away (or turning into something that is not lying down).
	character:GetAttributeChangedSignal("Emote"):Connect(function()
		if not blessed[character] then return end
		-- A beat before deciding. /roll is a stand and a lie-down back to back, so the pose goes
		-- through "nothing" on its way from face up to face down, and that is not standing up.
		task.delay(0.15, function()
			if not blessed[character] then return end
			local now = character:GetAttribute("Emote")
			if now == "belly" then
				-- Rolled over. Face down is not it: turning back over counts again, staying down does not.
				blessed[character] = nil
			elseif now ~= "lay" then
				risen(character)
			end
		end)
	end)
	character.AncestryChanged:Connect(function()
		if not character.Parent then blessed[character] = nil inside[character] = nil end
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(watch)
	if player.Character then watch(player.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end

task.spawn(function()
	while true do
		task.wait(LOOK)
		local w = water()
		if w then
			for _, player in ipairs(Players:GetPlayers()) do
				local ch = player.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				if root then
					local holding = holdingFish(ch)
					if not inWater(root.Position, w) then
						inside[ch] = nil
					elseif inside[ch] == nil then
						-- Stepping in: whether the fish came in with them is decided here, once.
						inside[ch] = { withFish = holding }
					elseif not holding then
						-- Put away inside: taking it out again does not count.
						inside[ch].withFish = false
					end
					local entry = inside[ch]
					if entry and entry.withFish and holding and not blessed[ch] and ch:GetAttribute("Emote") == "lay" then
						blessed[ch] = true
						print(("everliving: %s lies in the water"):format(player.Name))
					end
				end
			end
		end
	end
end)

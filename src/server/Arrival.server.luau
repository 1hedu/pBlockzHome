-- Nobody is put in the town before they can see it.
--
-- A character used to be made the moment a player joined, which is while they are still on the
-- title screen, and then under the black of the intro for however long the town takes to turn
-- up. Standing in the square the whole time, where anybody already here could hit them, and
-- they could do nothing about it. That's spawn camping with the lights off.
--
-- Roblox's way: Players.CharacterAutoLoads is off (default.project.json), so joining makes no
-- character, and the place loads one when it is ready for it. Here that is when the client
-- says so -- Intro.client.luau fires Arrived as the black starts to lift, when the town is
-- there to be seen -- and after that, RespawnTime after every death, because with
-- CharacterAutoLoads off nothing else will.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local arrivedEvent = Instance.new("RemoteEvent")
arrivedEvent.Name = "Arrived"
arrivedEvent.Parent = ReplicatedStorage

-- Who has been let in already. Once each: after that a character is the server's to give,
-- and firing Arrived again must not bring somebody back early from a death.
local arrived = {}

arrivedEvent.OnServerEvent:Connect(function(player)
	if arrived[player] then return end
	arrived[player] = true
	-- Already in: something let them in first (a test does, with nobody watching the intro).
	if player.Character then return end
	player:LoadCharacterAsync()
end)

local function watch(player)
	local function lives(character)
		local hum = character:WaitForChild("Humanoid", 10)
		if not hum then return end
		hum.Died:Connect(function()
			task.wait(Players.RespawnTime)
			-- Still here, and still that body: a place script that has loaded them again in the
			-- meantime has already done this.
			if player.Parent == Players and player.Character == character then
				player:LoadCharacterAsync()
			end
		end)
	end
	player.CharacterAdded:Connect(lives)
	-- And the body they already have, if something let them in before this script ran: it dies
	-- like any other and has to come back like any other.
	if player.Character then task.spawn(lives, player.Character) end
end

Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerRemoving:Connect(function(player)
	arrived[player] = nil
end)

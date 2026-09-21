# Gives every player a character as they join, for a test that is not about the intro.
#
#   const Arrive = preload("res://tests/Arrive.gd")
#   Arrive.now(world)          # the server's world (or Play Solo's), once it is in the tree
#
# The town leaves Players.CharacterAutoLoads off and lets Arrival.server.luau load the character
# once the client reports it can see -- about nine seconds with no character. Arrival.server.luau
# still runs afterwards and finds the character already there, so it changes nothing. The spawn's
# six-second ForceField goes too, so a swing landing in those seconds is measured, not the shield;
# a respawn after a death still gets one. forcefield_test covers the shield, and arrival_test
# must not use this, since arriving is what it tests.

static func now(world: PulseBlockzWorld) -> void:
	world.run_chunk("arrive", """
local Players = game:GetService("Players")
local function arrive(player)
	if player.Character then return end
	player:LoadCharacterAsync()
	local ff = player.Character and player.Character:FindFirstChildOfClass("ForceField")
	if ff then ff:Destroy() end
end
Players.PlayerAdded:Connect(arrive)
for _, player in ipairs(Players:GetPlayers()) do arrive(player) end
""")

-- Sounds are heard from where you stand, not from where the camera is.
--
-- Roblox listens from the camera unless a place says otherwise (SoundService:SetListener), and at
-- Roblox's zoom that is the same place. This town's sounds are tuned to the square -- a trampoline
-- tapers to silence at forty-five studs -- and a camera zoomed out past that heard the pad you
-- were standing on as if from the far side of the map. The listener is your character's root:
-- its position, with the camera's facing, so left and right are still the screen's left and right.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

local function follow(character)
	local root = character:WaitForChild("HumanoidRootPart", 30)
	if root then SoundService:SetListener(Enum.ListenerType.ObjectPosition, root) end
end

if player.Character then task.spawn(follow, player.Character) end
player.CharacterAdded:Connect(follow)

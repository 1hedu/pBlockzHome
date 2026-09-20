-- Clicking, while holding something you can swing.
--
-- Only while holding one: this binds a mouse button, and a game where the left button
-- swings an invisible weapon whether or not you own one would be a worse game. The check
-- is here so the click is ignored quietly, and again on the server, which is the one that
-- decides -- a client saying it is armed proves nothing.
--
-- Clicks that land on a window are not swings. Finch's shelf, the wardrobe and the drawing
-- table are all full of buttons, and buying a hat should not also stab the air.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("WeaponRemote")

-- Which accessories are weapons: the server's own list, read from the same place it does.
-- This end only needs to know whether to bother sending a click; the server decides what one
-- does, and again whether it is allowed at all.
local WEAPONS = require(ReplicatedStorage:WaitForChild("Weapons"))

-- Long enough to swallow a double-fire from one press, short enough that clicking fast
-- swings fast. The server owns the real pacing, and it lets a new swing cut off the one in
-- flight rather than dropping the click.
local COOLDOWN = 0.12
local last = 0

local function armed()
	local ch = player.Character
	if not ch then return false end
	for _, d in ipairs(ch:GetChildren()) do
		if d:IsA("Accoutrement") and WEAPONS[d.Name] then return true, d.Name end
	end
	return false
end

--- True while any of the town's panels is open over the world.
---
--- A panel is something you opened and can close. A HUD -- the hearts, the chat, the volume
--- strip -- is always on screen and is not in the way of anything, so it says so with a `Hud`
--- attribute and is passed over here. Without that distinction every permanent HUD added to
--- the town silently disarmed every weapon: this counted any enabled ScreenGui at all, so the
--- day the chat window arrived, clicking stopped swinging and nothing said why.
local function windowOpen()
	for _, screen in ipairs(gui:GetChildren()) do
		if screen:IsA("ScreenGui") and screen.Enabled and screen.Name ~= "TownDialog"
			and not screen:GetAttribute("Hud") then
			return true
		end
	end
	return false
end

--- Asks for a swing, if it is a reasonable moment to ask.
local function ask()
	if not armed() or windowOpen() then return end
	local now = os.clock()
	if now - last < COOLDOWN then return end
	last = now
	-- Noted here, on this machine, the instant it is asked: the server's word that a swing has
	-- started takes a round trip, and the body should already be turning to face the stroke.
	player:SetAttribute("SwingAskedAt", now)
	remote:FireServer()
end

-- One click, one swing. Holding the button does nothing: a weapon that keeps swinging while
-- the button is down takes the rhythm of the fight away from the player and hands it to a
-- timer, and every stroke after the first is one nobody chose to throw. An earlier version
-- repeated on RenderStepped while held and it was exactly as dull as that sounds.
--
-- Read off UserInputService rather than off the classic Mouse, for the second argument:
-- gameProcessedEvent is true when the click was taken by a control, and a press on the
-- action bar is a press on the action bar and not also a swing. The bar is a HUD, so
-- windowOpen() above passes it over on purpose -- it is not in the way of anything -- which
-- left every press on a square putting a hat on AND stabbing the air.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	ask()
end)

-- The button coming up, for a weapon that charges while it is held (the cane). Sent whatever
-- took the release -- a press that started a charge and ended over a button still has to end
-- the charge -- and the server ignores it when nothing is charging. Losing the window counts
-- too: a release the window never saw would leave the arm up until the server gives up on it.
local function letGo()
	local ok, name = armed()
	if ok and WEAPONS.charged[name] then remote:FireServer("release") end
end
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then letGo() end
end)
UserInputService.WindowFocusReleased:Connect(letGo)

-- The server says which swing it chose, so the two never disagree about whose turn it is --
-- or that it chose none, because the thing is still being drawn.
remote.OnClientEvent:Connect(function(kind)
	print(("weapons: %s"):format(tostring(kind)))
end)

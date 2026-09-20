-- The health meter: hearts, along the bottom of the screen.
--
-- The row itself is HeartRow, shared with the little one that hangs over everyone's head
-- while PvP is on. What is here is where it goes and what it listens to.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HeartRow = require(ReplicatedStorage:WaitForChild("HeartRow"))

local SIZE = 72               -- one heart, in pixels
local GAP = 7
-- Above the action bar, which is 54 tall and sits 65 up from the bottom edge.
local BOTTOM = 65 + 54 + 12

local player = Players.LocalPlayer
local screen = Instance.new("ScreenGui")

-- This town was laid out before the GUI inset existed, so it keeps the whole screen
-- and everything stays where it was put. A place written against Roblox wants the
-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.
screen.IgnoreGuiInset = true
screen.Name = "Hearts"
screen.ResetOnSpawn = false
-- Off until there is something to show. A ScreenGui is enabled when it is made, and the
-- first word from the server is almost always "you are not in a fight" -- so this came up,
-- then went off a second and a half later, and the sound that marks a panel opening or
-- closing fired on the way down. A click nobody clicked, every time the game started.
screen.Enabled = false
-- A HUD, not a panel: always on, never in the way. Weapons.client.luau refuses to swing while
-- a window is open and would otherwise count this as one.
screen:SetAttribute("Hud", true)
screen.Parent = player:WaitForChild("PlayerGui")

local row = HeartRow.new(screen, SIZE, GAP)
row.row.AnchorPoint = Vector2.new(0.5, 1)
row.row.Position = UDim2.new(0.5, 0, 1, -BOTTOM)

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("PlaceAssets", 180)
	local asset = folder and folder:WaitForChild("HeartIcon", 180)
	row:setIcon(asset and asset.Value or "")
end)

-- Nothing at all while you are out of duelling.
--
-- Not greyed and not empty: gone. Out of it you cannot be hit and cannot hit, so a health
-- meter is measuring something that will not move -- and the same rule already applies over
-- everyone's head, where the row appears exactly when they are in. Half a screen of HUD that
-- means nothing is worse than a gap.
ReplicatedStorage:WaitForChild("HeartsRemote").OnClientEvent:Connect(
	function(half, maxHalf, _fire, colours, fights)
		screen.Enabled = fights ~= false
		if fights == false then return end
		row:draw(half, maxHalf, colours)
	end)
row:fit(3)

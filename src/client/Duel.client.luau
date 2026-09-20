-- A ranked duel, from inside one: the score across the top of the screen, and the town's lines
-- about it in the chat.
--
-- The score is read, not sent: the server keeps each duel as a Configuration under
-- ReplicatedStorage.Duels, and this player's "Duel" attribute says which one they are in. The
-- lines -- who is in, who got whom, who won -- arrive on DuelRemote and go into the chat as system
-- messages, TextChannel:DisplaySystemMessage, which is where a Roblox place says things like that.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---- the chat lines -----------------------------------------------------------------------
local remote = ReplicatedStorage:WaitForChild("DuelRemote", 60)
if remote then
	remote.OnClientEvent:Connect(function(kind, text)
		if kind ~= "announce" or type(text) ~= "string" then return end
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general then
			pcall(function() general:DisplaySystemMessage("[Duel] " .. text) end)
		end
	end)
end

-- ---- the score ----------------------------------------------------------------------------
local W, H = 520, 64

local screen = Instance.new("ScreenGui")
screen.Name = "DuelScore"
screen.ResetOnSpawn = false
-- The whole screen, like the chat beside it, so the two line up along the top.
screen.IgnoreGuiInset = true
screen.Enabled = false
screen.Parent = playerGui

local TOP = 46   -- level with the chat window's top edge
local content, window = Theme.window(screen, UDim2.new(0, W, 0, H), UDim2.new(0, 0, 0, TOP))
local score = Theme.label(content, "", { size2 = UDim2.new(1, -16, 0, 32), pos = UDim2.new(0, 8, 0, 2),
	align = Enum.TextXAlignment.Center })
local limit = Theme.label(content, "", { size = Theme.t.small, colour = Theme.c.dim,
	size2 = UDim2.new(1, -16, 0, 20), pos = UDim2.new(0, 8, 0, 36), align = Enum.TextXAlignment.Center })

--- The right-hand edge of the chat, which sits in the top left and can be resized: the score is
--- centred, but never on top of it.
local function chatRight()
	local chat = playerGui:FindFirstChild("TownChat")
	local right = 0
	if chat and chat.Enabled then
		for _, child in ipairs(chat:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible and child.AbsolutePosition.Y < TOP + H then
				right = math.max(right, child.AbsolutePosition.X + child.AbsoluteSize.X)
			end
		end
	end
	return right
end

-- Top middle, measured off the ScreenGui once it has a size (see Theme.centre for why).
local function place()
	local size = screen.AbsoluteSize
	if size.X <= 0 then
		local cam = workspace.CurrentCamera
		size = cam and cam.ViewportSize or size
	end
	if size.X <= 0 then return end
	local x = math.max(math.floor((size.X - W) / 2), chatRight() + 12)
	window.Position = UDim2.new(0, x, 0, TOP)
end

local watching = nil
local conns = {}

--- Theme.label draws every label twice, a shadow one pixel down; both have to say the same thing.
local function setBoth(label, text)
	label.Text = text
	for _, child in ipairs(label.Parent:GetChildren()) do
		if child.Name == "Shadow" and child:IsA("TextLabel") and child.Position.Y.Offset == label.Position.Y.Offset + 1 then
			child.Text = text
		end
	end
end

local function draw()
	local node = watching
	if not node or not node.Parent then
		screen.Enabled = false
		return
	end
	local fa, fb = node:GetAttribute("FragsA") or 0, node:GetAttribute("FragsB") or 0
	setBoth(score, ("%s  %d - %d  %s"):format(tostring(node:GetAttribute("TeamA") or "?"), fa, fb,
		tostring(node:GetAttribute("TeamB") or "?")))
	local state = node:GetAttribute("State")
	setBoth(limit, state == "over" and "Over" or ("First to %d"):format(node:GetAttribute("Limit") or 0))
	screen.Enabled = true
	place()
end

local function follow()
	for _, c in ipairs(conns) do c:Disconnect() end
	conns = {}
	local id = player:GetAttribute("Duel")
	local folder = ReplicatedStorage:FindFirstChild("Duels")
	local node = type(id) == "string" and folder and folder:FindFirstChild(id) or nil
	-- Keep showing a duel that has just ended until the server takes it away, so the final
	-- score is on screen for a moment rather than vanishing with the last frag.
	if not node and watching and watching.Parent and watching:GetAttribute("State") == "over" then
		node = watching
	end
	watching = node
	if node then
		table.insert(conns, node.AttributeChanged:Connect(draw))
		table.insert(conns, node.AncestryChanged:Connect(function() task.defer(follow) end))
	end
	draw()
end

player:GetAttributeChangedSignal("Duel"):Connect(follow)
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("Duels", 60)
	if folder then folder.ChildAdded:Connect(function() task.defer(follow) end) end
	follow()
end)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
end

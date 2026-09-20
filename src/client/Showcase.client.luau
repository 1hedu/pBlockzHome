-- The window somebody else opens on your screen when they show you something.
--
-- It is theirs, not yours: you did not ask for it and you cannot pin it. It stays up
-- while the two of you are standing together and goes when either of you walks off,
-- which is the same rule a real conversation runs on.
--
-- The other half of this -- picking a thing and picking a person -- lives in the
-- character pane, because that is where you are already holding the thing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("ShowcaseRemote")

local W, H = 460, 300

local screen = Instance.new("ScreenGui")

-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "Showcase"
screen.Enabled = false
screen.ResetOnSpawn = false
screen.Parent = gui

local panel, panelWindow = Theme.window(screen, UDim2.new(0, 460, 0, 300), UDim2.new(1, -W - 24, 0.5, -H / 2))

local edge = Instance.new("UIStroke")
edge.Thickness = 2
edge.Color = Theme.c.accent
edge.Transparency = 0.4
edge.Parent = panel

local from = Instance.new("TextLabel")
from.Size = UDim2.new(1, -28, 0, 18)
from.Position = UDim2.new(0, 14, 0, 12)
from.BackgroundTransparency = 1
from.TextColor3 = Theme.c.accent
from.TextSize = Theme.t.small
from.TextXAlignment = Enum.TextXAlignment.Left
from.Text = ""
Theme.face(from)
from.Parent = panel

local name = Instance.new("TextLabel")
name.Size = UDim2.new(1, -28, 0, 24)
name.Position = UDim2.new(0, 14, 0, 32)
name.BackgroundTransparency = 1
name.TextColor3 = Theme.c.ink
name.TextSize = Theme.t.title
name.TextXAlignment = Enum.TextXAlignment.Left
name.TextTruncate = Enum.TextTruncate.AtEnd
name.Text = ""
Theme.face(name)
name.Parent = panel

local picture = Instance.new("ImageLabel")
picture.Size = UDim2.new(0, 72, 0, 72)
picture.Position = UDim2.new(0, 14, 0, 64)
picture.BackgroundColor3 = Theme.c.tile
picture.Image = ""
picture.Parent = panel
Theme.corner(picture, 6)

local body = Instance.new("TextLabel")
body.Size = UDim2.new(1, -110, 0, 78)
body.Position = UDim2.new(0, 96, 0, 62)
body.BackgroundTransparency = 1
body.TextColor3 = Theme.c.dim
body.TextSize = Theme.t.body
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.Text = ""
Theme.face(body)
body.Parent = panel

-- The record itself, in a monospaced-looking well, because a hash is the point.
local well = Instance.new("Frame")
well.Size = UDim2.new(1, -28, 0, 56)
well.Position = UDim2.new(0, 14, 0, 148)
well.BackgroundColor3 = Theme.c.field
well.BackgroundTransparency = 0.2
well.Parent = panel
Theme.corner(well, 6)

local hash = Instance.new("TextLabel")
hash.Size = UDim2.new(1, -16, 0, 18)
hash.Position = UDim2.new(0, 8, 0, 6)
hash.BackgroundTransparency = 1
hash.TextColor3 = Theme.c.ink
hash.TextSize = Theme.t.small
hash.TextXAlignment = Enum.TextXAlignment.Left
hash.TextTruncate = Enum.TextTruncate.AtEnd
hash.Text = ""
Theme.face(hash)
hash.Parent = well

local where = Instance.new("TextLabel")
where.Size = UDim2.new(1, -16, 0, 16)
where.Position = UDim2.new(0, 8, 0, 26)
where.BackgroundTransparency = 1
where.TextColor3 = Theme.c.faint
where.TextSize = Theme.t.small
where.TextXAlignment = Enum.TextXAlignment.Left
where.Text = ""
Theme.face(where)
where.Parent = well

local footer = Instance.new("TextLabel")
footer.Size = UDim2.new(1, -28, 0, 16)
footer.Position = UDim2.new(0, 14, 1, -26)
footer.BackgroundTransparency = 1
footer.TextColor3 = Theme.c.faint
footer.TextSize = Theme.t.small
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text = "Closes when you walk apart."
Theme.face(footer)
footer.Parent = panel

-- ---- a line back to the person doing the showing --------------------------------------

local toast = Instance.new("TextLabel")
toast.Size = UDim2.new(0, 380, 0, 26)
toast.Position = UDim2.new(0.5, -190, 1, -76)
toast.BackgroundColor3 = Theme.c.card
toast.BackgroundTransparency = 0.15
toast.TextColor3 = Theme.c.dim
toast.TextSize = Theme.t.small
toast.Text = ""
toast.Visible = false
Theme.face(toast)
toast.Parent = screen
Theme.corner(toast, 6)

local toastUntil = 0
local function note(text)
	toast.Text = text
	toast.Visible = true
	screen.Enabled = true
	toastUntil = os.clock() + 3
end

-- ---- opening what they showed you -------------------------------------------------------
--
-- Straight at the scan's own remote: "open" puts the window up, "go" walks it to the page.
-- Both are checked on the server exactly as they are when you type them yourself, so being
-- handed a link by somebody standing next to you gets you no further than you could get on
-- your own. That is the right amount of trust to place in a stranger's souvenir.
local openView, openPage = "", ""

local openButton = Theme.button(panel, "Open the page", Theme.c.good)
openButton.Size = UDim2.new(0, 160, 0, 30)
openButton.Position = UDim2.new(0, 18, 1, -46)
openButton.TextSize = Theme.t.small
openButton.Visible = false
openButton:SetAttribute("Sfx", "menu")
openButton.Activated:Connect(function()
	if openView == "" or openPage == "" then return end
	-- The explorer is this machine's own window, so it is asked directly: the server's remote has
	-- no "go", and a page is read by the player's own client anyway.
	local explorer = gui:FindFirstChild("Explorer")
	local goTo = explorer and explorer:FindFirstChild("Go")
	if goTo then goTo:Fire(openView, openPage) end
end)

-- ---- the showing ----------------------------------------------------------------------

local showing = nil        -- the name of whoever opened this, while they are in reach
local reach = 24

local function close()
	showing = nil
	panel.Visible = false
	if not toast.Visible then screen.Enabled = false end
end

remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "note" then
		note(tostring(payload))
		return
	end
	if kind ~= "card" then return end
	showing = payload.from
	reach = payload.reach or 24
	from.Text = ("%s is showing you"):format(payload.from)
	name.Text = payload.name
	picture.Image = payload.thumb or ""
	body.Text = payload.blurb ~= "" and payload.blurb or "A thing they are carrying."
	-- A link is for following. An Engram shown to you that you cannot open is a postcard of
	-- a door -- so the thing it is a memory OF is one press away, on your own scan, read
	-- fresh off the explorer rather than repeated from whatever they are carrying.
	openView = tostring(payload.view or "")
	openPage = tostring(payload.page or "")
	openButton.Visible = openView ~= "" and openPage ~= ""
	if payload.tx ~= "" then
		hash.Text = payload.tx
		where.Text = payload.block ~= "" and ("block %s   .   %s"):format(payload.block, payload.explorer)
			or payload.explorer
		well.Visible = true
	else
		well.Visible = false
	end
	panel.Visible = true
	screen.Enabled = true
end)

-- Open only while you are both standing there.
RunService.Heartbeat:Connect(function()
	if toast.Visible and os.clock() > toastUntil then
		toast.Visible = false
		if not showing then screen.Enabled = false end
	end
	if not showing then return end
	local them = Players:FindFirstChild(showing)
	local theirs = them and them.Character and them.Character:FindFirstChild("HumanoidRootPart")
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not theirs or not mine or (theirs.Position - mine.Position).Magnitude > reach then
		close()
	end
end)

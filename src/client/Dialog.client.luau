-- The dialog window every NPC in town talks through. The server decides what is said;
-- this only draws it.
--
-- One window, shared by the teller and the shopkeeper: you can only be in one
-- conversation at a time, and each reply goes back to whichever remote opened it.
--
-- Sized in scale rather than pixels so it fits whatever window you are playing in,
-- and the answer sits in a ScrollingFrame: some of them (the item list, the shop) are
-- longer than any fixed panel, and text that runs off the bottom may as well not have
-- been said.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Pictures = require(ReplicatedStorage:WaitForChild("Pictures"))
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

local INK = Theme.c.ink
local PANEL = Theme.c.panel
local ACCENT = Theme.c.accent
local LINE_HEIGHT = 18
-- The prompt that opens this reaches 10 studs. Close a good way past that rather
-- than right at the edge, so standing on the boundary does not flicker the window.
local CLOSE_DISTANCE = 16
local WRAP_AT = 40          -- characters per line, deliberately pessimistic: too much
                            -- room only means slack at the end, too little hides text

-- The panel's vertical plan, in one place.
--
-- These were scattered magic offsets and they drifted apart: the menu ended up 162 pixels
-- underneath the body, and the body is a ScrollingFrame with a transparent background --
-- invisible, but it still takes the click, because a control only declines the pointer if
-- it is told to. Every option the body covered stopped answering, which left exactly the
-- bottom one working. Reopening reshuffled which option that was.
--
-- So the sections are stacked from the bottom and never allowed to share a row: the menu
-- is pinned above the panel's bottom edge, the input box sits above the menu when it is
-- asked for, and the body takes whatever is left rather than the other way round.
local PANEL_W, PANEL_H = 820, 660
local EDGE = 12             -- margin from the panel's sides and bottom
local GAP = 8               -- between stacked sections
local MENU_H = 260          -- five options at OPT_H + OPT_GAP; it scrolls past that
local FIELD_H = 44
local BODY_TOP = 46
local BODY_INSET = EDGE + MENU_H + GAP + BODY_TOP          -- body height = PANEL_H - this
local BODY_INSET_FIELD = BODY_INSET + FIELD_H + GAP        -- ... with the input box up

local screen = Instance.new("ScreenGui")

-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "TownDialog"
screen.Enabled = false
screen.ResetOnSpawn = false
screen.Parent = gui

local panel, panelWindow = Theme.window(screen, UDim2.new(0, PANEL_W, 0, PANEL_H),
	UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2))
panel.Name = "Panel"

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -24, 0, 30)
title.Position = UDim2.new(0, 12, 0, 10)
title.BackgroundTransparency = 1
title.TextColor3 = ACCENT
title.TextScaled = true
title.Text = ""
Theme.face(title)
title.Parent = panel

-- Everything the NPC says goes in here, and scrolls if there is more of it than fits.
local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Body"
scroll.Position = UDim2.new(0, EDGE, 0, BODY_TOP)
scroll.Size = UDim2.new(1, -EDGE * 2, 1, -BODY_INSET)
scroll.BackgroundTransparency = 1
scroll.ScrollBarThickness = 8
scroll.ScrollBarImageColor3 = Theme.c.scrollbar
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = panel

-- The picture of whatever we are talking about: the host wrote the PNG to disk after
-- checking it against its content hash, and hands us the path. It scrolls with the
-- text rather than floating over it.
local thumb = Instance.new("ImageLabel")
thumb.Name = "Thumb"
thumb.Size = UDim2.new(0, 96, 0, 96)
thumb.Position = UDim2.new(0, 0, 0, 0)
thumb.BackgroundTransparency = 1
thumb.Visible = false
thumb.Parent = scroll

local body = Instance.new("TextLabel")
body.Name = "Text"
body.Size = UDim2.new(1, -10, 0, LINE_HEIGHT)
body.Position = UDim2.new(0, 0, 0, 0)
body.BackgroundTransparency = 1
body.TextColor3 = INK
body.TextSize = Theme.t.body
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.Text = ""
Theme.face(body)
body.Parent = scroll

-- Somewhere to type, for the answers that need an address or an amount. Hidden unless
-- the NPC asks for one, so most conversations are still just buttons.
local field = Instance.new("TextBox")
field.Name = "Input"
field.Position = UDim2.new(0, EDGE, 1, -(EDGE + MENU_H + GAP + FIELD_H))
field.Size = UDim2.new(1, -EDGE * 2, 0, FIELD_H)
field.BackgroundColor3 = Theme.c.field
field.TextColor3 = INK
field.PlaceholderColor3 = Theme.c.faint
field.TextSize = Theme.t.body
field.ClearTextOnFocus = false
field.Text = ""
field.Visible = false
Theme.face(field)
field.Parent = panel
local fieldCorner = Instance.new("UICorner")
fieldCorner.Parent = field

local menu = Instance.new("ScrollingFrame")
menu.Name = "Menu"
menu.Position = UDim2.new(0, EDGE, 1, -(EDGE + MENU_H))
menu.Size = UDim2.new(1, -EDGE * 2, 0, MENU_H)
menu.BackgroundTransparency = 1
menu.ScrollBarThickness = 6
menu.ScrollBarImageColor3 = Theme.c.scrollbar
menu.AutomaticCanvasSize = Enum.AutomaticSize.Y
menu.CanvasSize = UDim2.new(0, 0, 0, 0)
menu.Parent = panel
-- Options are placed by hand, for the same reason the shop's rows are: a UIListLayout
-- sorts by Name through a hash map, and every option is a TextButton with the same name,
-- so the order they appeared in was arbitrary and changed on every rebuild. That is what
-- made reopening with E shuffle the menu.
local OPT_H, OPT_GAP = 44, 6

-- Which remote opened the window, so an answer goes back to the NPC who asked, and
-- which part of the world we are standing at, so walking off ends the conversation.
local current = nil
local anchor = nil

-- E closes what E opened.
--
-- Bound only while the window is up, and unbound the moment it closes. A ContextAction is
-- offered a key before any ProximityPrompt is, so leaving this bound would take E away from
-- the prompts and there would be no way to start a conversation at all.
local E_ACTION = "DialogToggle"

local close
local function onE(_, state)
	if state == Enum.UserInputState.Begin then close() end
	return Enum.ContextActionResult.Sink
end

close = function()
	screen.Enabled = false
	current = nil
	anchor = nil
	ContextActionService:UnbindAction(E_ACTION)
end

-- The NPC's own torso, which is where its prompt lives.
local function anchorFor(name)
	if type(name) ~= "string" or name == "" then return nil end
	local map = workspace:FindFirstChild("Map")
	local npc = map and map:FindFirstChild(name)
	return npc and npc:FindFirstChild("Torso") or nil
end

-- Walking away closes the window. Talking to someone and then wandering off used to
-- leave their dialog hanging over the square for the rest of the session.
RunService.Heartbeat:Connect(function()
	if not screen.Enabled or anchor == nil then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if (root.Position - anchor.Position).Magnitude > CLOSE_DISTANCE then
		close()
	end
end)

-- Nothing here reports the wrapped height back, so estimate it: a long line takes
-- more than one, and the scroll region is sized from what the label claims to be.
local function setText(text: string, hasThumb: boolean)
	body.Text = text
	local rows = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		rows += math.max(1, math.ceil(#line / WRAP_AT))
	end
	local top = hasThumb and 104 or 0
	body.Position = UDim2.new(0, 0, 0, top)
	body.Size = UDim2.new(1, -10, 0, rows * LINE_HEIGHT + 8)
	scroll.CanvasPosition = Vector2.new(0, 0)
end

-- Before both users, or clearMenu() resets a global and button() counts an upvalue.
local nextOrder = 0

local function clearMenu()
	nextOrder = 0
	for _, child in ipairs(menu:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
end

local function button(text, onClick)
	local b = Instance.new("TextButton")
	nextOrder += 1
	b.Name = ("Option%02d"):format(nextOrder)
	b.Size = UDim2.new(1, -8, 0, OPT_H)
	b.Position = UDim2.new(0, 0, 0, (nextOrder - 1) * (OPT_H + OPT_GAP))
	b.BackgroundColor3 = Theme.c.button
	b.TextColor3 = INK
	b.TextSize = Theme.t.body
	b.Text = text
	Theme.face(b)
	b.Parent = menu
	local c = Instance.new("UICorner")
	c.Parent = b
	b.Activated:Connect(onClick)
	return b
end

local function setMenu(items)
	clearMenu()
	for _, item in ipairs(items or {}) do
		-- `arg` carries which thing the button is about, so one action id ("buy") can
		-- serve a whole shelf.
		local id, arg = item.id, item.arg
		button(item.label, function()
			-- Whatever is in the box rides along, so one handler can serve a form.
			if current then current:FireServer(id, arg, field.Text) end
		end)
	end
	button("Goodbye", close)
	menu.CanvasPosition = Vector2.new(0, 0)
end

-- `input = { placeholder = ..., text = ... }` asks for something to be typed.
local function showInput(spec)
	if type(spec) ~= "table" then
		field.Visible = false
		field.Text = ""
		scroll.Size = UDim2.new(1, -EDGE * 2, 1, -BODY_INSET)
		return
	end
	field.Visible = true
	field.PlaceholderText = spec.placeholder or ""
	field.Text = spec.text or ""
	-- The box takes its room from the body, not from the menu. Moving the menu instead
	-- pushed it off the panel's bottom edge, where the panel clips it away.
	scroll.Size = UDim2.new(1, -EDGE * 2, 1, -BODY_INSET_FIELD)
end

local function showThumb(path)
	if path and path ~= "" then
		Pictures.show(thumb, path)
		thumb.Visible = true
		return true
	end
	thumb.Visible = false
	return false
end

local function bind(remote)
	remote.OnClientEvent:Connect(function(kind, payload)
		if kind == "open" then
			current = remote
			anchor = anchorFor(payload.npc)
			title.Text = payload.title or "Someone"
			showInput(nil)
			setText(payload.greeting or "", showThumb(nil))
			setMenu(payload.menu)
			screen.Enabled = true
			ContextActionService:BindAction(E_ACTION, onE, false, Enum.KeyCode.E)
		elseif kind == "say" then
			if current ~= remote then return end          -- another NPC is not our business
			showInput(payload.input)
			setText(table.concat(payload.lines or {}, "\n"), showThumb(payload.thumb))
			setMenu(payload.menu)
		elseif kind == "close" then
			-- The NPC has opened something else for you and has nothing more to say.
			-- Only if it is still their window: another desk's close is not ours to obey.
			if current == remote then close() end
		elseif kind == "update" then
			-- The chain data arrived after this window opened. Replace what is on
			-- screen, but only while it is open and only for whoever we are talking
			-- to: the only thing it can be showing is "give me a moment".
			if screen.Enabled and current == remote then
				setText(payload.greeting or body.Text, showThumb(nil))
				setMenu(payload.menu)
			end
		end
	end)
end

for _, name in ipairs({ "BankRemote", "ShopRemote", "TradeRemote", "RecordsRemote", "TailorRemote",
		"FunRemote" }) do
	bind(ReplicatedStorage:WaitForChild(name))
end

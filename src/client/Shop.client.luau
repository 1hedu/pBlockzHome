-- The shelf, as a shelf.
--
-- Everything Finch sells has a picture on the chain, and a list of names with buttons
-- under it wastes that. This is a grid of cards: the thumbnail the creator published,
-- the name, the price, and one line saying what you can do about it -- buy it, you
-- own it already, or you are not a big enough fish yet.
--
-- The dialog window next door is still where the talking happens. This only opens when
-- you ask to see the shelf, and it closes when you walk away from the stall, because a
-- shop that follows you around the square is worse than one you have to walk back to.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Pictures = require(ReplicatedStorage:WaitForChild("Pictures"))
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("ShopRemote")

local INK = Theme.c.ink
local DIM = Theme.c.dim
local PANEL = Theme.c.panel
local CARD = Theme.c.card
local TILE = Theme.c.tile
local ACCENT = Theme.c.accent
local BUY = Theme.c.good
local LOCKED = Theme.c.warn
local OWNED = Theme.c.muted
local CLOSE_DISTANCE = 16

local screen = Instance.new("ScreenGui")


-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "ShopShelf"
screen.Enabled = false
screen.ResetOnSpawn = false
screen.Parent = gui

-- The window is Theme's now: a three-band bevel with the blue gradient inside it, the
-- same frame every panel in the town gets. What comes back is the inside of it.
-- As much room as the window will give, down to the size it was drawn at. Not magnified:
-- the cards and their prices are the size they should be, there were simply only four of
-- them on screen. Everything in here is anchored to an edge or sized against the panel, so
-- the extra height goes to the shelf, which is where it is wanted.
local SHOP_W, SHOP_H = Theme.roomFor(980, 580)
local panel, shopWindow = Theme.window(screen,
	UDim2.new(0, SHOP_W, 0, SHOP_H), UDim2.new(0.5, -SHOP_W / 2, 0.5, -SHOP_H / 2))

-- Steps this window through its sizes.
Theme.scaleButton(screen, panel, UDim2.new(1, -70, 0, 20))

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.6, 0, 0, 46)
title.Position = UDim2.new(0, 20, 0, 14)
title.BackgroundTransparency = 1
title.TextColor3 = ACCENT
title.TextSize = Theme.t.title
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Finch  <Shop>"
Theme.face(title)
title.Parent = panel

-- Who you are and what you are holding, up in the corner where a shop puts it.
local standing = Instance.new("TextLabel")
standing.Size = UDim2.new(0.4, -94, 0, 46)   -- the size button has the corner
standing.Position = UDim2.new(0.6, 12, 0, 12)
standing.BackgroundTransparency = 1
standing.TextColor3 = DIM
standing.TextSize = Theme.t.small
standing.TextXAlignment = Enum.TextXAlignment.Right
standing.TextYAlignment = Enum.TextYAlignment.Top
standing.Text = ""
Theme.face(standing)
standing.Parent = panel

local note = Instance.new("TextLabel")
note.Size = UDim2.new(1, -36, 0, 22)
note.Position = UDim2.new(0, 20, 0, 62)
note.BackgroundTransparency = 1
note.TextColor3 = DIM
note.TextSize = Theme.t.small
note.TextXAlignment = Enum.TextXAlignment.Left
note.Text = ""
Theme.face(note)
note.Parent = panel

local shelf = Instance.new("ScrollingFrame")
shelf.Position = UDim2.new(0, 16, 0, 92)
shelf.Size = UDim2.new(1, -32, 1, -156)
shelf.BackgroundTransparency = 1
shelf.ScrollBarThickness = 8
shelf.ScrollBarImageColor3 = Theme.c.scrollbar
shelf.AutomaticCanvasSize = Enum.AutomaticSize.Y
shelf.CanvasSize = UDim2.new(0, 0, 0, 0)
shelf.Parent = panel
-- A list, one item to a row, the way the reference stacks its panels. A grid of tiles
-- reads well at 14-pixel text and badly at 32: the name is the thing you are scanning
-- for and in a narrow cell it is the first thing to be truncated away.
--
-- The rows are placed by hand rather than by a UIListLayout, because the layout cannot
-- put them in a stable order. Its default SortOrder is by Name, it breaks ties by walking
-- the children through a hash map, and every row here is a Frame with the same name -- so
-- the shelf came out in a different order every time it was rebuilt. Setting LayoutOrder
-- would fix the order but not the deeper point: the position each row wants is one
-- multiplication, and stating it is both shorter and exact.
local ROW_H, ROW_GAP = 116, 10

local footer = Instance.new("TextLabel")
footer.Size = UDim2.new(0.62, 0, 0, 26)
footer.Position = UDim2.new(0, 20, 1, -40)
footer.BackgroundTransparency = 1
footer.TextColor3 = DIM
footer.TextSize = Theme.t.small
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text = "Registered on chain by whoever made it. Taking one costs only the gas."
Theme.face(footer)
footer.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 168, 0, 50)
closeButton.Position = UDim2.new(1, -188, 1, -62)
closeButton.BackgroundColor3 = Theme.c.button
closeButton.TextColor3 = INK
closeButton.TextSize = Theme.t.body
closeButton.Text = "Close"
Theme.face(closeButton)
closeButton.Parent = panel
local closeCorner = Instance.new("UICorner")
closeCorner.Parent = closeButton

-- Declared before both users: a local declared after a function that assigns it is a
-- different variable, and clear() would have been resetting a global while card()
-- counted up an upvalue that never went back to zero.
local cardOrder = 0

local function clear()
	cardOrder = 0
	for _, child in ipairs(shelf:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local function card(item)
	local frame = Instance.new("Frame")
	-- Numbered so the rows read in order in the tree as well as on the screen.
	cardOrder += 1
	frame.Name = ("Row%03d"):format(cardOrder)
	frame.BackgroundColor3 = CARD
	frame.Size = UDim2.new(1, -12, 0, ROW_H)
	frame.Position = UDim2.new(0, 0, 0, (cardOrder - 1) * (ROW_H + ROW_GAP))
	frame.Parent = shelf
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	-- The picture, on its own tile so an item with no thumbnail still looks deliberate.
	local tile = Instance.new("Frame")
	tile.Size = UDim2.new(0, 100, 0, 100)
	tile.Position = UDim2.new(0, 8, 0, 8)
	tile.BackgroundColor3 = TILE
	tile.Parent = frame
	local tileCorner = Instance.new("UICorner")
	tileCorner.CornerRadius = UDim.new(0, 6)
	tileCorner.Parent = tile

	-- The same rarity border the character pane uses, so a thing looks like itself in
	-- both windows. Nothing else on the card says what rung it is on until you read
	-- the button underneath.
	local edge = Instance.new("UIStroke")
	edge.Thickness = 2
	edge.Color = Theme.rarityOf(item.tier)
	edge.Transparency = 0.2
	edge.Parent = tile

	if item.thumb and item.thumb ~= "" then
		local picture = Instance.new("ImageLabel")
		picture.Size = UDim2.new(0, 96, 0, 96)
		picture.Position = UDim2.new(0.5, -48, 0.5, -48)
		picture.BackgroundTransparency = 1
		Pictures.show(picture, item.thumb)
		picture.Parent = tile
	else
		local none = Instance.new("TextLabel")
		none.Size = UDim2.new(1, 0, 1, 0)
		none.BackgroundTransparency = 1
		none.TextColor3 = DIM
		none.TextSize = Theme.t.small
		none.Text = "no picture\non chain"
		Theme.face(none)
	none.Parent = tile
	end

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -420, 0, 40)
	name.Position = UDim2.new(0, 120, 0, 14)
	name.BackgroundTransparency = 1
	name.TextColor3 = INK
	name.TextSize = Theme.t.body
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = item.name
	Theme.face(name)
	name.Parent = frame

	-- What it takes to stand where this thing is, rather than what it costs. Nothing here
	-- costs anything: the ladder is holdings, and the price the maker published is still on
	-- chain and still not what this counter reads.
	local rung = Instance.new("TextLabel")
	rung.Size = UDim2.new(0, 300, 0, 34)
	rung.Position = UDim2.new(0, 120, 0, 60)
	rung.BackgroundTransparency = 1
	rung.TextColor3 = Theme.rarityOf(item.tier)
	rung.TextSize = Theme.t.body
	rung.TextXAlignment = Enum.TextXAlignment.Left
	rung.Text = ("%s%s"):format(item.tier_name or Theme.rarityName(item.tier),
		item.tier_pls ~= nil and ("  -  %s PLS held"):format(tostring(item.tier_pls)) or "")
	Theme.face(rung)
	rung.Parent = frame

	-- Which socket it takes. Worth saying on the shelf: taking a ninth cape when you
	-- can only ever wear one is a thing to know beforehand rather than after.
	local where = Instance.new("TextLabel")
	where.Size = UDim2.new(0, 380, 0, 34)
	where.Position = UDim2.new(1, -640, 0, 60)
	where.BackgroundTransparency = 1
	where.TextColor3 = Theme.rarityOf(item.tier)
	where.TextSize = Theme.t.small
	where.TextXAlignment = Enum.TextXAlignment.Right
	where.Text = (item.slot and item.slot ~= "") and Theme.slotLabel(item.slot) or ""
	Theme.face(where)
	where.Parent = frame

	-- One line at the bottom saying what you can do about it.
	local action = Instance.new("TextButton")
	action.Size = UDim2.new(0, 236, 0, 46)
	action.Position = UDim2.new(1, -244, 0.5, -23)
	action.TextColor3 = INK
	action.TextSize = Theme.t.body
	action.AutoButtonColor = false
	-- Buying is not equipping. The item clip is for the moment a thing goes ON you, which
	-- happens at the wardrobe and nowhere else; the shop hands it to your bag.
	action:SetAttribute("Sfx", "menu")
	Theme.face(action)
	action.Parent = frame
	local actionCorner = Instance.new("UICorner")
	actionCorner.Parent = action

	if item.owned then
		action.BackgroundColor3 = OWNED
		action.TextColor3 = DIM
		action.Text = "Yours already"
	elseif item.locked then
		action.BackgroundColor3 = LOCKED
		action.TextColor3 = Theme.c.warnInk
		action.Text = (item.tier_name or "?") .. " and up"
	elseif not item.can_buy then
		action.BackgroundColor3 = OWNED
		action.TextColor3 = DIM
		action.Text = "No key loaded"
	else
		action.BackgroundColor3 = BUY
		action.AutoButtonColor = true
		action.Text = "Take it"
		action.Activated:Connect(function()
			action.Text = "Asking..."
			action.BackgroundColor3 = OWNED
			action.AutoButtonColor = false
			remote:FireServer("buy", item.id)
		end)
	end
	return frame
end

local function close()
	screen.Enabled = false
end

closeButton.Activated:Connect(close)


-- Walking away shuts the shelf, the same as the dialog beside it.
RunService.Heartbeat:Connect(function()
	if not screen.Enabled then return end
	local map = workspace:FindFirstChild("Map")
	local npc = map and map:FindFirstChild("Shopkeeper")
	local torso = npc and npc:FindFirstChild("Torso")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not torso or not root then return end
	if (root.Position - torso.Position).Magnitude > CLOSE_DISTANCE then
		close()
	end
end)

remote.OnClientEvent:Connect(function(kind, payload)
	if kind ~= "shelf" then return end
	clear()
	local holder = payload.holder or {}
	local gas = (payload.gas ~= nil and payload.gas ~= "") and payload.gas or "?"
	-- No name means no rung: holding less than the bottom one costs. Saying "You are Common"
	-- there was the panel's half of a shelf that offered things the chain then refused.
	standing.Text = (holder.name ~= nil and holder.name ~= "")
		and ("You are %s\n%s PLS"):format(holder.name, gas)
		or ("Not on the ladder\n%s PLS"):format(gas)
	local locked = 0
	for _, item in ipairs(payload.items or {}) do
		if item.locked then locked += 1 end
	end
	if locked > 0 and holder.next then
		note.Text = ("%d of these want a bigger fish. Hold %s PLS to be %s -- nothing is taken from you to unlock it.")
			:format(locked, holder.needed or "?", holder.next)
	else
		note.Text = "Registered on chain by whoever made it."
	end
	for _, item in ipairs(payload.items or {}) do
		card(item)
	end
	shelf.CanvasPosition = Vector2.new(0, 0)
	Theme.takeOver(gui)
	screen.Enabled = true
end)

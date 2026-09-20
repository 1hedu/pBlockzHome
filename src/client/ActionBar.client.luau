-- The action bar: ten of your things, above the hearts, on the number keys.
--
-- Everything the bar does could already be done in the wardrobe -- it fires the same two
-- messages at the same server. What it buys is not having to stop: putting a torch away to
-- take out a spoon meant opening a panel, which disarms the spoon, over a fight. So the ten
-- squares sit on screen all the time and 1 through 0 put things on and take them off.
--
-- A HUD, not a panel. It says so with the `Hud` attribute, which is what stops
-- Weapons.client.luau counting it as a window and refusing to swing while it is up.
--
-- Which ten: the first ten of your inventory, and the order is yours. Drag one square onto
-- another and they swap; the server writes the order down and it is still there tomorrow (see
-- ActionBar.luau, which keeps it in a DataStore, because where you put your torch is not a fact the
-- chain needs an opinion about).
--
-- It still arrives full. A bar you have to set up before it is useful is a worse bar than one
-- that is already usable, so an untouched bar is what it always was: your things, in the
-- order the chain handed them over, and anything you buy afterwards lands on the end.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Carry = require(ReplicatedStorage:WaitForChild("Carry"))
local ModelPicture = require(ReplicatedStorage:WaitForChild("ModelPicture"))
local Pictures = require(ReplicatedStorage:WaitForChild("Pictures"))

local SLOTS = 10
local SIZE = 54
local GAP = 6
-- A third of the way down the gap it used to leave under itself: it sat 98 clear of the
-- bottom edge, which is more space than a screen wants to give away, and the hearts above it
-- were creeping into the middle. The hearts follow it down.
local BOTTOM = 65

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("WardrobeRemote")

local screen = Instance.new("ScreenGui")


-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "ActionBar"
screen.ResetOnSpawn = false
screen:SetAttribute("Hud", true)
screen.Parent = gui

local row = Instance.new("Frame")
row.Name = "Row"
row.BackgroundTransparency = 1
row.AnchorPoint = Vector2.new(0.5, 1)
row.Position = UDim2.new(0.5, 0, 1, -BOTTOM)
row.Size = UDim2.new(0, SLOTS * SIZE + (SLOTS - 1) * GAP, 0, SIZE)
row.Parent = screen

-- What a square is, said in words. Nobody remembers ten icons, and the bar is the one panel
-- with no room to write anything on it: the squares are 54 pixels and a name does not fit.
--
-- Above the bar rather than under the pointer, and the same shape the bag's tooltip is, since
-- it is telling you the same thing about the same object. Kept off the pointer for the bag's
-- reason too: a tooltip under the cursor takes the hover off the thing it is describing, and
-- you get a flicker you cannot click through.
local TIP_PAD, TIP_W = 10, 230

local tip = Instance.new("Frame")
tip.Name = "Tooltip"
tip.Size = UDim2.new(0, TIP_W, 0, 52)
tip.BackgroundColor3 = Theme.c.tile
tip.BorderSizePixel = 0
tip.Visible = false
tip.ZIndex = 50
tip.Parent = screen
Theme.corner(tip, 6)

local tipEdge = Instance.new("UIStroke")
tipEdge.Thickness = 1
tipEdge.Color = Theme.c.bevelLight
tipEdge.Transparency = 0.4
tipEdge.Parent = tip

local tipName = Instance.new("TextLabel")
tipName.Size = UDim2.new(1, -TIP_PAD * 2, 0, 22)
tipName.Position = UDim2.new(0, TIP_PAD, 0, 5)
tipName.BackgroundTransparency = 1
tipName.TextColor3 = Theme.c.ink
tipName.TextSize = Theme.t.body
tipName.TextXAlignment = Enum.TextXAlignment.Left
tipName.TextTruncate = Enum.TextTruncate.AtEnd
tipName.ZIndex = 51
tipName.Text = ""
Theme.face(tipName)
tipName.Parent = tip

local tipSub = Instance.new("TextLabel")
tipSub.Size = UDim2.new(1, -TIP_PAD * 2, 0, 18)
tipSub.Position = UDim2.new(0, TIP_PAD, 0, 28)
tipSub.BackgroundTransparency = 1
tipSub.TextColor3 = Theme.c.dim
tipSub.TextSize = Theme.t.small
tipSub.TextXAlignment = Enum.TextXAlignment.Left
tipSub.TextTruncate = Enum.TextTruncate.AtEnd
tipSub.ZIndex = 51
tipSub.Text = ""
Theme.face(tipSub)
tipSub.Parent = tip

--- Puts the tooltip over a square, or takes it away.
---
--- Placed before it is shown: a tooltip visible for one frame in the last square's place is a
--- tooltip that jumps across the screen every time you move along the bar.
local function describe(item, button)
	if not item then
		tip.Visible = false
		return
	end
	tipName.Text = item.name
	tipName.TextColor3 = Theme.rarityOf(item.tier)
	local bits = { Theme.slotLabel(item.slot) }
	if item.worn then table.insert(bits, "worn") end
	-- What THIS click will do, which is not the same question once it is on: a worn thing
	-- with a trick does the trick, a worn thing without one comes off.
	if item.acts then table.insert(bits, "click: " .. item.acts)
	elseif item.worn then table.insert(bits, "click: take off")
	end
	tipSub.Text = table.concat(bits, "   .   ")
	local at = button.AbsolutePosition
	local x = at.X + button.AbsoluteSize.X / 2 - TIP_W / 2
	local view = screen.AbsoluteSize
	if view.X > 0 then x = math.clamp(x, 6, view.X - TIP_W - 6) end
	tip.Position = UDim2.new(0, x, 0, at.Y - 52 - 8)
	tip.Visible = true
end

-- 1 through 9 and then 0, which is where the tenth has lived since long before this.
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
	Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight,
	Enum.KeyCode.Nine, Enum.KeyCode.Zero }
local LABELS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }

local owned = {}      -- everything the chain says you have, by model name
local bar = {}        -- the ten squares: a model name, or "" for an empty one
local squares = {}
local dragging = nil  -- the square a press began on, while the button is still down
local over = nil      -- the square the pointer is on, for showing where a drag would land
local redraw          -- defined below; a drag draws the new arrangement before it sends it

--- What is in a square, looked up in what you own.
---
--- A square holds a NAME. Everything else about the thing -- its picture, its rung, whether
--- it is on you this second -- comes out of the inventory, so a bar cannot drift out of step
--- with what you actually have: sell something and its square is simply empty.
local function inSlot(i)
	local name = bar[i]
	return name and name ~= "" and owned[name] or nil
end

--- Which square the pointer is over, or nil.
---
--- Worked out from the pointer rather than from which button reports the release: a press is
--- routed to the control it started on until it is let go, so the square you dropped onto
--- never hears about it.
local function slotAt(where)
	for i, square in ipairs(squares) do
		local at, size = square.button.AbsolutePosition, square.button.AbsoluteSize
		if where.X >= at.X and where.X <= at.X + size.X
			and where.Y >= at.Y and where.Y <= at.Y + size.Y then
			return i
		end
	end
	return nil
end

--- Finishes a drag: the thing that was picked up changes places with whatever is where it
--- was dropped.
---
--- Swapped, not inserted. A bar is ten fixed squares and you are moving a thing between two
--- of them; shuffling the other eight along because something passed over them is how a
--- layout somebody arranged comes apart.
---
--- Drawn here at once and then sent. The server is the one that remembers, and its answer
--- will land a moment later saying the same thing -- but a bar that waits for a round trip
--- before showing you what you just did feels broken even when it is not.
local function send()
	local out = {}
	for i = 1, SLOTS do out[i] = bar[i] or "" end
	remote:FireServer("arrange", out)
end

--- Puts what was picked up wherever it was let go.
---
--- Three endings. Onto another square, and the two swap -- swapped rather than shuffled,
--- because a bar is ten fixed squares and moving one thing should not push the other nine
--- along. Onto nothing at all, and the square is emptied, which is how you take a thing off
--- a bar. Back where it started, and nothing happened, which is a click and is handled
--- elsewhere.
---
--- Drawn at once and then sent. The server remembers it and will say the same thing back a
--- moment later, but a bar that waits for a round trip before showing what you just did feels
--- broken even when it is not.
local function drop(from)
	-- The Mouse, not UserInputService:GetMouseLocation. The latter is the position of the
	-- last event the runtime saw, and one that came through a GuiObject used to arrive in
	-- that object's own coordinates -- so it answered with a point inside the last thing
	-- clicked. The engine hands those over in screen space now; this is the one that was
	-- right either way.
	local mouse = Players.LocalPlayer:GetMouse()
	local to = slotAt(Vector2.new(mouse.X, mouse.Y))
	if to == from then return end
	if to == nil then
		bar[from] = ""
	else
		bar[from], bar[to] = bar[to] or "", bar[from] or ""
	end
	redraw()
	send()
end

--- Something carried in from somewhere else -- the bag -- put down on a square.
local function take(model, x, y)
	local to = slotAt(Vector2.new(x, y))
	if to == nil or not model or model == "" then return end
	-- One square each. Dropping a thing that is already on the bar moves it rather than
	-- copying it, because two squares that do the same thing is a wasted square.
	for i = 1, SLOTS do
		if bar[i] == model then bar[i] = "" end
	end
	bar[to] = model
	redraw()
	send()
end

--- A square, clicked.
---
--- Three outcomes, not two. Off, it goes on. On and it can DO something, it does it. On and
--- it cannot, it comes off.
---
--- Taking a thing off was the only meaning a second click had, which is right for a hat and
--- wrong for the one thing on the bar with a trick in it: the Familiar is out, you click him
--- to hear him, and instead he goes away. The bag has had both gestures all along -- right
--- to wear, left to use -- and the bar has one, so the one it has should mean the more
--- useful of the two once the thing is already on.
---
--- Which leaves no click that takes the Familiar off the bar. The bag does that, which is
--- where putting things on and taking them off lives anyway.
---
--- `acts` is the server's word for it -- ItemActions.of, sent down with the item -- so the
--- bar never holds a list of what has a trick and cannot disagree with the bag about it.
local function use(i)
	local item = inSlot(i)
	if not item then return end
	if item.worn and item.acts then
		remote:FireServer("act", item.model)
		return
	end
	remote:FireServer(item.worn and "remove" or "wear", item.model)
end

for i = 1, SLOTS do
	local button = Instance.new("ImageButton")
	button.Name = "Slot" .. i
	button.BackgroundColor3 = Theme.c.tile
	button.BackgroundTransparency = 0.25
	button.AutoButtonColor = false
	button.Image = ""
	button.Size = UDim2.new(0, SIZE, 0, SIZE)
	button.Position = UDim2.new(0, (i - 1) * (SIZE + GAP), 0, 0)
	button.Parent = row
	Theme.corner(button, 5)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Theme.c.muted
	stroke.Transparency = 0.35
	stroke.Parent = button

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, -8, 1, -8)
	icon.Position = UDim2.new(0, 4, 0, 4)
	icon.Image = ""
	icon.Parent = button

	-- The item's name, for anything published before there were thumbnails.
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -6, 1, -14)
	name.Position = UDim2.new(0, 3, 0, 2)
	name.TextColor3 = Theme.c.faint
	name.TextSize = Theme.t.small
	name.TextWrapped = true
	name.Visible = false
	Theme.face(name)
	name.Parent = button

	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.BackgroundTransparency = 1
	key.Size = UDim2.new(1, -5, 0, 14)
	key.Position = UDim2.new(0, 0, 1, -15)
	key.TextColor3 = Theme.c.dim
	key.TextSize = Theme.t.small
	key.TextXAlignment = Enum.TextXAlignment.Right
	key.Text = LABELS[i]
	Theme.face(key)
	key.Parent = button

	-- A click uses it; a drag moves it. The two never collide, because a Click only happens
	-- when the release lands on the square the press began on -- so a press that finishes
	-- somewhere else is a drag and nothing else, and one that finishes at home is a click and
	-- nothing else.
	button.Activated:Connect(function() use(i) end)
	-- While something is held, the square under the pointer says it will take it.
	button.MouseEnter:Connect(function()
		over = i
		describe(inSlot(i), button)
		if dragging then redraw() end
	end)
	button.MouseLeave:Connect(function()
		if over == i then over = nil end
		describe(nil, button)
		if dragging then redraw() end
	end)
	button.MouseButton1Down:Connect(function()
		local item = inSlot(i)
		dragging = item and i or nil
		if dragging then
			Carry.lift(item.model, item.thumb, "bar")
			redraw()
		end
	end)
	button.MouseButton1Up:Connect(function()
		local from = dragging
		dragging = nil
		if from then drop(from) end
		redraw()
	end)
	-- And a release anywhere at all ends the carry, so the icon does not stay stuck to the
	-- pointer when a drag finishes over the world.
	squares[i] = { button = button, icon = icon, name = name, stroke = stroke, key = key }
end

function redraw()
	for i, square in ipairs(squares) do
		local item = inSlot(i)
		Pictures.show(square.icon, item and item.thumb or "")
		-- No thumbnail, but a model the town built (the fish, the rod): the model is the picture.
		-- Only redrawn when the square's thing changes, since each one is a little world.
		local model = item and (item.thumb == nil or item.thumb == "") and item.model or nil
		if square.drawn ~= model then
			square.drawn = model
			if not (model and ModelPicture.show(square.icon, model)) then
				ModelPicture.clear(square.icon)
				square.drawn = nil
			end
		end
		square.icon.Visible = item ~= nil and ((item.thumb ~= nil and item.thumb ~= "") or square.drawn ~= nil)
		square.name.Visible = item ~= nil and not square.icon.Visible
		square.name.Text = item and item.name or ""
		-- Worn is the loud state, because that is the one you are looking for mid-fight:
		-- which square is the thing currently in your hand. Green rather than the panel
		-- white it started as -- white is what an ordinary item's own rarity ring already
		-- is, so the one that mattered was the one that stood out least.
		square.stroke.Color = item and (item.worn and Theme.c.on or Theme.rarityOf(item.tier))
			or Theme.c.muted
		square.stroke.Transparency = item and (item.worn and 0 or 0.35) or 0.7
		square.button.BackgroundTransparency = item and 0.15 or 0.45
		-- Being moved. A drag with nothing to look at is a drag you cannot tell you have
		-- started: the one you picked up goes faint where it was, and whichever square the
		-- pointer is over lights up to say that is where it would land.
		if dragging == i then
			square.icon.ImageTransparency = 0.6
			square.button.BackgroundTransparency = 0.55
		else
			square.icon.ImageTransparency = 0
		end
		if dragging and over == i and over ~= dragging then
			square.stroke.Color = Theme.c.accent
			square.stroke.Transparency = 0
		end
		square.key.TextColor3 = item and Theme.c.ink or Theme.c.faint
		-- The item clip is for putting something on and nothing else. The bar equips on
		-- left-click the way it always has, so which clip a square wants depends on what is
		-- in it -- and an empty square is not a button that did anything.
		--
		-- A worn thing with a trick in it makes its OWN noise, so the square makes none.
		--
		-- Both of the bar's clips are the sound of a thing being moved: "item" is putting
		-- something on and "menu" is taking it off. Neither is true of a square that is about
		-- to ask the Familiar to speak, and "item" -- which this had first -- is the equip
		-- sound exactly, so pressing him played the sound of equipping something that was
		-- already equipped, underneath his voice. The trick is the feedback.
		local clip = "none"
		if item then
			if item.worn and item.acts then clip = "none"
			elseif item.worn then clip = "menu"
			else clip = "item" end
		end
		square.button:SetAttribute("Sfx", clip)
	end
end

remote.OnClientEvent:Connect(function(what, list, _standing, slots)
	if what ~= "items" or type(list) ~= "table" then return end
	owned = {}
	for _, item in ipairs(list) do owned[item.model] = item end
	if type(slots) == "table" then
		bar = {}
		for i = 1, SLOTS do bar[i] = slots[i] or "" end
	end
	redraw()
end)

-- Something let go over the bar, carried in from the bag. Fires for every drop anywhere, so
-- a release that landed somewhere else simply finds no square and does nothing.
Carry.dropped.Event:Connect(function(model, x, y, from)
	-- Its own drags are settled in the square's own handler, which swaps rather than places.
	if from == "bar" or not model then return end
	if slotAt(Vector2.new(x, y)) then
		take(model, x, y)
		Carry.claim()
	end
end)

-- Ask once. The wardrobe pushes the list when it changes and when the chain reports in, but
-- neither has necessarily happened by the time this bar exists, and a bar that stays empty
-- until you open a panel you were trying to avoid opening is no use at all.
task.spawn(function()
	for _ = 1, 8 do
		remote:FireServer("list")
		-- Stops as soon as anything has arrived. `owned` is keyed by name, so # on it is
		-- always nought -- which is the bug this line used to have with the old list, and
		-- would have had again.
		if next(owned) ~= nil then return end
		task.wait(2)
	end
end)

ContextActionService:BindAction("ActionBar", function(_, state, input)
	if state ~= Enum.UserInputState.Begin then return end
	-- Not while somebody is typing. The chat box and the bank's address field both take
	-- digits, and a 5 that puts a hat on instead of going into the amount is a bad trade.
	if UserInputService:GetFocusedTextBox() then return end
	for i, code in ipairs(KEYS) do
		if input.KeyCode == code then
			use(i)
			return Enum.ContextActionResult.Sink
		end
	end
	return Enum.ContextActionResult.Pass
end, false, table.unpack(KEYS))

redraw()

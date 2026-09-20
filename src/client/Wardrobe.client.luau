-- The character pane: a paper doll with a socket per body slot, and your bags below it.
--
-- The old version was a flat list of everything you own with a Wear button on each
-- row, which was fine at three items and useless at ten capes -- nothing in it said
-- that only one of them could be on at a time. Sockets say it: an empty one is a
-- question, a full one is an answer, and a slot only ever holds one thing.
--
-- Borders are the rung the shop gated the item on, collapsed to the five colours
-- everybody already reads without being told. The server decides what is in here and
-- whether a request is honoured; this panel only asks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Carry = require(ReplicatedStorage:WaitForChild("Carry"))
local ModelPicture = require(ReplicatedStorage:WaitForChild("ModelPicture"))
local Fish = require(ReplicatedStorage:WaitForChild("Fish"))
local Pictures = require(ReplicatedStorage:WaitForChild("Pictures"))
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("WardrobeRemote")
local showRemote = ReplicatedStorage:WaitForChild("ShowcaseRemote")
local mouse = player:GetMouse()

-- Sized to fit the shortest window anyone is likely to use, because it cannot be resized
-- later. GuiObject geometry in this runtime is worked out once, when the instance is
-- built: writing Size afterwards sets the property -- it reads back changed -- and
-- AbsoluteSize never moves, this frame or the next. So there is no fitting the panel to
-- the window after the fact; 700 was chosen against a full-screen client and put the title
-- off the top of anything shorter, since the panel is centred.
--
-- The bag is measured off H and scrolls, so it absorbs the difference.
-- Brought in. It was widened on a guess, and since the right column is measured from the
-- right edge, widening it was what pushed that column away from everything else.
--
-- So the width came down and nothing else moved: the left column is where it always was,
-- 18 in from the left, and the right one follows the edge in as it always did. The doll
-- goes in the middle of what is between them.
local W, H = 400, 700
local SOCKET = 54          -- a slot on the doll
local COL_X = 18                        -- the left column, unchanged
local COL_X2 = W - 18 - SOCKET          -- ... and the right, which comes in with the edge
local DOLL_W = COL_X2 - (COL_X + SOCKET) - 36       -- what is left between them
local CELL = 56            -- a square in the bag
local COL_Y, COL_STEP = 88, 62
local HAND_Y = 340         -- the weapon row, below both columns

local screen = Instance.new("ScreenGui")

-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "Wardrobe"
screen.Enabled = false
screen.ResetOnSpawn = false
screen.Parent = gui

local panel, window = Theme.window(screen,
	UDim2.new(0, W, 0, H), UDim2.new(0.5, -W / 2, 0.5, -H / 2))
panel.Name = "Panel"


-- Steps this window through its sizes.
Theme.scaleButton(screen, panel, UDim2.new(0, 18, 1, -28))

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 160, 0, 26)      -- and no wider: the rank sits beside it
title.Position = UDim2.new(0, 18, 0, 14)
title.BackgroundTransparency = 1
title.TextColor3 = Theme.c.accent
title.TextSize = Theme.t.title
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Character"
Theme.face(title)
title.Parent = panel

local rank = Instance.new("TextLabel")
rank.Size = UDim2.new(0, 190, 0, 26)
rank.Position = UDim2.new(1, -208, 0, 14)
rank.BackgroundTransparency = 1
rank.TextColor3 = Theme.c.dim
rank.TextSize = Theme.t.small
rank.TextXAlignment = Enum.TextXAlignment.Right
rank.Text = ""
Theme.face(rank)
rank.Parent = panel

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -36, 0, 16)
hint.Position = UDim2.new(0, 18, 0, 450)   -- between the save row and the bags
hint.BackgroundTransparency = 1
hint.TextColor3 = Theme.c.faint
hint.TextSize = Theme.t.small
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "Click to wear, right-click for more. I closes this."
Theme.face(hint)
hint.Parent = panel

-- ---- the doll -----------------------------------------------------------------------

-- Your name and how much of you is dressed, over the doll.
--
-- There was a stand-in for a character model here, 396 wide and written when the panel was
-- 720 -- so once the panel came in it ran off the side and printed itself across the socket
-- column. The doll is the thing it was waiting for, so it is gone and this is its caption.
local who = Instance.new("TextLabel")
who.Size = UDim2.new(1, -36, 0, 24)
who.Position = UDim2.new(0, 18, 0, 42)
who.BackgroundTransparency = 1
who.TextColor3 = Theme.c.ink
who.TextSize = Theme.t.body
who.Text = player.Name
who.TextXAlignment = Enum.TextXAlignment.Center
Theme.face(who)
who.Parent = panel

local dressed = Instance.new("TextLabel")
dressed.Size = UDim2.new(1, -36, 0, 20)
dressed.Position = UDim2.new(0, 18, 0, 66)
dressed.BackgroundTransparency = 1
dressed.TextColor3 = Theme.c.dim
dressed.TextSize = Theme.t.small
dressed.Text = ""
dressed.TextXAlignment = Enum.TextXAlignment.Center
Theme.face(dressed)
dressed.Parent = panel

-- ---- the tooltip ---------------------------------------------------------------------
-- What you are hovering, beside the pointer, the way bags have worked since bags.
--
-- It lives on the ScreenGui rather than the panel so it draws over everything, and it is
-- offset down and right of the cursor rather than under it. That is not cosmetic: a Frame
-- takes the pointer in this renderer, so a tooltip beneath the cursor would steal the
-- hover from the cell it is describing -- the cell reports a leave, this hides, the cell
-- reports an enter, and you get a flicker you cannot click through. Kept off the pointer,
-- it cannot happen.
local TIP_PAD, TIP_W = 10, 300

local tip = Instance.new("Frame")
tip.Name = "Tooltip"
tip.Size = UDim2.new(0, TIP_W, 0, 58)
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
tipName.Position = UDim2.new(0, TIP_PAD, 0, 6)
tipName.BackgroundTransparency = 1
tipName.TextColor3 = Theme.c.ink
tipName.TextSize = Theme.t.body
tipName.TextXAlignment = Enum.TextXAlignment.Left
-- The whole name, however long: wrapped rather than cut, and the tip grows to fit it below.
tipName.TextWrapped = true
tipName.ZIndex = 51
tipName.Text = ""
Theme.face(tipName)
tipName.Parent = tip

local tipSub = Instance.new("TextLabel")
tipSub.Size = UDim2.new(1, -TIP_PAD * 2, 0, 18)
tipSub.Position = UDim2.new(0, TIP_PAD, 0, 30)
tipSub.BackgroundTransparency = 1
tipSub.TextColor3 = Theme.c.dim
tipSub.TextSize = Theme.t.small
tipSub.TextXAlignment = Enum.TextXAlignment.Left
tipSub.TextTruncate = Enum.TextTruncate.AtEnd
tipSub.ZIndex = 51
tipSub.Text = ""
Theme.face(tipSub)
tipSub.Parent = tip

-- Tall enough for the name. TextBounds is the engine's measurement of the text in its font,
-- wrapped to the label's width, and it lands a frame after the text is set -- so the tip is
-- laid out again when it does, and placed again, since where it may sit depends on its height.
local tipAnchor = nil
local place
local function fit()
	local h = math.max(22, tipName.TextBounds.Y)
	tipName.Size = UDim2.new(1, -TIP_PAD * 2, 0, h)
	tipSub.Position = UDim2.new(0, TIP_PAD, 0, 8 + h)
	tip.Size = UDim2.new(0, TIP_W, 0, 8 + h + 18 + 10)
	if place then place(tipAnchor) end
end
tipName:GetPropertyChangedSignal("TextBounds"):Connect(fit)

-- Beside the thing it is describing, not under the pointer.
--
-- Following the pointer meant writing Position every frame, and a script's write here sets
-- the whole GUI dirty: the next sync restyles every GuiObject and re-sorts every parent's
-- children. With this panel open that is the doll, the bag, every stroke and icon and
-- label, and fourteen gradient bands per window -- all of it, every frame, while you read
-- one line of text. It was also asking a pointer that goes stale over a panel, because
-- motion the buttons consume never reaches the runtime.
--
-- An anchor's own rect is a thing the renderer always has to hand. To its right, or its
-- left when there is no room, and lifted back on screen if it would fall off the bottom.
place = function(anchor)
	if not anchor then return end
	tipAnchor = anchor
	local at = anchor.AbsolutePosition
	local size = anchor.AbsoluteSize
	local view = screen.AbsoluteSize
	local x = at.X + size.X + 8
	if view.X > 0 and x + TIP_W > view.X - 8 then x = at.X - TIP_W - 8 end
	local y = at.Y
	if view.Y > 0 and y + tip.AbsoluteSize.Y > view.Y - 8 then y = view.Y - tip.AbsoluteSize.Y - 8 end
	tip.Position = UDim2.new(0, math.max(x, 4), 0, math.max(y, 4))
end

--- Whether the menu gesture is being made rather than the equip one.
---
--- Right-click puts things on and takes them off, which is what a right-click in a bag means
--- nearly everywhere. What used to live there -- show to someone, destroy -- moves one
--- modifier along rather than being taken away.
local function menuing()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function describe(item, slotLabel, anchor)
	if not item then
		if slotLabel then
			tipName.Text = slotLabel .. " -- empty"
			tipName.TextColor3 = Theme.c.faint
			tipSub.Text = "Nothing you own goes here yet."
			place(anchor)
			tip.Visible = true
		else
			tip.Visible = false
		end
		return
	end
	tipName.Text = item.name
	tipName.TextColor3 = Theme.rarityOf(item.tier)
	local bits = { Theme.slotLabel(item.slot) }
	if item.tier_name and item.tier_name ~= "" then table.insert(bits, item.tier_name) end
	table.insert(bits, item.worn and "worn" or "in your bags")
	-- What the two gestures do, on the thing you are pointing at. Right-click is not a
	-- gesture anybody discovers by accident, and an item with a trick of its own is worth
	-- nothing at all if nobody knows it has one.
	if item.acts then table.insert(bits, "click: " .. item.acts) end
	table.insert(bits, item.worn and "right-click: take off" or "right-click: wear")
	tipSub.Text = table.concat(bits, "   .   ")
	-- Before it is shown, not after: a tooltip that is visible for one frame in the wrong
	-- place is a tooltip that flickers across the screen every time you point at something.
	place(anchor)
	tip.Visible = true
end

-- ---- keeping what you are wearing ------------------------------------------------------
-- On chain, so the next body puts back what you chose rather than working it out again --
-- the first thing it finds for each slot, in whatever order the registry hands the ids
-- over. Own two things for one hand and the higher id wins, whichever one you wanted.
--
-- In the row the detail strip used to hold, at the size the rest of the town's buttons
-- are. The line beside it is for anything the window needs to say back.
local SAVE_LABEL = "Save outfit"
local saveButton = Theme.button(panel, SAVE_LABEL)
saveButton.Size = UDim2.new(0, 200, 0, 34)
saveButton.Position = UDim2.new(1, -218, 0, 414)
saveButton:SetAttribute("Sfx", "menu")
saveButton.Activated:Connect(function()
	saveButton.Text = "Saving..."
	remote:FireServer("save")
end)

local say = Instance.new("TextLabel")
say.Size = UDim2.new(1, -254, 0, 20)
say.Position = UDim2.new(0, 18, 0, 421)
say.BackgroundTransparency = 1
say.TextColor3 = Theme.c.faint
say.TextSize = Theme.t.small
say.TextXAlignment = Enum.TextXAlignment.Left
say.TextTruncate = Enum.TextTruncate.AtEnd
say.Text = ""
Theme.face(say)
say.Parent = panel

-- ---- showing somebody --------------------------------------------------------------
-- Right-click a thing, then click a person. The block used to shout its hash over your
-- head at everybody; this is the other way round -- you choose the thing and you choose
-- who sees it, and it opens on their screen rather than hanging above yours.

local armed = nil          -- the item waiting for somebody to be clicked

local function disarm()
	armed = nil
	say.Text = ""
	say.TextColor3 = Theme.c.faint
	describe(nil)
end

local function arm(item)
	if armed and armed.model == item.model then
		disarm()
		return
	end
	armed = item
	say.Text = ("Showing %s -- now click somebody. Right-click it again to put it away."):format(item.name)
	say.TextColor3 = Theme.c.accent
end

-- ---- what you can do to a thing ---------------------------------------------------------
-- Two things, so a menu. It is built once and moved, rather than made and destroyed on
-- every click: the panel is rebuilt on every chain refresh and a menu parented into it
-- would go with it, halfway through being read.
-- Laid out from the top and measured, rather than four positions and a height typed in.
-- Which rows are in it depends on the item -- only an Engram can be shown to anybody -- so a
-- fixed height is either too tall for most things or too short for the one that has
-- everything, and it was the latter: the Cancel sat on the window's own bottom edge.
local MENU_W = 196
local MENU_TOP = 6            -- above the name
local MENU_ROW = 26           -- a button
local MENU_GAP = 4
local MENU_TITLE = 22
local MENU_BOTTOM = 8
local menuPanel, menuWindow = Theme.window(screen, UDim2.new(0, MENU_W, 0, 120))
local menuHeight = 120
menuWindow.Visible = false
menuWindow.ZIndex = 60          -- over the tooltip, which is 50

local menuFor = nil             -- the item the menu is open about
local openMenu                  -- declared before the closures that call it

local function closeMenu()
	menuWindow.Visible = false
	menuFor = nil
end

local menuTitle = Instance.new("TextLabel")
menuTitle.Size = UDim2.new(1, -16, 0, 20)
menuTitle.Position = UDim2.new(0, 8, 0, 6)
menuTitle.BackgroundTransparency = 1
menuTitle.TextColor3 = Theme.c.faint
menuTitle.TextSize = Theme.t.small
menuTitle.TextXAlignment = Enum.TextXAlignment.Left
menuTitle.TextTruncate = Enum.TextTruncate.AtEnd
menuTitle.Text = ""
Theme.face(menuTitle)
menuTitle.Parent = menuPanel

local function menuButton(label, colour)
	local b = Theme.button(menuPanel, label, colour)
	b.Size = UDim2.new(1, -16, 0, MENU_ROW)
	b.TextSize = Theme.t.small
	b:SetAttribute("Sfx", "menu")
	return b
end

local showOption = menuButton("Show to someone")
local destroyOption = menuButton("Destroy", Theme.c.danger)
local cancelOption = menuButton("Cancel")
cancelOption.Activated:Connect(closeMenu)

--- Stacks whichever rows this item has and sizes the window to them.
local function layOutMenu(item)
	-- Only an Engram. It IS a link, and showing one hands the link over so they can go and
	-- read the page themselves; everything else in the bag is a thing you are wearing, which
	-- whoever you are standing with can already see. The server says which is which.
	showOption.Visible = item ~= nil and item.shows == true
	local y = MENU_TOP + MENU_TITLE
	for _, row in ipairs({ showOption, destroyOption, cancelOption }) do
		if row.Visible then
			row.Position = UDim2.new(0, 8, 0, y)
			y += MENU_ROW + MENU_GAP
		end
	end
	menuHeight = y - MENU_GAP + MENU_BOTTOM
	menuWindow.Size = UDim2.new(0, MENU_W, 0, menuHeight)
end

-- Opened at the pointer, and pulled back on to the screen if it would hang off the
-- bottom or the right. Placed before it is shown, for the same reason the tooltip is: a
-- frame spent in the wrong place is a frame of it jumping across the screen.
function openMenu(item, anchor)
	menuFor = item
	menuTitle.Text = item.name
	layOutMenu(item)
	-- Off the button, for the same reason the tooltip is: the pointer's position goes
	-- stale the moment a control consumes the motion, and a menu is worse than a tooltip
	-- when it opens in the wrong corner.
	local at = anchor and anchor.AbsolutePosition or Vector2.new(0, 0)
	local size = anchor and anchor.AbsoluteSize or Vector2.new(0, 0)
	local view = screen.AbsoluteSize
	local x = at.X + size.X + 6
	if view.X > 0 and x + MENU_W > view.X - 8 then x = at.X - MENU_W - 6 end
	local y = at.Y
	if view.Y > 0 and y + menuHeight > view.Y - 8 then y = view.Y - menuHeight - 8 end
	menuWindow.Position = UDim2.new(0, math.max(x, 4), 0, math.max(y, 4))
	menuWindow.Visible = true
	tip.Visible = false          -- one thing about a thing at a time
end

showOption.Activated:Connect(function()
	local item = menuFor
	closeMenu()
	if item then arm(item) end
end)

-- Twice on purpose. Here, because this menu sits under the pointer and a mis-click must
-- not spend anything; and again in the wallet's own prompt, because it is a transaction
-- and every transaction here asks. This one cannot be undone by any means at all -- the
-- contract has no way to give it back and nobody has a key that could.
local confirming = nil

destroyOption.Activated:Connect(function()
	local item = menuFor
	if not item then return end
	if confirming ~= item.model then
		confirming = item.model
		destroyOption.Text = "Destroy - are you sure?"
		return
	end
	confirming = nil
	destroyOption.Text = "Destroy"
	closeMenu()
	say.Text = ("Destroying %s..."):format(item.name)
	say.TextColor3 = Theme.c.danger
	remote:FireServer("destroy", item.model)
end)

local function resetDestroy()
	confirming = nil
	destroyOption.Text = "Destroy"
end
cancelOption.Activated:Connect(resetDestroy)
showOption.Activated:Connect(resetDestroy)

-- Walk up from whatever the pointer hit until something is a player's body: the click
-- lands on an arm or a hat, not on the character.
local function personAt(part)
	local node = part
	while node do
		local who = Players:GetPlayerFromCharacter(node)
		if who then return who end
		node = node.Parent
	end
	return nil
end

mouse.Button1Down:Connect(function()
	if not armed then return end
	local target = personAt(mouse.Target)
	if not target or target == player then return end
	showRemote:FireServer("show", armed.id, target.Name)
	disarm()
end)

-- ---- sockets ------------------------------------------------------------------------

local sockets = {}          -- slot key -> the socket standing for it

local function makeSocket(def, x, y)
	local button = Instance.new("ImageButton")
	button.Size = UDim2.new(0, SOCKET, 0, SOCKET)
	button.Position = UDim2.new(0, x, 0, y)
	button.BackgroundColor3 = Theme.c.tile
	button.AutoButtonColor = false
	button.Image = ""
	button.Parent = panel
	Theme.corner(button, 6)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Theme.c.muted
	stroke.Transparency = 0.35
	stroke.Parent = button

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, -8, 1, -8)
	icon.Position = UDim2.new(0, 4, 0, 4)
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.Parent = button

	-- The slot's own name, showing only while the socket is empty.
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -4, 1, 0)
	label.Position = UDim2.new(0, 2, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.c.faint
	label.TextSize = Theme.t.small
	label.TextWrapped = true
	label.Text = def.label
	Theme.face(label)
	label.Parent = button

	local entry = { button = button, icon = icon, stroke = stroke, label = label, item = nil }
	button.MouseEnter:Connect(function()
		stroke.Transparency = 0
		describe(entry.item, def.label, button)
	end)
	button.MouseLeave:Connect(function()
		stroke.Transparency = entry.item and 0.1 or 0.35
		tip.Visible = false
	end)
	-- The same three gestures the bag has. A socket only ever holds something you are
	-- wearing, so its right-click is always the taking off, and its left-click is the same
	-- trick the tile in the bag does -- the Familiar is on your shoulder either way.
	-- Picked up on the press, so a worn thing can be dragged off you: let go over nothing and
	-- it comes off. Let go over the action bar and it goes on the bar, still worn.
	button.MouseButton1Down:Connect(function()
		if entry.item then Carry.lift(entry.item.model, entry.item.thumb, "socket") end
	end)
	button.Activated:Connect(function()
		if entry.item and entry.item.acts then remote:FireServer("act", entry.item.model) end
	end)
	button.MouseButton2Click:Connect(function()
		if not entry.item then return end
		if menuing() then
			openMenu(entry.item, button)
			return
		end
		remote:FireServer("remove", entry.item.model)
	end)
	button:SetAttribute("Sfx", "none")
	button:SetAttribute("SfxRight", "menu")
	button:SetAttribute("SfxShiftRight", "menu")
	entry.def = def
	sockets[def.key] = entry
	return entry
end

--- Which socket a point is over, if any.
local function socketAt(x, y)
	for _, socket in pairs(sockets) do
		local at, size = socket.button.AbsolutePosition, socket.button.AbsoluteSize
		if x >= at.X and x <= at.X + size.X and y >= at.Y and y <= at.Y + size.Y then
			return socket
		end
	end
	return nil
end

-- Dropped on a socket: put it on. Which socket does not matter -- the server decides where a
-- thing goes from what the thing is, and a hat dropped on the shoe square is still a hat.
Carry.dropped.Event:Connect(function(model, x, y)
	if not model or not screen.Enabled then return end
	if socketAt(x, y) then
		remote:FireServer("wear", model)
		Carry.claim()
	end
end)

-- Dropped on nothing at all, having been dragged off your own body: take it off. Nobody
-- claimed it, so it did not land on a socket or on the action bar -- it went on the floor,
-- which is the oldest way there is of saying you do not want it on.
Carry.missed.Event:Connect(function(model, _x, _y, from)
	if from == "socket" and model then
		remote:FireServer("remove", model)
	end
end)

do
	local leftY, rightY = COL_Y, COL_Y
	-- Centre however many the bottom row has, rather than assuming two: adding the pet
	-- slot to a hard-coded pair would have pushed the row off centre.
	local bottom = 0
	for _, def in ipairs(Theme.slots) do
		if def.col == "bottom" then bottom += 1 end
	end
	local handX = (W - (SOCKET * bottom + 18 * (bottom - 1))) / 2
	for _, def in ipairs(Theme.slots) do
		if def.col == "left" then
			makeSocket(def, COL_X, leftY)
			leftY += COL_STEP
		elseif def.col == "right" then
			makeSocket(def, COL_X2, rightY)
			rightY += COL_STEP
		else
			makeSocket(def, handX, HAND_Y)
			handX += SOCKET + 18
		end
	end
end


-- ---- the doll ----------------------------------------------------------------------------
-- A copy of you, in a world of its own. Its own world is the whole point: it can be turned
-- round and dressed without any of that happening to the body standing in the square.
--
-- The Humanoid comes with the copy. An Accessory sits on a head because the renderer sees a
-- character underneath it; a copy without one wears its hat off to the side.
local doll = Instance.new("ViewportFrame")
doll.Name = "Doll"
doll.Size = UDim2.new(0, DOLL_W, 0, 236)
doll.Position = UDim2.new(0, COL_X + SOCKET + 18, 0, 88)
doll.BackgroundColor3 = Theme.c.tile
doll.BackgroundTransparency = 0.35
doll.BorderSizePixel = 0
doll.Parent = panel
Theme.corner(doll, 6)

local dollCopy = nil

-- Which way the doll is facing, in degrees. 180 puts its front to you, because the frame
-- looks down -Z and a character faces -Z -- turn it half a turn and you are nose to nose.
--
-- Kept out here rather than inside showDoll so it SURVIVES a rebuild. Wearing something
-- rebuilds the doll from scratch, and having it snap back to front-on every time you put a
-- hat on would make turning it round useless for exactly the thing you turn it round for:
-- seeing what the thing you just put on looks like from behind.
local dollYaw = 180

--- Stands the doll at the angle it is meant to be at.
local function faceDoll()
	if not dollCopy then return end
	pcall(function()
		dollCopy:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(dollYaw), 0))
	end)
end

-- The body the doll in the frame was copied from, and what was on it at the time.
local dollFor = nil
local dollWore = nil

--- Rebuilt rather than adjusted: what you are wearing changes by parts appearing and
--- disappearing on the real body, and copying it again is both simpler and always right.
---
--- But only when it is actually a different body or a different outfit. Copying a character
--- is copying every part of it, and the panel is redrawn on every push of the list -- which
--- at start-up is eight of them two seconds apart, because the action bar goes on asking
--- until the chain answers with something. Eight whole-body clones and eight destroys, each
--- one re-aiming the viewport's camera, is what "my inventory takes way longer than normal"
--- was: nothing about the picture changed across any of them.
local function showDoll(wearing)
	local char = player.Character
	if dollCopy and dollFor == char and dollWore == wearing then return end
	dollFor = char
	dollWore = wearing
	if dollCopy then
		dollCopy:Destroy()
		dollCopy = nil
	end
	if not char then return end
	local ok, copy = pcall(function() return char:Clone() end)
	if not ok or not copy then return end
	copy.Name = "Doll"
	-- Anchored before it is parented, not after.
	--
	-- A clone of you keeps your Humanoid, and the frame is a world of its own with its own
	-- gravity -- so the doll FELL. Not out of sight in the usual way either: one was found
	-- nine thousand studs down, and since the frame aims its camera to take in everything
	-- inside it, the camera retreated to thirteen thousand studs to keep them all in shot.
	-- Which is why the panel looked empty rather than wrong.
	--
	-- Anchoring first means it never gets even one frame of falling.
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	-- Without the spawn shield. A clone taken in your first six seconds carries your ForceField,
	-- and the doll is only copied again when the outfit changes -- so it stood in its bubble
	-- long after yours had gone. The doll shows what you are wearing, and a shield is not worn.
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("ForceField") then d:Destroy() end
	end
	copy.Parent = doll
	-- Put down at the origin, at whatever angle it was last left at. The frame aims its
	-- camera at what is in it, looking down -Z, so this is what decides which side it sees.
	pcall(function()
		copy:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(dollYaw), 0))
	end)
	-- Remembered, so the NEXT rebuild can throw it away.
	--
	-- This line did not exist. `dollCopy` was read and cleared at the top of this function
	-- and never once assigned, so it was always nil, nothing was ever destroyed, and every
	-- refresh put another whole body in the frame. Eight of them were in there.
	dollCopy = copy
end

-- ---- turning it round -------------------------------------------------------------------
--
-- Two arrows in the corner of the frame, which is where every game that has ever had a
-- character sheet puts them. You buy a cape and the first thing you want is to see the back
-- of it, and until now the doll only ever stood one way.
--
-- It turns while you HOLD the arrow, and stops when you let go. Not a step a click: you are
-- looking for an angle, not counting notches, and clicking eight times to get round the back
-- of a cape is the sort of thing that makes a panel feel cheap.
--
-- Degrees a second. Slow enough to stop where you meant to, quick enough to get all the way
-- round without waiting -- a full turn takes three seconds.
local TURN_SPEED = 120

-- Which way it is being turned right now: -1, 0 or 1.
local turning = 0

local function arrow(text, x, way)
	local b = Theme.button(panel, text)
	b.Size = UDim2.new(0, 26, 0, 24)
	b.Position = UDim2.new(0, COL_X + SOCKET + 18 + x, 0, 92)
	b.TextSize = Theme.t.small
	b:SetAttribute("Sfx", "menu")
	b.MouseButton1Down:Connect(function() turning = way end)
	-- Three ways to stop, and all three are needed. Letting go is the obvious one; leaving
	-- the button while still holding is the one that spins forever if you forget it, because
	-- the button never sees the release.
	b.MouseButton1Up:Connect(function() turning = 0 end)
	b.MouseLeave:Connect(function() turning = 0 end)
	return b
end

-- Top left of the frame, side by side. Left turns it left.
arrow("<", 6, 1)
arrow(">", 36, -1)

-- RenderStepped, not Heartbeat: this moves something you are looking at, so it belongs in
-- the frame that draws it. It is also a client script, which is the only place RenderStepped
-- ever runs.
RunService.RenderStepped:Connect(function(dt)
	if turning == 0 or not dollCopy then return end
	dollYaw = (dollYaw + turning * TURN_SPEED * dt) % 360
	faceDoll()
end)

-- Closing the panel mid-turn would otherwise leave it spinning behind your back, and the
-- first thing you would see on opening it again is a doll that had been turning the whole
-- time you were away.
screen:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not screen.Enabled then turning = 0 end
end)

-- ---- the bags -----------------------------------------------------------------------

local bagTitle = Instance.new("TextLabel")
bagTitle.Size = UDim2.new(0, 158, 0, 20)   -- the count is right-aligned in the rest
bagTitle.Position = UDim2.new(0, 18, 0, 470)
bagTitle.BackgroundTransparency = 1
bagTitle.TextColor3 = Theme.c.ink
bagTitle.TextSize = Theme.t.heading
bagTitle.TextXAlignment = Enum.TextXAlignment.Left
bagTitle.Text = "Bags"
Theme.face(bagTitle)
bagTitle.Parent = panel

local bagCount = Instance.new("TextLabel")
bagCount.Size = UDim2.new(0, 200, 0, 20)
bagCount.Position = UDim2.new(1, -218, 0, 470)
bagCount.BackgroundTransparency = 1
bagCount.TextColor3 = Theme.c.faint
bagCount.TextSize = Theme.t.small
bagCount.TextXAlignment = Enum.TextXAlignment.Right
bagCount.Text = ""
Theme.face(bagCount)
bagCount.Parent = panel

local bag = Instance.new("ScrollingFrame")
bag.Position = UDim2.new(0, 18, 0, 496)
bag.Size = UDim2.new(1, -36, 0, H - 496 - 44)   -- the size button sits under it
bag.BackgroundTransparency = 1
bag.ScrollBarThickness = 6
bag.ScrollBarImageColor3 = Theme.c.scrollbar
bag.AutomaticCanvasSize = Enum.AutomaticSize.Y
bag.CanvasSize = UDim2.new(0, 0, 0, 0)
bag.Parent = panel
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0, CELL, 0, CELL)
grid.CellPadding = UDim2.new(0, 8, 0, 8)
grid.Parent = bag


local empty = Instance.new("TextLabel")
-- The bag's own box, not a 40-pixel strip. Wrapped text at 32 needs two lines here and a
-- GuiObject does not clip its text to its size, so the overflow simply drew outside the
-- panel and over the world.
empty.Position = UDim2.new(0, 18, 0, 496)
empty.Size = UDim2.new(1, -36, 0, H - 496 - 44)   -- same box as the bag, same room given up
empty.BackgroundTransparency = 1
empty.TextColor3 = Theme.c.dim
empty.TextSize = Theme.t.body
empty.TextWrapped = true
empty.TextXAlignment = Enum.TextXAlignment.Left
empty.TextYAlignment = Enum.TextYAlignment.Top
local EMPTY = "Nothing yet. Finch's stall is west of the square, at the end of the path."
local LOOKING = "Reading the ledger..."
empty.Text = LOOKING
empty.Visible = false
Theme.face(empty)
empty.Parent = panel

local function clearBag()
	for _, child in ipairs(bag:GetChildren()) do
		if child:IsA("ImageButton") then child:Destroy() end
	end
end

local function bagSquare(item)
	local button = Instance.new("ImageButton")
	button.BackgroundColor3 = Theme.c.tile
	button.AutoButtonColor = false
	button.Image = ""
	-- A clip per gesture. Left-click asks the thing to do its trick and the trick answers
	-- for itself -- the Familiar barks -- while a thing with no trick does nothing and says
	-- nothing, which is the truth about what just happened. Right-click is the equip, and
	-- putting something ON has always been the item clip, including swapping into a slot
	-- that is already full; taking it off is a menu action and gets the menu clip. Shift and
	-- right-click is the old menu, so it sounds like one.
	button:SetAttribute("Sfx", "none")
	button:SetAttribute("SfxRight", item.worn and "menu" or "item")
	button:SetAttribute("SfxShiftRight", "menu")
	button.Parent = bag
	Theme.corner(button, 5)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Theme.rarityOf(item.tier)
	stroke.Transparency = item.worn and 0.55 or 0.15
	stroke.Parent = button

	-- A thumbnail if it has one; the model itself if the town built it (the fish, the rod); and
	-- otherwise its name.
	local drawn = (item.thumb == nil or item.thumb == "") and ModelPicture.template(item.model)
	if (item.thumb and item.thumb ~= "") or drawn then
		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(1, -8, 1, -8)
		icon.Position = UDim2.new(0, 4, 0, 4)
		icon.BackgroundTransparency = 1
		Pictures.show(icon, item.thumb or "")
		icon.ImageTransparency = item.worn and 0.5 or 0
		-- The rod is a thin dark line drawn live, and on the tile's blue it drowned. White behind it.
		if drawn and item.model == Fish.ROD then
			icon.BackgroundTransparency = 0
			icon.BackgroundColor3 = Color3.new(1, 1, 1)
			Theme.corner(icon, 4)
		end
		icon.Parent = button
		if drawn then ModelPicture.frame(icon, drawn) end
	else
		local none = Instance.new("TextLabel")
		none.Size = UDim2.new(1, -6, 1, 0)
		none.Position = UDim2.new(0, 3, 0, 0)
		none.BackgroundTransparency = 1
		none.TextColor3 = Theme.c.faint
		none.TextSize = Theme.t.small
		none.TextWrapped = true
		none.Text = item.name
		Theme.face(none)
		none.Parent = button
	end

	-- Something already on the character stays in the bag, dimmed, so the grid does
	-- not reshuffle under the pointer every time you put a hat on.
	if item.worn then
		local on = Instance.new("TextLabel")
		on.Size = UDim2.new(1, 0, 0, 14)
		on.Position = UDim2.new(0, 0, 1, -15)
		on.BackgroundTransparency = 1
		on.TextColor3 = Theme.c.accent
		on.TextSize = Theme.t.small
		on.Text = "worn"
		Theme.face(on)
		on.Parent = button
	end

	button.MouseEnter:Connect(function()
		stroke.Transparency = 0
		describe(item, nil, button)
	end)
	button.MouseLeave:Connect(function()
		stroke.Transparency = item.worn and 0.55 or 0.15
		-- Nothing used to do this, so the tooltip sat over the panel after the pointer
		-- had gone and only a disarm ever took it down.
		tip.Visible = false
	end)
	-- Picked up on the press, so it can be carried out of the bag and dropped on the action
	-- bar. Nothing is lost if it goes nowhere: the icon only appears once the pointer has
	-- actually moved, and a release over nothing is a drop that finds no square.
	--
	-- This does not fight the click. A press and a release in the same place is a Click and
	-- still runs the trick below; a press that ends somewhere else is not one at all.
	button.MouseButton1Down:Connect(function()
		Carry.lift(item.model, item.thumb, "bag")
	end)

	-- Left-click does what the thing does. Nearly nothing does anything, and a tile with no
	-- trick is left alone rather than given one to fill the gesture in: the server decides
	-- which those are and says so in `acts`, so the panel never has to know the list.
	button.Activated:Connect(function()
		if not item.acts then return end
		remote:FireServer("act", item.model)
	end)
	button.MouseButton2Click:Connect(function()
		if menuing() then
			openMenu(item, button)
			return
		end
		remote:FireServer(item.worn and "remove" or "wear", item.model)
	end)
	return button
end

-- ---- filling it in ------------------------------------------------------------------

local function render(items, standing, loading)
	clearBag()
	armed = nil
	-- What is on the body, as one string, so the doll can tell whether it is being asked
	-- to copy a body it has already copied. Sorted, because the order the list arrives in
	-- is not promised and a re-ordering is not a change of outfit.
	local worn = {}
	for _, item in ipairs(items) do
		if item.worn then table.insert(worn, item.model) end
	end
	table.sort(worn)
	showDoll(table.concat(worn, ","))
	for _, socket in pairs(sockets) do
		socket.item = nil
		socket.icon.Image = ""
		ModelPicture.clear(socket.icon)
		socket.label.Visible = true
		socket.stroke.Color = Theme.c.muted
		socket.stroke.Transparency = 0.35
	end

	local wornCount = 0
	for _, item in ipairs(items) do
		bagSquare(item)
		if item.worn then
			wornCount += 1
			local socket = sockets[item.slot]
			if socket then
				socket.item = item
				socket.label.Visible = false
				Pictures.show(socket.icon, item.thumb or "")
				if not item.thumb or item.thumb == "" then ModelPicture.show(socket.icon, item.model) end
				socket.stroke.Color = Theme.rarityOf(item.tier)
				socket.stroke.Transparency = 0.1
			end
		end
	end

	empty.Visible = #items == 0
	empty.Text = loading and LOOKING or EMPTY
	bag.Visible = #items > 0
	bagCount.Text = ("%d item%s"):format(#items, #items == 1 and "" or "s")
	dressed.Text = ("%d worn of %d owned"):format(wornCount, #items)
	if standing and standing.name and standing.name ~= "" then
		rank.Text = standing.name
		rank.TextColor3 = Theme.rarityOf(standing.tier)
	elseif standing then
		-- Holding less than the bottom rung costs is a rung of nothing, and the label should
		-- say so rather than keep the name of a rung this wallet has fallen off.
		rank.Text = "Not on the ladder"
		rank.TextColor3 = Theme.c.dim
	end
end

local noteAt = 0
local drawnKey = nil

remote.OnClientEvent:Connect(function(kind, items, standing, _slots, loading)
	if kind == "note" then
		-- Two transactions get signed for this, so it is worth saying when it lands. Shown
		-- on the button itself and then taken back off, rather than a label that sits
		-- there afterwards saying something that has stopped being true.
		saveButton.Text = tostring(items)
		noteAt += 1
		local mine = noteAt
		task.delay(4, function()
			if noteAt == mine then saveButton.Text = SAVE_LABEL end
		end)
		return
	end
	if kind ~= "items" then return end
	-- Nothing is drawn while the panel is closed. Every wear and remove sends the list again, and
	-- redrawing seventy squares and cloning the doll into its own little world for a panel nobody
	-- can see was a ninety-millisecond frame on every equip, measured. Opening the panel asks for
	-- the list (toggle), and that is when it is drawn.
	if not screen.Enabled then
		drawnKey = nil
		return
	end
	-- The same list again draws nothing. The server sends it whenever anything in the wallet moves,
	-- and the wallet publishes once a minute (the block height is in it) -- so an unchanged bag was
	-- seventy squares, some of them 3D pictures, torn down and built again every minute, standing
	-- still. Checked here rather than on the server: other scripts on this machine listen for the
	-- same list, and only this one knows what it last drew.
	local ok, key = pcall(function()
		return HttpService:JSONEncode({ items or {}, standing or {}, loading == true })
	end)
	if ok and key == drawnKey then return end
	drawnKey = ok and key or nil
	render(items or {}, standing, loading == true)
end)

local function toggle(_, state)
	if state ~= Enum.UserInputState.Begin then return end
	screen.Enabled = not screen.Enabled
	if screen.Enabled then
		remote:FireServer("list")
	end
end

ContextActionService:BindAction("Wardrobe", toggle, false, Enum.KeyCode.I)
remote:FireServer("list")

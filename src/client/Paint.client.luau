-- The tailor's drawing table: a grid of cells, a column of colours, and a Publish
-- button. Deliberately the crudest possible paint program, because that is the joke
-- and because every extra tool is another thing to explain.
--
-- The grid and the palette both come from the host (ReplicatedStorage.Chain, forwarded
-- by the tailor when the panel opens) rather than being written down here as well.
-- Two copies of a palette drift apart, and then what you drew is not what gets stored.
--
-- Nothing here signs or publishes anything. Pressing Publish hands a string of palette
-- indices to the server, which asks the host, which asks you.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Cape = require(ReplicatedStorage:WaitForChild("Cape"))
local Paint = require(ReplicatedStorage:WaitForChild("Paint"))
local Glyphs = require(ReplicatedStorage:WaitForChild("Glyphs"))
local UserInputService = game:GetService("UserInputService")
local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("TailorRemote")

local INK = Theme.c.ink
local PANEL = Theme.c.panel
local ACCENT = Theme.c.accent

local screen = Instance.new("ScreenGui")

-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "PaintTable"
screen.Enabled = false
screen.ResetOnSpawn = false
screen.Parent = gui

-- The doll needs a column of its own, so the panel asks for the room rather than taking it
-- off the paper. Down to 720 when the window is small, which is what it was.
local DOLL_W = 260
local PANEL_W, PANEL_H = Theme.roomFor(720 + DOLL_W + 12, 600)
local panel, panelWindow = Theme.window(screen, UDim2.new(0, PANEL_W, 0, PANEL_H),
	UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2))

-- Steps this window through its sizes.
Theme.scaleButton(screen, panel, UDim2.new(1, -58, 0, 8))

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -90, 0, 26)   -- the size button has the corner
title.Position = UDim2.new(0, 12, 0, 8)
title.BackgroundTransparency = 1
title.TextColor3 = ACCENT
title.TextScaled = true
title.Text = "The drawing table"
Theme.face(title)
title.Parent = panel

local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(1, -24, 0, 16)
hint.Position = UDim2.new(0, 12, 0, 36)
hint.BackgroundTransparency = 1
hint.TextColor3 = Theme.c.dim
hint.TextSize = Theme.t.small
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "Click and drag to paint. The first swatch is the eraser."
Theme.face(hint)
hint.Parent = panel

-- The colours, down the left: two columns of eight.
--
-- It was one column of sixteen at forty pixels each -- 704 pixels in a panel with 454 to give
-- it, so the bottom five ran off the window, and the one that landed on the "Colour..." button
-- took every click meant for it. Nobody could open the picker.
local SWATCH = 34
local SWATCH_GAP = 4
local SWATCH_COLS = 2
local SWATCH_ROWS = 8
local LEFT_W = SWATCH_COLS * SWATCH + (SWATCH_COLS - 1) * SWATCH_GAP   -- 72
local swatches = Instance.new("Frame")
swatches.Position = UDim2.new(0, 12, 0, 86)
swatches.Size = UDim2.new(0, LEFT_W, 0, SWATCH_ROWS * (SWATCH + SWATCH_GAP) - SWATCH_GAP)
swatches.BackgroundTransparency = 1
swatches.Parent = panel
local swatchLayout = Instance.new("UIGridLayout")
swatchLayout.CellSize = UDim2.new(0, SWATCH, 0, SWATCH)
swatchLayout.CellPadding = UDim2.new(0, SWATCH_GAP, 0, SWATCH_GAP)
swatchLayout.SortOrder = Enum.SortOrder.LayoutOrder
swatchLayout.Parent = swatches
local LEFT_EDGE = 12 + LEFT_W + 8                -- where everything right of the colours starts

-- The space the drawing gets. Nothing is drawn on this: it is the room, not the paper.
local canvas = Instance.new("Frame")
canvas.Position = UDim2.new(0, LEFT_EDGE, 0, 86)
-- The doll has the right, the words row and the buttons have the bottom.
canvas.Size = UDim2.new(1, -LEFT_EDGE - DOLL_W - 24, 1, -86 - 104)
canvas.BackgroundTransparency = 1
canvas.Parent = panel

-- The paper, which is the drawing and nothing else. Sized to the cells rather than to the
-- room, because the two rarely have the same proportions: square cells that fit a 648x482
-- room at 48 across come out 13px, making a 624x260 drawing -- and a UIGridLayout packs
-- top-left, so every one of the 222 spare pixels fell underneath it. Centred here, so the
-- slack is a margin on both sides instead of a hole at the bottom.
local paper = Instance.new("Frame")
paper.BackgroundColor3 = Theme.c.field
paper.BorderSizePixel = 0
paper.Parent = canvas
local canvasCorner = Instance.new("UICorner")
canvasCorner.Parent = paper
local grid = Instance.new("UIGridLayout")
grid.CellPadding = UDim2.new(0, 0, 0, 0)
-- Said out loud rather than left to the tie-break. Every cell is an unnamed Frame, so under
-- the default -- sort by Name -- all six hundred and eighty tie, and where a tie lands is
-- the engine's business. The paper's order IS the drawing: cell n is row n/W, column n%W,
-- and everything downstream reads it that way, so this is not a preference.
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = paper

local nameBox = Instance.new("TextBox")
nameBox.Position = UDim2.new(0, 12, 1, -54)
nameBox.Size = UDim2.new(0, 188, 0, 44)   -- up to where the buttons start
nameBox.BackgroundColor3 = Theme.c.field
nameBox.TextColor3 = INK
nameBox.PlaceholderColor3 = Theme.c.faint
nameBox.PlaceholderText = "name it"
nameBox.TextSize = Theme.t.body
nameBox.ClearTextOnFocus = false
nameBox.Text = ""
Theme.face(nameBox)
nameBox.Parent = panel
local nameCorner = Instance.new("UICorner")
nameCorner.Parent = nameBox

-- Laid out in pixels, from the widths the words actually take in Reactor7 at this size.
-- As fractions of the panel, Publish came out a 73px box holding 80px of text, in a
-- position running 23px past the panel's own edge: clipped by its box and by the window.
local function makeButton(text, x, width, colour)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(0, x, 1, -54)
	b.Size = UDim2.new(0, width, 0, 40)
	b.BackgroundColor3 = colour
	b.TextColor3 = INK
	b.TextSize = Theme.t.body
	b.Text = text
	Theme.face(b)
	b.Parent = panel
	local c = Instance.new("UICorner")
	c.Parent = b
	return b
end

local tryButton = makeButton("Try it on", 206, 114, Theme.c.button)
local clearButton = makeButton("Clear", 326, 78, Theme.c.danger)
local closeButton = makeButton("Close", 410, 80, Theme.c.button)
local publishButton = makeButton("Publish", 496, 98, Theme.c.good)

-- ---- trying it on ------------------------------------------------------------------------
-- The cape and nothing else, hanging in a window of its own. Not on a copy of you: you are
-- probably already wearing one, and a cape worn over a cape draws the old one across the
-- new one -- which is exactly the picture this is supposed to replace. There is nothing a
-- body adds here either. The drawing covers the whole back panel, the panel is the cape,
-- and what you want to know is what the drawing looks like at cape size and cape shape.
-- Shaped like a cape rather than like the column it sits in. The frame aims its camera to
-- take in what is inside it, so a box twice as tall as the thing in it is a cape drawn half
-- size with empty blue above and below -- and in a box NARROWER than the thing, the sides
-- go off the edge. A cape's bounding box is about 2.0 by 2.5 studs, so this is too.
local DOLL_H = math.floor(DOLL_W * 2.5 / 2.02)
local doll = Instance.new("ViewportFrame")
doll.Name = "Doll"
doll.Size = UDim2.new(0, DOLL_W, 0, DOLL_H)
doll.Position = UDim2.new(1, -DOLL_W - 12, 0, 86)
doll.BackgroundColor3 = Theme.c.tile
doll.BackgroundTransparency = 0.35
doll.BorderSizePixel = 0
doll.Parent = panel
Theme.corner(doll, 6)

local dollNote = Instance.new("TextLabel")
dollNote.Size = UDim2.new(0, DOLL_W, 0, 18)
dollNote.Position = UDim2.new(1, -DOLL_W - 12, 0, 64)
dollNote.BackgroundTransparency = 1
dollNote.TextColor3 = Theme.c.faint
dollNote.TextSize = Theme.t.small
dollNote.TextXAlignment = Enum.TextXAlignment.Left
dollNote.Text = "Try it on to see it here"
Theme.face(dollNote)
dollNote.Parent = panel

local dollCopy = nil

--- Hangs the draft in the window.
---
--- `draft` is an Accessory built here and now out of what is on the paper -- see
--- Cape.preview. It used to be fetched from ReplicatedStorage.OnChain, where the host put
--- one after rendering the drawing on its side; the host stopped doing that when the tailor
--- moved into the town, and nothing replaced it, so "Try it on" did nothing at all for a
--- long time. It never needed a round trip: the panel is holding the drawing.
local function showDoll(draft)
	if dollCopy then
		dollCopy:Destroy()
		dollCopy = nil
	end
	if not draft then
		dollNote.Text = "Try it on to see it here"
		return
	end
	-- Anchored before it is parented, not after. The frame is a world of its own with its
	-- own gravity, and anything loose in it FALLS -- out of shot in a way that looks like a
	-- window that failed to draw rather than one with something falling through it, since
	-- the frame aims its camera to take in whatever is inside and retreats to keep up.
	for _, d in ipairs(draft:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	draft.Parent = doll
	-- Left as it is. The drawing is on the Handle's Back face, whose normal is +Z, and the
	-- frame looks down -Z from in front of what is in it -- so the side with the drawing on
	-- it is already the side facing you.
	pcall(function() draft:PivotTo(CFrame.new(0, 0, 0)) end)
	dollNote.Text = "Your draft"
	dollCopy = draft
end

-- ---- state -------------------------------------------------------------------------
local W, H = 720, 600
local palette = {}          -- index (1-based) -> Color3, where 1 is transparent
local swatchButtons = {}    -- ... and the button showing each, so one can be recoloured
local tool = "pencil"       -- pencil | fill | line | box | pick
local dragFrom = 0          -- the cell a line or a box was started from
local shown = {}            -- cells recoloured for a preview, put back before the next one
local undo = {}             -- snapshots of the whole drawing, newest last
local cells = {}            -- flat array of Frames, row-major
local pixels = {}           -- flat array of 0-based palette indices
local brush = 2             -- start on the first real colour
local painting = false
-- Empty cells can show as a checkerboard (so you can tell "nothing" from "white") or
-- as the cape's own cloth (so you can see what it will actually look like). Neither
-- is right all the time, so it toggles.
-- What an unpainted square looks like, which is what it will look like when worn. There
-- used to be a checkerboard behind a toggle; it answered a question nobody was asking, and
-- the honest view of a cape is the cape.
local CLOTH = Color3.fromRGB(242, 242, 246)

local function checker(_i)
	return CLOTH
end

local function paintCell(i)
	if i < 1 or i > #cells then return end
	pixels[i] = brush - 1
	cells[i].BackgroundColor3 = (brush == 1) and checker(i) or palette[brush]
end

-- ---- words ---------------------------------------------------------------------------------
-- One line in the town's own face, Reactor7, stamped into the cape's picture at full size -- see
-- Paint.checkText and Glyphs. Typed here, placed with the Text tool, coloured with whatever colour
-- is in your hand when you place it, and shown over the paper exactly as it will be stamped: the
-- overlay is drawn by Glyphs.stamp, the same function the stored picture is drawn with.
local words = { x = 0, y = 12, colour = 1, scale = 2, placed = false }

local wordsBox = Instance.new("TextBox")
wordsBox.Position = UDim2.new(0, LEFT_EDGE, 1, -98)
wordsBox.Size = UDim2.new(0, 300, 0, 36)
wordsBox.BackgroundColor3 = Theme.c.field
wordsBox.TextColor3 = INK
wordsBox.PlaceholderColor3 = Theme.c.faint
wordsBox.PlaceholderText = "words on the cape"
wordsBox.TextSize = Theme.t.body
wordsBox.ClearTextOnFocus = false
wordsBox.TextXAlignment = Enum.TextXAlignment.Left
wordsBox.Text = ""
Theme.face(wordsBox)
wordsBox.Parent = panel
Theme.corner(wordsBox)

local sizeButtons = {}
for i = 1, Paint.TEXT_SCALES do
	local b = Theme.button(panel, ("%dx"):format(i))
	b.Size = UDim2.new(0, 40, 0, 30)
	b.Position = UDim2.new(0, LEFT_EDGE + 308 + (i - 1) * 46, 1, -95)
	b.TextSize = Theme.t.small
	b:SetAttribute("Sfx", "menu")
	sizeButtons[i] = b
end

-- The words as the paper shows them: a picture the size of the stored one, laid over the paper
-- and stretched with it, pixelated so a stamped pixel stays square. Not Active, so a click goes
-- straight through it to the cell underneath.
local wordsImage = AssetService:CreateEditableImage({ Size = Vector2.new(Paint.W * Paint.SCALE, Paint.H * Paint.SCALE) })
local wordsLayer = Instance.new("ImageLabel")
wordsLayer.Name = "Words"
wordsLayer.BackgroundTransparency = 1
wordsLayer.ImageContent = Content.fromObject(wordsImage)
wordsLayer.ResampleMode = Enum.ResamplerMode.Pixelated
wordsLayer.ZIndex = 5
wordsLayer.Active = false
wordsLayer.Parent = canvas

--- The words as they would be published, or nil if there are none.
local function wordsSpec()
	local text = wordsBox.Text
	if text:gsub("%s", "") == "" then return nil end
	return Paint.checkText({ text = text, x = words.x, y = words.y, colour = words.colour, scale = words.scale })
end

--- Redraws the overlay from the box, the place, the colour and the size.
local function drawWords()
	local w, h = Paint.W * Paint.SCALE, Paint.H * Paint.SCALE
	local px = table.create(w * h * 4, 0)
	local spec = wordsSpec()
	if spec and #palette > 0 then
		-- Not placed yet: centred near the top, where words on a cape usually go.
		if not words.placed then
			local tw = Glyphs.measure(spec.text, spec.scale)
			spec.x = math.floor((w - tw) / 2)
			words.x = spec.x
		end
		local c = palette[spec.colour + 1]
		if c then
			Glyphs.stamp(px, w, h, spec.text, spec.x, spec.y, { math.floor(c.R * 255 + 0.5),
				math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), 255 }, spec.scale)
		end
	end
	local bytes = buffer.create(#px)
	for i, v in ipairs(px) do
		if v ~= 0 then buffer.writeu8(bytes, i - 1, v) end
	end
	wordsImage:WritePixelsBuffer(Vector2.new(0, 0), Vector2.new(w, h), bytes)
	for i, b in ipairs(sizeButtons) do
		b.BackgroundColor3 = (i == words.scale) and Theme.c.good or Theme.c.button
	end
end

--- Puts the words' top-left corner at a cell, in the colour in your hand.
local function placeWords(index)
	if wordsBox.Text:gsub("%s", "") == "" then
		hint.Text = "Type your words in the box under the paper first."
		return
	end
	local col, row = (index - 1) % W, math.floor((index - 1) / W)
	words.x, words.y = col * Paint.SCALE, row * Paint.SCALE
	words.placed = true
	if brush > 1 then words.colour = brush - 1 end
	drawWords()
	hint.Text = "There. Click somewhere else to move them."
end

for i, b in ipairs(sizeButtons) do
	b.Activated:Connect(function()
		words.scale = i
		drawWords()
	end)
end
wordsBox:GetPropertyChangedSignal("Text"):Connect(function()
	if #wordsBox.Text > Paint.TEXT_MAX then
		wordsBox.Text = wordsBox.Text:sub(1, Paint.TEXT_MAX)
		return
	end
	-- The first words typed take the colour in your hand, so they are not invisible cloth-on-cloth.
	if not words.placed and brush > 1 then words.colour = brush - 1 end
	drawWords()
end)

-- ---- the tools ---------------------------------------------------------------------------
-- Every one of them writes `pixels`, the array of palette indices the pencil has always
-- written, so none of this changes what is published or how it is read back.

local function colourOf(i)
	local idx = pixels[i]
	return idx == 0 and checker(i) or palette[idx + 1]
end

--- The drawing as it stands, kept so it can be put back.
local function remember()
	local snap = table.create(#pixels)
	table.move(pixels, 1, #pixels, 1, snap)
	table.insert(undo, snap)
	-- Twenty deep. A snapshot is a thousand small numbers, and keeping every stroke of a
	-- long session is a lot of them to hold for a button nobody presses that far back.
	if #undo > 20 then table.remove(undo, 1) end
end

local function stepBack()
	local snap = table.remove(undo)
	if not snap then
		hint.Text = "Nothing left to undo."
		return
	end
	for i = 1, #cells do
		pixels[i] = snap[i] or 0
		cells[i].BackgroundColor3 = colourOf(i)
	end
end

--- Where a cell is, in columns and rows.
local function at(i)
	return (i - 1) % W, math.floor((i - 1) / W)
end

local function indexOf(x, y)
	if x < 0 or y < 0 or x >= W or y >= H then return 0 end
	return y * W + x + 1
end

--- The cells a straight line between two of them passes through. Bresenham, so it is the
--- same line the drawing would have if it were drawn a pixel at a time by hand.
local function lineCells(a, b)
	local x0, y0 = at(a)
	local x1, y1 = at(b)
	local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
	local sx = x0 < x1 and 1 or -1
	local sy = y0 < y1 and 1 or -1
	local err = dx + dy
	local out = {}
	while true do
		table.insert(out, indexOf(x0, y0))
		if x0 == x1 and y0 == y1 then break end
		local e2 = 2 * err
		if e2 >= dy then
			err += dy
			x0 += sx
		end
		if e2 <= dx then
			err += dx
			y0 += sy
		end
	end
	return out
end

--- The outline of the box with those two cells at opposite corners.
local function boxCells(a, b)
	local x0, y0 = at(a)
	local x1, y1 = at(b)
	if x0 > x1 then x0, x1 = x1, x0 end
	if y0 > y1 then y0, y1 = y1, y0 end
	local out = {}
	for x = x0, x1 do
		table.insert(out, indexOf(x, y0))
		if y1 ~= y0 then table.insert(out, indexOf(x, y1)) end
	end
	for y = y0 + 1, y1 - 1 do
		table.insert(out, indexOf(x0, y))
		if x1 ~= x0 then table.insert(out, indexOf(x1, y)) end
	end
	return out
end

--- The outline of the ellipse that fits the box those two cells corner. Midpoint, mirrored
--- into four quadrants, so it comes out symmetrical however it is dragged -- an ellipse
--- drawn by rounding a sine is lopsided by a pixel on one side and it shows.
local function ovalCells(a, b)
	local x0, y0 = at(a)
	local x1, y1 = at(b)
	if x0 > x1 then x0, x1 = x1, x0 end
	if y0 > y1 then y0, y1 = y1, y0 end
	local rx, ry = (x1 - x0) / 2, (y1 - y0) / 2
	local cx, cy = x0 + rx, y0 + ry
	local out = {}
	local seen = {}
	local function put(x, y)
		local i = indexOf(math.floor(x + 0.5), math.floor(y + 0.5))
		if i > 0 and not seen[i] then
			seen[i] = true
			table.insert(out, i)
		end
	end
	-- A degenerate box is a line, and an ellipse through it is that line.
	if rx < 0.5 or ry < 0.5 then return lineCells(a, b) end
	local steps = math.max(8, math.floor((rx + ry) * 4))
	for s = 0, steps do
		local ang = (s / steps) * math.pi / 2
		local dx, dy = rx * math.cos(ang), ry * math.sin(ang)
		put(cx + dx, cy + dy)
		put(cx - dx, cy + dy)
		put(cx + dx, cy - dy)
		put(cx - dx, cy - dy)
	end
	return out
end

--- Every cell the same colour as the one you clicked, reachable from it four ways.
local function fillFrom(start)
	local want = pixels[start]
	local paint = brush - 1
	if want == paint then return end
	local seen = { [start] = true }
	local queue = { start }
	local head = 1
	while head <= #queue do
		local i = queue[head]
		head += 1
		pixels[i] = paint
		cells[i].BackgroundColor3 = colourOf(i)
		local x, y = at(i)
		for _, n in ipairs({ indexOf(x - 1, y), indexOf(x + 1, y), indexOf(x, y - 1), indexOf(x, y + 1) }) do
			if n > 0 and not seen[n] and pixels[n] == want then
				seen[n] = true
				table.insert(queue, n)
			end
		end
	end
end

--- Takes the last preview off, so dragging does not leave a trail of every shape it passed
--- through on the way.
local function unpreview()
	for _, i in ipairs(shown) do
		cells[i].BackgroundColor3 = colourOf(i)
	end
	shown = {}
end

local function preview(list)
	unpreview()
	for _, i in ipairs(list) do
		if i > 0 then
			-- The eraser's preview is each cell's own checker square, not one of them
			-- repeated: the checkerboard alternates, so a single colour would read as a
			-- painted line rather than as clearing.
			cells[i].BackgroundColor3 = (brush == 1) and checker(i) or palette[brush]
			table.insert(shown, i)
		end
	end
end

local function clearAll()
	for i = 1, #cells do
		pixels[i] = 0
		cells[i].BackgroundColor3 = checker(i)
	end
end

-- The drawing as the host wants it: one hex digit per cell, in reading order.
local function encode()
	local digits = table.create(#pixels)
	for i = 1, #pixels do
		digits[i] = string.format("%x", pixels[i])
	end
	return table.concat(digits)
end

-- Sixteen colours, six hex digits each, in slot order. Sent with every drawing: this
-- file's own warning at the top is why -- two copies of a palette drift apart, and then
-- what you drew is not what gets stored. Slot 1 is the eraser and its value is ignored,
-- but it is written anyway so the string is a fixed 96 characters and the host can check
-- the length rather than trust a count.
local function encodePalette()
	local out = table.create(#palette)
	for i = 1, #palette do
		local c = palette[i]
		out[i] = string.format("%02x%02x%02x",
			math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end
	return table.concat(out)
end

--- Which swatch is in your hand: a light border round it, so it is plain which colour Mix...
--- would change and which colour the words will take.
local function showBrush()
	for i, b in ipairs(swatchButtons) do
		local stroke = b:FindFirstChildOfClass("UIStroke")
		if not stroke then
			stroke = Instance.new("UIStroke")
			stroke.Thickness = 3
			stroke.Parent = b
		end
		stroke.Color = Theme.c.accent
		stroke.Enabled = i == brush
	end
end

local function buildPalette(spec)
	for _, child in ipairs(swatches:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	palette = {}
	swatchButtons = {}
	for i, rgba in ipairs(spec) do
		local colour = Color3.fromRGB(rgba[1], rgba[2], rgba[3])
		palette[i] = colour
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		-- The eraser's swatch shows what erasing gives you, which is the cloth.
		b.BackgroundColor3 = (i == 1) and CLOTH or colour
		b.Text = (i == 1) and "x" or ""
		b.TextColor3 = INK
		b.TextSize = Theme.t.small
		Theme.face(b)
		b.Parent = swatches
		swatchButtons[i] = b
		local c = Instance.new("UICorner")
		c.Parent = b
		local index = i
		b.Activated:Connect(function()
			brush = index
			hint.Text = (index == 1) and "Eraser." or ("Colour %d. Mix... changes it."):format(index - 1)
			showBrush()
		end)
	end
end

local function buildCanvas(w, h)
	for _, child in ipairs(paper:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	W, H = w, h
	cells, pixels = {}, {}
	-- Square cells that fit the room, worked out from the room's own pixel size -- which
	-- is why the cells go on the paper and not in here: measuring a thing you are about
	-- to resize gives a different answer every time it is rebuilt.
	local size = math.floor(math.min(canvas.AbsoluteSize.X / w, canvas.AbsoluteSize.Y / h))
	if size < 4 then size = 4 end
	grid.CellSize = UDim2.new(0, size, 0, size)
	paper.Size = UDim2.new(0, w * size, 0, h * size)
	paper.Position = UDim2.new(0.5, -(w * size) / 2, 0.5, -(h * size) / 2)
	wordsLayer.Size = paper.Size
	wordsLayer.Position = paper.Position
	for i = 1, w * h do
		local cell = Instance.new("Frame")
		cell.BackgroundColor3 = checker(i)
		cell.BorderSizePixel = 0
		cell.LayoutOrder = i
		-- Active, because a cell is something you press. A GuiObject that is not Active
		-- receives no input at all in Roblox -- that is what Active means -- so a Frame you
		-- want InputBegan and MouseEnter from has to say so. These are the only frames in
		-- the town that want either.
		cell.Active = true
		cell.Parent = paper
		cells[i] = cell
		pixels[i] = 0
		local index = i
		cell.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			if tool == "pick" then
				-- Reads rather than writes, so there is nothing to remember and nothing to draw.
				brush = pixels[index] + 1
				hint.Text = (brush == 1) and "Eraser." or ("Colour %d."):format(brush - 1)
				showBrush()
				return
			end
			if tool == "text" then
				placeWords(index)
				return
			end
			if tool == "fill" then
				remember()
				fillFrom(index)
				return
			end
			painting = true
			dragFrom = index
			if tool == "pencil" then
				remember()
				paintCell(index)
			end
		end)
		-- Dragging: the pencil paints as it goes; a shape only shows what it would do.
		cell.MouseEnter:Connect(function()
			if not painting then return end
			if tool == "pencil" then
				paintCell(index)
			elseif tool == "line" then
				preview(lineCells(dragFrom, index))
			elseif tool == "box" then
				preview(boxCells(dragFrom, index))
			elseif tool == "oval" then
				preview(ovalCells(dragFrom, index))
			end
		end)
	end
end

-- Letting go is what commits a shape. Until then the cells are only recoloured, so a drag
-- you thought better of leaves the drawing exactly as it was.
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if painting and #shown > 0 then
		local list = shown
		shown = {}
		remember()
		for _, i in ipairs(list) do
			paintCell(i)
		end
	end
	unpreview()
	painting = false
	dragFrom = 0
end)

-- ---- picking one -------------------------------------------------------------------------
-- Along the top, above the paper rather than beside the colours: which tool you are holding
-- and which colour it is loaded with are two questions, and the answers should not share a
-- column.
local TOOLS = {
	{ id = "pencil", label = "Pencil", w = 60, hint = "Click or drag to draw." },
	{ id = "fill", label = "Fill", w = 44, hint = "Click an area to flood it." },
	{ id = "line", label = "Line", w = 48, hint = "Drag from one end to the other." },
	{ id = "box", label = "Box", w = 44, hint = "Drag out a rectangle." },
	{ id = "oval", label = "Circle", w = 62, hint = "Drag out an ellipse; square for a circle." },
	{ id = "pick", label = "Pick", w = 46, hint = "Click a square to take its colour." },
	{ id = "text", label = "Text", w = 46, hint = "Type your words below, then click where they go. They take the colour you're holding." },
}
local toolButtons = {}

local function showTool()
	for id, b in pairs(toolButtons) do
		b.BackgroundColor3 = (id == tool) and Theme.c.good or Theme.c.button
	end
end

local tx = LEFT_EDGE
for _, t in ipairs(TOOLS) do
	local b = Theme.button(panel, t.label)
	b.Size = UDim2.new(0, t.w, 0, 24)
	b.Position = UDim2.new(0, tx, 0, 56)
	b.TextSize = Theme.t.small
	b:SetAttribute("Sfx", "menu")
	b.Activated:Connect(function()
		tool = t.id
		hint.Text = t.hint
		showTool()
	end)
	toolButtons[t.id] = b
	tx += t.w + 6
end

local undoButton = Theme.button(panel, "Undo")
undoButton.Size = UDim2.new(0, 56, 0, 24)
undoButton.Position = UDim2.new(0, tx + 10, 0, 56)
undoButton.TextSize = Theme.t.small
undoButton:SetAttribute("Sfx", "menu")
undoButton.Activated:Connect(stepBack)

showTool()


-- The picture the draft is wearing, held so it stays alive. An EditableImage is not
-- parented to anything -- the Decal points at it by id -- so the only thing keeping it is a
-- reference, and a collected one is a cape with nothing on it.
local draftImage = nil

tryButton.Activated:Connect(function()
	if #pixels == 0 then return end
	-- Costs nothing, signs nothing and asks nobody: the drawing is already here.
	local cape, image = Cape.preview(encode(), palette, wordsSpec())
	draftImage = image
	showDoll(cape)
	hint.Text = "Have a look behind you."
end)

clearButton.Activated:Connect(function()
	clearAll()
	wordsBox.Text = ""
	words.placed = false
	drawWords()
end)
closeButton.Activated:Connect(function() screen.Enabled = false end)
publishButton.Activated:Connect(function()
	if #pixels == 0 then return end
	local any = wordsSpec() ~= nil
	for i = 1, #pixels do
		if pixels[i] ~= 0 then any = true break end
	end
	if not any then
		hint.Text = "There's nothing on it yet."
		return
	end
	screen.Enabled = false
	remote:FireServer("publish", encode(), nameBox.Text, encodePalette(), wordsSpec())
end)

remote.OnClientEvent:Connect(function(kind, payload)
	if kind ~= "paint" then return end
	if type(payload) ~= "table" or type(payload.palette) ~= "table" then return end
	Theme.takeOver(gui)
	screen.Enabled = true
	-- Wait a frame so AbsoluteSize is real before the cells are sized from it.
	task.wait()
	buildPalette(payload.palette)
	buildCanvas(tonumber(payload.w) or 20, tonumber(payload.h) or 26)
	brush = math.min(2, #palette)
	showBrush()
	drawWords()
end)

-- ---- choosing a colour ------------------------------------------------------------------
-- A real picker, not a bigger tray of fixed swatches: AssetService:CreateEditableImage and
-- WritePixels are implemented here, so the square and the strip are drawn rather than
-- faked. WritePixels takes a plain table of floats, which is why there is no buffer in
-- sight -- this runtime has no buffer library.
--
-- Small images stretched by the ImageLabel. 64x64 is four thousand pixels to rewrite when
-- the hue moves; the same square at panel size would be thirty times that, every drag.
local SV = 64
local HUES = 128
local mouse = player:GetMouse()

local pickerPanel, pickerWindow = Theme.window(screen, UDim2.new(0, 240, 0, 240),
	UDim2.new(0.5, -120, 0.5, -120))
pickerWindow.Visible = false
pickerWindow.ZIndex = 40

local pickTitle = Instance.new("TextLabel")
pickTitle.Size = UDim2.new(1, -24, 0, 20)
pickTitle.Position = UDim2.new(0, 12, 0, 8)
pickTitle.BackgroundTransparency = 1
pickTitle.TextColor3 = INK
pickTitle.TextSize = Theme.t.small
pickTitle.TextXAlignment = Enum.TextXAlignment.Left
pickTitle.Text = "Choose a colour"
Theme.face(pickTitle)
pickTitle.Parent = pickerPanel

local svImage = AssetService:CreateEditableImage({ Size = Vector2.new(SV, SV) })
local svPad = Instance.new("ImageButton")
svPad.Size = UDim2.new(0, 192, 0, 128)
svPad.Position = UDim2.new(0, 12, 0, 32)
svPad.BackgroundColor3 = Theme.c.field
svPad.AutoButtonColor = false
svPad.ImageContent = Content.fromObject(svImage)
svPad.Parent = pickerPanel

local hueImage = AssetService:CreateEditableImage({ Size = Vector2.new(HUES, 1) })
local huePad = Instance.new("ImageButton")
huePad.Size = UDim2.new(0, 192, 0, 18)
huePad.Position = UDim2.new(0, 12, 0, 168)
huePad.BackgroundColor3 = Theme.c.field
huePad.AutoButtonColor = false
huePad.ImageContent = Content.fromObject(hueImage)
huePad.Parent = pickerPanel

local preview = Instance.new("Frame")
preview.Size = UDim2.new(0, 20, 0, 154)
preview.Position = UDim2.new(0, 210, 0, 32)
preview.BorderSizePixel = 0
preview.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
preview.Parent = pickerPanel
Theme.corner(preview, 4)

local hue, sat, val = 0, 1, 1

local function toHSV(c: Color3): (number, number, number)
	local r, g, b = c.R, c.G, c.B
	local hi = math.max(r, g, b)
	local lo = math.min(r, g, b)
	local d = hi - lo
	if d <= 0 then return 0, 0, hi end
	local h
	if hi == r then h = ((g - b) / d) % 6
	elseif hi == g then h = (b - r) / d + 2
	else h = (r - g) / d + 4 end
	return h / 6, d / hi, hi
end

-- 0..1 channels as the bytes WritePixelsBuffer takes: red, green, blue, alpha.
local function asBytes(px)
	local b = buffer.create(#px)
	for i, v in ipairs(px) do
		buffer.writeu8(b, i - 1, math.clamp(math.round(v * 255), 0, 255))
	end
	return b
end

local function drawHues()
	local px = table.create(HUES * 4)
	local n = 0
	for x = 0, HUES - 1 do
		local c = Color3.fromHSV(x / (HUES - 1), 1, 1)
		px[n + 1], px[n + 2], px[n + 3], px[n + 4] = c.R, c.G, c.B, 1
		n += 4
	end
	hueImage:WritePixelsBuffer(Vector2.new(0, 0), Vector2.new(HUES, 1), asBytes(px))
end

local function drawSquare()
	local px = table.create(SV * SV * 4)
	local n = 0
	for y = 0, SV - 1 do
		local v = 1 - y / (SV - 1)
		for x = 0, SV - 1 do
			local c = Color3.fromHSV(hue, x / (SV - 1), v)
			px[n + 1], px[n + 2], px[n + 3], px[n + 4] = c.R, c.G, c.B, 1
			n += 4
		end
	end
	svImage:WritePixelsBuffer(Vector2.new(0, 0), Vector2.new(SV, SV), asBytes(px))
end

local function chosen()
	return Color3.fromHSV(hue, sat, val)
end

local function showChoice()
	preview.BackgroundColor3 = chosen()
end

-- Where in a control the pointer is, 0..1 on both axes. AbsolutePosition and AbsoluteSize
-- are what the panel already lays itself out from, so this needs nothing new.
local function fractionIn(control)
	local size = control.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return nil end
	local at = control.AbsolutePosition
	return math.clamp((mouse.X - at.X) / size.X, 0, 1), math.clamp((mouse.Y - at.Y) / size.Y, 0, 1)
end

local draggingSV, draggingHue = false, false

-- Both of these only act on a change. A GuiObject write sets the whole GUI dirty and the
-- next sync restyles every object in the tree; redrawing the square is four thousand
-- pixels on top of that. Neither is worth doing to arrive at the value already showing.
local function takeSV()
	local x, y = fractionIn(svPad)
	if not x then return end
	if x == sat and (1 - y) == val then return end
	sat, val = x, 1 - y
	showChoice()
end

local function takeHue()
	local x = fractionIn(huePad)
	if not x or x == hue then return end
	hue = x
	drawSquare()
	showChoice()
end

svPad.MouseButton1Down:Connect(function() draggingSV = true takeSV() end)
svPad.MouseButton1Up:Connect(function() draggingSV = false end)
svPad.MouseLeave:Connect(function() draggingSV = false end)
huePad.MouseButton1Down:Connect(function() draggingHue = true takeHue() end)
huePad.MouseButton1Up:Connect(function() draggingHue = false end)
huePad.MouseLeave:Connect(function() draggingHue = false end)

-- RenderStepped: this follows the pointer and has to be right for the frame being drawn.
RunService.RenderStepped:Connect(function()
	if draggingSV then takeSV() elseif draggingHue then takeHue() end
end)

local useButton = Theme.button(pickerPanel, "Use it", Theme.c.good)
useButton.Size = UDim2.new(0, 100, 0, 26)
useButton.Position = UDim2.new(0, 12, 0, 196)
useButton.TextSize = Theme.t.small
useButton:SetAttribute("Sfx", "menu")

local dropButton = Theme.button(pickerPanel, "Cancel")
dropButton.Size = UDim2.new(0, 100, 0, 26)
dropButton.Position = UDim2.new(0, 124, 0, 196)
dropButton.TextSize = Theme.t.small
dropButton:SetAttribute("Sfx", "menu")
dropButton.Activated:Connect(function() pickerWindow.Visible = false end)

useButton.Activated:Connect(function()
	pickerWindow.Visible = false
	if brush <= 1 then return end          -- slot 1 is the eraser; it has no colour
	palette[brush] = chosen()
	if swatchButtons[brush] then swatchButtons[brush].BackgroundColor3 = palette[brush] end
	-- Everything already drawn in this slot is drawn in this colour. That is what an
	-- index means, and it is the whole reason changing one is worth doing.
	for i = 1, #cells do
		if pixels[i] == brush - 1 then cells[i].BackgroundColor3 = palette[brush] end
	end
	hint.Text = ("Colour %d is yours now."):format(brush - 1)
	showBrush()
	drawWords()
end)

local pickButton = Theme.button(panel, "Mix...")
pickButton.Size = UDim2.new(0, LEFT_W, 0, 26)
-- Straight under the colours it mixes, in the clear.
pickButton.Position = UDim2.new(0, 12, 0, 86 + SWATCH_ROWS * (SWATCH + SWATCH_GAP) + 4)
pickButton.TextSize = Theme.t.small
pickButton:SetAttribute("Sfx", "menu")
pickButton.Activated:Connect(function()
	if brush <= 1 then
		hint.Text = "Pick a colour slot first -- the top one is the eraser."
		return
	end
	-- Opens on the colour that slot already holds, so a nudge is a nudge. Written out
	-- rather than called: this runtime has Color3.fromHSV and no toHSV to go back with.
	hue, sat, val = toHSV(palette[brush])
	pickTitle.Text = ("Colour %d"):format(brush - 1)
	drawSquare()
	showChoice()
	pickerWindow.Visible = true
end)

drawHues()
drawSquare()
showChoice()

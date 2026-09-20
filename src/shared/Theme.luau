-- One palette and one type scale, for every panel in the town.
--
-- There were four before this: the dialog, the wardrobe, the drawing table and the
-- shelf each wrote their own colours out by hand, and they had already drifted --
-- 232,238,248 against 233,238,248 for the same ink, three different panel darks, five
-- text sizes doing the work of three. None of that is visible in any one file, which
-- is exactly why it happens.
--
-- Colours are named for what they are for rather than what they look like, so a panel
-- asks for `Theme.c.dim` and not for a particular grey.
--
-- The numbers are Final Fantasy VII's, sampled off screenshots of the real thing rather
-- than remembered: a window is a vertical gradient of pure blue, brightest at the TOP,
-- inside a three-band bevel of greys. Nothing here is a guess at "roughly FF7 blue" --
-- the fill really is R and G at zero, and the gradient really does run dark downward,
-- which is the opposite of what it looks like from memory.
local Theme = {}

Theme.c = {
	ink = Color3.fromRGB(242, 232, 240),      -- body text on a panel
	-- Both of these were dark greys, and the ground they sit on is a dark blue -- so a
	-- hint or a unit or a placeholder was grey-on-navy and barely there. They are lifted
	-- well clear of it now. The order still means what it did: ink is what you read, dim
	-- is what you read second, faint is what you read only if you go looking.
	dim = Color3.fromRGB(196, 190, 208),      -- secondary text, hints, units, unavailable
	faint = Color3.fromRGB(158, 152, 174),    -- placeholders
	panel = Color3.fromRGB(0, 0, 104),        -- a window's ground, mid-gradient
	card = Color3.fromRGB(0, 0, 120),         -- something sitting on that ground
	tile = Color3.fromRGB(0, 0, 82),          -- a well inside a card, behind a picture
	field = Color3.fromRGB(0, 0, 46),         -- somewhere to type
	accent = Color3.fromRGB(221, 219, 222),   -- titles: the bevel's own highlight
	-- "this one is on": equipped, selected, in your hand. The same green the uncommon
	-- rung is drawn in, which is where the eye has been reading "yes" since forever.
	on = Color3.fromRGB(60, 200, 80),
	button = Color3.fromRGB(0, 0, 120),       -- an ordinary button
	good = Color3.fromRGB(0, 0, 151),         -- the button that does the thing
	danger = Color3.fromRGB(96, 0, 40),       -- clear, delete
	warn = Color3.fromRGB(96, 74, 0),         -- locked, out of reach
	warnInk = Color3.fromRGB(228, 190, 120),
	muted = Color3.fromRGB(58, 58, 78),       -- a button that cannot be pressed
	figure = Color3.fromRGB(222, 203, 207),   -- a number worth reading down a column

	-- The window itself.
	fillTop = Color3.fromRGB(0, 0, 151),
	fillBottom = Color3.fromRGB(0, 0, 56),
	bevel = Color3.fromRGB(147, 147, 147),      -- the outer band
	bevelLight = Color3.fromRGB(221, 219, 222), -- the highlight that makes it stand up
	bevelDark = Color3.fromRGB(73, 73, 73),     -- the line between frame and fill
	shadow = Color3.fromRGB(8, 8, 12),          -- under every piece of text
	gaugeFill = Color3.fromRGB(222, 203, 207),
	gaugeEmpty = Color3.fromRGB(89, 89, 89),
	-- A scrollbar. Roblox's default for ScrollBarImageColor3 is black, and the renderer
	-- honours that faithfully, which on this town's navy grounds is a bar you cannot see.
	scrollbar = Color3.fromRGB(226, 224, 232),
}

-- The face the place ships with, set by the host once it has fetched it; until then
-- this is nil and every label keeps the engine's default rather than failing.
--
-- Reactor7 is a pixel font drawn on a 16-pixel grid, so the sizes are 16 and its
-- multiples. Anything between them lands glyph edges on half pixels and furs up the
-- whole panel, which is the one way to make a pixel font look worse than a smooth one.
Theme.font = nil

-- One working size, and a half size for units and hints.
--
-- 32 rather than 16 because Reactor7's ascender is 0.5625 em where a text face is nearer
-- 0.75: at the same nominal size it draws about a third smaller than the font it replaces,
-- so 16 would have quietly shrunk every panel in the town. 32 and 16 are both on the
-- font's own 16-pixel grid; anything between them lands glyph edges on half pixels.
--
-- Title, heading and body are deliberately the same. The reference sets "Gained EXP and
-- AP." in the same size as "Cloud" and "Select a slot." in the same size as "SLOT 1":
-- hierarchy there comes from which box a thing sits in, not from type size.
Theme.t = { title = 32, heading = 32, body = 32, small = 16 }

Theme.pad = 16          -- a panel's inner margin
Theme.gap = 8           -- between things that belong together
Theme.radius = 2        -- square, near enough: the corners are barely eased

function Theme.corner(inst: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.radius)
	c.Parent = inst
	return c
end

-- Everything the face has been put on, so it can be put on again.
--
-- Weak keys: a panel that has been destroyed should not be held alive by this list, and
-- the shop builds a fresh card for every item on every refresh.
local faced = setmetatable({}, { __mode = "k" })

--- Puts the place's own face on a label or button, if there is one yet.
---
--- Public, because most panels build their text with Instance.new rather than through
--- Theme.label -- they want a size or an alignment the helper does not take -- and a font
--- that only reached the two helpers would have styled about a fifth of the town.
function Theme.face(inst: Instance)
	faced[inst] = true
	-- The town's face is a pixel font: drawn hard-edged in PulseBlockz. Roblox ignores the attribute
	-- and draws it smooth, as it draws every font.
	pcall(function() inst:SetAttribute("PixelFont", true) end)
	if Theme.font then
		pcall(function() inst.FontFace = Theme.font end)
	end
	return inst
end
local face = Theme.face

--- The place's face has arrived. Applies it to everything already built.
---
--- Panels build their chrome the moment their script loads, and the font is a published
--- asset that has to be fetched -- so the title bar, the footer and the close button exist
--- well before it lands, while the rows built later already have it. Setting Theme.font
--- alone gave exactly that: a panel in two typefaces at once.
function Theme.setFont(font)
	Theme.font = font
	for inst in pairs(faced) do
		pcall(function() inst.FontFace = font end)
	end
end

--- A window: the three-band bevel with the blue gradient inside it.
---
--- Returns the inner frame to put things in, not the outer one. The bands are nested
--- frames rather than an UIStroke because a stroke is one colour and this is three, and
--- the middle one is a highlight -- take it away and the panel lies flat against the
--- world instead of standing off it.
--- How big to draw a window, given the smallest it works at.
---
--- Not a scale: this does not magnify anything. the text, rows and
--- buttons keep the size they already are, and the window simply gets more room to put them
--- in -- so a list shows ten rows instead of four rather than four larger ones. For panels
--- whose contents already read well and whose layout is anchored to its edges.
---
--- Height grows further than width on purpose: what runs out is nearly always rows, and a
--- row stretched to twice its drawn width just has more gap in the middle of it.
---
--- Worked out once, when the panel is built. Geometry in this runtime is settled at build
--- time, so a window resized afterwards does not move it.
function Theme.roomFor(minW: number, minH: number): (number, number)
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 800)
	if vp.X < 1 or vp.Y < 1 then return minW, minH end
	return math.floor(math.clamp(vp.X * 0.9, minW, minW * 1.4)),
	       math.floor(math.clamp(vp.Y * 0.9, minH, minH * 2))
end

--- Magnifies a whole ScreenGui to suit the window it is in.
---
--- For panels drawn at a fixed pixel size that read correctly at that size and are simply
--- too small on a big screen -- the scan, the screener, the swap panel. A UIScale on the
--- ScreenGui scales its layer, so everything inside keeps its place and its proportions and
--- the pointer still lands where it looks like it does.
---
--- `w` and `h` are the size the panel was drawn for. The scale is how many of those fit,
--- with a little room around it, and never below one: shrinking a panel that already reads
--- correctly is not what this is for.
--- A button that steps a window through its sizes.
---
--- It sets the scale, and that is all it does. The version before this worked out what would
--- fit the window and multiplied your choice into it, then capped the result at what fits --
--- so every step at or above one came out the same number and five settings drew two sizes.
--- Directly is easier to write, easier to read, and it does what the label says.
---
--- Whole steps up from the size it was drawn at, and nothing below it: a panel smaller than
--- it was drawn is not something anybody wants a button for.
---
--- It stops at one and three quarters. TWO was the one that was too big -- these panels are
--- drawn near the size of a window already, so doubling one does not show you more of it, it
--- puts the edges past the screen. One and three quarters went with it by mistake and is
--- back, which is what was asked for.
Theme.scaleSteps = { 1, 1.25, 1.5, 1.75 }

--- `screen` is the ScreenGui the scale goes on -- the window scales, not the button -- and
--- `pos` is wherever that panel has room for it.
function Theme.scaleButton(screen: Instance, parent: Instance, pos: UDim2)
	local scale = screen:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = screen
	end

	local at = 1
	local b = Theme.button(parent, "1x")
	-- Inverted, white with blue ink: it sits wherever each window has room for it rather than in one
	-- place, so it has to stand out from the buttons around it to be found.
	b.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	b.TextColor3 = Theme.c.good
	b.Size = UDim2.new(0, 46, 0, 22)
	b.Position = pos
	b.TextSize = Theme.t.small
	b:SetAttribute("Sfx", "menu")
	b.Activated:Connect(function()
		at = at % #Theme.scaleSteps + 1
		scale.Scale = Theme.scaleSteps[at]
		b.Text = ("%gx"):format(Theme.scaleSteps[at])
	end)
	return b
end

function Theme.window(parent: Instance, size: UDim2, pos: UDim2?)
	local outer = Instance.new("Frame")
	outer.BackgroundColor3 = Theme.c.bevel
	outer.BorderSizePixel = 0
	outer.Size = size
	if pos then outer.Position = pos end
	outer.Parent = parent
	Theme.corner(outer)

	local light = Instance.new("Frame")
	light.BackgroundColor3 = Theme.c.bevelLight
	light.BorderSizePixel = 0
	light.Position = UDim2.new(0, 2, 0, 2)
	light.Size = UDim2.new(1, -4, 1, -4)
	light.Parent = outer
	Theme.corner(light)

	local dark = Instance.new("Frame")
	dark.BackgroundColor3 = Theme.c.bevelDark
	dark.BorderSizePixel = 0
	dark.Position = UDim2.new(0, 3, 0, 3)
	dark.Size = UDim2.new(1, -6, 1, -6)
	dark.Parent = light
	Theme.corner(dark)

	local inner = Instance.new("Frame")
	inner.Name = "Content"
	-- Nothing draws outside the window. A GuiObject does not clip its own text to its size
	-- here, so a wrapped label in a box an inch too short spills over the edge and onto the
	-- world, and a row of columns laid out for a narrower panel runs off the side. Clipping
	-- at the window turns both into something merely cut off rather than something loose on
	-- the screen.
	inner.ClipsDescendants = true
	inner.BackgroundColor3 = Theme.c.fillTop
	inner.BorderSizePixel = 0
	inner.Position = UDim2.new(0, 2, 0, 2)
	inner.Size = UDim2.new(1, -4, 1, -4)
	inner.Parent = dark

	-- The gradient, as bands rather than a UIGradient, because the renderer does not
	-- implement UIGradient -- it is accepted, it changes nothing, and the panel comes out
	-- flat. Bands are also nearer the truth: the original is a PlayStation gradient and
	-- has visible steps in it, so this is not a workaround pretending to be smooth.
	--
	-- They sit behind everything at ZIndex 0, which the host reads as the sibling order
	-- for hit testing as well as for drawing. That matters more than it sounds: a Frame is
	-- offered the pointer even with nothing drawn in it, so a band that came out on top
	-- would quietly eat every click on the button above it -- and these tile the whole
	-- window, so it would be every button in every panel, a different scattering of them
	-- each run. ZIndex is what keeps them underneath; do not leave it to the default.
	local BANDS = 14
	for i = 0, BANDS - 1 do
		local band = Instance.new("Frame")
		band.Name = "Band" .. i
		band.BorderSizePixel = 0
		band.BackgroundColor3 = Theme.c.fillTop:Lerp(Theme.c.fillBottom, i / (BANDS - 1))
		band.Position = UDim2.new(0, 0, i / BANDS, 0)
		band.Size = UDim2.new(1, 0, 1 / BANDS, 1)
		band.ZIndex = 0
		band.Active = false
		band.Parent = inner
	end
	-- Both: the inside to put things in, and the outside to move or resize. A caller that
	-- wants neither can ignore the second, but a panel that has to fit itself to the window
	-- cannot get at the frame it needs to change without it.
	return inner, outer
end

--- Centres a window in the viewport, and again whenever the viewport changes.
---
--- Every panel needs this and none of them can do it with a scale term. A client script
--- builds its panel the instant it loads, when the ScreenGui reports 0 x 0 and the camera
--- reports a placeholder 1024 x 768 against the real window; `0.5` is resolved once against
--- whichever of those it got and never revisited, so the panel sits off-centre for the
--- session while its Position property reads back as though it were fine. AnchorPoint is
--- not honoured by this renderer either, so offsets computed from a viewport we have
--- actually seen are what is left.
function Theme.centre(window: Instance, w: number, h: number)
	-- Measured off the ScreenGui, not the camera.
	--
	-- The camera reports a placeholder 1024 x 768 and, in a windowed client, goes on
	-- reporting it -- every panel centred against it sat a fixed distance left and high, and
	-- the widest one hung off the left edge at x -28. The ScreenGui knows the real size; it
	-- just does not know it yet at load, when it reads 0 x 0. So: prefer the ScreenGui once
	-- it has a size, fall back to the camera until then, and keep checking for a few
	-- seconds because neither of them announces the moment it becomes true.
	local function place()
		local surface = window
		while surface and not surface:IsA("ScreenGui") do
			surface = surface.Parent
		end
		local size = surface and surface.AbsoluteSize
		if not size or size.X <= 0 then
			local cam = workspace.CurrentCamera
			size = cam and cam.ViewportSize
		end
		if not size or size.X <= 0 then return end
		window.Position = UDim2.new(0, math.floor((size.X - w) / 2), 0, math.floor((size.Y - h) / 2))
	end
	place()
	task.defer(place)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
	end
	-- And keep placing it for the first few seconds regardless. The camera reports a
	-- placeholder size at load and the changed signal does not always arrive when it stops
	-- being a placeholder, which left panels centred in a window that was never there --
	-- one of them at x -28, hanging off the left edge.
	task.spawn(function()
		for _ = 1, 40 do
			task.wait(0.1)
			place()
		end
	end)
end

--- A panel taking over from the conversation that opened it.
---
--- Every one of these is reached by choosing something from an NPC's menu, and the server
--- answers with both the panel and a line of dialogue -- so the dialog stayed up, centred,
--- over a panel that is also centred and about the same size. It sat on top and took every
--- click: nothing on the shelf or the board could be pressed, and the only thing that still
--- worked was the dialog menu showing through underneath.
function Theme.takeOver(gui: Instance)
	local dialog = gui:FindFirstChild("TownDialog")
	if dialog then dialog.Enabled = false end
end

--- A label with the usual defaults: transparent, left aligned, body sized.
---
--- Every one of them is drawn twice, the lower copy in near-black one pixel down and
--- right. FF7 puts white text straight onto a mid blue and it stays legible because of
--- that shadow; without it the same text over the bright top of the gradient goes soft.
function Theme.label(parent: Instance, text: string, opts)
	opts = opts or {}
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = opts.colour or Theme.c.ink
	l.TextSize = opts.size or Theme.t.body
	l.TextXAlignment = opts.align or Enum.TextXAlignment.Left
	l.TextYAlignment = opts.valign or Enum.TextYAlignment.Center
	l.Text = text
	if opts.size2 then l.Size = opts.size2 end
	if opts.pos then l.Position = opts.pos end
	face(l)
	l.Parent = parent

	if not opts.flat then
		local sh = l:Clone()
		-- Faced itself, not only copied: a label made before the font arrives is re-faced when it
		-- lands, and a copy nobody told about kept the engine's face -- a shadow in another typeface,
		-- the wrong size and offset from the words it is under.
		face(sh)
		sh.Name = "Shadow"
		sh.TextColor3 = Theme.c.shadow
		sh.ZIndex = l.ZIndex - 1
		sh.Position = UDim2.new(l.Position.X.Scale, l.Position.X.Offset + 1,
			l.Position.Y.Scale, l.Position.Y.Offset + 1)
		sh.Parent = parent
	end
	return l
end

function Theme.button(parent: Instance, text: string, colour: Color3?)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = colour or Theme.c.button
	b.TextColor3 = Theme.c.ink
	b.TextSize = Theme.t.body
	b.Text = text
	face(b)
	b.Parent = parent
	Theme.corner(b)
	return b
end

-- Rarity, one colour per rung of the ladder, because there are now six rungs and six is
-- exactly what the twenty-year-old loot palette has room for. It used to be ten rungs
-- collapsed onto five colours, which meant two rungs shared a ring and nobody could tell
-- which one a thing was.
--
-- Gold is the new one, sat between purple and orange: five colours had orange as the top and
-- there was nowhere left to put a sixth without inventing one nobody reads.
Theme.rarity = {
	Color3.fromRGB(220, 224, 232),   -- 5 PLS   common
	Color3.fromRGB(60, 200, 80),     -- 10      uncommon
	Color3.fromRGB(52, 132, 245),    -- 20      rare
	Color3.fromRGB(168, 82, 240),    -- 30      epic
	Color3.fromRGB(232, 190, 64),    -- 40      gold
	Color3.fromRGB(255, 138, 26),    -- 50      legendary
}

-- What each rung is called. Named for the ring rather than for a sea creature: the fish
-- ladder was a second vocabulary for the same six numbers, and nobody could say whether a
-- Crab outranked a rare without looking it up.
Theme.rarityNames = { "Common", "Uncommon", "Rare", "Epic", "Gold", "Legendary" }

--- The name of a rung, clamped the way its colour is.
function Theme.rarityName(tier: number?): string
	local i = math.clamp((tier or 0) + 1, 1, #Theme.rarityNames)
	return Theme.rarityNames[i]
end

--- The colour for a rung, clamped, so an unknown tier is common rather than an error.
function Theme.rarityOf(tier: number?)
	local i = math.clamp((tier or 0) + 1, 1, #Theme.rarity)
	return Theme.rarity[i]
end

-- The paper doll. `col` is which side of the character panel it hangs on; the order
-- here is the order they are drawn. Slots nothing is published for yet are still
-- drawn, empty -- an empty socket says "this is a thing you could have" in a way a
-- missing one does not.
--
-- Five a side: the left column is the trunk, top down, and the right the limbs. A sixth
-- socket on a side would sit under the weapon row.
Theme.slots = {
	{ key = "head",     label = "Head",      col = "left"   },
	{ key = "neck",     label = "Neck",      col = "left"   },
	{ key = "back",     label = "Back",      col = "left"   },
	{ key = "chest",    label = "Chest",     col = "left"   },
	{ key = "shirt",    label = "Shirt",     col = "left"   },
	{ key = "hands",    label = "Hands",     col = "right"  },
	{ key = "wrist",    label = "Wrist",     col = "right"  },
	{ key = "waist",    label = "Waist",     col = "right"  },
	{ key = "legs",     label = "Legs",      col = "right"  },
	{ key = "feet",     label = "Feet",      col = "right"  },
	{ key = "mainhand", label = "Main Hand", col = "bottom" },
	{ key = "offhand",  label = "Off Hand",  col = "bottom" },
	{ key = "pet",      label = "Pet",       col = "bottom" },
}

function Theme.slotLabel(key: string?)
	for _, s in ipairs(Theme.slots) do
		if s.key == key then return s.label end
	end
	return "Trinket"          -- anything published before slots existed
end

return Theme

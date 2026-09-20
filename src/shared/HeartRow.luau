-- A row of hearts, wherever hearts have to be drawn.
--
-- Two places need them now: the meter along the bottom of your own screen, and the little
-- row over everyone's head while PvP is on. They are the same hearts and they are read the
-- same way -- half a container is half a heart -- so they are built once here rather than
-- twice, in a screen HUD and a billboard that would drift apart the first time either was
-- touched.
--
-- One picture serves every state. An ImageLabel's ImageColor3 multiplies, so the white heart
-- scripts/prep-hearts.js draws is a red heart when tinted red, an empty container when
-- tinted grey, and a streak's four colours when tinted with them. Halves are clipped rather
-- than drawn: a whole heart sits inside a frame that shows as much of its width as is left.
local HeartRow = {}
HeartRow.__index = HeartRow

--- The most containers anybody can have: three, or four while they are on a streak.
local MOST = 4

local EMPTY = Color3.fromRGB(52, 48, 60)
local PLAIN = Color3.fromRGB(228, 48, 48)

--- The Heart Cape's four colours, in its order: what the containers turn on a streak.
---
--- Here rather than in Health.luau because three sides need them now and none of them is
--- the authority. The server decides WHO is on a streak; the meter along your own screen
--- and the row over everyone's head both decide what that looks like, and the one over
--- their head is drawn on each client off a replicated flag rather than sent down with the
--- colours in the message. A table written twice is a streak that is four colours in one
--- place and red in the other.
local FIRE = {
	Color3.fromRGB(228, 48, 48),
	Color3.fromRGB(238, 200, 44),
	Color3.fromRGB(66, 190, 76),
	Color3.fromRGB(56, 200, 220),
}

HeartRow.PLAIN = PLAIN
HeartRow.FIRE = FIRE

--- What colours a row should be drawn in, on or off a streak.
function HeartRow.colours(onFire: boolean?)
	return onFire and FIRE or { PLAIN }
end

--- A row that grows from its middle, so three containers and four are both centred.
---
--- `fill`: laid out in shares of `parent` rather than in pixels, for a row that has to grow and
--- shrink with whatever it is in -- the one over a head, which is sized in studs and so is bigger
--- the closer it is. `parent` is then MOST hearts wide and one heart high, and `size` and `gap` are
--- only their proportions.
function HeartRow.new(parent, size, gap, fill)
	local row = Instance.new("Frame")
	row.Name = "Hearts"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.new(0.5, 0, 0.5, 0)
	row.Size = fill and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 0, 0, size)
	row.Parent = parent
	return setmetatable({ row = row, size = size, gap = gap, fill = fill == true, slots = {}, icon = "" }, HeartRow)
end

--- The picture, which arrives with the place assets and so is usually late.
function HeartRow:setIcon(image)
	self.icon = image or ""
	for _, slot in ipairs(self.slots) do
		slot.empty.Image = self.icon
		slot.full.Image = self.icon
	end
end

--- Builds or removes containers until there are `n` of them.
function HeartRow:fit(n)
	while #self.slots > n do
		self.slots[#self.slots].holder:Destroy()
		self.slots[#self.slots] = nil
	end
	while #self.slots < n do
		local i = #self.slots + 1
		local holder = Instance.new("Frame")
		holder.Name = "Heart" .. i
		holder.BackgroundTransparency = 1
		holder.Size = self.fill and UDim2.new(0, 0, 1, 0) or UDim2.new(0, self.size, 0, self.size)
		holder.Parent = self.row

		local empty = Instance.new("ImageLabel")
		empty.Name = "Empty"
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 1, 0)
		empty.Image = self.icon
		empty.ImageColor3 = EMPTY
		empty.Parent = holder

		-- The filled part, shown through a window that narrows as it is spent.
		local window = Instance.new("Frame")
		window.Name = "Window"
		window.BackgroundTransparency = 1
		window.ClipsDescendants = true
		window.Size = UDim2.new(1, 0, 1, 0)
		window.Parent = holder

		local full = Instance.new("ImageLabel")
		full.Name = "Full"
		full.BackgroundTransparency = 1
		-- Sized to the holder, not to the window, so clipping the window takes a slice off
		-- the heart instead of squashing it.
		full.Size = self.fill and UDim2.new(1, 0, 1, 0) or UDim2.new(0, self.size, 0, self.size)
		full.Image = self.icon
		full.Parent = window

		self.slots[i] = { holder = holder, empty = empty, window = window, full = full }
	end
	if self.fill then
		-- In shares: the row is as wide as n hearts of the MOST the parent was made for, and each
		-- heart a share of the row.
		local most = MOST * self.size + (MOST - 1) * self.gap
		local width = n * self.size + math.max(0, n - 1) * self.gap
		self.row.Size = UDim2.new(width / most, 0, 1, 0)
		for i, slot in ipairs(self.slots) do
			slot.holder.Size = UDim2.new(self.size / width, 0, 1, 0)
			slot.holder.Position = UDim2.new((i - 1) * (self.size + self.gap) / width, 0, 0, 0)
		end
		return
	end
	self.row.Size = UDim2.new(0, n * self.size + math.max(0, n - 1) * self.gap, 0, self.size)
	for i, slot in ipairs(self.slots) do
		slot.holder.Position = UDim2.new(0, (i - 1) * (self.size + self.gap), 0, 0)
	end
end

--- half: half-hearts left. maxHalf: out of how many. colours: one per container, or one for
--- all of them.
function HeartRow:draw(half, maxHalf, colours)
	-- Never more containers than this town has, whatever it is told.
	--
	-- Health here IS the half-heart count -- MaxHealth is six, or eight on a streak -- which
	-- is what keeps a graze exactly one and a container exactly two, with no rounding. The
	-- cost is that a body the server has not dressed yet still carries Roblox's default
	-- MaxHealth of 100, and asked to draw that this made fifty containers in a row nineteen
	-- hundred pixels wide: "a line of like 100 hearts will show for a sec", on every spawn.
	--
	-- The caller waiting for a sane MaxHealth is the real fix. This is the one that cannot be
	-- forgotten by the next caller, and there will be one -- the screen HUD and the row over a
	-- head already share this.
	local containers = math.clamp(math.ceil(maxHalf / 2), 1, MOST)
	self:fit(containers)
	colours = colours or { PLAIN }
	for i, slot in ipairs(self.slots) do
		local left = math.clamp(half - (i - 1) * 2, 0, 2)
		slot.window.Size = UDim2.new(left / 2, 0, 1, 0)
		slot.window.Visible = left > 0
		-- Filling in shares, the heart is the holder's size however narrow its window is.
		if self.fill and left > 0 then slot.full.Size = UDim2.new(2 / left, 0, 1, 0) end
		slot.full.ImageColor3 = colours[i] or colours[1] or PLAIN
	end
end

--- How wide the row is now, in pixels: what a billboard needs to size itself to.
function HeartRow:width()
	local n = #self.slots
	return n * self.size + math.max(0, n - 1) * self.gap
end

return HeartRow

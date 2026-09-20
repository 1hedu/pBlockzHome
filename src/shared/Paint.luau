-- What the tailor's drawing is made of.
--
-- The grid and the sixteen colours a cape is painted in. This was in the client, published
-- to the place in every payload as a `paint` field -- which meant a place could only offer
-- painting if its client happened to hold a palette, and only ever THIS palette. A place
-- that wants a different sixteen, or a bigger grid, had no way to say so.
--
-- Both halves read it: the panel draws with it and the server encodes with it. That is the
-- reason it is shared rather than sitting on either side -- a palette that is two lists is
-- a cape that does not look like the drawing.
local Paint = {}

--- The grid. Twenty by twenty-six is a cape-shaped rectangle, small enough to draw with a
--- mouse and few enough cells to send as one short string.
Paint.W = 20
Paint.H = 26

--- Blown up this much before it is stored. A Decal stretched from twenty pixels across a
--- whole back is a blur; nearest-neighbour at six keeps the pixel art crisp at the size a
--- cape actually is.
Paint.SCALE = 6

--- Sixteen colours, indexed by one hex digit each. Index 0 is transparent, so a drawing can
--- have holes in it rather than a white background it never asked for.
Paint.PALETTE = {
	{ 0, 0, 0, 0 },        { 24, 24, 28, 255 },   { 245, 245, 248, 255 }, { 140, 140, 150, 255 },
	{ 220, 50, 50, 255 },  { 240, 140, 40, 255 }, { 245, 215, 60, 255 },  { 70, 180, 80, 255 },
	{ 40, 190, 190, 255 }, { 60, 110, 230, 255 }, { 110, 70, 220, 255 },  { 225, 60, 180, 255 },
	{ 250, 150, 180, 255 },{ 140, 95, 60, 255 },  { 214, 172, 66, 255 },  { 20, 230, 255, 255 },
}

--- The colour a hex digit means, as {r, g, b, a}. Anything unrecognised is index 0, which
--- is transparent -- a drawing with a stray character in it comes back with a hole, not a
--- wrong colour and not an error.
function Paint.colour(digit)
	local at = (string.find("0123456789abcdef", tostring(digit):lower(), 1, true) or 1) - 1
	return Paint.PALETTE[at + 1] or Paint.PALETTE[1]
end

--- A palette as the table sends it: sixteen colours, six hex digits each, in slot order. The
--- swatches can be mixed to any colour, and what was drawn is what gets stored -- so the colours
--- travel with the drawing. Slot 1 is the eraser whatever it says, and is always transparent.
--- Returns {r, g, b, a} lists like PALETTE, or nil and a reason.
function Paint.parsePalette(hex)
	if type(hex) ~= "string" or #hex ~= 96 or hex:find("[^%x]") then
		return nil, "that is not a palette"
	end
	local out = { { 0, 0, 0, 0 } }
	for i = 2, 16 do
		local at = (i - 1) * 6
		table.insert(out, { tonumber(hex:sub(at + 1, at + 2), 16), tonumber(hex:sub(at + 3, at + 4), 16),
			tonumber(hex:sub(at + 5, at + 6), 16), 255 })
	end
	return out
end

-- ---- words ---------------------------------------------------------------------------------
-- One line of words on a cape, in the town's own face (shared/Glyphs.luau), stamped into the
-- picture at full size rather than into the cells: a letter is ten pixels tall and a cell is six,
-- so on the cell grid a word would be a smudge.

Paint.TEXT_MAX = 24          -- characters
Paint.TEXT_SCALES = 3        -- 1x, 2x, 3x

--- Words as the table sends them -- { text, x, y, colour, scale }, x and y in the stored picture's
--- pixels, colour a palette slot -- checked and cleaned. Nil for "no words", which is fine; nil and
--- a reason for words that cannot be used.
function Paint.checkText(spec)
	if spec == nil then return nil end
	if type(spec) ~= "table" or type(spec.text) ~= "string" then return nil, "those are not words" end
	local text = spec.text:gsub("[^\32-\126]", ""):sub(1, Paint.TEXT_MAX)
	if text:gsub("%s", "") == "" then return nil end
	local colour = math.floor(tonumber(spec.colour) or 0)
	if colour < 1 or colour > 15 then return nil, "the words need a colour, not the eraser" end
	local scale = math.clamp(math.floor(tonumber(spec.scale) or 1), 1, Paint.TEXT_SCALES)
	local x = math.floor(tonumber(spec.x) or 0)
	local y = math.floor(tonumber(spec.y) or 0)
	local w, h = Paint.W * Paint.SCALE, Paint.H * Paint.SCALE
	if x < -w or x > w or y < -h or y > h then return nil, "the words are off the cape" end
	return { text = text, x = x, y = y, colour = colour, scale = scale }
end

--- Is this a drawing this place can accept? Returns false and a reason.
function Paint.check(indices)
	if type(indices) ~= "string" then return false, "that is not a drawing" end
	if #indices ~= Paint.W * Paint.H then
		return false, ("a drawing is %d cells; that one is %d"):format(Paint.W * Paint.H, #indices)
	end
	return true
end

return Paint

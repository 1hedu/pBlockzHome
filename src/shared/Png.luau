-- Pixels to a PNG, in the place.
--
-- The tailor lets a player draw a cape and publish it, and publishing means bytes. Turning
-- pixels into those bytes lived in the client -- Godot's Image.save_png_to_buffer -- which
-- made "a place where people make things" a feature of the program rather than of the place.
--
-- ---- why this one is ours ------------------------------------------------------------
-- Decoding belongs to the client and always did: it must decode a PNG to draw anything at
-- all, the same as a mesh or a font. Encoding is the other direction, and there is no Roblox
-- precedent to copy because a Roblox place cannot publish what a player made to a chain --
-- the whole motion does not exist there. So it is not a parity question. It is the thing
-- this project is FOR, and it belongs to the place, which is what decides that people may
-- make things here.
--
-- It was never blocked, either. Encoding calldata needs keccak and Luau has no hash, which
-- is why the wallet does that one. A PNG needs bytes and arithmetic, and Luau has bit32,
-- buffer, string.pack and string.byte.
--
-- ---- stored, not compressed ----------------------------------------------------------
-- A PNG's pixel data is a zlib stream, and zlib allows blocks that are copied through --
-- no Huffman tree, no back-references, no compressor. The images here are a small drawing
-- scaled up, a few tens of kilobytes at worst, paid for once in gas rather than every time
-- they are served. A deflate compressor written here to save a few kilobytes would be a lot
-- of code that can be subtly wrong in ways a picture does not reveal until somebody looks.
local Base64 = require(game:GetService("ReplicatedStorage"):WaitForChild("Base64"))

local Png = {}

local crcTable = nil
local function crc32Table()
	if crcTable then return crcTable end
	crcTable = {}
	for i = 0, 255 do
		local c = i
		for _ = 1, 8 do
			if bit32.band(c, 1) == 1 then
				c = bit32.bxor(0xEDB88320, bit32.rshift(c, 1))
			else
				c = bit32.rshift(c, 1)
			end
		end
		crcTable[i] = c
	end
	return crcTable
end

local function crc32(s)
	local t = crc32Table()
	local c = 0xFFFFFFFF
	for i = 1, #s do
		c = bit32.bxor(t[bit32.band(bit32.bxor(c, string.byte(s, i)), 0xFF)], bit32.rshift(c, 8))
	end
	return bit32.bxor(c, 0xFFFFFFFF)
end

--- Adler-32, which is what zlib checksums the UNCOMPRESSED bytes with. A different sum from
--- the CRC over each chunk, and mixing the two up makes a file every decoder rejects with
--- the same unhelpful message.
local function adler32(s)
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + string.byte(s, i)) % 65521
		b = (b + a) % 65521
	end
	return b * 65536 + a
end

local function be32(n)
	return string.char(bit32.band(bit32.rshift(n, 24), 0xFF),
		bit32.band(bit32.rshift(n, 16), 0xFF),
		bit32.band(bit32.rshift(n, 8), 0xFF),
		bit32.band(n, 0xFF))
end

--- One chunk. The CRC covers the type and the data but NOT the length, which is where a
--- hand-written encoder usually goes wrong.
local function chunk(kind, data)
	return be32(#data) .. kind .. data .. be32(crc32(kind .. data))
end

--- zlib around raw bytes, as stored blocks.
local function zlib(raw)
	local out = { string.char(0x78, 0x01) }        -- CM 8, 32k window, no preset dictionary
	local at, n = 1, #raw
	if n == 0 then
		return table.concat(out) .. string.char(1, 0, 0, 0xFF, 0xFF) .. be32(adler32(raw))
	end
	while at <= n do
		local take = math.min(65535, n - at + 1)
		out[#out + 1] = string.char((at + take > n) and 1 or 0)
		-- LEN then its complement, both little-endian. A decoder checks they disagree
		-- exactly, which catches a stream that has lost its place.
		out[#out + 1] = string.char(bit32.band(take, 0xFF), bit32.rshift(take, 8))
		local inv = bit32.bxor(take, 0xFFFF)
		out[#out + 1] = string.char(bit32.band(inv, 0xFF), bit32.rshift(inv, 8))
		out[#out + 1] = string.sub(raw, at, at + take - 1)
		at += take
	end
	out[#out + 1] = be32(adler32(raw))
	return table.concat(out)
end

--- An RGBA PNG from a flat array of bytes, four per pixel, row by row from the top left.
--- Returns the file as a string of bytes.
function Png.encode(width, height, pixels)
	assert(width > 0 and height > 0, "a picture needs a size")
	assert(#pixels == width * height * 4,
		("expected %d bytes, got %d"):format(width * height * 4, #pixels))

	-- Each row carries its filter byte first. Zero means "as it is": filtering exists to
	-- help a compressor spot patterns, and there is no compressor here to help.
	local rows = {}
	for y = 0, height - 1 do
		local row = table.create(width * 4 + 1)
		row[1] = string.char(0)
		local base = y * width * 4
		for x = 1, width * 4 do
			row[x + 1] = string.char(pixels[base + x])
		end
		rows[#rows + 1] = table.concat(row)
	end
	local raw = table.concat(rows)

	local ihdr = be32(width) .. be32(height) .. string.char(8, 6, 0, 0, 0)   -- 8-bit, RGBA
	return string.char(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
		.. chunk("IHDR", ihdr)
		.. chunk("IDAT", zlib(raw))
		.. chunk("IEND", "")
end

--- The same from what a paint panel actually holds: one hex digit per pixel and a palette
--- of up to sixteen {r, g, b, a}. `scale` repeats each pixel, so a small drawing arrives as
--- something you can look at.
function Png.fromPalette(width, height, indices, palette, scale)
	scale = math.max(1, math.floor(scale or 1))
	local w, h = width * scale, height * scale
	local px = table.create(w * h * 4)
	for y = 0, h - 1 do
		local sy = math.floor(y / scale)
		for x = 0, w - 1 do
			local sx = math.floor(x / scale)
			local i = sy * width + sx + 1
			local d = string.sub(indices, i, i):lower()
			local at = (string.find("0123456789abcdef", d, 1, true) or 1) - 1
			local c = palette[at + 1] or { 0, 0, 0, 0 }
			local o = (y * w + x) * 4
			px[o + 1] = c[1] or 0
			px[o + 2] = c[2] or 0
			px[o + 3] = c[3] or 0
			px[o + 4] = c[4] or 255
		end
	end
	return Png.encode(w, h, px)
end

--- Base64, because that is how bytes reach the wallet's `store`.
-- Kept under this name because it is what the tailor and the tests call, but the encoder
-- itself is Base64.luau now: an Engram publishes two documents with no picture in either,
-- so base64 is not a PNG concern and should not have to be required through one.
function Png.base64(bytes)
	return Base64.encode(bytes)
end

return Png

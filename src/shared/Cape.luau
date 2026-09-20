-- A cape somebody drew: its geometry, its picture, and putting it on the chain.
--
-- All of this was in the client. That made "a town with a tailor in it" a feature of the
-- program: load this place with any other client and the counter takes your drawing and can
-- do nothing with it.
--
-- The sequence is why `store` exists as a verb of its own. A cape is four things -- the
-- drawing, the model that wears it, a picture for the shelf, and a description naming the
-- other three -- and each one's content hash is an argument to the next. A place cannot say
-- in advance what call it wants to make, because it does not know the hashes until the
-- earlier ones have landed.
local Png = require(game:GetService("ReplicatedStorage"):WaitForChild("Png"))
local Paint = require(game:GetService("ReplicatedStorage"):WaitForChild("Paint"))
local Glyphs = require(game:GetService("ReplicatedStorage"):WaitForChild("Glyphs"))

local Cape = {}

local CLOTH = { 242, 242, 246 }

--- The cape's shape, written down once.
---
--- Both the model that goes on the chain and the draft you try on at the table are built
--- from this. Two copies of these numbers is a preview that lies about what you are about
--- to publish, which is the one thing a preview must not do.
---
--- A flat back panel with the drawing decalled across it, and two edges canted five degrees
--- out so it reads as cloth hanging rather than a board strapped on.
---
--- Out at the HEM, and these signs are the way round they are for a measured reason.
---
--- They were `side * -5` from 084cb9b until the drawing table could show a cape on its own,
--- at which point it was plain that the cloth splayed at the shoulders and pinched at the
--- bottom -- a cape worn upside down. It had never been visible: the shelf picture comes
--- from Cape.thumbnail, which widens toward the hem and always did, and the picture was the
--- only thing anybody looked at.
---
--- Measured off the preview with these values: the cloth is 159 pixels across at the top
--- and 175 at the bottom. Do not flip them back on a right-hand-rule argument -- that is
--- exactly what nearly put them back the wrong way round; take a picture instead.
local SHAPE = {
	{ name = "Handle",    pos = { 0, -0.55, 0.14 },     size = { 1.9, 2.5, 0.08 },   roll = 0 },
	{ name = "EdgeLeft",  pos = { -0.93, -0.55, 0.14 }, size = { 0.16, 2.28, 0.07 }, roll = -5 },
	{ name = "EdgeRight", pos = { 0.93, -0.55, 0.14 },  size = { 0.16, 2.28, 0.07 }, roll = 5 },
}

--- Where the cape hangs off you, in the Handle's own frame.
local NECK = { 0, 0.55, -0.14 }

--- The cape, as the model JSON the wardrobe will wear.
function Cape.model(title, emblemUri)
	local children = {}
	for _, part in ipairs(SHAPE) do
		local properties = {
			Position = part.pos, Size = part.size,
			Material = "Fabric", Color = { Color3uint8 = CLOTH },
			CanCollide = false, Massless = true,
		}
		if part.roll ~= 0 then properties.Orientation = { 0, 0, part.roll } end
		local kids = nil
		if part.name == "Handle" then
			kids = {
				{ className = "Attachment", name = "BodyBackAttachment",
				  properties = { Position = NECK } },
				{ className = "Decal", name = "DecalBack",
				  properties = { Face = "Back", Texture = emblemUri } },
			}
		end
		table.insert(children, { className = "Part", name = part.name,
			properties = properties, children = kids })
	end
	for _, name in ipairs({ "EdgeLeft", "EdgeRight" }) do
		table.insert(children, { className = "WeldConstraint", name = name .. "Weld",
			properties = { Part0 = "Handle", Part1 = name } })
	end
	return { className = "Accessory", name = title, properties = { Name = title }, children = children }
end

--- The picture a cape wears, as a flat RGBA array (0..255), blown up by Paint.SCALE, with its
--- words stamped on top. The one place the drawing becomes pixels: the draft at the table and
--- the picture that is stored are both this, so the two cannot come out different.
---
--- `palette` is sixteen {r, g, b, a} in slot order -- the table's, as mixed, not the fixed
--- sixteen. `words` is Paint.checkText's shape, or nil.
function Cape.emblemPixels(indices, palette, words)
	local W, H, S = Paint.W, Paint.H, Paint.SCALE
	local w, h = W * S, H * S
	local px = table.create(w * h * 4)
	local n = 0
	for y = 0, h - 1 do
		local row = math.floor(y / S) * W
		for x = 0, w - 1 do
			local cell = row + math.floor(x / S) + 1
			local digit = string.sub(indices, cell, cell)
			local at = (string.find("0123456789abcdef", digit:lower(), 1, true) or 1) - 1
			-- Index 0 is the eraser, and what it leaves behind is the cloth showing through --
			-- not white, and not a hole you can see the body through.
			local c = at == 0 and { 0, 0, 0, 0 } or (palette[at + 1] or Paint.colour(digit))
			px[n + 1], px[n + 2], px[n + 3], px[n + 4] = c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 255
			n += 4
		end
	end
	if words then
		Glyphs.stamp(px, w, h, words.text, words.x, words.y, palette[words.colour + 1] or { 0, 0, 0, 255 }, words.scale)
	end
	return px, w, h
end

--- A palette of Color3s, as the table holds it, in the {r, g, b, a} shape everything else takes.
function Cape.rgbaPalette(colours)
	local out = {}
	for i, c in ipairs(colours) do
		out[i] = { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), 255 }
	end
	return out
end

--- The draft you try on, as instances, built right here.
---
--- The same shape as Cape.model, wearing the drawing as it stands rather than as it was
--- published -- so there is nothing to sign, nothing to wait for and nothing to undo. The
--- picture is an EditableImage and the Decal shows it through its TextureContent, which is how
--- Roblox puts a bitmap a script made onto a face. There is no other way for a place to do it:
--- a Texture names a uri, and a place cannot write a file.
---
--- `palette` is the table's sixteen Color3s, because its swatches can be mixed and a preview
--- drawn from the fixed sixteen would be a different cape. `words` as Paint.checkText gives them.
function Cape.preview(indices, palette, words)
	local AssetService = game:GetService("AssetService")
	local px, w, h = Cape.emblemPixels(indices, palette and Cape.rgbaPalette(palette) or Paint.PALETTE, words)
	local image = AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	local bytes = buffer.create(#px)
	for i, v in ipairs(px) do
		buffer.writeu8(bytes, i - 1, v)
	end
	image:WritePixelsBuffer(Vector2.new(0, 0), Vector2.new(w, h), bytes)

	local cloth = Color3.fromRGB(CLOTH[1], CLOTH[2], CLOTH[3])
	local accessory = Instance.new("Accessory")
	accessory.Name = "CapePreview"
	local made = {}
	for _, part in ipairs(SHAPE) do
		local p = Instance.new("Part")
		p.Name = part.name
		p.Size = Vector3.new(part.size[1], part.size[2], part.size[3])
		p.Position = Vector3.new(part.pos[1], part.pos[2], part.pos[3])
		if part.roll ~= 0 then p.Orientation = Vector3.new(0, 0, part.roll) end
		p.Material = Enum.Material.Fabric
		p.Color = cloth
		p.CanCollide = false
		p.Massless = true
		p.Parent = accessory
		made[part.name] = p
	end
	local neck = Instance.new("Attachment")
	neck.Name = "BodyBackAttachment"
	neck.Position = Vector3.new(NECK[1], NECK[2], NECK[3])
	neck.Parent = made.Handle
	local decal = Instance.new("Decal")
	decal.Name = "DecalBack"
	decal.Face = Enum.NormalId.Back
	decal.TextureContent = Content.fromObject(image)
	decal.Parent = made.Handle
	for _, name in ipairs({ "EdgeLeft", "EdgeRight" }) do
		local weld = Instance.new("WeldConstraint")
		weld.Name = name .. "Weld"
		weld.Part0 = made.Handle
		weld.Part1 = made[name]
		weld.Parent = made.Handle
	end
	return accessory, image
end

--- The picture for the shelf, 64 x 64.
---
--- Not the drawing itself: the drawing is the emblem, stretched across a whole back face,
--- and on its own it is a rectangle floating on nothing. This hangs it on the same tapered
--- cape shape the catalogue paints, so a thing you made looks like the things you bought.
function Cape.thumbnail(indices, palette)
	palette = palette or Paint.PALETTE
	local S = 64
	local px = table.create(S * S * 4)
	for i = 1, S * S * 4 do px[i] = 0 end
	local top, height = 6, 54
	for y = top, top + height - 1 do
		local v = (y - top) / height              -- 0 at the shoulders, 1 at the hem
		local half = 14 + 7 * v                   -- ever so slightly trapezoidal
		local lit = 1.02 - 0.2 * v                -- a little light from the top
		for x = 0, S - 1 do
			local across = x + 0.5 - 32
			if math.abs(across) <= half then
				-- Where this pixel falls in the drawing, which covers the whole face.
				local u = (across + half) / (2 * half)
				local cell = math.floor(v * Paint.H) * Paint.W + math.floor(u * Paint.W) + 1
				local digit = string.sub(indices, cell, cell)
				local at = (string.find("0123456789abcdef", digit:lower(), 1, true) or 1) - 1
				local c = palette[at + 1] or Paint.colour(digit)
				local o = (y * S + x) * 4
				px[o + 1] = math.clamp(math.floor((c[1] or 0) * lit), 0, 255)
				px[o + 2] = math.clamp(math.floor((c[2] or 0) * lit), 0, 255)
				px[o + 3] = math.clamp(math.floor((c[3] or 0) * lit), 0, 255)
				px[o + 4] = c[4] or 255
			end
		end
	end
	return Png.encode(S, S, px)
end

--- Everything a cape is, as bytes ready to store: the drawing, the model, the picture.
--- The description is built last, by publish, because it names the other three.
function Cape.parts(indices, title, palette, words)
	palette = palette or Paint.PALETTE
	local px, w, h = Cape.emblemPixels(indices, palette, words)
	return {
		emblem = Png.encode(w, h, px),
		thumb = Cape.thumbnail(indices, palette),
		model = function(emblemUri) return Cape.model(title, emblemUri) end,
	}
end

return Cape

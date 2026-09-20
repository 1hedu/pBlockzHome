-- An Engram: a memory of something that happened on the chain, cut so you can hold it.
--
-- ---- what one is -----------------------------------------------------------------------
-- Unger's whole argument in the Hall of Records is that the record is public and permanent.
-- Handing you one to carry makes the point better than saying it does. You pick a
-- transaction out of your history -- or a page out of the explorer -- and it becomes an
-- accessory: a translucent PulseChain badge with a heartbeat across it, named for the block
-- it remembers, that goes in your inventory like anything else and can be worn in the
-- square.
--
-- What it carries is a NOTE of where the thing is, not a copy of it. Showing it later goes
-- and reads the chain again. That is the point: an Engram cannot be forged into saying
-- something the chain does not, because it does not contain the claim -- it contains the
-- address of the claim.
--
-- ---- why this is the town's ------------------------------------------------------------
-- The badge geometry used to be built in the client, in GDScript, which meant the shape of
-- this town's souvenir was a property of the program you run it with. It is a model like
-- any other model here now -- and the take-from-the-explorer button, which asked the client
-- for a request shape it never supported and so did nothing at all, works because the town
-- decides what an Engram is rather than asking whether the client happens to agree.
local ModelJson = require(script.Parent:WaitForChild("ModelJson"))

local Engram = {}

local W = 1.1                    -- across the points
local H = 1.0                    -- flat top to flat bottom
local T = 0.18                   -- thickness -- enough to read as an object
local MID = W / 4.0              -- half the width of the middle band
local DROP = -0.5                -- the badge hangs below the grip

local BLUE = { 0, 170, 255 }
local VIOLET = { 150, 40, 230 }
local ROSE = { 235, 20, 120 }
local WHITE = { 255, 255, 255 }

-- The heartbeat, as a run of points across the badge: flat, a small dip, the tall spike,
-- the deep one under it, a bounce, and flat again.
local LINE = {
	{ -0.50, 0.00 }, { -0.22, 0.00 }, { -0.14, 0.10 }, { -0.04, -0.30 },
	{ 0.06, 0.34 }, { 0.14, -0.10 }, { 0.22, 0.00 }, { 0.50, 0.00 },
}

local function part(name, pos, size, colour, material, transparency, orientation, shape)
	local props = {
		Position = pos, Size = size, Material = material, Transparency = transparency,
		Color = { Color3uint8 = colour }, CanCollide = false, Massless = true,
	}
	if orientation then props.Orientation = orientation end
	if shape then props.Shape = shape end
	return { className = "Part", name = name, properties = props }
end

--- The badge, as the model JSON an Accessory is made of.
---
--- Glass at 0.45 rather than opaque: the whole thing is a receipt for something that
--- happened somewhere else, and you should be able to see the square through it.
---
--- `look`, when the place has its pictures, is { mesh = EngramBadge, texture = PulseGradient }: the
--- badge is then one hexagon wearing the PulseBlockz gradient -- the player character's own, lying
--- across it at the diagonal it lies across a body, and the same picture the cane's orb wears. A
--- SpecialMesh FileMesh is the Roblox way to paint a shape; a Part's own shapes take no picture.
--- Without them it is the badge it always was, a violet band and rose and blue points.
function Engram.model(title, look)
	local parts = {}

	-- The Handle is the middle of the badge, so the hand holds it by its centre and the points
	-- balance either side of the grip. Turned half round about the upright, so what faces out of
	-- the hand is the badge flipped left for right.
	local handleChildren = {
		{ className = "Attachment", name = "LeftGripAttachment",
		  properties = { Position = { 0, -DROP, 0 }, Orientation = { 0, 180, 0 } } },
		{ className = "PointLight", name = "Glow",
		  properties = { Color = { Color3uint8 = VIOLET }, Brightness = 1.1, Range = 6 } },
	}
	if look and look.mesh and look.texture then
		-- The whole hexagon, points and all, in the gradient. White, so the Glass takes nothing
		-- of its own colour into the picture.
		local handle = part("Handle", { 0, DROP, 0 }, { W, H, T }, WHITE, "Glass", 0.45)
		table.insert(handleChildren, { className = "SpecialMesh", name = "Mesh",
			properties = { MeshType = "FileMesh", MeshId = look.mesh, TextureId = look.texture, Scale = { 1, 1, 1 } } })
		handle.children = handleChildren
		table.insert(parts, handle)
	else
		-- The middle band.
		local handle = part("Handle", { 0, DROP, 0 }, { MID * 2.0, H, T }, VIOLET, "Glass", 0.45)
		handle.children = handleChildren
		table.insert(parts, handle)

		-- The two points. Each is two right-angled wedges meeting on the badge's midline: the
		-- upright edge inboard, the slope running out to the tip.
		local quarter = H / 4.0
		local reach = W / 2.0 - MID                 -- how far a point sticks out
		local mid = MID + reach / 2.0
		local corners = {
			{ "PointLeftTop", -mid, quarter, { 0, 90, 0 }, ROSE },
			{ "PointLeftFoot", -mid, -quarter, { 0, 90, 180 }, ROSE },
			{ "PointRightTop", mid, quarter, { 0, -90, 0 }, BLUE },
			{ "PointRightFoot", mid, -quarter, { 0, -90, 180 }, BLUE },
		}
		for _, c in ipairs(corners) do
			table.insert(parts, part(c[1], { c[2], DROP + c[3], 0 },
				{ T, H / 2.0, reach }, c[5], "Glass", 0.45, c[4], "Wedge"))
		end
	end

	-- The heartbeat, one box a segment, standing a hair proud of both faces so it reads as
	-- marked on the badge rather than suspended inside it. Neon, so it carries in the dark.
	for i = 1, #LINE - 1 do
		local a, b = LINE[i], LINE[i + 1]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local run = math.sqrt(dx * dx + dy * dy)
		table.insert(parts, part(("Beat%d"):format(i - 1),
			{ (a[1] + b[1]) * 0.5, DROP + (a[2] + b[2]) * 0.5, 0 },
			{ run + 0.05, 0.055, T + 0.04 }, WHITE, "Neon", 0.15,
			{ 0, 0, math.deg(math.atan2(dy, dx)) }))
	end

	-- Welded to the Handle, every one of them. Roblox welds only the Handle to the body;
	-- everything else here is held on by these, and a part with no weld is a part that
	-- stays behind in the square when you walk off.
	local children = {}
	for _, p in ipairs(parts) do table.insert(children, p) end
	for _, p in ipairs(parts) do
		if p.name ~= "Handle" then
			table.insert(children, { className = "WeldConstraint", name = p.name .. "Weld",
				properties = { Part0 = "Handle", Part1 = p.name } })
		end
	end
	return { className = "Accessory", name = title, properties = { Name = title },
		children = children }
end

-- ---- from a description to a thing you can hold -----------------------------------------
--
-- `Engram.model` returns the badge as a description -- the same shape the host mounts when
-- it pulls a model off the chain. It was that shape because the badge USED to go on chain:
-- built here, JSON-encoded, base64'd, stored, and fetched back.
--
-- It does not go on chain any more (Engrams.luau says why), so the last step of that journey
-- happens here instead. Same description, same geometry, no round trip.

--- The badge, as real Instances, ready to be cloned onto anybody.
---
--- Welds name their parts rather than pointing at them -- a description has no references in
--- it -- so they are joined up once everything exists. A weld left unjoined is a part that
--- stays behind in the square when you walk off.
function Engram.build(name, look)
	return ModelJson.build(Engram.model(name or "Engram", look))
end

--- The badge's look out of the place's assets -- the hexagon and the gradient -- or nil while
--- either has not arrived, when the badge is built from plain parts instead.
function Engram.look()
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("PlaceAssets")
	local mesh = folder and folder:FindFirstChild("EngramBadge")
	local texture = folder and folder:FindFirstChild("PulseGradient")
	if not mesh or mesh.Value == "" or not texture or texture.Value == "" then return nil end
	return { mesh = mesh.Value, texture = texture.Value }
end

-- What used to be here: Engram.metadata, the document that described one for the chain --
-- name, kind, slot, blurb, licence, the model's content hash, and whatever it remembered.
-- An Engram is not published any more (see Engrams.luau), so there is nothing to describe
-- to anybody: the link IS the Engram, and it lives on the server for as long as you do.

return Engram

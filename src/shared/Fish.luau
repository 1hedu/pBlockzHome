-- The fish, and the rod they are caught with.
--
-- One fish. Every fish in the town is this model in a colour: the Everliving Fish in a light brown,
-- and the ones space fishing brings up in the nine below -- each of those in a glass bubble helmet,
-- because they come up out of space. The Everliving Fish needs no such thing. A humble fish, the
-- shape a child draws: an egg of a body, a forked tail, a fin on top and an eye each side.
--
-- The order of COLOURS is the Fishing contract's species order (contracts/Fishing.sol): species 0 is
-- the first colour here, 8 the last, and 9 is the Everliving Fish. Keep them in step.
--
-- Built by the town (Made.server.luau), not published: who has caught what is the Fishing contract's
-- to say, and a fish is primitives -- there are no bytes to put on a chain.
local ModelJson = require(script.Parent.ModelJson)
local part, accessory = ModelJson.part, ModelJson.accessory

local Fish = {}

Fish.COLOURS = {
	{ name = "Red", rgb = { 214, 40, 44 } },
	{ name = "Magenta", rgb = { 222, 44, 170 } },
	{ name = "Purple", rgb = { 132, 58, 204 } },
	{ name = "Blue", rgb = { 44, 96, 222 } },
	{ name = "Cyan", rgb = { 36, 196, 214 } },
	{ name = "Yellow", rgb = { 236, 204, 44 } },
	{ name = "Orange", rgb = { 238, 128, 34 } },
	{ name = "Indigo", rgb = { 72, 52, 160 } },
	{ name = "Green", rgb = { 52, 172, 72 } },
}
Fish.EVERLIVING = 9                              -- the contract's species number for it
Fish.EVERLIVING_NAME = "Everliving Fish"
Fish.EVERLIVING_RGB = { 196, 160, 112 }          -- well lighter than Louis's leather
Fish.ROD = "Dysnomia Rod"

--- What a species is called, and what its model is called: "Red Fish", "Everliving Fish".
function Fish.nameOf(species)
	if species == Fish.EVERLIVING then return Fish.EVERLIVING_NAME end
	local c = Fish.COLOURS[species + 1]
	return c and (c.name .. " Fish") or nil
end

--- The species a model name is, or nil.
function Fish.speciesOf(name)
	if name == Fish.EVERLIVING_NAME then return Fish.EVERLIVING end
	for i, c in ipairs(Fish.COLOURS) do
		if name == c.name .. " Fish" then return i - 1 end
	end
	return nil
end

local function darker(rgb, f)
	return { math.floor(rgb[1] * f), math.floor(rgb[2] * f), math.floor(rgb[3] * f) }
end

--- The fish's parts, in worn space for an off-hand grip: carried along the arm, head forward (-Z),
--- hung just under the fist.
local function fishParts(rgb, helmet)
	local body = { color = rgb, material = "SmoothPlastic" }
	local fin = { color = darker(rgb, 0.72), material = "SmoothPlastic" }
	local Y = -0.32
	local function with(t, extra)
		local out = table.clone(t)
		for k, v in pairs(extra) do out[k] = v end
		return out
	end
	local parts = {
		part("Body", { 0, Y, 0 }, { 0.42, 0.62, 1.3 }, with(body, {
			children = { { className = "SpecialMesh", name = "Mesh", properties = { MeshType = "Sphere" } } } })),
		part("TailUpper", { 0, Y + 0.16, 0.8 }, { 0.06, 0.34, 0.36 }, with(fin, { orientation = { 35, 0, 0 } })),
		part("TailLower", { 0, Y - 0.16, 0.8 }, { 0.06, 0.34, 0.36 }, with(fin, { orientation = { -35, 0, 0 } })),
		part("Dorsal", { 0, Y + 0.34, 0.08 }, { 0.05, 0.2, 0.5 }, with(fin, { orientation = { -12, 0, 0 } })),
		part("Belly", { 0, Y - 0.32, 0.18 }, { 0.05, 0.12, 0.26 }, fin),
		part("EyeLeft", { -0.19, Y + 0.08, -0.4 }, { 0.09, 0.09, 0.09 }, { color = { 16, 12, 10 }, shape = "Ball" }),
		part("EyeRight", { 0.19, Y + 0.08, -0.4 }, { 0.09, 0.09, 0.09 }, { color = { 16, 12, 10 }, shape = "Ball" }),
	}
	if helmet then
		-- A fishbowl worn the wrong way round, and a collar where it meets the fish.
		table.insert(parts, part("Helmet", { 0, Y + 0.04, -0.42 }, { 0.78, 0.78, 0.78 }, {
			color = { 210, 236, 255 }, material = "Glass", transparency = 0.62, reflectance = 0.35, shape = "Ball" }))
		table.insert(parts, part("HelmetCollar", { 0, Y + 0.04, -0.12 }, { 0.62, 0.62, 0.08 }, {
			color = { 168, 176, 190 }, material = "Metal", reflectance = 0.3 }))
	end
	return parts
end

--- A fish's model description: the Everliving Fish, or a colour in its helmet.
function Fish.model(species)
	if species == Fish.EVERLIVING then
		return accessory(Fish.EVERLIVING_NAME, "LeftGripAttachment", fishParts(Fish.EVERLIVING_RGB, false))
	end
	local c = Fish.COLOURS[species + 1]
	return accessory(c.name .. " Fish", "LeftGripAttachment", fishParts(c.rgb, true))
end

--- The rod: out the front of the fist and up, the way a rod is held waiting for a bite -- the cork
--- grip in the hand, the blank rising forward at thirty-five degrees, a reel under the grip, and a
--- line hanging from the tip with a red and white float on it.
Fish.RISE = 35
Fish.ROD_TIP = 4.1
Fish.LINE = 1.6

function Fish.rodModel()
	local rad = math.rad(Fish.RISE)
	local function along(d)
		return { 0, math.floor(d * math.sin(rad) * 1000 + 0.5) / 1000, -math.floor(d * math.cos(rad) * 1000 + 0.5) / 1000 }
	end
	local tilt = { Fish.RISE - 90, 0, 0 }
	local tip = along(Fish.ROD_TIP)
	local reelAt = along(0.45)
	return accessory(Fish.ROD, "RightGripAttachment", {
		part("Grip", along(0.05), { 0.17, 0.7, 0.17 }, { color = { 176, 132, 84 }, material = "Fabric", orientation = tilt }),
		part("Butt", along(-0.36), { 0.2, 0.12, 0.2 }, { color = { 40, 40, 44 }, orientation = tilt }),
		part("BlankLow", along(1.35), { 0.09, 1.9, 0.09 }, { color = { 30, 44, 70 }, reflectance = 0.2, orientation = tilt }),
		part("BlankHigh", along(3.2), { 0.05, 1.8, 0.05 }, { color = { 30, 44, 70 }, reflectance = 0.2, orientation = tilt }),
		part("Reel", { 0, reelAt[2] - 0.2, reelAt[3] }, { 0.16, 0.3, 0.3 }, { color = { 178, 184, 194 }, material = "Metal", reflectance = 0.35, shape = "Cylinder" }),
		part("Line", { 0, tip[2] - Fish.LINE / 2, tip[3] }, { 0.02, Fish.LINE, 0.02 }, { color = { 236, 236, 236 }, transparency = 0.3 }),
		part("FloatTop", { 0, tip[2] - Fish.LINE - 0.06, tip[3] }, { 0.18, 0.18, 0.18 }, { color = { 214, 36, 40 }, shape = "Ball" }),
		part("FloatBottom", { 0, tip[2] - Fish.LINE - 0.18, tip[3] }, { 0.16, 0.16, 0.16 }, { color = { 240, 240, 240 }, shape = "Ball" }),
	})
end

--- Every model this module describes, built: the ten fish and the rod.
function Fish.buildAll()
	local out = {}
	for species = 0, Fish.EVERLIVING do
		table.insert(out, ModelJson.build(Fish.model(species)))
	end
	table.insert(out, ModelJson.build(Fish.rodModel()))
	return out
end

return Fish

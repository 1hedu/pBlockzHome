-- Where a cast lands: off the edge of the map, out into space and well down under the town.
--
-- A cast is charged: hold the button with the rod in hand and he winds up over CHARGE_FULL seconds,
-- let go and it goes, which way the aim says. Short of full, the charge is the length: up to
-- FULL_FLOOR of the way out. A full charge rolls the rest -- anywhere from FULL_FLOOR to all the way --
-- so a row of people fishing off the same edge throw a spread of lines, every one a different length.
-- The further out it goes the further down it sinks.
--
-- None of it touches the catch -- that is the chain's -- so the length is decided on the angler's
-- own machine with math.random, and the server only checks it is a cast at all.
local SpaceFishing = {}

--- Seconds for a full charge.
SpaceFishing.CHARGE_FULL = 1
--- The furthest a cast goes, across; how far a tap goes, and where a full charge starts rolling from,
--- as shares of it.
SpaceFishing.FURTHEST = 90
SpaceFishing.TAP = 0.15
SpaceFishing.FULL_FLOOR = 0.6
--- How far past the edge the float has to land, so it is plainly out in space.
SpaceFishing.PAST = 4

--- The map's half-width, the height of its surface, and its middle.
function SpaceFishing.edge()
	local map = workspace:FindFirstChild("Map")
	local ground = map and map:FindFirstChild("Ground", true)
	if ground and ground:IsA("BasePart") then
		return math.min(ground.Size.X, ground.Size.Z) / 2, ground.Position.Y + ground.Size.Y / 2,
			Vector3.new(ground.Position.X, 0, ground.Position.Z)
	end
	return 70, 0, Vector3.zero
end

--- Whether a point is past the map's edge by at least `by`.
function SpaceFishing.offEdge(point, by)
	local edge, _, middle = SpaceFishing.edge()
	local past = edge + (by or 0)
	return math.abs(point.X - middle.X) > past or math.abs(point.Z - middle.Z) > past
end

--- How far through a full charge `seconds` of holding is, 0 to 1.
function SpaceFishing.fraction(seconds)
	return math.clamp((seconds or 0) / SpaceFishing.CHARGE_FULL, 0, 1)
end

--- How far out a cast goes: the charge's length short of full, and a roll from FULL_FLOOR to the
--- furthest for a full one.
function SpaceFishing.reach(fraction)
	fraction = math.clamp(fraction, 0, 1)
	if fraction >= 1 then
		return SpaceFishing.FURTHEST * (SpaceFishing.FULL_FLOOR + (1 - SpaceFishing.FULL_FLOOR) * math.random())
	end
	return SpaceFishing.FURTHEST * math.max(SpaceFishing.TAP, SpaceFishing.FULL_FLOOR * fraction)
end

--- How far from `from` along the level `heading` the map's edge is, plus the PAST a float needs.
function SpaceFishing.toEdge(from, heading)
	local edge, _, middle = SpaceFishing.edge()
	local rel = Vector3.new(from.X - middle.X, 0, from.Z - middle.Z)
	local far = math.huge
	if math.abs(heading.X) > 1e-3 then
		far = math.min(far, ((heading.X > 0 and edge or -edge) - rel.X) / heading.X)
	end
	if math.abs(heading.Z) > 1e-3 then
		far = math.min(far, ((heading.Z > 0 and edge or -edge) - rel.Z) / heading.Z)
	end
	return math.max(far, 0) + SpaceFishing.PAST + 1
end

--- How far under the town's surface a float sinks, `out` studs away across.
function SpaceFishing.depth(out)
	return 6 + out * 0.45
end

--- How high a rod's tip is over the feet of the one holding it, near enough.
local TIP_ABOVE = 3
--- How far over the edge of the town a line has to pass.
local CLEARANCE = 2

--- How high a float `out` studs out along `heading` from `from` hangs: as deep as a cast that far
--- sinks, unless that would take the line from the rod tip through the edge of the town -- cast from
--- well back, it is raised until the line passes over the edge with room to spare.
function SpaceFishing.floatHeight(from, heading, out)
	local _, top = SpaceFishing.edge()
	local y = top - SpaceFishing.depth(out)
	local toEdge = SpaceFishing.toEdge(from, heading) - SpaceFishing.PAST - 1
	if toEdge > 0 and out > toEdge then
		local tip = from.Y + TIP_ABOVE
		-- The line crosses the edge `toEdge / out` of the way along; there it must be above the surface.
		local lowest = tip - (tip - (top + CLEARANCE)) * out / toEdge
		y = math.max(y, lowest)
	end
	return y
end

local function across(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

--- Where a cast aimed along `origin` + `dir`, released at `fraction` of a full charge, lands for
--- somebody standing at `from` -- or nil and why not ("map": it would come down on the town).
function SpaceFishing.castPoint(origin, dir, from, fraction, ignore)
	if dir.Magnitude < 1e-6 then return nil, "map" end
	dir = dir.Unit
	local _, top = SpaceFishing.edge()
	-- Which way: toward where the aim meets the ground's level, or straight along it if it is aimed
	-- at the sky.
	local toward
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local hit = workspace:Raycast(origin, dir * 1000, params)
	if hit then
		toward = hit.Position
	elseif dir.Y < -1e-3 then
		toward = origin + dir * ((top - origin.Y) / dir.Y)
	else
		toward = origin + dir * 100
	end
	local heading = Vector3.new(toward.X - from.X, 0, toward.Z - from.Z)
	if heading.Magnitude < 1e-3 then
		heading = Vector3.new(dir.X, 0, dir.Z)
		if heading.Magnitude < 1e-3 then return nil, "map" end
	end
	heading = heading.Unit
	-- A short roll still clears the edge: never less than it takes to get past it.
	local out = math.max(SpaceFishing.reach(fraction), SpaceFishing.toEdge(from, heading))
	if out > SpaceFishing.FURTHEST then return nil, "map" end
	local flat = Vector3.new(from.X, 0, from.Z) + heading * out
	local point = Vector3.new(flat.X, SpaceFishing.floatHeight(from, heading, out), flat.Z)
	if not SpaceFishing.offEdge(point, SpaceFishing.PAST) then return nil, "map" end
	return point, nil
end

--- Where a line picked up again hangs when where it was cast is not known: off the nearest edge.
function SpaceFishing.restingPoint(from)
	local edge, top, middle = SpaceFishing.edge()
	local rel = Vector3.new(from.X - middle.X, 0, from.Z - middle.Z)
	local heading
	if math.abs(rel.X) > math.abs(rel.Z) then
		heading = Vector3.new(rel.X >= 0 and 1 or -1, 0, 0)
	else
		heading = Vector3.new(0, 0, rel.Z >= 0 and 1 or -1)
	end
	local out = SpaceFishing.toEdge(from, heading) + 20
	local flat = Vector3.new(from.X, 0, from.Z) + heading * out
	return Vector3.new(flat.X, SpaceFishing.floatHeight(from, heading, out), flat.Z)
end

--- Whether a point somebody at `from` says they cast to is a cast at all: off the edge, no further
--- than a rod throws, and hanging no deeper than a float that far out sinks, nor higher than the
--- town's roofs (raised, a cast from well back can hang above the surface).
function SpaceFishing.fair(point, from)
	if typeof(point) ~= "Vector3" then return false end
	local _, top = SpaceFishing.edge()
	local out = across(point, from)
	return SpaceFishing.offEdge(point, SpaceFishing.PAST - 0.5)
		and out <= SpaceFishing.FURTHEST + 8
		and point.Y >= top - SpaceFishing.depth(out) - 2
		and point.Y <= top + 60
end

return SpaceFishing

-- Pets: the things you own that stand next to you rather than on you.
--
-- Everything else in the catalogue is an Accessory welded to a limb. A pet is not worn,
-- so it is a Model that lives in the workspace and is moved every frame to keep station
-- on its owner. The wardrobe still decides whether you have one out, because ownership
-- is ownership -- the pet slot holds one, the same as the head slot holds one hat.
--
-- Two gaits, because the two pets are different animals. The pup walks: it stays on the
-- ground, lags behind, and only bothers to catch up once you are far enough away that
-- standing still would look wrong. Steven floats: he holds a slow ring over your
-- shoulder, bobbing, and never touches anything.
local RunService = game:GetService("RunService")

local Pets = {}

local out = {}          -- player -> { model, kind, phase }

local FOLLOW_BEHIND = 3.6     -- studs the pup trails at
local FOLLOW_SLACK = 2.2      -- how far it lets you get before it moves at all
local FOLLOW_SPEED = 9

local RING = 2.6              -- radius of Steven's orbit
local RING_HEIGHT = 3.4
local RING_SPEED = 0.7        -- radians a second, deliberately slow
local BOB = 0.28

local function rootOf(player)
	local ch = player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart") or nil
end

-- The wings are not swung here. Two CFrames a wing every frame, replicated to everybody, was
-- most of what the wire carried while one bird followed one player; each client flaps them
-- for itself from the model and the clock (Pets.client.luau), as it would a walk.

local STEP_SPEED = 8.5         -- the pup's stride, in strides a second at full pelt
local STEP_BOUNCE = 0.16       -- how far it rises off the ground each stride
local STEP_ROLL = 0.10         -- the waddle
local STEP_PITCH = 0.07        -- nose down as it pushes off, up as it lands

-- A car does none of that, and the thing that gives it away is not the bouncing but the
-- sliding: it has no sideways. It only ever moves along its own nose, and the only way it
-- reaches anything off to one side is to steer the nose round first and drive an arc. So
-- there is a speed it builds up and sheds, a bounded steering rate, and no motion that is
-- not along the heading -- which is the whole difference between driving and being dragged.
local GLIDE_SPEED = 13         -- top speed, studs a second: a little quicker than the pup
local GLIDE_ACCEL = 18         -- and how briskly it gets there, or stops
local GLIDE_STEER = 3.2        -- most it can turn in a second, radians, at full pelt
local GLIDE_TRACK = 3.5        -- how hard it pulls the nose towards where it is going
-- No roll. It was meant as a touch of weight going to the outside of a bend, but the
-- steering is at full lock nearly every frame -- the thing it is chasing is almost never
-- straight ahead -- so the lean sat pinned at its limit instead of coming and going, and a
-- car permanently tilted three degrees is a car up on two wheels. Four on the ground.
local GLIDE_RIDE = 0.12        -- clearance, so the wheels are not buried in the pavement

-- How far under the root part the ground is: measured off the character rather than guessed,
-- as the two numbers before it were. The legs reach exactly three studs below the root, so
-- that is the floor you are standing on.
--
-- It is only the fallback now. A pet finds its own floor by looking down for it, and this is
-- the answer when there is nothing under it to find -- off the edge of the map, or over open
-- water -- where keeping station with you is better than falling for ever.
local FLOOR_UNDER_ROOT = 3.0

-- The wheels turn with the distance covered, but not at the rate they really would: they
-- are a fifth of a stud across, so honest rolling is twenty-odd revolutions a second and
-- strobes into a smear. This is slow enough to see and still stops dead when the car does,
-- which is the part anyone actually reads.
local WHEEL_SPIN = 1.2         -- radians a wheel turns per stud travelled

-- How high a ledge a pet will find above where it is standing. A kerb, a step, the lip of a
-- raised path: things it should end up on top of rather than inside. Higher than this and it
-- is a wall, and a pet does not climb walls.
local STEP_UP = 5
-- And how far down it will look for something to stand on before giving up.
local LOOK_DOWN = 80

-- One filter, reused: the list is rewritten each time, and building a RaycastParams per pet
-- per frame is sixty of them a second for nothing.
local GROUND = RaycastParams.new()
GROUND.FilterType = Enum.RaycastFilterType.Exclude
GROUND.RespectCanCollide = true

--- The height of the floor under a spot, found by looking for it.
---
--- This used to be worked out from the player -- root height less the length of a leg -- and
--- that is what put the car under the raised path. The number it gave was the height of the
--- floor YOU were standing on, so the moment the two of you were on different floors, which
--- is most of the time a path is raised at all, the pet was placed at your floor's height and
--- the path closed over it. A pet stands on what is under the pet.
---
--- CanCollide is respected, so the ray passes through everything you can walk through --
--- other pets, the decorations -- exactly as your own legs do. The player's own character and
--- the pet's own model are excluded outright: standing on your owner's head is not a floor.
---
--- `floor` is what to answer when there is nothing down there at all, which is a real case:
--- the edge of the map, or a pet over open water. Then it keeps station with you instead.
local function groundAt(x, z, model, character, from, floor)
	GROUND.FilterDescendantsInstances = { model, character }
	local top = math.max(from, floor) + STEP_UP
	local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -LOOK_DOWN, 0), GROUND)
	return hit and hit.Position.Y or floor
end

--- How far the driven part sits above the lowest thing in the model.
---
--- Measured from THAT part, not from the middle of the model. Half the height is only the
--- same number when the part being moved happens to sit at the model's vertical centre, and
--- most of them do not: a dog's body is up on its legs, so sitting the body half a dog above
--- the floor leaves the feet in the air with a shadow underneath.
---
--- What is wanted is the distance from the part's own middle down to the lowest face in the
--- model, because the part's middle is the thing being placed.
local function liftOf(model, body)
	if not body then return 0 end
	local lo
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			lo = math.min(lo or (d.Position.Y - d.Size.Y / 2), d.Position.Y - d.Size.Y / 2)
		end
	end
	return lo and (body.Position.Y - lo) or 0
end

--- How far the model reaches out from the middle of the driven part, on the flat.
---
--- What it is for is standing off: a pet keeps station a few studs behind you, and that few
--- studs was measured against a car a stud and a bit long. Tripled, the same number puts its
--- bonnet through your back. So the distance it hangs back is the distance PLUS its own
--- reach, and the pet can then be any size without the follow having to be retuned for it.
local function reachOf(model, body)
	if not body then return 0 end
	local far = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local off = d.Position - body.Position
			far = math.max(far,
				math.sqrt(off.X * off.X + off.Z * off.Z) + math.max(d.Size.X, d.Size.Z) / 2)
		end
	end
	return far
end

--- The wheels, and where each sits relative to the model, captured once for the same reason
--- the wings are: they are driven by CFrame every frame, so reading them back later would
--- give the turned pose and they would wind themselves round for ever.
---
--- Each is a disc lying on the X axis with its own middle for an origin, which is what
--- scripts/prep-roma.js cut them out of the body for: a part turns about its own middle and
--- nowhere else.
local function wheelsOf(model, body)
	local out = {}
	if not body then return out end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:match("^Wheel") then
			table.insert(out, { part = d, rest = body.CFrame:ToObjectSpace(d.CFrame) })
		end
	end
	return out
end

--- Puts a pet in the world. Returns the model, or nil if it could not be placed.
function Pets.summon(player, template, name)
	Pets.dismiss(player)
	local root = rootOf(player)
	if not root then return nil end
	local model = template:Clone()
	model.Name = ("Pet_%s"):format(player.Name)
	-- Nothing about a pet should push the player around or be stood on.
	--
	-- The pivot has to be a part nothing here animates. Every frame PivotTo puts the pivot
	-- part where the pet belongs and carries the rest of the model along by the same
	-- transform -- so if the pivot were a wheel, the turn written onto that wheel would be
	-- read back as the model's own orientation and handed to every other part as its
	-- inverse. The body tumbles, a little further every frame, and ends up on its roof.
	-- Same trap for a wing. So the moving pieces are passed over and the body is the pivot.
	local spare
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Anchored = true
			if not spare then spare = d end
			if not model.PrimaryPart and not d.Name:match("^Wheel") and not d.Name:match("^Wing") then
				model.PrimaryPart = d
			end
		end
	end
	if not model.PrimaryPart then model.PrimaryPart = spare end
	model.Parent = workspace
	out[player] = { model = model, kind = name, phase = 0, stride = 0,
		wheels = {}, speed = 0, spin = 0 }
	if model.PrimaryPart then
		model:PivotTo(CFrame.new(root.Position + Vector3.new(0, 0, -FOLLOW_BEHIND)))
	end
	out[player].body = model:FindFirstChild("Chassis") or model.PrimaryPart
	out[player].wheels = wheelsOf(model, out[player].body)
	out[player].lift = liftOf(model, out[player].body)
	out[player].reach = reachOf(model, out[player].body)
	return model
end

function Pets.dismiss(player)
	local entry = out[player]
	if entry and entry.model and entry.model.Parent then
		entry.model:Destroy()
	end
	out[player] = nil
end

--- The part a pet's own sounds come out of, or nil when it is not out.
---
--- The driven part rather than the model: a Sound plays from the part it is inside, and the
--- driven one is the only one guaranteed to be where the pet actually is on any given frame.
--- A pet that is not summoned has no speaker at all, which is the answer to "can he say
--- something" being no rather than a sound coming out of nowhere.
function Pets.speaker(player)
	local entry = out[player]
	if not entry or not entry.model or not entry.model.Parent then return nil end
	local body = entry.body
	if body and body.Parent then return body end
	return entry.model.PrimaryPart
end

function Pets.has(player)
	local entry = out[player]
	return entry ~= nil and entry.model ~= nil and entry.model.Parent ~= nil
end

-- One loop for every pet in the world. Anchored parts moved by PivotTo, so nothing here
-- depends on physics: a pet that fell over or got shoved into a wall would be worse than
-- one that glides.
RunService.Heartbeat:Connect(function(dt)
	for player, entry in pairs(out) do
		local model = entry.model
		if not model or not model.Parent or not model.PrimaryPart then
			out[player] = nil
		else
			local root = rootOf(player)
			if root then
				entry.phase += dt
				local here = model:GetPivot().Position

				if entry.kind == "glide" then
					-- Where it wants to be is behind you and on the ground, as the pup does.
					-- Getting there is the difference: it cannot go straight at the spot, it
					-- has to point at it and drive.
					local body = entry.body
					if not body or not body.Parent then body = model.PrimaryPart end
					-- Far enough back that its nose is not in you, whatever size it is.
					local back = FOLLOW_BEHIND + (entry.reach or 0)
					local behind = root.CFrame.LookVector * -back
					local target = Vector3.new(root.Position.X + behind.X, 0, root.Position.Z + behind.Z)
					-- Where the body actually is, read off the part rather than off the
					-- model's stored pivot, which only ever repeats what it was last given.
					local at = body.CFrame
					local flat = Vector3.new(at.Position.X, 0, at.Position.Z)

					-- Flat, always: a car does not pitch its nose up to climb towards you.
					local heading = entry.heading or at.LookVector
					heading = Vector3.new(heading.X, 0, heading.Z)
					heading = heading.Magnitude > 1e-4 and heading.Unit or Vector3.new(0, 0, -1)

					local toGo = target - flat
					local gap = toGo.Magnitude

					-- Enough speed to close the gap and none at all once it is closed, taken
					-- up and shed by degrees. Snapping between still and moving is what makes
					-- a thing read as a sliding block rather than a car.
					local want = gap > FOLLOW_SLACK and math.min(GLIDE_SPEED, (gap - FOLLOW_SLACK) * 3) or 0
					local speed = entry.speed + math.clamp(want - entry.speed, -GLIDE_ACCEL * dt, GLIDE_ACCEL * dt)
					entry.speed = speed

					-- Steering, bounded, and only while it is rolling: a parked car cannot
					-- spin on the spot. Because the bound is on the rate and not the radius,
					-- slowing down tightens the arc, which is what lets it come back round to
					-- you instead of circling for ever at one distance.
					local turn = 0
					if gap > 1e-3 and speed > 0.05 then
						local aim = toGo.Unit
						-- Signed, about the vertical: positive swings the nose to its left.
						local off = math.atan2(heading.Z * aim.X - heading.X * aim.Z, heading:Dot(aim))
						-- A share of the error, not all of it. Aiming straight at the target
						-- every frame demands the whole of the available turn every frame, so
						-- the steering sat at full lock permanently -- front wheels cocked
						-- over going down a straight line, and the body leaning with them.
						-- Turning in proportion to how far off it is leaves lock for corners.
						local most = GLIDE_STEER * dt
						turn = math.clamp(off * math.min(1, dt * GLIDE_TRACK), -most, most)
						heading = (CFrame.Angles(0, turn, 0) * heading).Unit
					end
					entry.heading = heading

					-- Along its own nose and nowhere else. This is the whole of it.
					local travelled = speed * dt
					local moved = flat + heading * travelled
					-- Sat on its own wheels on whatever is under IT, found where it is going
					-- rather than where it is: at thirteen studs a second, sampling the spot
					-- it is leaving puts a wheel through the kerb it is climbing.
					local floor = root.Position.Y - FLOOR_UNDER_ROOT
					local under = groundAt(moved.X, moved.Z, model, root.Parent, at.Position.Y - entry.lift, floor)
					moved = Vector3.new(moved.X, under + entry.lift + GLIDE_RIDE, moved.Z)

					-- Every part placed off one frame, and no PivotTo. Its front is on -Z,
					-- which is what CFrame.new(from, to) points down, so there is no
					-- half-turn to undo here as there is on the Familiar.
					local frame = CFrame.new(moved, moved + heading)
					body.CFrame = frame

					-- And the wheels, once the body is where it is going: they turn with the
					-- ground they cover and stop when it stops, which is the whole of what a
					-- wheel has to do to read as one.
					--
					-- They do not steer. Pointing the front pair where the car was turning
					-- was an addition nobody asked for, and it saturated the way the lean
					-- did -- both front wheels cranked to full lock down a straight line.
					if #entry.wheels > 0 then
						-- Forward is -Z and the axle is X, so rolling forward is a negative
						-- turn about it.
						entry.spin -= travelled * WHEEL_SPIN
						local rolling = CFrame.Angles(entry.spin, 0, 0)
						for _, w in ipairs(entry.wheels) do
							if w.part.Parent then w.part.CFrame = frame * w.rest * rolling end
						end
					end
				elseif entry.kind == "float" then
					-- A slow ring over the shoulder, and a bob that is not in step with it,
					-- so the two never quite line up and it reads as drifting.
					local a = entry.phase * RING_SPEED
					local target = root.Position
						+ Vector3.new(math.cos(a) * RING, RING_HEIGHT + math.sin(entry.phase * 1.9) * BOB, math.sin(a) * RING)
					local moved = here:Lerp(target, math.min(1, dt * 3.2))
					-- Looking at you, from over your shoulder.
					--
					-- Aimed at the root it stared at your waist, and hovering three studs up
					-- that is a steep nose-down tilt. Aiming higher, at about head height,
					-- takes most of the pitch out without making it stare past you.
					local look = root.Position + Vector3.new(0, 1.6, 0)
					-- Turned about, because the face is on the far side from the look vector.
					--
					-- Baking the half-turn into the model does not work here: PivotTo sets the
					-- PIVOT part's CFrame to the target, the pivot is the model's first part,
					-- and a turn baked into that part is therefore cancelled by the very call
					-- meant to carry it. Orientation belongs to the animation, not the parts.
					model:PivotTo(CFrame.new(moved, moved + (look - moved)) * CFrame.Angles(0, math.pi, 0))
				else
					-- Behind you, on the ground. It only starts moving once you have got
					-- far enough away that standing still would look like it had stopped
					-- caring, which is also what stops it jittering when you do.
					local behind = root.CFrame.LookVector * -FOLLOW_BEHIND
					-- On the floor under the spot it is heading for, lifted by however far
					-- its own body sits above its own feet. The 1.4 this replaces was the
					-- height of one particular dog, guessed once and then true of nothing:
					-- it left this one's paws in the air with its shadow underneath, and it
					-- had the same trouble with the raised path the car did.
					local floor = root.Position.Y - FLOOR_UNDER_ROOT
					local tx, tz = root.Position.X + behind.X, root.Position.Z + behind.Z
					local target = Vector3.new(tx,
						groundAt(tx, tz, model, root.Parent, here.Y - entry.lift, floor) + entry.lift, tz)
					-- How far it has to walk, measured on the flat. Counting the height in
					-- made a pet at the bottom of a step "far away" and set it trotting on
					-- the spot to close a gap it cannot walk off.
					local far = (Vector3.new(here.X - tx, 0, here.Z - tz)).Magnitude
					if far > FOLLOW_SLACK then
						local step = here:Lerp(target, math.min(1, dt * FOLLOW_SPEED / 4))
						-- Across the ground it eases towards you. Its height it does not:
						-- that is read off the floor every frame and never read back.
						--
						-- It used to be eased too, and the stride's bounce was added to the
						-- result -- so the bounce came back in as the next frame's starting
						-- height, an easing towards a target it was being lifted away from
						-- again every frame. The two settled a few studs apart and the dog
						-- trotted along in the air with its shadow on the ground beneath it.
						-- Which way up a thing is belongs to the animation. Where the floor
						-- is does not.
						local moved = Vector3.new(step.X, target.Y, step.Z)
						-- A trot, not a glide. One stride is a bounce, a waddle and a nod,
						-- all off the same phase but at different multiples so they never
						-- line up into a single bob. The stride only advances while it is
						-- actually travelling, so a pet that has caught up stands still.
						entry.stride += dt * STEP_SPEED * math.min(1, far / 6)
						local s = entry.stride
						local bounce = math.abs(math.sin(s)) * STEP_BOUNCE
						local roll = math.sin(s * 0.5) * STEP_ROLL
						local pitch = math.cos(s * 2) * STEP_PITCH
						local look = Vector3.new(target.X, moved.Y, target.Z)
						local facing = CFrame.new(moved + Vector3.new(0, bounce, 0),
							look + Vector3.new(0.001, bounce, 0))
						model:PivotTo(facing * CFrame.Angles(pitch, 0, roll))
					else
						-- Standing: breathing, and a slow sway where a tail would be.
						local idle = math.sin(entry.phase * 1.6) * 0.02
						local sway = math.sin(entry.phase * 0.9) * 0.05
						-- Standing where it already stands, so the floor is read there and
						-- not under the spot behind you it was aiming at -- otherwise a pet
						-- that stopped short of a step hovers at the step's height.
						local rest = groundAt(here.X, here.Z, model, root.Parent, here.Y - entry.lift, floor)
							+ entry.lift + 0.04 + idle
						model:PivotTo(CFrame.new(Vector3.new(here.X, rest, here.Z),
							Vector3.new(here.X, rest, here.Z) + model:GetPivot().LookVector)
							* CFrame.Angles(0, 0, sway))
					end
				end
			end
		end
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	Pets.dismiss(player)
end)

return Pets

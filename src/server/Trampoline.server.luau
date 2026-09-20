-- The trampolines on the roofs.
--
-- Two on each building, in the corners of its outer edge, tilted in toward the middle of the
-- town. Step on one and you are thrown across the square -- somewhere between just past the
-- building you were standing on and very nearly off the far side of the map, and which of
-- those it is you do not get to choose.
--
-- ---- what is here and what is in the map -------------------------------------------------
-- The pads themselves are not built here. They are Parts in map/Shops.model.json and
-- map/Bank.model.json like every other thing in the town, and this script only finds them by
-- name and does the throwing. The server does position; it does not build models.
--
-- ---- which way you go --------------------------------------------------------------------
-- Off the pad's own UpVector, not off a table of directions written down twice. A trampoline
-- tilted toward the square throws you toward the square, and a pad turned round in the map
-- file turns the throw round with it -- which is what "angled" is for. Nobody has to keep a
-- list here in step with the geometry there.
--
-- ---- how far ----------------------------------------------------------------------------
-- The near end is a hop: over the parapet and down in front of your own building. The far end
-- is worked out from the pad to the edge of the map, less a margin, so the longest throw the
-- town can give you still lands on it. Where between the two is a coin toss every time.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--- The shortest throw: far enough to clear your own roof and come down in front of it.
local NEAR = 14

--- How much of the map's edge is kept spare. The map is the Plaza's Ground, 140 studs
--- square, so this is how close to falling off the longest throw comes.
local MARGIN = 10

--- How high the arc goes over the pad. The same every time, whatever the distance.
---
--- Deliberately not a share of the distance. A short hop and a throw across the whole town
--- go up exactly as far and hang in the air exactly as long; what changes between them is
--- only how fast you are travelling sideways. That is the part that makes it feel like a
--- trampoline rather than like a catapult with a range setting -- and thirty studs over a
--- ten-stud roof is three buildings up, which is a long enough look at the town on the way
--- past to be worth doing again.
local RISE = 30

--- How much of your sideways approach comes out the other side. See the launch below: at 1
--- the angle of attack is worth a stud or two against a throw of fifty, which is no angle at
--- all.
local SWING = 3.0

--- How far the sound carries. Everyone near hears somebody go up; the far side of the square
--- does not.
local NEAR, FAR = 10, 45

--- How long before the same person can be thrown again. Long enough that landing back on the
--- pad you left -- which the short throws can do -- is a landing rather than a second launch.
local AGAIN = 1.6

--- How hard the world pulls, studs per second squared. workspace.Gravity, read once.
local g = workspace.Gravity

local thrownAt = {}    -- player -> when they were last launched

local function mapEdge()
	local ground = workspace:FindFirstChild("Map")
	ground = ground and ground:FindFirstChild("Ground", true)
	if ground then return math.min(ground.Size.X, ground.Size.Z) / 2 end
	return 70
end

--- Where a straight line from `at` going `dir` leaves the map, in studs.
---
--- Both walls, nearer one wins. dir is level and unit by the time this is called, so a
--- component at nought simply never meets that wall and is skipped.
local function runway(at, dir, edge)
	local far = math.huge
	if math.abs(dir.X) > 1e-3 then
		far = math.min(far, ((dir.X > 0 and edge or -edge) - at.X) / dir.X)
	end
	if math.abs(dir.Z) > 1e-3 then
		far = math.min(far, ((dir.Z > 0 and edge or -edge) - at.Z) / dir.Z)
	end
	return far
end

--- The published clip behind a name, or "" before the host has fetched it.
local function clip(name)
	local folder = ReplicatedStorage:FindFirstChild("PlaceAssets")
	local value = folder and folder:FindFirstChild(name)
	return (value and value.Value) or ""
end

--- The noise a pad makes, on the pad.
---
--- In the world rather than on the bouncer's own machine, because the point of it is the
--- people watching: somebody going up off a roof should be something you HEAR happen across
--- the way, not something only they know about. Roll-off does the rest -- full volume for
--- anyone near the building, gone by the middle of the square.
---
--- InverseTapered rather than the default Inverse: an inverse curve never quite reaches
--- nought, so "not too rangey" with one is a long thin tail of trampoline audible from the
--- far corner. Tapered is inverse close in and linear-square further out, so it arrives at
--- silence at RollOffMaxDistance and means it.
---
--- On the one going up, not on the pad. Their own momentum is carried into the launch (SWING),
--- so bouncing pad to pad gets faster each time, and from the pad a sound that tapers at FAR was
--- under them for less of its second on every bounce -- "it gets quieter with each use of the
--- trampoline", and back to full after standing still. On their root it flies with them: they
--- hear the whole of it, and everyone else hears it from the person going up.
local voices = {}          -- character root -> its Sound, made once; it goes when the body does

local function bounce(root)
	local sound = voices[root]
	if not sound or sound.Parent ~= root then
		local asset = clip("SfxTrampoline")
		if asset == "" then return end             -- not published yet: it is simply quiet
		sound = Instance.new("Sound")
		sound.Name = "TrampolineBounce"
		sound.SoundId = asset
		sound.Volume = 1
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = NEAR
		sound.RollOffMaxDistance = FAR
		sound.Parent = root
		voices[root] = sound
	end
	sound.TimePosition = 0
	sound:Play()
end

--- How long the fabric takes to stretch, and how long to come back.
---
--- The recoil is the slower half. The launch itself is instant -- you are gone on the frame
--- you touch it -- so what there is to watch is the sheet snapping taut and easing back, and
--- a fifth of a second each way is about what a real one takes. A tenth was too quick to
--- read as anything: the eye caught the two end states and nothing between them.
local TIGHTEN = 0.13
local RELAX = 0.19

--- How far it draws in across its own face, and how far it sinks straight back into it.
---
--- Across only. Scaling all three axes took a sheet 0.35 studs thick down to 0.16 and sank
--- it into the frame it sits in, so the stretch read as the fabric blinking out and back
--- rather than as fabric. It keeps its thickness; cloth pulls tight, it does not get thinner.
--- BACK has very little room, and the room is worth writing down because getting it wrong
--- looks like the sheet blinking rather than like a distance being too big.
---
--- The bed's centre sits 0.95 studs off the frame's middle along the face's normal and the
--- bed is 0.35 thick, so its top face is at 1.125. The frame is 1.4 deep, so the frame's own
--- face is at 0.7. That leaves 0.425 studs of travel before the sheet is entirely inside the
--- frame and cannot be seen at all.
---
--- It was two studs -- which did not sink the fabric into the frame, it sent it out through
--- the underside and back into the roof. That is the blink, both times: not the sheet
--- disappearing, the sheet leaving.
local SQUASH = 0.62
local BACK = 0.35

local flexing = {}         -- pad -> true while its fabric is mid-stretch

--- The blue sheet taking the weight and throwing it back.
---
--- It shrinks toward its own centre on every side and slides down the slope at the same time,
--- smallest and furthest back together, and then the whole thing runs backwards. Fast: a
--- ninth of a second each way, which is about what a real one takes and is what makes it read
--- as the fabric doing the throwing rather than as a panel being resized.
---
--- "Back" is perpendicular to the pad's face, which is the pad's own -UpVector -- straight
--- into the sheet, along the same axis it throws you out along. A bed deflects at right
--- angles to its own plane; it does not slide down its own surface, which is what this did
--- at first and why the stretch looked like it was going somewhere else.
---
--- Taken off the pad rather than written down, so a pad turned round in the map file brings
--- its stretch with it and one expression is right for all eight.
local function flex(pad)
	local bed = pad:FindFirstChild(pad.Name .. "Bed")
	if not bed or flexing[pad] then return end
	flexing[pad] = true

	local size, at = bed.Size, bed.Position
	local into = -pad.CFrame.UpVector

	-- Thickness kept, so the sheet stays a sheet.
	local taut = Vector3.new(size.X * SQUASH, size.Y, size.Z * SQUASH)

	task.spawn(function()
		local t = 0
		while t < TIGHTEN + RELAX do
			t += task.wait()
			-- Nought at rest, one at full stretch, nought again -- and eased at both ends,
			-- because a straight ramp arrives and leaves at full speed and that is what made
			-- the quick version look like a switch being thrown rather than cloth moving.
			local k = t < TIGHTEN and (t / TIGHTEN) or math.max(0, 1 - (t - TIGHTEN) / RELAX)
			k = math.clamp(k, 0, 1)
			local ease = k * k * (3 - 2 * k)
			bed.Size = size:Lerp(taut, ease)
			bed.Position = at + into * (BACK * ease)
		end
		bed.Size = size
		bed.Position = at
		flexing[pad] = nil
	end)
end

--- Throws `player` off `pad`.
---
--- A velocity on the root and nothing else, which is how Roblox does a jump pad: the world's
--- gravity makes the arc, the Humanoid goes to Freefall on its own, and the flight is
--- physics rather than a script stepping somebody through the air.
local function launch(player, pad)
	local now = os.clock()
	if thrownAt[player] and now - thrownAt[player] < AGAIN then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	-- Said, so the journal answers "did the town launch them" without a guess.
	print(("trampoline: %s launched from %s at %.3f"):format(player.Name, pad.Name, workspace:GetServerTimeNow()))

	-- The way the pad is leaning, flattened. The tilt says which way; the distance is
	-- decided below, so the angle of the pad is not also secretly its power.
	local aim = pad.CFrame.UpVector
	local dir = Vector3.new(aim.X, 0, aim.Z)
	if dir.Magnitude < 1e-3 then return end            -- a pad lying flat throws nobody
	dir = dir.Unit

	local edge = mapEdge()
	local far = math.max(NEAR, runway(root.Position, dir, edge) - MARGIN)
	local reach = NEAR + math.random() * (far - NEAR)

	-- Up RISE studs, then down to the ground -- which is further than the rise, because you
	-- started on a roof. Both halves are the same on every launch, so the time in the air is
	-- fixed and the distance is carried entirely by the sideways speed. That is what makes
	-- them all feel like the same trampoline.
	local up = math.sqrt(2 * RISE * g)
	local flight = math.sqrt(2 * RISE / g) + math.sqrt(2 * (RISE + math.max(root.Position.Y, 0)) / g)

	-- And the way you came in steers the way you go out, hard.
	--
	-- Only the SIDEWAYS half of your approach is kept: the forward half is the random
	-- distance's business, so running at one flat out does not let you pick the long throw.
	-- What you can pick is the line.
	--
	-- Multiplied, because unmultiplied it is nothing. A walk is sixteen studs a second and
	-- the throw itself is four or five times that, so a perfect sideways entry moved the
	-- landing by a couple of studs and the angle may as well not have been there. At this
	-- gain a full-sideways approach carries the landing about as far across as the throw
	-- carries it forward, which is what makes the line worth aiming.
	--
	-- NOT clamped to the map. The promise that a throw lands on the town is about the
	-- straight-on bounce, which is what you get by walking onto a pad without thinking; going
	-- off the edge on a hard angle is a thing you did on purpose.
	local across = Vector3.new(-dir.Z, 0, dir.X)
	local vin = root.AssemblyLinearVelocity
	local side = (across.X * vin.X + across.Z * vin.Z) * SWING

	-- And the promise that a straight-on bounce lands on the town, kept over the WHOLE throw.
	--
	-- The reach above is clamped to the runway, and then the sideways gain was added after it
	-- and clamped by nothing. Nobody walks onto a pad perfectly square: a few studs a second
	-- of drift from turning, multiplied by SWING and carried for the whole flight, is thirty
	-- studs across -- which is over the edge from the middle of the map. "despite us having a
	-- limit against launching off a trampoline head on, and flying off map, that happened more
	-- than once."
	--
	-- So the landing point is worked out from the whole velocity and pulled back in. Only for
	-- a throw that is going roughly where the pad points: a deliberate angle is allowed off the
	-- map, which is the thing worth being able to do on purpose.
	local flat = dir * (reach / flight) + across * side
	if flat.Magnitude > 1e-3 and flat.Unit:Dot(dir) > 0.94 then     -- within ~20 degrees of square
		local lim = edge - MARGIN
		local land = root.Position + flat * flight
		local k = 1
		if math.abs(land.X) > lim and math.abs(flat.X) > 1e-3 then
			k = math.min(k, ((land.X > 0 and lim or -lim) - root.Position.X) / (flat.X * flight))
		end
		if math.abs(land.Z) > lim and math.abs(flat.Z) > 1e-3 then
			k = math.min(k, ((land.Z > 0 and lim or -lim) - root.Position.Z) / (flat.Z * flight))
		end
		flat = flat * math.clamp(k, 0, 1)
	end

	root.AssemblyLinearVelocity = flat + Vector3.new(0, up, 0)
	thrownAt[player] = now
	bounce(root)
	flex(pad)
end

--- Every pad in the map, wired once.
---
--- By name, because a trampoline is a thing the map file decides to have: adding a building
--- with two more on it is an edit to a .model.json and nothing here.
local function wire()
	local map = workspace:WaitForChild("Map", 30)
	if not map then return end
	local n = 0
	for _, part in ipairs(map:GetDescendants()) do
		if part:IsA("BasePart") and part.Name:match("^Trampoline") and not part.Name:match("Bed$") then
			n += 1
			part.Touched:Connect(function(hit)
				local char = hit and hit.Parent
				local player = char and Players:GetPlayerFromCharacter(char)
				if player then launch(player, part) end
			end)
		end
	end
	print(("trampolines: %d on the roofs"):format(n))
end

Players.PlayerRemoving:Connect(function(player) thrownAt[player] = nil end)

task.spawn(wire)

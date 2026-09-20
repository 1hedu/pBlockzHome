-- Space fishing, as everybody sees it: the wind-up and the cast, the line out of the rod, the float
-- out in space, the bite, and the fish coming up out of it.
--
-- The cast is charged. Hold the button with the rod in hand and he loads up over a second, the rod
-- going back over his shoulder, and at the top of it he shakes with it; let go and he lunges forward
-- and the float flies. How far is the angler's own machine's to say -- a random length, longer for a
-- harder throw (SpaceFishing.luau) -- and the cast rings out as it goes: BFS 9000's stroke, higher
-- the harder it was thrown.
--
-- What is caught is not decided here. The angler's own wallet casts and reels on the Fishing
-- contract (contracts/Fishing.sol) -- see Fishing.client.luau -- and the chain decides when a fish
-- bites and what it is. This end draws it for the whole town, and when the angler says they
-- reeled one in, it reads the contract to find out what they actually got (Angling.luau) before it
-- shows anybody a fish.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Fish = require(ReplicatedStorage:WaitForChild("Fish"))
local SpaceFishing = require(ReplicatedStorage:WaitForChild("SpaceFishing"))
local Contracts = require(ReplicatedStorage:WaitForChild("Contracts"))
local Angling = require(script.Parent.Angling)
local Ledger = require(script.Parent.Ledger)
local Health = require(script.Parent.Health)

local remote = Instance.new("RemoteEvent")
remote.Name = "FishingRemote"
remote.Parent = ReplicatedStorage

local folder = Instance.new("Folder")
folder.Name = "SpaceFishing"
folder.Parent = workspace

--- How long, after the reel is sent, to keep reading for the catch. A public node can be a few
--- blocks behind the one the transaction landed in.
local LANDING_SECONDS = 40

-- The colours a line can be, one picked at random for each cast. Only for the look of it: what
-- bites is the chain's business, and this has nothing to do with that.
local LINE_COLOURS = { "Red", "Magenta", "Purple", "Blue", "Cyan" }

local function lineColour()
	local want = LINE_COLOURS[math.random(#LINE_COLOURS)]
	for _, c in ipairs(Fish.COLOURS) do
		if c.name == want then return Color3.fromRGB(c.rgb[1], c.rgb[2], c.rgb[3]) end
	end
	return Color3.fromRGB(236, 236, 236)
end

-- The parts of the rod that are the line hanging from it at rest: hidden while the line is out.
local HANGING = { Line = true, FloatTop = true, FloatBottom = true }

-- ---- where lines were cast, kept -------------------------------------------------------------
-- A line is on the chain until it is reeled in or its window passes, whoever walks off. So where it
-- was cast is written down against the address, and a line picked up again -- after leaving, or after
-- putting the rod down -- goes back where it was (Fishing.client.luau resumes it).
local store = nil
local function lineStore()
	if store then return store end
	local ok, got = pcall(function() return DataStoreService:GetDataStore("Fishing") end)
	store = ok and got or nil
	return store
end
local function lineKey(player)
	local address = Ledger.addressOf(player)
	return address and ("line/" .. address:lower()) or nil
end
local function keepLine(player, point)
	local key, s = lineKey(player), lineStore()
	if key and s then
		task.spawn(pcall, function() s:SetAsync(key, { point.X, point.Y, point.Z }) end)
	end
end
local function forgetLine(player)
	local key, s = lineKey(player), lineStore()
	if key and s then task.spawn(pcall, function() s:RemoveAsync(key) end) end
end
local function keptLine(player)
	local key, s = lineKey(player), lineStore()
	if not key or not s then return nil end
	local ok, got = pcall(function() return s:GetAsync(key) end)
	if ok and type(got) == "table" and #got == 3 then return Vector3.new(got[1], got[2], got[3]) end
	return nil
end

local lines = {}         -- player -> { model, tip, rod, before, landing }
local winding = {}       -- player -> { start, joints } while the button is held with the rod
local throwing = {}      -- player -> { t, from (pose), fraction, point, cast } through the lunge and home

-- ---- the wind-up and the lunge --------------------------------------------------------------
-- Poses in degrees, the columns Weapons.server.luau measured for the R6 rig: the right shoulder's
-- sx (out to his right when negative), sy (across the body), sz (up and forward), then the waist's
-- wx (leans forward), wy (rolls), wz (twists to his left).
local REST = { 0, 0, 0, 0, 0, 0 }
-- Loaded: the rod back up over his right shoulder, weight on the back foot, turned away.
local LOADED = { -12, -10, 168, -14, 0, -18 }
-- The lunge: arm out and down past level, leaning into it, turned through to face the throw.
local LUNGE = { 0, 6, 84, 22, 0, 12 }
local SHAKE = 3.5          -- degrees each way once fully charged
local SHAKE_HZ = 22
local LUNGE_SECS = 0.16    -- into the lunge, fast
local HOLD_SECS = 0.35     -- held out while the line goes
local HOME_SECS = 0.4      -- and back
local LET_GO = 0.1         -- seconds into the lunge the float leaves the rod
local CAST_SOUND = "master"
local EARSHOT = 70

local function jointsOf(player)
	local ch = player.Character
	local torso = ch and ch:FindFirstChild("Torso")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not torso then return nil end
	return { right = torso:FindFirstChild("Right Shoulder"), waist = root and root:FindFirstChild("RootJoint") or nil }
end

local function smooth(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function blend(a, b, u)
	local out = {}
	for i = 1, 6 do out[i] = a[i] + (b[i] - a[i]) * u end
	return out
end

--- Poses the rod arm and the waist. Home is exactly the identity, so the walk has the limbs back.
local function pose(j, v)
	if not j then return end
	if j.right and j.right.Parent then
		j.right.Transform = CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
	end
	if j.waist and j.waist.Parent then
		j.waist.Transform = CFrame.Angles(math.rad(v[4]), math.rad(v[5]), math.rad(v[6]))
	end
end

--- Where the wind-up has got to, `held` seconds in: the pose, and it shakes once it is full.
local function windPose(held)
	local frac = SpaceFishing.fraction(held)
	local v = blend(REST, LOADED, smooth(frac))
	if frac >= 1 then
		local now = os.clock()
		v[3] += math.sin(now * SHAKE_HZ * 2 * math.pi) * SHAKE
		v[2] += math.cos(now * SHAKE_HZ * 1.7 * 2 * math.pi) * SHAKE * 0.6
		v[6] += math.sin(now * SHAKE_HZ * 1.3 * 2 * math.pi) * SHAKE * 0.5
	end
	return v
end
local announced = false  -- the Everliving Fish has been announced to the town

local function rodOf(player)
	local ch = player.Character
	local rod = ch and ch:FindFirstChild(Fish.ROD)
	return rod and rod:IsA("Accoutrement") and rod or nil
end

local function showHanging(rod, shown)
	if not rod then return end
	for _, d in ipairs(rod:GetDescendants()) do
		if d:IsA("BasePart") and HANGING[d.Name] then
			d.Transparency = shown and (d.Name == "Line" and 0.3 or 0) or 1
		end
	end
end

--- Holds an angler where they stand while their line is out: no walking and no jumping, though
--- they can still turn. Given back exactly as it was when the line goes.
local function hold(player, line)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	line.held = { humanoid = hum, walk = hum.WalkSpeed, jump = hum.JumpPower, height = hum.JumpHeight }
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.JumpHeight = 0
end

local function letGoOf(line)
	local h = line.held
	line.held = nil
	if h and h.humanoid.Parent then
		h.humanoid.WalkSpeed = h.walk
		h.humanoid.JumpPower = h.jump
		h.humanoid.JumpHeight = h.height
	end
end

local function clear(player)
	local line = lines[player]
	if not line then return end
	lines[player] = nil
	letGoOf(line)
	if line.model then line.model:Destroy() end
	if line.tip then line.tip:Destroy() end
	if line.rod and line.rod.Parent then showHanging(line.rod, true) end
end

--- The end of the rod, where the line comes out.
local function tipOf(rod)
	local blank = rod:FindFirstChild("BlankHigh", true)
	if not blank then return nil end
	local tip = Instance.new("Attachment")
	tip.Name = "LineTip"
	tip.Position = Vector3.new(0, blank.Size.Y / 2, 0)
	tip.Parent = blank
	return tip
end

-- The float: one ball, red over white, cut in half the way a Roblox builder makes one -- a ball with
-- a block subtracted from it (GeometryService:SubtractAsync) -- once, at start, and copied for every cast.
local FLOAT_SIZE = 1.3
local floatHalves = nil   -- { top = UnionOperation, bottom = UnionOperation }, once made

local function halfBall(colour, keepTop)
	local whole = Instance.new("Part")
	whole.Shape = Enum.PartType.Ball
	whole.Size = Vector3.one * FLOAT_SIZE
	whole.Color = colour
	whole.Material = Enum.Material.SmoothPlastic
	whole.Anchored = true
	whole.CFrame = CFrame.new()
	local cutter = Instance.new("Part")
	cutter.Size = Vector3.new(FLOAT_SIZE + 0.2, FLOAT_SIZE / 2 + 0.1, FLOAT_SIZE + 0.2)
	cutter.Anchored = true
	cutter.CFrame = CFrame.new(0, (keepTop and -1 or 1) * (FLOAT_SIZE / 4 + 0.05), 0)
	-- GeometryService's, which takes parts that are not in the Workspace; BasePart:SubtractAsync does not.
	local half = game:GetService("GeometryService"):SubtractAsync(whole, { cutter })[1]
	half.UsePartColor = true
	half.Color = colour
	half.Material = Enum.Material.SmoothPlastic
	whole:Destroy()
	cutter:Destroy()
	return half
end

task.spawn(function()
	local ok, err = pcall(function()
		local top = halfBall(Color3.fromRGB(214, 36, 40), true)
		local bottom = halfBall(Color3.fromRGB(240, 240, 240), false)
		floatHalves = { top = top, bottom = bottom }
	end)
	if not ok then warn("fishing: the float could not be cut in half (" .. tostring(err) .. "); two balls it is") end
end)

local function ball(name, size, colour, at)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(size, size, size)
	p.Color = colour
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(at)
	return p
end

local function cast(player, point, resumed)
	local rod = rodOf(player)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not rod or not root then return false end
	-- A line picked up again goes back where it was, wherever its angler is standing now.
	if not resumed and not SpaceFishing.fair(point, root.Position) then return false end
	clear(player)

	local tip = tipOf(rod)
	if not tip then return false end
	local model = Instance.new("Model")
	model.Name = player.Name
	-- Big enough to be seen bobbing ninety studs out and forty-odd down. The model hangs off a point at
	-- the ball's middle; the two halves are placed about it, so moving the point moves the float.
	local float = ball("Float", 0.1, Color3.new(1, 1, 1), point)
	float.Transparency = 1
	float.Parent = model
	for _, half in ipairs({ { "FloatTop", "top", Color3.fromRGB(214, 36, 40), 1 }, { "FloatBottom", "bottom", Color3.fromRGB(240, 240, 240), -1 } }) do
		local part
		if floatHalves then
			part = floatHalves[half[2]]:Clone()
			-- A union keeps the place of the part it was cut from: both halves were cut from a ball at the
			-- origin, so both go where the ball's middle is.
			part.CFrame = CFrame.new(point)
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		else
			part = ball(half[1], FLOAT_SIZE * 0.9, half[3], point + Vector3.new(0, half[4] * 0.35, 0))
		end
		part.Name = half[1]
		part.Parent = model
	end
	model.PrimaryPart = float
	local eye = Instance.new("Attachment")
	eye.Name = "LineEnd"
	eye.Position = Vector3.new(0, 0.62, 0)
	eye.Parent = float

	local beam = Instance.new("Beam")
	beam.Name = "Line"
	beam.Attachment0 = tip
	beam.Attachment1 = eye
	local length = (tip.WorldPosition - point).Magnitude
	beam.Width0 = 0.05
	beam.Width1 = 0.12
	beam.FaceCamera = true
	beam.Segments = 20
	beam.CurveSize0 = 0
	beam.CurveSize1 = -math.min(length * 0.12, 10)   -- slack, sagging toward the float
	beam.Color = ColorSequence.new(lineColour())
	beam.LightEmission = 0.6
	beam.Transparency = NumberSequence.new(0.1)
	beam.Parent = model

	model:SetAttribute("Angler", player.UserId)
	model:SetAttribute("State", "out")
	-- Where the throw starts, so every client can fly the float out from the rod.
	model:SetAttribute("From", tip.WorldPosition)
	model:SetAttribute("CastAt", workspace:GetServerTimeNow())
	-- How long the float is in the air: longer for a longer cast.
	model:SetAttribute("Throw", 0.45 + (length / SpaceFishing.FURTHEST) * 0.75)
	model.Parent = folder
	showHanging(rod, false)
	if not resumed then keepLine(player, point) end

	-- What they had before this cast, read now rather than remembered: the reel is a later block
	-- than the cast, so a read made now cannot already include what this line brings up.
	local line = { model = model, tip = tip, rod = rod, before = {} }
	lines[player] = line
	hold(player, line)
	local function snapshot()
		for species = 0, Fish.EVERLIVING do line.before[species] = Angling.caught(player, species) end
	end
	snapshot()
	task.spawn(function()
		Angling.readCatches(player)
		if lines[player] == line and not line.landing then snapshot() end
	end)
	return true
end

--- How big a caught fish is held up for everyone to see, and for how long.
local SHOW_SCALE = 3
local RISE_SECS = 1.1
local SHOW_SECS = 2.4
local IN_SECS = 0.5

--- A fish up out of the float, three times its size, held in the air in front of the angler and
--- turning -- the angler's camera goes to it (Fishing.client.luau) -- and then into their hands.
local function landFish(player, species, from)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local made = ReplicatedStorage:FindFirstChild("Made")
	local template = made and made:FindFirstChild(Fish.nameOf(species))
	if not root or not template then return end
	local holder = Instance.new("Model")
	holder.Name = "Caught"
	local copy = template:Clone()
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true d.CanCollide = false d.CanQuery = false end
	end
	copy.Parent = holder
	holder.PrimaryPart = copy:FindFirstChild("Handle")
	holder:PivotTo(CFrame.new(from))
	holder.Parent = folder

	-- In front of him, toward where it came from, and up where it can be seen.
	local out = Vector3.new(from.X - root.Position.X, 0, from.Z - root.Position.Z)
	out = out.Magnitude > 1e-3 and out.Unit or root.CFrame.LookVector
	local show = root.Position + out * 8 + Vector3.new(0, 6, 0)
	-- Side on to him, head to his right, as a fish is held up to be looked at.
	local sideways = CFrame.lookAt(show, show + out:Cross(Vector3.yAxis))

	-- A CFrameValue and a NumberValue tweened and followed: a Model has no CFrame of its own and
	-- its size is Model:ScaleTo's.
	local where = Instance.new("CFrameValue")
	where.Value = CFrame.new(from)
	local size = Instance.new("NumberValue")
	size.Value = 1
	local spin = 0
	local function place()
		if not holder.Parent then return end
		holder:PivotTo(where.Value * CFrame.Angles(0, spin, 0))
	end
	where.Changed:Connect(place)
	size.Changed:Connect(function(v) if holder.Parent then holder:ScaleTo(math.max(v, 0.05)) end end)

	local rising = TweenInfo.new(RISE_SECS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(where, rising, { Value = sideways }):Play()
	TweenService:Create(size, rising, { Value = SHOW_SCALE }):Play()
	remote:FireClient(player, "showcase", holder, RISE_SECS + SHOW_SECS)
	task.wait(RISE_SECS)

	-- Hung there, turning a little one way and back, bobbing.
	local t0 = os.clock()
	while os.clock() - t0 < SHOW_SECS and holder.Parent do
		local t = os.clock() - t0
		spin = math.sin(t * 2.2) * 0.5
		where.Value = sideways + Vector3.new(0, math.sin(t * 3) * 0.25, 0)
		task.wait()
	end

	local hands = (ch:FindFirstChild("Head") and ch.Head.Position or root.Position) + Vector3.new(0, 1, 0)
	local going = TweenInfo.new(IN_SECS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(where, going, { Value = CFrame.new(hands) }):Play()
	local shrink = TweenService:Create(size, going, { Value = 0.3 })
	shrink:Play()
	shrink.Completed:Wait()
	holder:Destroy()
	where:Destroy()
	size:Destroy()
end

local offerDiscovery   -- defined below; landed() calls it

--- Whoever found the Everliving Fish, off the contract.
local function readDiscoverer()
	local answer = Ledger.request({ action = "read", to = Contracts.Fishing, fn = "discoverer()", args = {}, returns = { "address" } })
	local who = answer and answer.ok and answer.words and answer.words[1]
	return type(who) == "string" and who or nil
end

--- Whether this player caught the Everliving Fish while it was undiscovered and has not claimed it.
local function mayClaim(player)
	local address = Ledger.addressOf(player)
	if not address or not Contracts.Fishing or Contracts.Fishing == "" then return false end
	local who = readDiscoverer()
	if who == nil or not who:match("^0x0+$") then return false end
	local answer = Ledger.request({ action = "read", to = Contracts.Fishing, fn = "canClaimDiscovery(address)",
		args = { address }, returns = { "bool" } })
	return answer ~= nil and answer.ok and answer.words ~= nil and answer.words[1] == true
end

--- The choice: mint the one token and unlock the Everliving Fish for everyone, or not. Theirs, from
--- their own wallet (Fishing.client.luau), and offered again every time they come back until
--- somebody has claimed it.
offerDiscovery = function(player)
	if not mayClaim(player) or not player.Parent then return end
	remote:FireClient(player, "discovery", { name = player.Name, address = Ledger.addressOf(player) })
end

--- They say they claimed it. The chain says whether they did, and the town hears it once.
local function claimed(player)
	local mine = Ledger.addressOf(player)
	for _ = 1, 20 do
		local who = readDiscoverer()
		if who and mine and who:lower() == mine:lower() then
			if not announced then
				announced = true
				local news = ReplicatedStorage:FindFirstChild("CombatNews")
				if news then
					news:FireAllClients(("%s has discovered the Everliving Fish, and unlocked it for everyone!"):format(player.Name), 5)
				end
			end
			return
		end
		task.wait(2)
	end
end

--- They say they reeled in. Read what the contract now counts for them until something has
--- changed, and show that.
local function landed(player)
	local line = lines[player]
	if not line or line.landing then return end
	line.landing = true
	line.model:SetAttribute("State", "reel")
	-- The line is in: nothing holds them where they stand any more. Reading what came up can
	-- take a while (a public node lags), and being frozen for it, with no way out, was the bug.
	letGoOf(line)
	local at = line.model.PrimaryPart and line.model.PrimaryPart.Position
	local caught = nil
	local deadline = os.clock() + LANDING_SECONDS
	while os.clock() < deadline and player.Parent and lines[player] == line do
		Angling.readCatches(player)
		for species = 0, Fish.EVERLIVING do
			if Angling.caught(player, species) > (line.before[species] or 0) then caught = species break end
		end
		if caught then break end
		task.wait(2)
	end
	if lines[player] ~= line then return end
	clear(player)
	forgetLine(player)
	if not player.Parent then return end
	if caught == nil then
		remote:FireClient(player, "result", "It got away.")
		return
	end
	local name = Fish.nameOf(caught)
	remote:FireClient(player, "result", ("You caught %s %s!"):format(name:match("^[AEIOU]") and "an" or "a", name))
	if at then task.spawn(landFish, player, caught, at) end
	if caught == Fish.EVERLIVING then task.spawn(offerDiscovery, player) end
end

remote.OnServerEvent:Connect(function(player, action, arg)
	if action == "charge" then
		-- The button down with the rod in hand and nothing out: the wind-up starts.
		if rodOf(player) and not lines[player] and not throwing[player] then
			winding[player] = { start = os.clock(), joints = jointsOf(player) }
		end
	elseif action == "flourish" then
		-- Let go of a wind-up with nowhere to cast to: the lunge, for the fun of it, and nothing thrown.
		local w = winding[player]
		winding[player] = nil
		if w then
			throwing[player] = { t = 0, from = windPose(os.clock() - w.start), joints = w.joints,
				fraction = SpaceFishing.fraction(os.clock() - w.start) }
		end
	elseif action == "resume" then
		-- A line still out on the chain, picked up again: drawn back where it was cast.
		if not lines[player] and rodOf(player) then
			task.spawn(function()
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if not root then return end
				local point = keptLine(player) or SpaceFishing.restingPoint(root.Position)
				if not lines[player] and cast(player, point, true) then
					lines[player].model:SetAttribute("State", arg == "bite" and "bite" or "out")
				end
			end)
		end
	elseif action == "claimed" then
		task.spawn(claimed, player)
	elseif action == "uncharge" then
		local w = winding[player]
		winding[player] = nil
		if w then throwing[player] = { t = LUNGE_SECS, from = windPose(os.clock() - w.start), joints = w.joints, home = true } end
	elseif action == "cast" then
		local w = winding[player]
		winding[player] = nil
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local fraction = w and SpaceFishing.fraction(os.clock() - w.start) or 0
		if not w or not root or not rodOf(player) or not SpaceFishing.fair(arg, root.Position) then
			if w then throwing[player] = { t = LUNGE_SECS, from = windPose(os.clock() - w.start), joints = w.joints, home = true } end
			-- Why, so the angler is told the truth: a line still coming in is not a bad aim.
			local line = lines[player]
			remote:FireClient(player, "refused", line and (line.landing and "landing" or "out") or "there")
			return
		end
		-- The lunge; the float leaves the rod a moment into it (the Heartbeat below).
		throwing[player] = { t = 0, from = windPose(os.clock() - w.start), joints = w.joints,
			fraction = fraction, point = arg }
	elseif action == "bite" then
		local line = lines[player]
		if line and not line.landing then line.model:SetAttribute("State", "bite") end
	elseif action == "reel" then
		local line = lines[player]
		if line and not line.landing then line.model:SetAttribute("State", "reel") end
	elseif action == "waiting" then
		local line = lines[player]
		if line and not line.landing then line.model:SetAttribute("State", "out") end
	elseif action == "landed" then
		task.spawn(landed, player)
	elseif action == "gone" or action == "cancel" then
		-- A line being landed can be let go of too: landed() sees it is gone and stops reading.
		if lines[player] then clear(player) end
		-- Gone is gone from the chain too; a cancel is only this machine letting go of it, and the
		-- line is still out there to be picked up again.
		if action == "gone" then forgetLine(player) end
	end
end)

-- The wind-up, the lunge and the way home, every frame.
RunService.Heartbeat:Connect(function(dt)
	for player, w in pairs(winding) do
		if not player.Parent or not rodOf(player) then
			winding[player] = nil
			if player.Parent then pose(w.joints, REST) end
		else
			pose(w.joints, windPose(os.clock() - w.start))
		end
	end
	for player, th in pairs(throwing) do
		th.t += dt
		if not player.Parent then
			throwing[player] = nil
		elseif th.home then
			-- Put down without a throw: straight back from wherever it had got to.
			local u = (th.t - LUNGE_SECS) / HOME_SECS
			if u >= 1 then
				pose(th.joints, REST)
				throwing[player] = nil
			else
				pose(th.joints, blend(th.from, REST, smooth(math.max(u, 0))))
			end
		else
			if th.t < LUNGE_SECS then
				pose(th.joints, blend(th.from, LUNGE, smooth(th.t / LUNGE_SECS)))
			elseif th.t < LUNGE_SECS + HOLD_SECS then
				pose(th.joints, LUNGE)
			elseif th.t < LUNGE_SECS + HOLD_SECS + HOME_SECS then
				pose(th.joints, blend(LUNGE, REST, smooth((th.t - LUNGE_SECS - HOLD_SECS) / HOME_SECS)))
			else
				pose(th.joints, REST)
				throwing[player] = nil
			end
			if not th.cast and th.t >= LET_GO then
				th.cast = true
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then Health.soundNear(root.Position, CAST_SOUND, EARSHOT, 1 + th.fraction) end
				if th.point then
					-- Accepted or not, said so: the client asks the wallet to cast only once the town has
					-- taken the cast. It used to ask at the same time, so a refused cast still put a
					-- prompt up -- for a transaction the chain was about to reject.
					if cast(player, th.point) then remote:FireClient(player, "casting")
					else remote:FireClient(player, "refused", lines[player] and "out" or "there") end
				end
			end
		end
	end
end)

-- Put the rod away, or lose the body holding it, and the line comes in.
task.spawn(function()
	while true do
		task.wait(0.5)
		for player, line in pairs(lines) do
			if not line.landing and (not player.Parent or rodOf(player) ~= line.rod) then clear(player) end
		end
	end
end)

-- An Everliving Fish caught and not claimed is offered again when its angler comes back.
local function watchSignIn(player)
	player:GetAttributeChangedSignal("WalletAddress"):Connect(function()
		task.delay(3, offerDiscovery, player)
	end)
	if Ledger.addressOf(player) then task.delay(3, offerDiscovery, player) end
end
Players.PlayerAdded:Connect(watchSignIn)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(watchSignIn, player) end

Players.PlayerRemoving:Connect(function(player)
	clear(player)
	winding[player] = nil
	throwing[player] = nil
end)

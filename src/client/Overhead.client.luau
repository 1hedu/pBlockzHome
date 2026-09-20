-- Who that is, and how many hearts they have left: over everyone else's head.
--
-- A fight you can only follow from your own meter is a fight where you have no idea whether
-- the person you are swinging at is one hit from going over. So while someone is up for a
-- fight their hearts hang above them, under their name, and go away again the moment they
-- turn PvP off at the bank.
--
-- ---- why this is a client script -------------------------------------------------------
-- Because it is a thing drawn on a screen. The server does spatial information, combat,
-- chat, the Familiar's voice, the trampolines and the Engrams; it does not build models and
-- it does not build interface. This was on the server, as one BillboardGui per player
-- parented into the world, and every question it raised was a question about making a
-- server-built GUI cross a wire -- which is the wrong question, and the reason no bot ever
-- had hearts over its head.
--
-- Each client draws the players it can see, off state that is already replicated:
--
--   the hearts    Humanoid.Health and MaxHealth, which are Humanoid properties.
--   in a fight    the Fights attribute Health.push sets on the Player.
--   on a streak   the OnFire attribute, same place.
--   the name      Player.DisplayName, and "#n" after it: the Rank attribute, their place on the
--                 ranked duel leaderboard (Duels.refreshRanks), for anybody who has a place.
--
-- Nothing has to be sent for any of it, nothing goes stale for a client that joined late,
-- and there is no per-player message on the wire while a fight is going on.
--
-- ---- only what you can see --------------------------------------------------------------
-- A player's hearts show only while you can see that player. Behind a wall, round a corner,
-- inside a building, the hearts go: how hurt somebody is is something you find out by looking at
-- them, not something the walls tell you. The name stays, so you still know who is in the
-- square. Seen means a clear ray from the camera to their head or their middle -- either will
-- do, so somebody half behind a crate is still somebody you can see -- with bodies (players',
-- and anything else with a Humanoid, the town's people included) and anything mostly
-- see-through, glass included, not in the way.

-- ---- the name --------------------------------------------------------------------------
-- The engine draws its own name tag, and it draws it in the engine's default face. This
-- draws the name instead, in the place's own Reactor7, in the same board as the hearts so
-- the two cannot drift apart -- and Health.dress turns the built-in one off. That is how a
-- Roblox place does a name tag it wants to style.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeartRow = require(ReplicatedStorage:WaitForChild("HeartRow"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local TownOwner = require(ReplicatedStorage:WaitForChild("TownOwner"))

-- In studs: the board is part of the world, so it is bigger up close and smaller far off, the
-- way the body under it is. Sized in pixels it was the same few pixels at any distance -- a name
-- nobody could read standing next to it.
local SIZE = 1.1              -- a heart
local GAP = 0.12
local NAME_H = 0.9            -- the name's line, over the hearts
local ABOVE = 2.4             -- studs over the head
local FAR = 120               -- studs at which the whole thing stops being drawn
local LOOK_EVERY = 0.1        -- seconds between line-of-sight checks
local SEE_THROUGH = 0.5       -- a part at least this transparent does not block the view


local me = Players.LocalPlayer

-- Its own ScreenGui rather than a BillboardGui per character, and the boards hang off it by
-- Adornee. A client has no business parenting anything into another player's character:
-- that is the server's tree, the body can be replaced under you at any respawn, and a
-- billboard left in it is a billboard nothing owns.
local screen = Instance.new("ScreenGui")
screen.Name = "Overhead"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
-- A HUD, not a panel: Weapons.client.luau refuses to swing while a window is open and would
-- otherwise count this as one.
screen:SetAttribute("Hud", true)
screen.Parent = me:WaitForChild("PlayerGui")

local boards = {}             -- player -> { gui, row, name, head }
local icon = ""

local function drop(player)
	local kept = boards[player]
	boards[player] = nil
	if kept and kept.gui and kept.gui.Parent then kept.gui:Destroy() end
end

--- The board for one player, hung on `head`, made if there is not one on that head already.
---
--- Keyed on the head as well as the player because a respawn hands them a new one, and a
--- board still adorned to the old head is adorned to a part that has been destroyed -- which
--- draws nothing and looks exactly like this script never running.
local function board(player, head)
	local kept = boards[player]
	if kept and kept.gui.Parent and kept.head == head then return kept end
	drop(player)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Overhead" .. player.Name
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.StudsOffset = Vector3.new(0, ABOVE, 0)
	-- A BillboardGui's Size scale is studs, so it is drawn at the size it is in the world, getting
	-- smaller the further off it is -- but no bigger than it is six studs away, so somebody standing on
	-- top of you is not a wall of name.
	gui.DistanceLowerLimit = 6
	local wide = 4 * SIZE + 3 * GAP
	local tall = NAME_H + GAP + SIZE
	gui.Size = UDim2.new(wide * 1.6, 0, tall, 0)   -- room either side for a long name
	gui.MaxDistance = FAR
	gui.Parent = screen

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, NAME_H / tall, 0)
	name.Position = UDim2.new(0, 0, 0, 0)
	name.Text = player.DisplayName ~= "" and player.DisplayName or player.Name
	name.TextScaled = true
	name.TextSize = Theme.t.small
	name.TextColor3 = TownOwner.EVERYONE
	name.TextStrokeTransparency = 0.2
	name.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	-- The place's own face, and re-applied if it has not arrived yet: the font is a
	-- published asset and a player can be on screen well before it lands.
	Theme.face(name)
	name.Parent = gui

	-- The hearts sit under the name in their own band, so HeartRow can go on centring
	-- itself in what it is given without having to know a name is up there.
	local under = Instance.new("Frame")
	under.Name = "Hearts"
	under.BackgroundTransparency = 1
	under.Position = UDim2.new((1 - 1 / 1.6) / 2, 0, (NAME_H + GAP) / tall, 0)
	under.Size = UDim2.new(1 / 1.6, 0, SIZE / tall, 0)
	under.Parent = gui

	local row = HeartRow.new(under, SIZE, GAP, true)
	row:setIcon(icon)

	boards[player] = { gui = gui, row = row, name = name, under = under, head = head }
	return boards[player]
end

--- Draws one player as they are this instant.
local function redraw(player)
	if player == me then return end
	local ch = player.Character
	local head = ch and ch:FindFirstChild("Head")
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not head or not hum then
		drop(player)
		return
	end
	local kept = board(player, head)
	if not kept then return end
	-- The whole board goes out of sight together, name and hearts: a name floating over a wall is
	-- as much a giveaway of where somebody is as their hearts are.
	kept.name.Visible = kept.seen ~= false
	local rank = player:GetAttribute("Rank")
	local shown = player.DisplayName ~= "" and player.DisplayName or player.Name
	kept.name.Text = type(rank) == "number" and ("%s #%d"):format(shown, rank) or shown
	-- The town's owner in gold -- the address the Announcements contract names, not a name -- and
	-- everybody else in purple.
	kept.name.TextColor3 = TownOwner.is(player) and TownOwner.COLOUR or TownOwner.EVERYONE

	-- Dead bodies keep no board. A corpse with three hearts over it reads as somebody still
	-- in the fight, and the respawn is a second and a half away.
	if hum.Health <= 0 then
		kept.gui.Enabled = false
		return
	end
	kept.gui.Enabled = true

	local fights = player:GetAttribute("Fights")
	-- Absent means in: Health.fights is on for everyone until they turn it off, and a client
	-- that reads the attribute before the first push should not draw them as a pacifist.
	kept.under.Visible = fights ~= false and kept.seen ~= false
	if fights == false then return end

	-- A guard that hid every row went here and is gone: anything whose MaxHealth was above
	-- eight had its hearts hidden, and "no hearts whatsoever" arrived with it. HeartRow clamps
	-- the container count now, which stops the hundred-heart flash on spawn without being able
	-- to hide anything.
	kept.row:draw(math.max(0, math.floor(hum.Health + 0.5)), hum.MaxHealth,
		HeartRow.colours(player:GetAttribute("OnFire") == true))
end

--- Watches one player for everything that can change what is over their head.
---
--- Every one of these is an OPTIMISATION and none of them is load-bearing: the sweep below
--- redraws everybody twice a second whatever happens here. That is deliberate now. It used
--- to WaitForChild the Humanoid inside a spawned task, and on a busy server that threw --
--- "attempt to index nil with 'Wait'", eight times, once per player in the town -- which
--- killed the task before a single listener was attached. Nothing after it ran.
local function watch(player)
	if player == me then return end
	-- Health is a Humanoid property and the Humanoid goes with the body, so the listeners
	-- are hung per character and dropped with it.
	--
	-- FindFirstChild and not WaitForChild: a body that has not finished assembling is not
	-- worth yielding for here, because the sweep will come round and hook it in half a
	-- second. Yielding was what made this fragile.
	local function follow(ch)
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		hum:GetPropertyChangedSignal("Health"):Connect(function() redraw(player) end)
		hum:GetPropertyChangedSignal("MaxHealth"):Connect(function() redraw(player) end)
		redraw(player)
	end
	pcall(function()
		player.CharacterAdded:Connect(function(ch)
			drop(player)
			pcall(follow, ch)
		end)
		player.CharacterRemoving:Connect(function() drop(player) end)
		player:GetAttributeChangedSignal("Fights"):Connect(function() redraw(player) end)
		player:GetAttributeChangedSignal("OnFire"):Connect(function() redraw(player) end)
		player:GetAttributeChangedSignal("Rank"):Connect(function() redraw(player) end)
		player:GetAttributeChangedSignal("WalletAddress"):Connect(function() redraw(player) end)
	end)
	if player.Character then pcall(follow, player.Character) end
end

-- The owner's address arriving off the chain recolours whoever is them.
TownOwner.known.Event:Connect(function()
	for player in pairs(boards) do pcall(redraw, player) end
end)

--- Whether your character can see `ch`: a clear ray from your own head to its head or its middle.
---
--- From the character, not the camera. The camera can be swung round a corner or pulled up over a
--- wall while you stand behind it, and what you are able to see is what your character could --
--- otherwise hiding behind a wall hides nothing from anybody who turns their camera.
local function inSight(ch)
	local mine = me.Character
	local eyes = mine and mine:FindFirstChild("Head")
	local cam = workspace.CurrentCamera
	if not eyes and not cam then return true end
	local from = eyes and eyes.Position or cam.CFrame.Position
	-- Every character out of the way: a body between you and them is not a wall.
	local skip = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(skip, p.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _, name in ipairs({ "Head", "HumanoidRootPart" }) do
		local target = ch:FindFirstChild(name)
		if target then
			local through = table.clone(skip)
			-- A few goes, stepping past anything see-through the ray meets.
			for _ = 1, 6 do
				params.FilterDescendantsInstances = through
				local hit = workspace:Raycast(from, target.Position - from, params)
				if not hit then return true end
				-- A body is not a wall: step past the whole of it.
				local model = hit.Instance:FindFirstAncestorOfClass("Model")
				if model and model:FindFirstChildOfClass("Humanoid") then
					table.insert(through, model)
				elseif hit.Instance.Transparency >= SEE_THROUGH then
					table.insert(through, hit.Instance)
				else
					break
				end
			end
		end
	end
	return false
end

-- The look, a few times a second, for everyone with a board. A change redraws that one row.
task.spawn(function()
	while true do
		task.wait(LOOK_EVERY)
		for player, kept in pairs(boards) do
			local ch = player.Character
			if ch and kept.gui.Parent then
				local ok, seen = pcall(inSight, ch)
				seen = not ok or seen
				if kept.seen ~= seen then
					kept.seen = seen
					pcall(redraw, player)
				end
			end
		end
	end
end)

Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(drop)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end

-- A sweep as well as the signals, and it is the half that has to work.
--
-- Health on a body this machine does not simulate arrives as a replicated property change,
-- and a property set to the value it already holds fires nothing -- so a player who respawns
-- at full hearts after dying at full hearts never signals. The sweep also catches a body
-- that finished assembling after the last redraw, and any player whose listeners never
-- attached. Twice a second over however many people are in the town, which is nothing.
--
-- Each player in its own pcall, and that is the important word. One player mid-respawn
-- throwing inside redraw used to take the whole loop down with it -- and a dead sweep is
-- every row in the town frozen at whatever it last said, for the rest of the session. Which
-- is exactly what "they dont update everyone always shows 3 above their head" looks like.
local complained = false

task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= me then
				local ok, why = pcall(redraw, player)
				-- Said once, not twice a second: a row that cannot be drawn is worth knowing
				-- about, and a log that repeats it forever is worth nothing.
				if not ok and not complained then
					complained = true
					warn("overhead: could not draw a row -- " .. tostring(why))
				end
			end
		end
	end
end)

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("PlaceAssets", 180)
	local asset = folder and folder:WaitForChild("HeartIcon", 180)
	icon = asset and asset.Value or ""
	for _, kept in pairs(boards) do
		kept.row:setIcon(icon)
	end
end)

-- ---- the townsfolk's names ------------------------------------------------------------------
-- Every NPC wears a NameTag billboard in its map model -- a name, and under most of them a role in angle brackets -- and they are
-- in the place's own face like the rest of the town's words. The face is a published asset that
-- arrives after the map does, so Theme.face is what puts it on (and puts it on again when it lands).
local function faceNameTag(inst)
	if inst:IsA("TextLabel") then
		local tag = inst:FindFirstAncestorOfClass("BillboardGui")
		if tag and tag.Name == "NameTag" then Theme.face(inst) end
	end
end
task.spawn(function()
	local map = workspace:WaitForChild("Map", 60)
	if not map then return end
	for _, d in ipairs(map:GetDescendants()) do faceNameTag(d) end
	map.DescendantAdded:Connect(faceNameTag)
end)

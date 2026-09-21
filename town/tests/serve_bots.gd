# The town, with somebody in it to hit.
#
#   godot --headless --path . -s res://tests/serve_bots.gd -- [--port=8800]
#   ... then tests/bot.gd a few times, and join normally yourself.
#
# The bots are real clients over the wire, so their swings go through WeaponRemote and the
# server judges them as it judges yours. This half arms them, which a client may not do for
# itself: Spoon takes an Accoutrement whose Name is in the weapon list and nothing else, so a
# handle and the right name is a whole weapon.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")
const Preview = preload("res://tests/Preview.gd")

## Where `node scripts/stage-preview.js all` writes; bots.ps1 runs it for you.
const STAGED := "res://../../../.preview"

const DEFAULT_PORT := 8800
var world: PulseBlockzWorld
var staged := 0
var main: Node
var armed := false
var t := 0.0

func _flag(name: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return int(a.get_slice("=", 1))
	return fallback

func _initialize() -> void:
	var port := _flag("port", DEFAULT_PORT)
	main = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = port
	world.default_camera = false
	world.default_controls = false
	world.auto_join = false
	# Anything built but not yet on chain, off disk -- the trampolines' bounce above all.
	StandIns.stage("bots")
	# The shop's unpublished models, a separate queue from the blobs: without them an item whose
	# model changed since it was published stands in the world at its old shape.
	staged = Preview.stage("bots", ProjectSettings.globalize_path(STAGED))
	get_root().add_child(main)
	# No script_print handler here: Main.gd already prints it, and a second doubles every line.
	print("[bots] the town is up on %d; start bots and join" % port)

func _process(delta: float) -> bool:
	t += delta
	if armed or t < 4.0:
		return false
	armed = true
	world.run_chunk("standins", StandIns.chunk("bots"))
	# Only once the world is running: install works through chunks and add_model, so it waits
	# out the same gate instead of going in _initialize.
	if staged > 0:
		Preview.install(world, "bots", ProjectSettings.globalize_path(STAGED))
	world.run_chunk("bots", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Name says weapon: a client that calls itself "HEX Torch" gets one. Nothing here trusts
-- the name for anything that matters -- it decides which stick to hand over, and the
-- server judges every swing the same way whatever is holding it.
--
-- The place's own list, not a copy of it. A copy here drifted the way Weapons.luau says lists
-- do: the cane became a weapon and nobody told this file.
local WEAPONS = require(game:GetService("ReplicatedStorage"):WaitForChild("Weapons"))

local function root(p)
	local ch = p.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function arm(p, name)
	local ch = p.Character
	if not ch then return false end
	-- Nothing else in the hand. The wardrobe dresses a bot in the account's outfit, and that
	-- outfit holds the Gold-Topped Cane -- a weapon now -- so a HEX Torch bot was holding the
	-- cane and the torch at once, and the server swings whichever weapon it finds first. It
	-- found the cane, charged it, and a bot never lets the button up: 59 clicks, 11 swings.
	-- Every pass, since a respawn dresses the new body again.
	for _, d in ipairs(ch:GetChildren()) do
		if d:IsA("Accoutrement") and d.Name ~= name and WEAPONS[d.Name] then d:Destroy() end
	end
	if ch:FindFirstChild(name) then return false end
	local acc = Instance.new("Accessory")
	acc.Name = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 2.2, 0.4)
	handle.Parent = acc
	acc.Parent = ch
	return true
end

-- When each dummy was last hurt, so a fight is never interrupted by the row tidying itself.
local touched = {}
local Health = require(game:GetService("ServerScriptService").Health)
local realHit = Health.hit
Health.hit = function(who, attacker, half, shove)
	local landed = realHit(who, attacker, half, shove)
	if landed then touched[who] = os.clock() end
	-- Every blow the server judges, named. This is the line that answers whether a player's
	-- swings are landing at all, and it goes in the server's log where it can be read.
	print(("HIT %s -> %s for %s, landed=%s"):format(
		attacker and attacker.Name or "(nobody)", who and who.Name or "?",
		tostring(half), tostring(landed)))
	return landed
end

-- Every swing REQUEST, one level above the blow.
--
-- The log says thirty blows landed and not one of them was Ada's, which does not say where
-- his stopped: the click may never have reached the server, or the server may have refused it
-- for want of a weapon, or the swing may have happened and caught nobody. A second listener on
-- the same remote sees the request itself, so the three are told apart.
--
-- Listening rather than intercepting: Weapons.server.luau keeps its own connection and decides
-- as it always did.
task.spawn(function()
	local remote = game:GetService("ReplicatedStorage"):WaitForChild("WeaponRemote", 30)
	if not remote then print("SWING no WeaponRemote to listen on") return end
	remote.OnServerEvent:Connect(function(player)
		local ch = player.Character
		local worn = {}
		if ch then
			for _, d in ipairs(ch:GetChildren()) do
				if d:IsA("Accoutrement") then table.insert(worn, d.Name) end
			end
		end
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		print(("SWING %s asked; wearing [%s]; fights=%s; at %s"):format(
			player.Name, table.concat(worn, ", "),
			tostring(Health.fights(player)),
			root and tostring(root.Position) or "no body"))
	end)
end)

local home = nil
local slot = {}                 -- player -> which place in the row is theirs, kept for life
local slots = 0
local waited = 0

--- How far apart the dummies stand.
---
--- Wide, and it matters. They used to be 2.4 studs apart, which is inside every weapon in the
--- game -- so the row spent the time before anybody arrived cutting each other down, and the
--- last one standing was the only one still holding anything. "just one bot is ever striking
--- ... this may be them being hit and falling before i log in": that is exactly what it was.
--- Five clears the longest reach in the game, so they swing at air until you walk in.
local APART = 5

task.spawn(function()
	while true do
		-- The row lays itself out near whoever is testing, so the dummies are somewhere you
		-- will actually walk past. If nobody has turned up after a while, put them down
		-- anyway rather than waiting forever -- a rig that only works when watched is a rig
		-- that cannot be checked.
		waited = waited + 1
		for _, p in ipairs(Players:GetPlayers()) do
			local r = root(p)
			-- The first body that is not a bot is where the row gets laid out, so the
			-- dummies stand where whoever is testing can actually find them.
			if r and not home and not WEAPONS[p.Name] and p.Name ~= "Runner" then
				home = r.Position
			elseif r and not home and waited > 8 then
				home = r.Position
			end
			if r and home and WEAPONS[p.Name] then
				-- Every pass, not once. A dummy that dies gets a NEW character, and the
				-- weapon went with the old one -- so a bot that had been killed stood there
				-- for the rest of the session holding nothing, which looked like the swing
				-- being broken rather than like the stick being gone.
				if not slot[p] then
					slots = slots + 1
					slot[p] = slots
				end
				if arm(p, p.Name) then print(("armed %s"):format(p.Name)) end
				-- Put back in its own place EVERY pass, not once when it was armed.
				--
				-- A dummy is a body its own client simulates: one CFrame from here is a
				-- suggestion, and its next report puts it back where it thought it was. So
				-- they never left the spawn -- ten of them in one pile, every one inside
				-- every other one's reach, cutting each other down before anybody arrived and
				-- their rows of hearts buried inside each other. Measured: two bots reporting
				-- the same X and Z, stacked five studs apart in Y.
				--
				-- Written until it sticks rather than once, and only while it is out of
				-- place, so a dummy somebody has knocked across the square walks back to its
				-- spot instead of being pinned there mid-fight.
				-- Put back only when it is FAR out, and never while it is being fought.
				--
				-- At a stud and a half this dragged a dummy home the instant anybody knocked
				-- it back -- "they get hit and reset to their positions" -- which is worse
				-- than the pile it was meant to fix. Twenty-five studs is a body that has
				-- fallen off the map or respawned at the spawn point, not one that has just
				-- been hit.
				-- It WALKS back now, and only teleports when walking cannot help.
				--
				-- A CFrame written here is a body vanishing and reappearing somewhere else,
				-- because that is exactly what it is -- "they disappear sometimes and seems
				-- like theyre coming back somewhere else". It was tolerable while the only
				-- way to cross twenty-five studs was to fall off the map. Then a dying man
				-- started going twenty studs from one BFS 9000 blow, so an ordinary fight puts
				-- bots over the line all the time, and six seconds after the last hit the
				-- whole row would blink home.
				--
				-- So: too far, walk. Under the map or hopelessly lost, snap, because a body
				-- at the bottom of the void has nowhere to walk from and that is the case
				-- this was written for in the first place.
				local spot = home + Vector3.new(-9 + slot[p] * APART, 0, 11)
				local hurtAgo = os.clock() - (touched[p] or 0)
				local away = (r.Position - spot).Magnitude
				local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
				if (away > 100 or r.Position.Y < home.Y - 20) and hurtAgo > 6 then
					r.CFrame = CFrame.new(spot)
					r.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				elseif away > 25 and hurtAgo > 6 and hum then
					hum:MoveTo(spot)
				end
			elseif r and home and p.Name == "Runner" and not slot[p] then
				slot[p] = 0
				print("Runner is walking a circle")
			end
		end
		task.wait(1)
	end
end)

-- Moved rather than walked. A Humanoid pathing round a fountain is a second thing that can
-- be wrong when the question is whether a cut lands on a body that is not standing still.
local turned = 0
RunService.Heartbeat:Connect(function(dt)
	if not home then return end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name == "Runner" then
			local r = root(p)
			if r then
				turned = turned + dt * 0.7
				r.CFrame = CFrame.new(home + Vector3.new(math.cos(turned) * 9, 0, math.sin(turned) * 9 + 7))
			end
		end
	end
end)
""")
	return false

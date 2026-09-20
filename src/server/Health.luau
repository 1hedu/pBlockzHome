-- Hearts, hits, knockback, and who is on a streak.
--
-- Three hearts, and half a heart is the smallest thing that can be taken off you, so health
-- is counted in half-hearts and MaxHealth is six. That is not a presentation trick: a
-- Humanoid whose Health reaches zero fires Died, and Arrival.server.luau loads the player
-- again RespawnTime later, so counting in the Humanoid's own
-- number means death, respawn and the core health bar all come for free. Hearts are just
-- Health/2, drawn by Hearts.client.luau.
--
-- Knockback is scripted rather than thrown. Setting AssemblyLinearVelocity from a script
-- only reaches a RigidBody3D, and a character is a CharacterBody3D -- the write is accepted
-- and then does nothing (pulseblockz_world.cpp, the AssemblyLinearVelocity branch). Writing
-- Position does move a character, so a shove here is a short arc stepped frame by frame.
-- Which is the point of the whole feature: you are meant to be able to put someone over the
-- edge, and the edge is what the void check below is for.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Flames = require(ReplicatedStorage:WaitForChild("Flames"))
local HeartRow = require(ReplicatedStorage:WaitForChild("HeartRow"))

local Health = {}

local PER_HEART = 2           -- half-hearts, so a heart is two and a graze is one

--- What a weapon's shove number is worth as a velocity, and how much of it goes upward.
---
--- A fight's knockback is not a trampoline and is not meant to feel like one. It is a
--- stagger: you are put off your feet and off your line, a couple of studs, and then you
--- have them back.
---
--- These exist because the weapons' numbers -- 26 for the Spoonie, 54 for BFS 9000 --
--- were tuned against the old hand-stepped arc, which ran for less than half a second at a
--- gravity of 60 and had the character controller fighting it the whole way. Handed straight
--- to the real thing at 196.2 they threw people across the square. Rather than retune every
--- weapon, the conversion is one place with two numbers in it.
---
--- The lift is what makes the rest of it read at all: the walk pushes hard once your feet
--- are down, so a shove with no lift in it is rubbed out before you have moved.
local KNOCK = 0.58
local LIFT = 0.26

--- What being nearly out of hearts multiplies the shove by.
---
--- One at full containers and this at none of them, straight in between. A blow on someone
--- who has just arrived is a stagger; the same blow on someone down to their last half
--- takes them off their feet and a good way across the square, which is what makes the end
--- of a fight the loud part of it -- and the reason to keep hitting rather than to back off.
---
--- Read after the damage has come off, not before: Health.shove is called at the end of
--- hit(), so the blow that puts you on your last half is already the bigger one.
---
--- Off the fraction remaining rather than off the half-hearts, so a streak, which raises
--- MaxHealth to eight, does not quietly make everybody harder to move as well as harder to
--- kill.
---
--- It is a velocity, so the distance goes up by more than the multiplier: the throw carries
--- further AND hangs in the air longer, and those multiply. Travel roughly doubles for each
--- half again of shove.
---
--- Two, chosen deliberately and with the cost in view.
---
--- One and a half was here first, and it is arithmetically fine -- measured over the wire on
--- the victim's own machine, 17.40 studs a second at full containers and 24.65 on the last
--- half, which is exactly what the sum asks for. It read as nothing all the same, because
--- the weapon it was being judged with was the crude spoon: shove 26 puts the whole range
--- between 1.5 studs and 3.4, a third of a body's width to two thirds. There is nothing
--- there to see. "knockbacks dont scale with hp, definitely not noticeably."
---
--- Measured after the change, at a shove of 30: 1.65 studs at full containers and 7.76 on
--- the last half, where one and a half gave 1.65 and 5.00.
---
--- What two costs is the top end, and it is the same cost as last time: BFS 9000 throws a
--- dying man 19.96 studs, a seventh of the town, which is the trampoline this was once
--- told not to be -- "fight knockback is far too great it should be nothing liek the
--- trampoline". That was put to Ada with the number on it and he took it. Recorded here so
--- the next person to read this does not quietly tune it back down as an obvious mistake: it
--- is a choice, and the thing it buys is a crude spoon whose last half can be felt.
---
--- Full containers are untouched either way -- at full health this multiplier is one -- so
--- the complaint that set the size of an ordinary shove is not being reopened. It is only
--- the dying end that moves.
local HURT_KNOCK = 2.0

--- How much vertical speed counts as being off the ground, studs per second.
---
--- A jump leaves at about fifty and the fall comes back faster, so anything in this
--- neighbourhood is either standing still or the last frame of a landing. It is a backstop
--- for GetState() rather than the main test: the state is what the engine says, and a body
--- whose own client simulates it may not have told this machine it is in the air yet.
local AIRBORNE = 2.0

--- The vertical speed by which none of a shove's lift lands any more, studs per second.
---
--- Not a line between standing and falling -- there is no such line here, and pretending there
--- was is what made a shove sometimes do nothing. It is the width of the blend: at nought you
--- take the whole lift, at this you take none, straight in between. A jump leaves at fifty and
--- a fall is past twenty within a fifth of a second, so anything genuinely in the air is well
--- clear of it and anything standing is well inside.
local MOVING = 12.0
local HEARTS = 3
local FIRE_HEARTS = 4         -- what a streak is worth: one more container
local STREAK = 3              -- kills without dying to catch fire
local FALLING_Y = -6          -- under the map: you are going down and there is no bottom
local VOID_Y = -25            -- below this you are not coming back on your own
local RESPAWN = 1.6           -- seconds face down before a new body
local CREDIT = 8              -- seconds a hit still counts as the killer's
local IFRAMES = 0.35          -- how long you cannot be hurt again after being hurt

-- The Heart Cape's four colours and the plain red, from the module that draws them.
--
-- They used to be written here and sent down with every message. They still travel with the
-- message, for your own meter -- but the row over everyone else's head is drawn on each
-- client now, off a replicated flag, and a client cannot be sent a colour table for a
-- player the server has not just pushed. So the table lives with HeartRow, which is what
-- both rows are made of.
local FIRE_COLOURS = HeartRow.FIRE
local PLAIN = HeartRow.PLAIN

local function humanoidOf(player)
	local ch = player.Character
	return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end

local function rootOf(player)
	local ch = player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart") or nil
end

local remote = Instance.new("RemoteEvent")
remote.Name = "HeartsRemote"
remote.Parent = ReplicatedStorage

-- Combat audio. The same blow is a different sound at each end -- you hear that you landed
-- one, they hear that they took one -- so the server, which is the only thing that knows
-- both, says who hears what rather than letting each client guess from its own side.
local sfx = Instance.new("RemoteEvent")
sfx.Name = "CombatSfx"
sfx.Parent = ReplicatedStorage

local LOW = 2                 -- half-hearts left before the warning starts

-- The whole town hears about a streak. Kills without dying, in any fight -- the open square or a
-- ranked duel -- announced to everybody in the chat, because a player on a run is the most
-- interesting thing happening in the square and everybody else would like to know who to avoid.
local news = Instance.new("RemoteEvent")
news.Name = "CombatNews"
news.Parent = ReplicatedStorage

--- What the town says about `n` kills without dying, or nil when it says nothing: on fire at
--- three, the same moment the fourth heart arrives, and then every five.
function Health.streakLine(name, n)
	if n == STREAK then return ("%s is on fire!"):format(name) end
	if n >= 5 and n % 5 == 0 then return ("%s is on a %d kill streak!"):format(name, n) end
	return nil
end

--- Plays a clip for one player.
function Health.sound(player, clip)
	if player and player.Parent then sfx:FireClient(player, clip) end
end

--- Plays a clip for everyone near a spot. A swing across the square should not be audible
--- from the other side of town, and a spoon is not a rifle.
function Health.soundNear(at, clip, radius, speed)
	for _, other in ipairs(Players:GetPlayers()) do
		local root = rootOf(other)
		if root and (root.Position - at).Magnitude <= radius then
			sfx:FireClient(other, clip, speed)
		end
	end
end

local kills = {}      -- player -> kills since they last died
local onFire = {}     -- player -> on a streak
local lastHit = {}    -- player -> { by = player, at = clock }
local hurtAt = {}     -- player -> when they were last hurt, for the mercy window
local falling = {}    -- player -> already told they are going over
local peaceful = {}   -- player -> true when they have turned PvP off; absent means on
local sides = {}      -- player -> { duel = id, team = "A" | "B" } while they are in a ranked duel
local killWatchers = {}

-- Anything that wants to know when someone's hearts change. The row over a head is drawn by
-- another script entirely, and it has no business polling six players every frame to find out
-- whether one of them took a hit.
local watchers = {}

--- True unless they have turned it off at the bank. On for everyone by default: a town where
--- you have to opt in to being hit is a town where nobody is ever hit.
---
--- And true for anybody in a ranked duel, whatever their setting: accepting a challenge is saying
--- yes to that fight, and only that fight -- see Health.mayHurt.
function Health.fights(player)
	return sides[player] ~= nil or peaceful[player] ~= true
end

--- Puts a player on a side of a ranked duel, or takes them off one (`duel` nil).
function Health.setSide(player, duel, team)
	sides[player] = duel and { duel = duel, team = team } or nil
	if player.Parent and Health.push then Health.push(player) end
end

--- Which duel and team a player is on, or nil.
function Health.sideOf(player)
	local s = sides[player]
	return s and s.duel, s and s.team
end

--- Whether `attacker` may hurt `victim`.
---
--- A ranked duel is sealed. Somebody in one can be hurt only by the other team in the same duel,
--- and can hurt only them: nobody outside can interfere, whether they are duelling somebody else
--- or not, and a duellist cannot wander off and pick a fight with the square. Everybody else is
--- the open town, where both have to be up for it.
function Health.mayHurt(attacker, victim)
	local a, v = sides[attacker], sides[victim]
	if a or v then
		return a ~= nil and v ~= nil and a.duel == v.duel and a.team ~= v.team
	end
	return Health.fights(attacker) and Health.fights(victim)
end

--- Whether `healer` may mend `victim`. Mending yourself is always yours to do. In a duel, only
--- your own team can put hearts back into you -- a friend from outside topping you up is as much
--- interference as a stranger knocking you down -- and you mend nobody outside it.
function Health.mayHeal(healer, victim)
	if not healer or healer == victim then return true end
	local h, v = sides[healer], sides[victim]
	if h or v then
		return h ~= nil and v ~= nil and h.duel == v.duel and h.team == v.team
	end
	return true
end

--- Calls fn(victim, killer) for every death, killer nil when nobody gets the credit.
function Health.onKill(fn)
	table.insert(killWatchers, fn)
end

--- What one player's hearts look like right now, for anyone drawing them.
function Health.state(player)
	local hum = humanoidOf(player)
	if not hum then return nil end
	return {
		half = math.max(0, math.floor(hum.Health + 0.5)),
		maxHalf = hum.MaxHealth,
		onFire = onFire[player] == true,
		colours = onFire[player] and FIRE_COLOURS or { PLAIN },
		fights = Health.fights(player),
	}
end

function Health.onChange(fn)
	table.insert(watchers, fn)
end

-- Five seconds of staring at nothing is the default, and far too long for a fall you can
-- take by walking two steps the wrong way.
Players.RespawnTime = RESPAWN

--- Tells one client what to draw: how many half-hearts it has, out of how many, and in
--- which colours. The colours travel with the message so the streak look lives in one place.
local function push(player)
	local hum = humanoidOf(player)
	if not hum then return end
	remote:FireClient(player, math.max(0, math.floor(hum.Health + 0.5)), hum.MaxHealth,
		onFire[player] == true, onFire[player] and FIRE_COLOURS or { PLAIN },
		Health.fights(player))
	-- And the same two facts where EVERY client can read them, because the row over this
	-- player's head is drawn on all of the other machines rather than here.
	--
	-- Attributes rather than a broadcast: they replicate with the instance, they are there
	-- for a client that joins later without anybody having to remember to resend, and they
	-- are two booleans that change when somebody visits the bank or ends a streak -- not
	-- something to put on the wire sixty times a second. Health itself needs no help: it is
	-- a Humanoid property and already replicated.
	player:SetAttribute("Fights", Health.fights(player))
	player:SetAttribute("OnFire", onFire[player] == true)
	local state = Health.state(player)
	for _, fn in ipairs(watchers) do
		task.spawn(fn, player, state)
	end
end
Health.push = push

--- Turns fighting on or off for one player, which the bank teller is the only way to do.
---
--- It cuts both ways on purpose: someone who has opted out cannot be hit and cannot hit
--- anyone either. Half of it would be a cheat rather than a setting.
function Health.setFights(player, on)
	peaceful[player] = (not on) or nil
	push(player)
end

--- Sets a body up with the right number of containers. Called on every spawn, because a new
--- body arrives with the Humanoid's own defaults and knows nothing about a streak.
function Health.dress(player)
	local hum = humanoidOf(player)
	if not hum then return end
	local hearts = onFire[player] and FIRE_HEARTS or HEARTS
	hum.MaxHealth = hearts * PER_HEART
	hum.Health = hum.MaxHealth
	-- The engine draws its own bar over the head; the hearts are the health meter here.
	hum.HealthDisplayDistance = 0
	-- And its own name tag, in the engine's default face. Off, because the client draws the
	-- name itself now -- in Reactor7, above the hearts, in one board so the two cannot drift
	-- apart. Which is how a Roblox place does a name tag it wants to style: turn the built-in
	-- one off and hang your own BillboardGui.
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	push(player)
end

--- Are their feet off the ground?
---
--- Two ways of asking, because neither alone is enough. GetState is what the engine says, and
--- it is the one that is right at the very top of a jump -- where the vertical speed passes
--- through nought and the numbers say "standing". The speed is the one that is right for a
--- body whose own client simulates it, which may not have told this machine it is in the air
--- yet; a jump leaves at about fifty, so AIRBORNE at two is nowhere near a standing body.
---
--- Two things read this: what a shove does to somebody already airborne, and what a blow
--- SOUNDS like when the one swinging it is.
function Health.aloft(player)
	local hum = humanoidOf(player)
	local root = rootOf(player)
	if not hum or not root then return false end
	-- The state, and only the state.
	--
	-- The vertical speed used to be asked first and anything over two studs a second called
	-- airborne. That was a backstop from when a watcher could not be told what a body was
	-- doing; it can now -- the machine simulating a body publishes StateName and it
	-- replicates. And as a backstop it was wrong far more often than it was right: a body
	-- being jostled in a brawl crosses two studs a second constantly, and an airborne target
	-- gets no lift, so the flat shove is rubbed out by the walk within a few frames. That is
	-- knockback that "sometimes doesnt happen", and it hides the scaling with it, because a
	-- shove you cannot see cannot be seen to be bigger.
	local ok, state = pcall(function() return hum:GetState() end)
	return ok and (state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping)
end

--- A push and nothing else. Away from whoever swung, and -- if their feet are down -- upward:
--- a shove along the ground alone just scuffs someone sideways, and the point is to be able
--- to put them over an edge. Somebody already in the air keeps whatever vertical they had
--- and gets nothing added; see AIRBORNE below.
---
--- Its own function because a blow that does no damage still has to move people. A torch is
--- the case. Its damage is a burn that arrives over the next five seconds, but the
--- swing itself still has to move whoever it caught -- and running that through hit() with a
--- damage of nought would spend their mercy window and sound as if they had been struck twice.
--- `evenIfDown` shoves a body that has just been emptied. hit() passes it, because the blow
--- that kills somebody is exactly the one that should throw them -- and it takes the damage
--- off BEFORE it shoves, so the guard below refused every killing blow. "knockback ...
--- sometimes not happen."
function Health.shove(victim, attacker, force, evenIfDown)
	local root = rootOf(victim)
	local hum = humanoidOf(victim)
	if not root or not hum or not force or force <= 0 then return end
	if hum.Health <= 0 and not evenIfDown then return end
	local from = attacker and rootOf(attacker)
	local away = from and (root.Position - from.Position) or root.CFrame.LookVector * -1
	away = Vector3.new(away.X, 0, away.Z)
	away = away.Magnitude > 1e-3 and away.Unit or Vector3.new(0, 0, -1)
	-- Harder the fewer hearts are left. Both halves of it, so the lift grows with the push
	-- and a big shove still gets the air under it that makes the rest of it read.
	local left = hum.MaxHealth > 0 and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 1
	local hurt = 1 + (1 - left) * (HURT_KNOCK - 1)

	-- Nothing is added upward to somebody already off the ground, and what they had is kept.
	--
	-- Which makes the vertical a thing you can play, the way the angle you run onto a
	-- trampoline is. Caught on the way down and you keep going down: the push is flat, the
	-- ground arrives in a fraction of a second, and you are set down a couple of studs away
	-- instead of thrown. Caught on the way up and you keep going up, stay in the air the
	-- whole arc, and go further than you would have standing there -- so jumping into a swing
	-- is the wrong half of the jump and jumping out of one is the right half.
	--
	-- The lift is only there to get a grounded body off the floor at all; the walk rubs out a
	-- shove along the ground before it has moved anyone. Someone airborne has no floor to be
	-- lifted off, so adding it there was only ever making them float.
	-- How much of the lift lands is decided by the vertical they ALREADY have, and nothing
	-- else. All of it standing still; none of it once they are properly moving.
	--
	-- This used to ask Health.aloft -- a yes or no off the state and the vertical speed -- and
	-- give the whole lift or none. Two things wrong with that. It has a cliff: two studs a
	-- second under the line gets thrown, a hair over gets nothing, for no reason anybody can
	-- see. And a classifier can be WRONG, which is a shove that visibly does not happen -- a
	-- body being jostled in a brawl crosses any such line constantly, and without the lift the
	-- flat push is rubbed out by the walk within a few frames.
	--
	-- Fading it does the same job with no line to be on the wrong side of, and it is closer to
	-- what was asked for: caught on the way down you keep going down and are set into the
	-- ground a couple of studs away; caught on the way up you keep going up and sail further;
	-- caught standing you are thrown. The middle blends instead of snapping.
	local vel = root.AssemblyLinearVelocity
	local fade = math.clamp(1 - math.abs(vel.Y) / MOVING, 0, 1)
	root.AssemblyLinearVelocity = away * (force * KNOCK * hurt)
		+ Vector3.new(0, vel.Y + force * LIFT * hurt * fade, 0)
end

--- Whether somebody is behind a ForceField -- the moments after arriving, SpawnLocation.Duration.
local function shielded(player)
	local ch = player.Character
	return ch ~= nil and ch:FindFirstChildOfClass("ForceField") ~= nil
end

--- Half-hearts off, from `attacker` if there was one, plus a shove away from them.
---
--- `half` is in half-hearts: 1 is a graze, 2 is a whole container.
---
--- A ForceField turns the whole blow away, the shove with the damage: somebody who has just
--- arrived cannot be hurt and cannot be knocked off the edge either, which would be the same
--- spawn camp by other means. The damage itself goes through Humanoid:TakeDamage, the way a
--- Roblox weapon respects a shield; the void and the fall write Health directly, and a
--- shield does not save anybody from those, on Roblox or here.
function Health.hit(victim, attacker, half, shove)
	local hum = humanoidOf(victim)
	local root = rootOf(victim)
	if not hum or hum.Health <= 0 or not root then return false end
	if shielded(victim) then return false end
	-- Only between two people who are both up for it. Nothing without an attacker is a fight
	-- -- the void, and the preview's hurt keys -- so those go through either way.
	if attacker and not Health.mayHurt(attacker, victim) then return false end
	-- A moment's mercy after a blow. Swings can be spammed as fast as the mouse allows, and
	-- without this the damage multiplies with the click rate: three hearts is under a second
	-- of clicking, and a fight is decided by whoever gets the first hit in.
	local now = os.clock()
	if hurtAt[victim] and now - hurtAt[victim] < IFRAMES then return false end
	hurtAt[victim] = now
	if attacker then lastHit[victim] = { by = attacker, at = now } end
	hum:TakeDamage(half)
	-- Who hears what: the one who swung hears a hit land, the one who took it hears
	-- themselves get hurt. Death has its own pair and is left to died().
	if hum.Health > 0 then
		-- A blow struck in mid-air is a different sound at both ends. Normally the two ends
		-- hear different clips -- you hear one land, they hear themselves hurt -- but a jump
		-- attack landing is one loud thing that happened, and both of them were there for
		-- it. So the pair is replaced rather than one of them dressed up.
		local jumped = attacker ~= nil and Health.aloft(attacker)
		Health.sound(victim, jumped and "stronghit" or "hurt")
		if attacker then Health.sound(attacker, jumped and "stronghit" or "enemyhit") end
		if hum.Health <= LOW then Health.sound(victim, "lowhp") end
	end
	Health.shove(victim, attacker, shove, true)
	push(victim)
	return true
end

--- Half-hearts back on, up to whatever the body's containers hold.
---
--- No duelling gate. Mending someone who has stepped out of it is not something they need
--- protecting from, and refusing would make the peaceful setting worse for the people who
--- chose it rather than better. It does not raise MaxHealth either: a streak's fourth
--- container is earned, and a candle is not how you earn it.
function Health.heal(victim, healer, half)
	local hum = humanoidOf(victim)
	if not hum or hum.Health <= 0 or hum.Health >= hum.MaxHealth then return false end
	if not Health.mayHeal(healer, victim) then return false end
	hum.Health = math.min(hum.MaxHealth, hum.Health + half)
	Health.sound(victim, "item")
	if healer and healer ~= victim then Health.sound(healer, "item") end
	push(victim)
	return true
end

local burning = {}    -- player -> { left, every, nextAt, by, flame }

-- The sprite a tongue of flame is drawn with, which arrives with the place assets. Looked up
-- once and then remembered, because a burn happens mid-fight and mid-fight is no time to go
-- waiting on a folder.
local sprite = nil
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("PlaceAssets", 180)
	local v = folder and folder:WaitForChild("FlameSprite", 180)
	sprite = v and v.Value ~= "" and v.Value or nil
end)

-- Where a burning body's fire hangs. The torso, because it is the one part every rig has in
-- the middle of it, and because fire on a leg reads as a bug.
local BURN_MARK = "OnFire"

--- Puts the fire on someone, or takes it off. Visible to everyone, unlike the sounds: being
--- able to see who is alight is most of what makes a torch worth carrying.
local function ignite(player, flame)
	local ch = player.Character
	local torso = ch and (ch:FindFirstChild("Torso") or ch:FindFirstChild("UpperTorso"))
	if not torso or torso:FindFirstChild(BURN_MARK) then return end
	local at = Instance.new("Part")
	at.Name = BURN_MARK
	at.Size = Vector3.new(1.6, 1.6, 0.8)
	at.Transparency = 1
	at.CanCollide = false
	at.Massless = true
	at.CFrame = torso.CFrame
	at.Parent = ch
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = at
	weld.Parent = at
	local e = Instance.new("ParticleEmitter")
	e.Name = "Flame"
	e.Parent = at
	e.Rate = 90
	e.Lifetime = NumberRange.new(0.3, 0.5)
	e.Speed = NumberRange.new(2, 3.4)
	e.Acceleration = Vector3.new(0, 6, 0)
	e.SpreadAngle = Vector2.new(26, 26)
	e.EmissionDirection = Enum.NormalId.Top
	e.LightEmission = 0.35
	e.LockedToPart = false
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.3, 0.7),
		NumberSequenceKeypoint.new(1, 0.08),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.55, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Squash = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 2.1),
		NumberSequenceKeypoint.new(1, 2.7),
	})
	Flames.light(e, flame, sprite)
end

local function douse(player)
	local ch = player.Character
	local at = ch and ch:FindFirstChild(BURN_MARK)
	if at then at:Destroy() end
end

--- Sets someone alight: `half` half-hearts spread over `secs` seconds, from `attacker`.
---
--- A burn is not a blow. It ignores the mercy window a swing respects, because it is not
--- being re-applied every tick -- it was applied once and is still going -- and it does not
--- shove, because there is nothing pushing. What it does instead is keep the credit fresh:
--- each tick renews who did it, so someone who walks off an edge with a torch's fire on them
--- is still that torch's kill.
---
--- The first tick lands on contact. Without it a torch reads as having missed: the swing
--- passes through, nothing happens, and the damage turns up a second and a half later with
--- nothing to connect it to.
---
--- But only the first. Setting someone who is already alight on fire again tops the burn back
--- up and leaves its clock alone -- it does not start a second one and it does not tick on
--- the spot. That immediate tick is the whole mercy window in reverse: a torch that dealt
--- half a heart on contact every time it touched you would empty three hearts in six clicks,
--- which is faster than BFS 9000 and with no way to trade blows against it.
function Health.burn(victim, attacker, half, secs, flame)
	local hum = humanoidOf(victim)
	if not hum or hum.Health <= 0 then return false end
	if shielded(victim) then return false end
	if attacker and not Health.mayHurt(attacker, victim) then return false end
	local ticks = math.max(1, math.floor(half + 0.5))
	-- Spread so the LAST tick lands on `secs`, not the one after it: the first is on contact,
	-- so three half-hearts over fifteen seconds is nought, seven and a half, fifteen. Dividing
	-- by the count instead put the last one two thirds of the way in and quietly made every
	-- burn a third shorter than it said it was.
	local every = ticks > 1 and (secs / (ticks - 1)) or secs
	local mark = burning[victim]
	if mark then
		mark.left = ticks
		mark.every = every
		mark.by = attacker or mark.by
		return true
	end
	burning[victim] = { left = ticks, every = every, nextAt = os.clock(), by = attacker,
		flame = flame }
	if flame then ignite(victim, flame) end
	return true
end

--- One tick of a burn: a half-heart, and the sounds that go with taking one.
local function scorch(victim, mark)
	local hum = humanoidOf(victim)
	if not hum or hum.Health <= 0 then
		burning[victim] = nil
		douse(victim)
		return
	end
	if mark.by then lastHit[victim] = { by = mark.by, at = os.clock() } end
	hum.Health = math.max(0, hum.Health - 1)
	if hum.Health > 0 then
		Health.sound(victim, "hurt")
		if mark.by then Health.sound(mark.by, "enemyhit") end
		if hum.Health <= LOW then Health.sound(victim, "lowhp") end
	end
	push(victim)
end

--- Who gets the credit for a death, if anyone: whoever landed a hit recently enough.
local function killerOf(player)
	local mark = lastHit[player]
	if not mark or not mark.by or mark.by == player then return nil end
	if os.clock() - mark.at > CREDIT then return nil end
	return mark.by.Parent and mark.by or nil
end

local function died(player)
	local killer = killerOf(player)
	-- A duel's kill has to be one the duel allowed. Credit only ever comes from a blow that
	-- landed, so this is belt and braces -- but a burn set before a duel began can still be
	-- ticking once it has started, and that is not a frag.
	if killer and not Health.mayHurt(killer, player) then killer = nil end
	for _, fn in ipairs(killWatchers) do task.spawn(fn, player, killer) end
	lastHit[player] = nil
	burning[player] = nil
	douse(player)
	-- You lose the streak and the container that came with it.
	kills[player] = 0
	onFire[player] = false
	Health.sound(player, "dies")
	if killer then
		Health.sound(killer, "enemydies")
		kills[killer] = (kills[killer] or 0) + 1
		local line = Health.streakLine(killer.Name, kills[killer])
		-- The count goes with the words: the chime climbs with the streak.
		if line then news:FireAllClients(line, kills[killer]) end
		if kills[killer] >= STREAK and not onFire[killer] then
			onFire[killer] = true
			local hum = humanoidOf(killer)
			if hum then
				-- The extra container arrives full; the ones already spent stay spent.
				hum.MaxHealth = FIRE_HEARTS * PER_HEART
				hum.Health = math.min(hum.MaxHealth, hum.Health + PER_HEART)
			end
		end
		push(killer)
	end
end

local function watch(player)
	kills[player] = 0
	onFire[player] = false
	local function born(character)
		lastHit[player] = nil
		falling[player] = nil
		burning[player] = nil
		local hum = character:WaitForChild("Humanoid", 10)
		if not hum then return end
		task.wait(0.1)               -- let the rig finish assembling
		Health.dress(player)
		hum.Died:Connect(function() died(player) end)
	end
	player.CharacterAdded:Connect(born)
	if player.Character then task.spawn(born, player.Character) end
end

Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(watch, player) end
Players.PlayerRemoving:Connect(function(player)
	kills[player] = nil
	onFire[player] = nil
	hurtAt[player] = nil
	falling[player] = nil
	lastHit[player] = nil
	burning[player] = nil
	peaceful[player] = nil
	sides[player] = nil
end)

RunService.Heartbeat:Connect(function(dt)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		local hum = humanoidOf(player)
		if root and hum and hum.Health > 0 then
			-- Still alight? A tick is due when the clock has caught up with it. Stepped this
			-- way rather than on a timer per victim so that a burn stops the moment the body
			-- does, rather than a second and a half later on a thread nobody can see.
			local mark = burning[player]
			if mark then
				if os.clock() >= mark.nextAt then
					scorch(player, mark)
					mark.left -= 1
					mark.nextAt = os.clock() + mark.every
					if mark.left <= 0 then
						burning[player] = nil
						douse(player)
					end
				end
			end
			-- Off the edge, in two parts. The cry goes up as you pass under the map, which is
			-- the moment you know it has happened; the dying is nineteen studs further down,
			-- so the death sound lands with the death rather than a second before the fall
			-- has even read as one.
			--
			-- The host does kill a character below FallenPartsDestroyHeight, but that is five
			-- hundred studs down and only in the world that is following it, which is why
			-- this floor exists at all.
			if root.Position.Y < FALLING_Y and not falling[player] then
				falling[player] = true
				Health.sound(player, "fall")
			end
			if root.Position.Y < VOID_Y then
				hum.Health = 0
			end
		end
	end
end)

return Health

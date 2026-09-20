-- The things you can swing, swung: every weapon the town has, one script.
--
-- Which weapon is in the hand decides what a click does; the list of them, and the cycle of
-- techniques each walks, is shared/Weapons.luau, which both ends read. The Spoonie is
-- held like a dagger, so it swings like one: click and it slashes, click again and it
-- thrusts, alternating. BFS 9000 is five studs of shaped steel and swings the hachimonji, the
-- character eight, one stroke a click: down to his left, then back down to his right,
-- alternating. The off hand comes across and joins the grip -- only for the swing; it is
-- carried in one hand.
--
-- They do hit now. Each technique has a window inside its own timing where the head is
-- travelling through the cut rather than winding up or coming home, and only during that
-- window is anything in front of it struck. The head's position is not guessed at: it is
-- read off the shoulder joint the same way the off hand's target is, so it follows whatever
-- the keyframes are doing today rather than a number written beside them once.
--
-- Each swing is keyframed rather than driven by a single sine, because a sine out and back
-- along one axis is the same shape whatever you call it -- the first pair were literally
-- indistinguishable in motion. A blow reads as a blow because of what comes before and
-- after it: the arm cocks away, the strike is over in a fifth of the time it took to wind
-- up, it overshoots slightly, and only then does it come home. The waist turns with it;
-- an arm swinging alone off a body that stands perfectly still reads as a broken puppet.
--
-- The arm is animated by its shoulder joint rather than by moving the part. An R6 rig
-- hangs each arm off a Motor6D on the torso, so the hand, and anything gripped in it,
-- follow the joint for free; setting the arm's own CFrame would leave the weapon behind.
--
-- The joint is posed through Transform, not C0. A limb sits at Part0 * C0 * Transform *
-- C1^-1, and C0 is the rest offset the joint was built with -- writing it is legal, reads
-- back changed, and moves nothing, because the pose the renderer draws comes from
-- Transform. An earlier version swung C0 and looked entirely convincing from the script's
-- side: the joint swept a full arc on every click while the weapon's world position sat at
-- the same three numbers from the first frame to the last.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Health = require(script.Parent.Health)
local Ranks = require(ReplicatedStorage:WaitForChild("Ranks"))

local remote = Instance.new("RemoteEvent")
remote.Name = "WeaponRemote"
remote.Parent = ReplicatedStorage

-- Seconds per swing, wind-up to recovery. The two-stroke cut needs the room; making them
-- share one duration would have meant slowing the jab to pay for it.
-- `firethrust` is the crude spoon's thrust played back slower, and nothing else: a torch is
-- heavier than a spoon and swung by someone being careful with it.
-- `candle` is the hachimonji's first stroke and nothing else, cut quicker than BFS 9000 cuts it
-- and then home.
-- `hachimonji` and `hachimonjiBack` are the eight's two strokes as two swings. They were one
-- technique of 1.05 seconds, both cuts in it; each is now a click of its own at twice the pace
-- it had inside that -- the same 1.05 seconds for one stroke that used to cover two.
--
-- Reach costs speed, which is the whole of the balance here. BFS 9000 used to have more reach
-- AND more damage per second than the crude spoon -- two half-hearts every 0.82s against one
-- every 0.5s, so 2.44 against 2.0 -- which made it strictly better and the spoon pointless.
-- Now the short one is the fast one: 2.17 half-hearts a second against BFS 9000's 1.90. What
-- the long weapon buys is standing further away. (Still 1.90 with the eight split in two: a
-- swing strikes somebody once, and it was one swing per 1.05 seconds then as it is now.)
-- `cast` is the cane's: up over his head, then lunged out level in front of him.
local SWING = { slash = 0.46, thrust = 0.46, hachimonji = 1.05, hachimonjiBack = 1.05, firethrust = 0.80,
                candle = 0.70, cast = 0.80 }

-- What each weapon can do, and the cycle a repeated click walks. In ReplicatedStorage
-- because the client needs the same list to know whether a click is worth sending.
local WEAPONS = require(ReplicatedStorage:WaitForChild("Weapons"))

local TORCH_FLAME = { ["PLS Torch"] = "pulse", ["PLSX Torch"] = "pulsex",
                      ["HEX Torch"] = "hex", ["PRVX Torch"] = "provex", ["INC Torch"] = "inc" }

-- What each weapon does when it lands, and how far down the shaft its head is. The reach is
-- measured in the arm's own frame, along the shaft from the fist -- the same axis the off
-- hand takes hold on, further out.
--
-- Half-hearts: the crude spoon grazes for one, BFS 9000 takes a whole container. The shove is
-- what actually settles a fight, since the ground runs out long before three hearts do.
--
-- ---- radius must be SMALLER than reach ---------------------------------------------------
-- The hit is a ball of `radius` centred `reach` studs out along the arm. Every one of these
-- used to have a radius BIGGER than its reach -- the crude spoon 2.2 against 1.7 -- so the
-- ball swallowed the swinger's own body and reached half a stud out behind him. Melee was
-- omnidirectional: there was no side to attack from, and being killed while flanking
-- somebody was not a mystery, it was geometry.
--
-- Now every weapon has a dead zone in front of it (reach minus radius) and a wall behind
-- (reach plus radius), and the long ones have the bigger dead zone: get inside a BFS 9000 and
-- it cannot touch you, which is the other half of what reach costs.
--
-- ---- and an arc --------------------------------------------------------------------------
-- `arc` is the half-angle, in degrees, off where the swinger is facing. The fast short
-- weapon sweeps widest and the long slow one narrowest, so flanking a BFS 9000 works best of
-- all -- which is what you would expect of a two-handed thing.
-- ---- and the radius is now a ball against BODIES ----------------------------------------
-- So it is smaller than it reads. The sweep asks GetPartBoundsInRadius, which answers with
-- everything the ball TOUCHES, and a character is about two studs across -- so every number
-- here reaches roughly a stud further than it says, and the dead zone in front is a stud
-- shallower. They came down when the sweep changed to keep the shape of each weapon.
--
-- A fifth of a stud wider all round (2026-09-16), judged by eye with /hitbox on: the
-- capsules read a touch narrow against a body. Every radius is still under its reach.
local HITS = {
	["Spoonie"] = { reach = 2.6, radius = 1.4, arc = 100, half = 1, shove = 26 },
	["BFS 9000"] = { reach = 5.0, radius = 1.9, arc = 70, half = 2, shove = 54 },
}

-- A torch does not cut, it lights you. Three half-hearts -- a heart and a half -- spread
-- over five seconds, which is a slower death than BFS 9000 deals and a much harder one to
-- walk away from: it follows you, and the credit follows with it.
--
-- No shove at all, unlike the spoons. A torch that also threw people would be the best weapon
-- in the game by a distance -- it is the only one whose damage carries on after you have
-- stopped swinging -- and knocking someone away is the one thing that puts them out of reach
-- of a second application.
local BURN_HALF = 3

-- How long the burn takes, which is the one thing the five torches do not share.
--
-- Same heart and a half either way; what changes is how long you have to do something about
-- it. The busiest token of the day burns you in three seconds and the quietest takes fifteen.
--
-- Not evenly spaced, and deliberately not. Three to five seconds is the difference between a
-- weapon and a slightly slower weapon -- both of them kill you before you have crossed the
-- square. Fifteen is long enough to run to a green candle, and ten is long enough to think
-- about it, so the bottom of the ladder is a burn you can survive and the top is one you
-- cannot. The gaps widen towards the bottom because that is where the interesting decisions
-- are; between first and second place nobody is deciding anything.
--
-- The flames stay evenly spaced -- a height is a reading and has to be regular -- so the
-- ladder is the same ladder either way round; only what it buys you differs.
--
-- Read at the moment of the swing rather than fixed at load, because the server looks again
-- every few minutes and a torch should be worth what the token is worth now.
local BURN_SECS = { 3, 5, 10, 12, 15 }

local function burnSecs(flame)
	return BURN_SECS[math.clamp(Ranks.of(flame), 1, #BURN_SECS)] or BURN_SECS[#BURN_SECS]
end

for _, name in ipairs(WEAPONS.torches) do
	HITS[name] = { reach = 3.3, radius = 1.6, arc = 90, shove = 0,
		burn = { half = BURN_HALF, flame = TORCH_FLAME[name] } }
end

-- The candles: two whole hearts, one way or the other, and then the thing is spent. Two
-- hearts is the hardest blow anything here lands and the largest mending anything here does,
-- which is what one use buys you. `consume` is what makes it one -- Wardrobe.server.luau
-- takes it off and will not put it back on.
--
-- Reach is BFS 9000's, because it is the same length: a katana of a candle, held in both
-- hands, with the flame out past everything.
--
-- Two hearts from one blow is the hardest thing in the game, and the reason it is allowed to
-- be is DRAW below: you cannot open with a spoon and finish with a candle inside a second.
-- No shove on either of them. A candle is not a club: it is a thing you spend, and throwing
-- somebody as well would make the red one strictly better than every spoon in the game.
HITS["Red Candle"] = { reach = 5.0, radius = 1.9, arc = 70, half = 4, shove = 0, consume = true }
-- Mending has no gate either. Someone who has stepped out of duelling can still be put back
-- on their feet by a friend -- refusing that would make the peaceful setting worse for them
-- rather than better.
HITS["Green Candle"] = { reach = 5.0, radius = 1.9, arc = 70, heal = 4, shove = 0, consume = true }

-- ---- the Wizard Hat ------------------------------------------------------------------------
-- A wizard is no good with a blade and very good with a wand. Wearing the hat, everything you
-- swing hurts half as much -- the spoons, the torches' burns, the red candle -- and every shot
-- from the cane throws whoever it hits as hard as a full charge does, charged or not. Mending is
-- left alone: the green candle is not a weapon.
--
-- Read off the character at the moment of the blow, the same way a weapon is: an Accoutrement
-- named for it is the hat, so taking it off takes the magic off with it.
local WIZARD_HAT = "Wizard Hat"
local WIZARD_MELEE = 0.5

local function wizard(player)
	local ch = player and player.Character
	local hat = ch and ch:FindFirstChild(WIZARD_HAT)
	return hat ~= nil and hat:IsA("Accoutrement")
end

-- When in each technique the head is actually cutting. Read off the keyframes below: the
-- stroke rows, not the cock or the recovery.
local STRIKE = {
	slash = { { 0.34, 0.60 } },
	thrust = { { 0.32, 0.58 } },
	hachimonji = { { 0.36, 0.76 } },
	hachimonjiBack = { { 0.36, 0.76 } },
}
-- The windows are fractions of the swing rather than seconds, so the torch's slower thrust
-- gets the same shape stretched over its own longer duration for free.
STRIKE.firethrust = STRIKE.thrust
-- The hachimonji's first window, over the shorter swing: the same tenth of a second either
-- side of the same cut.
STRIKE.candle = { { 0.27, 0.57 } }
-- The cast has no cut. Its window is the lunge, and what happens at the start of it is that the
-- orb leaves the tip (castOrb below); nothing is swept, because the cane has no HITS entry.
STRIKE.cast = { { 0.44, 0.64 } }

-- Which clip each technique makes. The crude spoon's two strokes get the two fighter sword
-- sounds so that alternating them is audible; BFS 9000 gets the master sword, on both strokes.
local SWING_SFX = { slash = "sword1", thrust = "sword2", hachimonji = "master", hachimonjiBack = "master",
                    firethrust = "fire", candle = "sword1" }
local EARSHOT = 70            -- studs; the square is 140 across, so this is most of it

--- Which stroke of a technique is cutting right now, or nil between them.
---
--- The index matters, not just the fact: the hachimonji is two strokes and wants two sounds,
--- one for each diagonal, so they have to be told apart.
local function strikeIndex(kind, a)
	for i, w in ipairs(STRIKE[kind] or {}) do
		if a >= w[1] and a <= w[2] then return i end
	end
	return nil
end

local swinging = {}           -- player -> { joints, kind, t }
local held = {}               -- player -> the clock when the button went down, while it is down
local kept = {}               -- player -> seconds of charge let go of and not yet fired
local nextIndex = {}          -- player -> where in its weapon's cycle the next click is

-- How long a freshly drawn weapon is dead in the hand.
--
-- Without it a fight is decided by how fast you can press two number keys. BFS 9000 takes a
-- whole heart and the Red Candle takes two: land one, swap, land the other, and three hearts
-- are gone in about a second and a half with nothing the other player could have done about
-- it. Neither weapon is too strong on its own -- what was wrong is that swapping cost
-- nothing.
--
-- A second is about one swing's worth, so changing your mind mid-fight is a real decision
-- rather than a free one. It is timed from the moment the thing appears in your hand rather
-- than from the click, so the cost is paid whether or not you use it.
local DRAW = 1.0
local drawnAt = {}            -- player -> when what they are holding last changed
local holding = {}            -- player -> what that was
local lastWorn = {}           -- player -> the weapons on them last frame, by name

-- The two swings, as keyframes in degrees.
--
-- Columns are a time along the swing, then the shoulder and then the waist. Both joints'
-- axes were measured with tests/joint_probe.gd rather than assumed, because the R6 shoulder
-- carries a baked quarter-turn in its C0 and CFrame.Angles(x, y, z) on its Transform is
-- therefore nothing like pitch, yaw and roll in the body's own axes. The earlier pair were
-- written on the assumption that it was: what they actually produced was a slash that swung
-- the arm backwards behind him and a thrust that raised it sideways like a wing.
--
--   right arm  sx  lateral raise, out to his right when negative
--              sy  horizontal sweep, across the body when positive
--              sz  raises the arm forward and up
--   left arm    lx  inward, across the body -- the same sign as the right arm's
--               ly  twist
--               lz  raises the arm forward when NEGATIVE, the mirror of the right
--   waist       wx  leans forward
--               wy  rolls
--               wz  twists to his left
--
-- The two arms do not share a sign convention. Their shoulders' C0s are mirrored, so the
-- left arm's forward is -lz where the right arm's is +sz; writing one and negating it for
-- the other lands nowhere near. Measured, both, with tests/joint_probe.gd.
local SWINGS = {
	-- Down and across: cocks up over his right shoulder, cuts through to his left hip.
	--
	-- The horizontal placing is all sy, which sweeps about the vertical and so moves the
	-- head sideways without lifting it; sz and sx carry the height. That split is why the
	-- stroke stays level rather than scalloping up at the end.
	slash = {
		--  t      sx    sy    sz    lx  ly   lz     wx   wy    wz
		{ 0.00,     0,    0,    0,    0,  0,   0,     0,   0,    0 },
		{ 0.30,   -38,  -52,   42,    0,  0,   0,    -7,  -5,  -25 },   -- cock up and out
		{ 0.46,    10,   62,  -12,    0,  0,   0,    13,   6,   27 },   -- the cut
		{ 0.58,    14,   72,  -26,    0,  0,   0,    10,   4,   20 },   -- follow through past it
		{ 1.00,     0,    0,    0,    0,  0,   0,     0,   0,    0 },
	},

	-- Straight out: chambers back by his hip, then drives the head out in front of him.
	--
	-- The arm stays low, which is not a compromise but the only way this grip can thrust.
	-- The spoon is held across the fist, square to the forearm, so it points where it does
	-- only while the arm hangs: raise the arm towards horizontal and the head swings up with
	-- it and finishes pointing at the sky. The first version drove the shoulder to 86
	-- degrees and produced exactly that, a man presenting a spoon overhead. Nothing about
	-- the angles fixes it -- with a straight arm the head is always square to the arm, so it
	-- can point up, down or sideways at full reach, but never along it.
	--
	-- So the reach comes from the waist and the shoulder only swings from behind his hip to
	-- a little in front of it, which carries the head forward fast at gut height with the
	-- tip leading. An elbow would lift this restriction entirely -- upper arm forward,
	-- forearm hanging, tip out front at chest height -- and the runtime would take one:
	-- limb_group() in pulseblockz_world.cpp already folds RightLowerArm into the right arm's
	-- swing chain. It wants the visible arm split in two, which is a change to the avatar
	-- rather than to this spoon, so it is not done here.
	-- Hachimonji: the cut that traces the character eight, two diagonals diverging downward.
	--
	-- BFS 9000's, and the reason it needs both hands. He cocks up over his right shoulder
	-- with the off hand coming across to the shaft and cuts down across to his left; the next
	-- click cocks up again with the blade turned over and cuts down across to his right. Two
	-- clicks, two strokes, and the pair leave an eight hanging in the air. They were one
	-- motion, with a lift between the cuts; they are two swings now, each from rest and back,
	-- at half the pace. Then the left arm lets go and it is carried in
	-- one hand again, which is the only honest way to do it here: with the weapon bound to
	-- the right hand and no elbows, the left hand cannot reach the shaft where it hangs at
	-- his side. It can reach it once the cut has brought it up and across the chest.
	--
	-- Which angle drives a stroke decides whether it cuts or slaps, and there is no choice
	-- about it. The spoon is a flat paddle whose width runs across the bowl; the tip moves
	-- along w x r for a shoulder turning about w, and the arm itself is most of r. Turn about
	-- the vertical (sy) or about the shaft (sx) and that cross product comes out square to
	-- the blade every time -- a broadside slap, and no amount of rolling fixes it, because
	-- rolling turns the path and the blade together and leaves the angle between them exactly
	-- where it was. tests/edge_probe.gd measured precisely that: 53 degrees off edge-first,
	-- unchanged by a 50 degree roll.
	--
	-- Only sz, the turn about the lateral axis, gives the tip a velocity with a component
	-- ALONG the blade. So each stroke is driven by sz, and sx is held still through it --
	-- not to roll the blade but to tilt the plane the stroke sweeps in, one way for the cut
	-- down to his left and the mirror for the cut down to his right. That is what makes the
	-- eight: two sagittal cuts through planes canted either side of vertical. sx moves only
	-- on the way up to a cut, which is where a hand turns the blade over anyway.
	--
	-- The off hand's three columns are zero and ignored: it is aimed at the shaft instead,
	-- every frame, by offHand() below. Hand-written angles for it were wrong the moment the
	-- right arm's numbers changed, and they changed a great deal.
	-- The first stroke. Cock and cut at the times they had in the one technique, doubled.
	hachimonji = {
		--  t      sx    sy    sz    lx  ly   lz     wx   wy    wz
		{ 0.00,     0,    0,    0,    0,  0,   0,     0,   0,    0 },
		{ 0.32,    46,  -20,   80,    0,  0,   0,    -8,  -6,  -26 },   -- cocked high, plane set for the left diagonal
		{ 0.68,    46,    6,  -38,    0,  0,   0,    14,   6,   28 },   -- the stroke: sz drives it down through
		{ 1.00,     0,    0,    0,    0,  0,   0,     0,   0,    0 },   -- release, back to one hand
	},

	-- The second: up with the plane rolled to the mirror -- the pose the lift used to reach --
	-- and down through the other way.
	hachimonjiBack = {
		--  t      sx    sy    sz    lx  ly   lz     wx   wy    wz
		{ 0.00,     0,    0,    0,    0,  0,   0,     0,   0,    0 },
		{ 0.32,   -46,   12,   74,    0,  0,   0,     2,   4,   16 },   -- cocked high, plane rolled to the mirror
		{ 0.68,   -46,  -12,  -38,    0,  0,   0,    14,  -5,  -22 },   -- the stroke, down through to his right
		{ 1.00,     0,    0,    0,    0,  0,   0,     0,   0,    0 },   -- release, back to one hand
	},

	thrust = {
		--  t      sx    sy    sz    lx  ly   lz     wx   wy    wz
		{ 0.00,     0,    0,    0,    0,  0,   0,     0,   0,    0 },
		{ 0.28,   -10,  -20,  -46,    0,  0,   0,   -15,   0,  -17 },   -- chamber, weight back
		{ 0.42,     6,   14,   28,    0,  0,   0,    23,   0,   17 },   -- drive, tip leading
		{ 0.56,     4,   12,   33,    0,  0,   0,    20,   0,   15 },   -- reach
		{ 1.00,     0,    0,    0,    0,  0,   0,     0,   0,    0 },
	},
}

-- The torch's swing is the thrust's own keyframes. Shared rather than copied: retuning the
-- thrust retunes the torch, which is what "the same animation, slower" has to mean if it is
-- to stay true a month from now. The slowing is SWING.firethrust and nothing else.
SWINGS.firethrust = SWINGS.thrust

-- The candle's swing is the hachimonji's first stroke: cock high with the plane set for the
-- left diagonal, cut down through it, and then home rather than lifting into the second.
-- Taken from the same rows so that retuning the eight retunes this, with its own times.
SWINGS.candle = {
	SWINGS.hachimonji[1],
	{ 0.24, table.unpack(SWINGS.hachimonji[2], 2) },
	{ 0.51, table.unpack(SWINGS.hachimonji[3], 2) },
	SWINGS.hachimonji[4],
}

-- The cast: the arm goes up, then lunges forward and stops level, pointing where he faces.
--
-- The cane can do what the spoon cannot, because of how it is held. The spoon runs across the
-- fist, so raising the arm points it at the sky; the cane hangs straight down out of the fist,
-- along the arm, so the arm raised level points the cane level -- the tip leads. sz alone
-- carries it: 150 is up over his head, 90 is straight out in front of an upright body. The
-- waist leans back to raise it and forward into the lunge, which is what makes it a lunge and
-- not a point -- and the arm hangs off the torso, so the lean tips it down with it. The lunge's
-- sz is 90 plus the lean, which keeps the cane level in the world: at 88 with an 18 degree
-- lean the orb left from below his waist (measured, the tip 0.57 under the root).
SWINGS.cast = {
	--  t      sx    sy    sz    lx  ly   lz     wx   wy    wz
	{ 0.00,     0,    0,    0,    0,  0,   0,     0,   0,    0 },
	{ 0.30,    -8,   -6,  150,    0,  0,   0,    -9,   0,  -12 },   -- raised, weight back
	{ 0.44,     0,    4,  108,    0,  0,   0,    18,   0,   10 },   -- lunged: level, tip leading
	{ 0.64,     0,    4,  105,    0,  0,   0,    15,   0,    8 },   -- held while the orb goes
	{ 1.00,     0,    0,    0,    0,  0,   0,     0,   0,    0 },
}

local function ease(u)
	return u * u * (3 - 2 * u)
end

--- The nine angles, in radians, at a point along a swing.
local function poseAt(rows, a)
	local i = 1
	while i < #rows - 1 and a > rows[i + 1][1] do
		i += 1
	end
	local p, q = rows[i], rows[i + 1]
	local span = q[1] - p[1]
	local u = span > 0 and ease(math.clamp((a - p[1]) / span, 0, 1)) or 0
	local out = {}
	for k = 2, 10 do
		out[k - 1] = math.rad(p[k] + (q[k] - p[k]) * u)
	end
	return out
end

--- Which weapon is in the hand, and the cycle of techniques it swings.
--- Every weapon on the character, by name.
local function wornWeapons(player)
	local out = {}
	local ch = player.Character
	if not ch then return out end
	for _, d in ipairs(ch:GetChildren()) do
		if d:IsA("Accoutrement") and WEAPONS[d.Name] then out[d.Name] = true end
	end
	return out
end

--- The weapon in the hand: the one drawn last, when more than one is worn.
---
--- A character can wear two -- a saved outfit with the cane in it, and a spoon put on after --
--- and this used to take whichever the children happened to come in, so the cane was seen
--- swinging a spoon's technique. What is held is what was picked up most recently (tracked
--- by the loop below as things go on and off); with no history, the first by name, which is at
--- least the same answer every frame.
local function heldWeapon(player)
	local worn = wornWeapons(player)
	local name = holding[player]
	if name and worn[name] then return name, WEAPONS[name] end
	local names = {}
	for n in pairs(worn) do table.insert(names, n) end
	table.sort(names)
	if names[1] then return names[1], WEAPONS[names[1]] end
	return nil, nil
end

local function joints(player)
	local ch = player.Character
	local torso = ch and ch:FindFirstChild("Torso")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not torso then return nil end
	return {
		right = torso:FindFirstChild("Right Shoulder"),
		left = torso:FindFirstChild("Left Shoulder"),
		waist = root and root:FindFirstChild("RootJoint") or nil,
	}
end

local REST = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }

--- Where the head of the weapon is, in the world, right now.
---
--- Worked out from the joints rather than from the weapon: a weapon is an Accoutrement
--- welded into the fist, and the fist is wherever the shoulder has put it. Reading the
--- shoulder is also what offHand() does to find the shaft, so the two cannot disagree about
--- where the thing is -- and neither goes stale when the keyframes are retuned.
---
--- MINUS reach, and the sign is the whole of it. In worn space the shaft runs along +Z
--- towards the BUTT -- OFF_GRIP above is +0.85 and is described as "behind the right fist,
--- between it and the butt" -- so a positive reach measures out of the wrong end of the
--- weapon. It put the hit five studs BEHIND the swinger, which with the old radius being
--- larger than the reach still overlapped his own body: hits landed, so nothing looked
--- broken, and what actually decided them was a ball round his back. That is being killed
--- from the side by somebody who cannot see you.
local function headAt(ch, j, reach)
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	-- Straight out in front of the BODY, not out of the right shoulder.
	--
	-- It used to be worked out from the Right Shoulder's animated pose, which put the hit a
	-- stud and a half to the right of the person swinging -- measured. So the same weapon
	-- reached further on your right than on your left, by different amounts for each weapon
	-- since they have different reaches: "it doesnt feel equal from all sides with all
	-- weapons".
	--
	-- The arm still decides WHEN, through the strike windows, which is what makes a stroke
	-- land when it looks like it should. It no longer decides WHERE, because where the
	-- shoulder happens to be mid-animation is not something anybody is aiming.
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
	return root.Position + look * reach
end

--- Spends a one-use weapon: off the character, and out of the wardrobe's list of what to
--- put back on.
---
--- Said rather than done here. What a player is wearing is Wardrobe.server.luau's to decide
--- -- it is the thing that dresses a new body -- so destroying the accessory from this side
--- would put it straight back on at the next respawn.
local spent = ReplicatedStorage:FindFirstChild("ItemConsumed")
local function consume(player, name)
	spent = spent or ReplicatedStorage:FindFirstChild("ItemConsumed")
	if spent then spent:Fire(player, name) end
end

-- ---- seeing the hit ------------------------------------------------------------------------
-- `/hitbox` draws what sweep() measures, for everybody, until it is typed again: on every
-- body, a ball the size its root counts for; along every stroke, the capsule the weapon
-- cuts, from the root out to the head and `radius` wide. The numbers in HITS were shaped by
-- complaints; this is for judging them by eye, with bots swinging, before they are final.
-- Off by default. The parts live in Workspace.Hitboxes and go when it is switched off.
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")
local showHitboxes = false
local hitboxFolder = nil
local bodyBalls = {}      -- player -> the ball on their root
local strokeGhosts = {}   -- swing -> { shaft, tip }, while the stroke is being drawn

local function ghost(name, shape, colour)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 0.65
	p.Material = Enum.Material.SmoothPlastic
	p.Color = colour
	return p
end

local function hitboxes()
	if not hitboxFolder or not hitboxFolder.Parent then
		hitboxFolder = Instance.new("Folder")
		hitboxFolder.Name = "Hitboxes"
		hitboxFolder.Parent = Workspace
	end
	return hitboxFolder
end

local function clearHitboxes()
	if hitboxFolder then hitboxFolder:Destroy() end
	hitboxFolder = nil
	bodyBalls = {}
	strokeGhosts = {}
end

--- The capsule this stroke cuts, this frame, drawn exactly where sweep() looks.
local function drawStroke(swing, from, head, radius)
	local g = strokeGhosts[swing]
	if not g then
		local red = Color3.fromRGB(255, 70, 70)
		g = { shaft = ghost("Stroke", Enum.PartType.Cylinder, red), tip = ghost("StrokeHead", Enum.PartType.Ball, red) }
		g.shaft.Parent = hitboxes()
		g.tip.Parent = hitboxes()
		strokeGhosts[swing] = g
	end
	local len = (head - from).Magnitude
	g.shaft.Size = Vector3.new(math.max(len, 0.05), radius * 2, radius * 2)
	-- A cylinder is long along its X; lookAt points -Z at the head, so a quarter turn about
	-- Y brings X round to lie along the stroke.
	g.shaft.CFrame = CFrame.lookAt((from + head) / 2, head) * CFrame.Angles(0, math.rad(90), 0)
	g.tip.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	g.tip.Position = head
end

--- Every body's ball, where its root is; a stroke's ghost only while its swing is alive.
local function keepHitboxes()
	-- The attribute is the switch's state, and a test or a tool may flip it directly.
	local want = Workspace:GetAttribute("ShowHitboxes") == true
	if want ~= showHitboxes then
		showHitboxes = want
		if not want then clearHitboxes() end
	end
	if not showHitboxes then return end
	local alive = {}
	for _, swing in pairs(swinging) do alive[swing] = true end
	for swing, g in pairs(strokeGhosts) do
		if not alive[swing] then
			g.shaft:Destroy()
			g.tip:Destroy()
			strokeGhosts[swing] = nil
		end
	end
	local seen = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if root then
			seen[other] = true
			local ball = bodyBalls[other]
			if not ball or not ball.Parent then
				ball = ghost("Body", Enum.PartType.Ball, Color3.fromRGB(70, 200, 255))
				ball.Parent = hitboxes()
				bodyBalls[other] = ball
			end
			-- The width sweep() counts for a body: its root's, as a ball round the root.
			local wide = math.max(root.Size.X, root.Size.Z)
			ball.Size = Vector3.new(wide, wide, wide)
			ball.Position = root.Position
		end
	end
	for other, ball in pairs(bodyBalls) do
		if not seen[other] then
			ball:Destroy()
			bodyBalls[other] = nil
		end
	end
end

do
	local commands = TextChatService:WaitForChild("TextChatCommands")
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "hitbox"
	cmd.PrimaryAlias = "/hitbox"
	cmd.SecondaryAlias = "/hitboxes"
	cmd.Parent = commands
	cmd.Triggered:Connect(function(source)
		local player = source and Players:GetPlayerByUserId(source.UserId)
		if not player then return end
		showHitboxes = not showHitboxes
		Workspace:SetAttribute("ShowHitboxes", showHitboxes)
		if not showHitboxes then clearHitboxes() end
		print(("weapons: hitboxes %s, by %s"):format(showHitboxes and "shown" or "hidden", player.Name))
	end)
end

--- Anyone standing where the head is, once per swing each.
---
--- Once per swing rather than once per frame: at sixty frames a second a stroke that lasted
--- a quarter of a second would otherwise land fifteen times and take off seven hearts.
local function sweep(player, swing)
	local spec = HITS[swing.weapon]
	if not spec then return end
	local head = headAt(swing.character, swing.joints, spec.reach)
	if not head then return end
	-- Where the swinger is facing, flattened. Taken off the root rather than off the arm:
	-- the root's facing is where the player is aiming and it is known for every character,
	-- including the ones this machine does not simulate.
	local mine = swing.character and swing.character:FindFirstChild("HumanoidRootPart")
	if not mine then return end                  -- no body, no facing, no swing
	local look = mine.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
	local widest = math.cos(math.rad(spec.arc or 180))
	if showHitboxes then drawStroke(swing, mine.Position, head, spec.radius) end

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and not swing.hit[other] then
			local oc = other.Character
			local root = oc and oc:FindFirstChild("HumanoidRootPart")
			-- A ball against a BODY, not against a point.
			--
			-- This compared the distance to the target's HumanoidRootPart against the radius and
			-- nothing else, which asks for their spine to be inside the ball. A character is two
			-- studs across, so half a body's width of them could be well inside a swing and take
			-- nothing -- and anything moving was most of a width away by the time the stroke
			-- arrived. That is "i cannot attack the 1 bot that moves around in a circle".
			--
			-- So the target's own half-width is added, off its root rather than written down: a
			-- body counts for the size it is.
			--
			-- Not GetPartBoundsInRadius, which is the obvious Roblox answer and is wrong here for
			-- a reason worth writing down: a character this machine does not simulate has limbs
			-- that do not follow its root. Measured, with a bot teleported twelve studs away --
			-- its own Head, Torso and legs stayed five to eleven studs behind, and its accessory
			-- handles were sixty studs off. A sweep that asks what the ball TOUCHES then catches a
			-- limb left lying next to the swinger and lands a blow at any range at all. The root
			-- is the one part of a remote body that is where the body is.
			local wide = root and math.max(root.Size.X, root.Size.Z) / 2 or 0
			-- And in front. The angle is measured from the swinger to the target rather than
			-- from the weapon's head, because close in the head can be past somebody and the
			-- question is which side of you they are on.
			local at = root and (root.Position - mine.Position)
			local flat = at and Vector3.new(at.X, 0, at.Z)
			local infront = flat and (flat.Magnitude < 1e-3 or look:Dot(flat.Unit) >= widest)
			-- Anywhere along the swing, not just at the end of it.
			--
			-- This measured to the weapon's head only, which makes the hit a BALL sitting
			-- `reach` studs out -- with a hole in the middle. A BFS 9000 could not touch
			-- anything closer than 2.3 studs from any angle: "i can be right up aginst them
			-- with spoonie and miss constantly while spamming and rotating". You were inside
			-- the hole, and turning cannot get you out of it.
			--
			-- The distance to the SEGMENT from the body to the head, so the weapon cuts the
			-- whole way out rather than only where it ends. The dead zone goes, the fan widens
			-- as somebody gets closer -- which is what a swing does -- and the arc is what
			-- keeps a front, which is the job it was written for.
			local swept = head - mine.Position
			local len2 = swept:Dot(swept)
			local along = 0
			if root and len2 > 1e-6 then
				along = math.clamp((root.Position - mine.Position):Dot(swept) / len2, 0, 1)
			end
			local nearest = mine.Position + swept * along
			if root and infront and (root.Position - nearest).Magnitude <= spec.radius + wide then
				-- A torch sets them alight; everything else takes a piece off them.
				local landed
				local scale = wizard(player) and WIZARD_MELEE or 1
				if spec.burn then
					landed = Health.burn(other, player, spec.burn.half * scale,
						burnSecs(spec.burn.flame), spec.burn.flame)
				elseif spec.heal then
					landed = Health.heal(other, player, spec.heal)
				else
					landed = Health.hit(other, player, spec.half * scale, spec.shove)
				end
				if landed then
					swing.hit[other] = true
					-- One use. Spent the moment it lands on somebody, not when it is swung:
					-- a candle you waved at the air is still a candle.
					if spec.consume then consume(player, swing.weapon) end
				end
			end
		end
	end
end

-- Which techniques are taken in both hands.
local TWO_HANDED = { hachimonji = true, hachimonjiBack = true, candle = true }

-- Where along the shaft the off hand takes hold, in worn space: behind the right fist,
-- between it and the butt.
local OFF_GRIP = 0.85

-- How far in front of his own shoulder the off hand must always be reaching, whatever the
-- grip is doing. See offHand().
local AHEAD = 0.6

--- The left shoulder Transform that reaches the off hand to the shaft.
---
--- Aimed rather than authored. The off hand has to arrive wherever the right hand has taken
--- the handle, and the right hand's path is six numbers that get retuned every time the cut
--- changes; angles written by hand to match one version of it are wrong for the next. So
--- this reads where the shaft actually is and turns the left arm to point at it.
---
--- It points at the grip rather than reaching it. A shoulder is two degrees of freedom on a
--- fixed-length arm, and for much of the swing the shaft is simply further away than the arm
--- is long -- there is no pose that touches it, and there is no elbow to make one. Aiming is
--- what is left, and it reads correctly: the arm follows the weapon through the technique.
local function offHand(ch, j, weight)
	if weight <= 0 or not j.left then return CFrame.new() end
	local root = ch:FindFirstChild("HumanoidRootPart")
	local torso = ch:FindFirstChild("Torso")
	if not root or not torso then return CFrame.new() end
	-- The torso is itself posed by the waist, and both arms hang off wherever it ended up.
	local torsoCF = torso.CFrame
	if j.waist then
		torsoCF = root.CFrame * j.waist.C0 * j.waist.Transform * j.waist.C1:Inverse()
	end
	local rightCF = torsoCF * j.right.C0 * j.right.Transform * j.right.C1:Inverse()
	local target = rightCF:PointToWorldSpace(Vector3.new(0, -1, OFF_GRIP))

	-- Never behind him. The grip it aims at is up the handle from the fist, towards the
	-- butt, which is where a second hand goes on a two-handed weapon -- and for a good part
	-- of this technique that spot is behind the plane of his chest. Aiming a shoulder at a
	-- point behind the body is the one case where "point at it" reads as something else
	-- entirely: the arm swings out backwards and the off hand does the whole cut behind him
	-- while the sword is out in front. Measured at the start of the hachimonji, the fist is
	-- 0.31 in front of him and the grip 0.47 BEHIND.
	--
	-- So the reach is measured from his own left shoulder and, when it points backwards, is
	-- swung round to the front: same height, same side, but always out in front of him. He
	-- cannot reach the grip either way -- there is no elbow and the arm is too short, which
	-- the whole of this function is an admission of -- and of the two lies available, an off
	-- hand reaching towards the weapon is the one that reads as a grip.
	local shoulder = torsoCF * j.left.C0
	local reach = root.CFrame:VectorToObjectSpace(target - shoulder.Position)
	if reach.Z > -AHEAD then
		target = shoulder.Position
			+ root.CFrame:VectorToWorldSpace(Vector3.new(reach.X, reach.Y, -AHEAD))
	end

	-- Solve in the left shoulder joint's own frame, where the problem is just "rotate this
	-- one vector onto that one": the hand sits at a fixed offset h from the joint, and the
	-- Transform is a pure rotation, so the answer is the turn from h to the target.
	local J = torsoCF * j.left.C0
	local h = j.left.C1:Inverse() * Vector3.new(0, -1, 0)
	local want = J:PointToObjectSpace(target)
	if h.Magnitude < 1e-4 or want.Magnitude < 1e-4 then return CFrame.new() end
	local a, b = h.Unit, want.Unit
	local axis = a:Cross(b)
	if axis.Magnitude < 1e-5 then return CFrame.new() end
	local aim = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(a:Dot(b), -1, 1)))
	return CFrame.new():Lerp(aim, weight)
end

-- ---- the cane's orb ----------------------------------------------------------------------
-- A translucent ball painted in the player character's own gradient, lying across it at the same
-- diagonal it lies across a body: red low on one side through pink, purple and blue to cyan high on
-- the other. The picture is PulseGradient, the one the Engram wears too, painted from the same
-- definition the character's skin is built from (scripts/prep-gradient.js).
--
-- One ball with a picture on it, the way a Roblox builder paints a ball: a SpecialMesh of type
-- FileMesh carrying a sphere mesh and a texture (a Part's own Ball shape takes no texture, and a
-- SpecialMesh ignores TextureId unless it is a FileMesh). Both are place assets, OrbMesh and
-- PulseGradient, made by scripts/prep-gradient.js.
--
-- Not five see-through balls one inside the next, which was the first try. Translucent things
-- sharing one centre have no order to be drawn in, so whichever shell drew last covered the rest:
-- head-on it was a magenta ball with a red rim and no purple, blue or cyan anywhere. And not
-- Neon, which glows by adding light, and summed every band to the same pink-white.
local ORB_SIZE = 1.6          -- studs across, uncharged; a full charge is four times that
local ORB_TRANSPARENCY = 0.3
local ORB_SPEED = 45          -- studs a second
-- How far it goes before it is gone: across the whole map at its longest. The ground is 140 by
-- 140, so corner to corner is 198 studs ("it should be able to snipe from across the map at
-- longest point"). It used to give out at 63, less than halfway.
local ORB_RANGE = 200
local ORB_LIFE = ORB_RANGE / ORB_SPEED   -- seconds
-- It spins as it goes: rolling forward over the top, like a ball thrown with topspin, about the
-- axis across its flight. Not about the vertical -- the bands run round the ball, so a spin on
-- that axis turns them in place and looks like no spin at all.
local ORB_SPIN = 3 * 2 * math.pi          -- radians a second: three turns
local ORB_GROW = 0.12         -- seconds to swell from a point at the tip to full size
-- Down the arm from the shoulder joint's hand end to the cane's tip: the grip is at the end of
-- the arm, and the ferrule's far face is 1.88 below the grip in worn space.
local CANE_TIP = Vector3.new(0, -1 - 1.88, 0)

-- ---- charging it ----
-- Samus's charge beam, with her rule about letting go. Hold the button and the arm goes up;
-- once it is up, standing still charges it. Let go and nothing fires -- the charge is kept. From
-- there, at any level, a click throws it and a hold carries on charging it, up to full. A click
-- with nothing kept is an ordinary shot. A click is a press let go before the arm is up; a hold
-- is one that gets it there. Six seconds is a full charge, and a full one blinks: the cane
-- strobes in the orb's colours so everyone near can see what is coming.
--
-- Walking charges nothing and holds no pose: the arm comes down and he walks as he always does,
-- with the charge and its sound paused where they got to. Stop, still holding, and the arm goes
-- back up and carries on. In the air counts as still unless he is steering, so a charge keeps
-- building off a trampoline.
--
-- What a charge buys:
--
--   damage   half a heart for a click, up to two hearts at six seconds -- in half-hearts, 1 plus
--            3 steps, one more every two seconds, the last only at the full six
--   size     up to four times across
--   sound    the charge is VanishingBlocks played six times slower, only while it is charging
--            (the clip is built to run exactly 6s at that speed, ending as the charge fills --
--            scripts/prep-sfx.js); the shot is MegaBuster, pitched down from 1x to 6x lower the
--            longer the charge -- PlaybackSpeed, which in Roblox is pitch and speed together, so
--            a big shot is a slower, boomier one
local CHARGE_FULL = 6         -- seconds for the biggest shot
local CHARGE_SLOW = 6         -- how many times slower the charge sound plays
-- The charge sound moves as it builds. Slowed six times the clip is a long, even drone, so it goes
-- somewhere: the room swells as it charges, to its fullest by CHARGE_ROOM and held there to the top,
-- and from CHARGE_THIN a high-pass sweeps up until, at full, the low end is gone -- a thin, bright
-- sound ringing round a big room, which is what about to go off sounds like.
--
-- The Audio API, because a high-pass is an AudioFilter: a Sound's effects have no filter of that
-- kind. AudioPlayer -> AudioReverb -> AudioFilter -> AudioEmitter on his root, joined by Wires.
-- The reverb swells in amplitude, not decibels, so it builds steadily rather than arriving all at
-- once at the end; the filter climbs in octaves, which is how a sweep is heard.
local CHARGE_WET = 0          -- dB of reverb at its fullest
local CHARGE_DECAY = 3        -- seconds of tail
local CHARGE_ROOM = 5.5       -- seconds into a charge the reverb is at its fullest
local CHARGE_THIN = 2         -- seconds into a charge the high-pass starts to climb
local THIN_FROM = 20          -- Hz: where the high-pass starts, below anything heard
local THIN_TO = 3000          -- Hz: where it is at full
local RETUNE_STEP = 0.1       -- seconds of charge between retunes, which replicate
local STROBE_HZ = 10          -- how fast a fully charged cane flashes
local STILL = 0.1             -- a MoveDirection shorter than this is not walking
local ORB_GROWTH = 4          -- how many times across a full charge is
local SHOT_DEEPEST = 6        -- how many times lower a full charge's shot is pitched
local RAISED = 0.30           -- the cast's raised row, as a fraction of it: where a charge holds
local CLICK = 0.3             -- seconds: a press let go sooner than this, arm not yet up, is a click

local orbs = {}               -- flying: { part, mesh, from, at, dir, t, size, half, caster }

--- A place asset's path, or nil while it has not arrived.
local function placeAsset(name)
	local folder = ReplicatedStorage:FindFirstChild("PlaceAssets")
	local v = folder and folder:FindFirstChild(name)
	return v and v.Value ~= "" and v.Value or nil
end

--- The orb's mesh and picture, or nil while they have not arrived.
local function orbAssets()
	local mesh, bands = placeAsset("OrbMesh"), placeAsset("PulseGradient")
	if not mesh or not bands then return nil end
	return mesh, bands
end

--- How wet the charge sound's reverb is `secs` into a charge: silent at nought, CHARGE_WET from CHARGE_ROOM.
local function chargeWet(secs)
	local amount = math.clamp(secs / CHARGE_ROOM, 0, 1)
	if amount <= 0.0001 then return -80 end
	return math.max(-80, CHARGE_WET + 20 * math.log10(amount))
end

--- Where the charge sound's high-pass is `secs` into a charge: THIN_FROM until CHARGE_THIN, THIN_TO at full.
local function chargeThin(secs)
	local u = math.clamp((secs - CHARGE_THIN) / (CHARGE_FULL - CHARGE_THIN), 0, 1)
	return THIN_FROM * (THIN_TO / THIN_FROM) ^ u
end

--- Plays a place asset from a body, heard by everyone near it: a Sound the server makes is in
--- everyone's world. Nil, and silence, while the asset has not arrived.
local function soundFrom(parent, asset, speed)
	local id = placeAsset(asset)
	if not id or not parent then return nil end
	local s = Instance.new("Sound")
	s.Name = asset
	s.SoundId = id
	s.Volume = 1
	s.PlaybackSpeed = speed
	s.Parent = parent
	s:Play()
	return s
end

--- The charge sound, `secs` into a charge, playing from his root: an AudioPlayer wired through the
--- room and the filter into an emitter. Heard falling away as a Sound with the default roll-off
--- was -- Inverse from ten studs -- so nobody hears it any further or nearer than they did.
--- Nil, and silence, while the clip has not arrived.
local function chargeVoice(root, secs)
	local id = placeAsset("SfxCharge")
	if not id or not root then return nil end
	local player = Instance.new("AudioPlayer")
	player.Name = "SfxCharge"
	player.Asset = id
	player.Volume = 1
	player.PlaybackSpeed = 1 / CHARGE_SLOW
	-- The clip is the charge, a sixth of a second of it for every second charged: a kept charge
	-- carries on from the same place.
	player.TimePosition = secs / CHARGE_SLOW
	local room = Instance.new("AudioReverb")
	room.Name = "Room"
	room.DecayTime = CHARGE_DECAY
	room.DryLevel = 0
	room.WetLevel = chargeWet(secs)
	room.Parent = player
	local thin = Instance.new("AudioFilter")
	thin.Name = "Thin"
	thin.FilterType = Enum.AudioFilterType.Highpass12dB
	thin.Frequency = chargeThin(secs)
	thin.Parent = player
	local out = Instance.new("AudioEmitter")
	out.Name = "SfxChargeOut"
	out.DistanceAttenuationMode = Enum.DistanceAttenuationMode.Inverse
	out.DistanceAttenuationBounds = NumberRange.new(10, 10000)
	out.Parent = root
	for _, pair in ipairs({ { player, room }, { room, thin }, { thin, out } }) do
		local w = Instance.new("Wire")
		w.SourceInstance = pair[1]
		w.TargetInstance = pair[2]
		w.Parent = player
	end
	player.Parent = root
	player:Play()
	return { player = player, room = room, thin = thin, out = out, tunedAt = secs, held = false }
end

--- Retunes a charge sound for `secs`: every RETUNE_STEP, and always on reaching CHARGE_ROOM and full,
--- or the last step short of either leaves the room or the sweep just short of where it should be.
local function retuneVoice(voice, secs)
	if secs - voice.tunedAt < RETUNE_STEP
		and not (secs >= CHARGE_ROOM and voice.tunedAt < CHARGE_ROOM)
		and not (secs >= CHARGE_FULL and voice.tunedAt < CHARGE_FULL) then
		return
	end
	voice.tunedAt = secs
	voice.room.WetLevel = chargeWet(secs)
	voice.thin.Frequency = chargeThin(secs)
end

local function dropVoice(voice)
	if not voice then return end
	voice.out:Destroy()
	voice.player:Destroy()
end

--- How far through a full charge a hold of `secs` is, 0 to 1.
local function chargeFraction(secs)
	return math.clamp((secs or 0) / CHARGE_FULL, 0, 1)
end

--- Half-hearts for a charge: 1 for a click, 4 -- two hearts -- for a full one.
local function chargeHalf(frac)
	return 1 + math.floor(3 * frac + 1e-6)
end

-- The orb's bands, which a full cane strobes through.
local BAND_COLOURS = {
	Color3.fromRGB(255, 45, 70), Color3.fromRGB(255, 50, 205), Color3.fromRGB(145, 60, 235),
	Color3.fromRGB(55, 95, 255), Color3.fromRGB(40, 230, 255),
}

--- Flashes a fully charged cane, or stops: a Highlight on the accessory, on and off STROBE_HZ
--- times a second, stepping through the bands each time it comes on. A Highlight because it is
--- what Roblox draws over a whole model at once -- every part of the cane lights together -- and
--- it is an instance in everyone's world, so everyone sees it, not only the one holding it.
local strobes = {}            -- player -> { light, from }
local function blink(player, on)
	local st = strobes[player]
	if not on then
		if st then st.light:Destroy() end
		strobes[player] = nil
		return
	end
	if not st or not st.light.Parent then
		local acc
		for _, d in ipairs(player.Character and player.Character:GetChildren() or {}) do
			if d:IsA("Accoutrement") and WEAPONS.charged[d.Name] then acc = d break end
		end
		if not acc then return end
		local h = Instance.new("Highlight")
		h.Name = "ChargedStrobe"
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = acc
		st = { light = h, from = os.clock() }
		strobes[player] = st
	end
	local step = math.floor((os.clock() - st.from) * STROBE_HZ)
	local lit = step % 2 == 0
	local colour = BAND_COLOURS[(step // 2) % #BAND_COLOURS + 1]
	st.light.FillColor = colour
	st.light.OutlineColor = colour
	st.light.FillTransparency = lit and 0.1 or 1
	st.light.OutlineTransparency = lit and 0 or 1
end

--- Where the cane's tip is, from the pose the arm is in now.
local function caneTip(ch, j)
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local torso = ch and ch:FindFirstChild("Torso")
	if not root or not torso or not j.right then return nil end
	local torsoCF = torso.CFrame
	if j.waist then
		torsoCF = root.CFrame * j.waist.C0 * j.waist.Transform * j.waist.C1:Inverse()
	end
	local rightCF = torsoCF * j.right.C0 * j.right.Transform * j.right.C1:Inverse()
	return rightCF:PointToWorldSpace(CANE_TIP)
end

--- Sends an orb out of the cane's tip, the way the caster is facing.
---
--- Faced along the body rather than along the shaft, for the same reason the spoons aim off
--- the root: where the player is facing is what they are aiming, and the arm is only nearly
--- level at the moment the orb leaves.
---
--- Without its pictures it is still a shot: a plain purple ball, which flies, hits and stops at
--- walls the same. What an asset that has not arrived may cost is a look, never a fight.
local function castOrb(player, swing)
	local ch = swing.character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local tip = caneTip(ch, swing.joints)
	local frac = chargeFraction(swing.charge)
	-- The shot is heard whether or not the orb can be drawn.
	if root then
		local shot = soundFrom(root, "SfxBuster", 1 / (1 + (SHOT_DEEPEST - 1) * frac))
		if shot then task.delay(3, function() shot:Destroy() end) end
	end
	if not root or not tip then return end
	local meshId, bandsId = orbAssets()
	local size = ORB_SIZE * (1 + (ORB_GROWTH - 1) * frac)
	local half = chargeHalf(frac)
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
	local ball = Instance.new("Part")
	ball.Name = "CaneOrb"
	ball.Size = Vector3.one * size
	-- What it carries, on it, for anything that wants to know what is coming.
	ball:SetAttribute("Charge", swing.charge or 0)
	ball:SetAttribute("Half", half)
	ball.Transparency = ORB_TRANSPARENCY
	ball.Material = Enum.Material.SmoothPlastic
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanTouch = false
	ball.CanQuery = false
	ball.CastShadow = false
	-- Turned the way he faces, so the gradient starts out lying across the orb as it lies across
	-- him -- red low on his left, cyan high on his right -- and not along whatever way the world's
	-- axes happen to point, which put the red corner on top for half the directions a shot can go.
	local facing = CFrame.lookAt(Vector3.zero, look)
	ball.CFrame = CFrame.new(tip) * facing
	local mesh = nil
	if meshId then
		mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = meshId
		mesh.TextureId = bandsId
		-- A FileMesh is drawn at its own size times Scale, not stretched to the part; the sphere is
		-- one stud across, so Scale is the diameter.
		mesh.Scale = Vector3.one * 0.05
		mesh.Parent = ball
	else
		ball.Shape = Enum.PartType.Ball
		ball.Color = Color3.fromRGB(145, 60, 235)
		ball.Size = Vector3.one * 0.05
	end
	ball.Parent = workspace
	table.insert(orbs, { part = ball, mesh = mesh, from = tip, at = tip, dir = look, t = 0,
		size = size, half = half, caster = player, full = (swing.charge or 0) >= CHARGE_FULL, facing = facing,
		wizard = wizard(player) })
end

--- The first body in an orb's path this step, other than the caster's.
---
--- A body is its root and its width, for the reason sweep() gives: a body the server does not
--- simulate has limbs trailing wherever it last was, and the root is the one part that is where
--- the body is. The orb touches it when the root comes within the orb's radius plus the body's
--- half-width of the stretch the orb moved along.
local function bodyInPath(orb, from, to, radius)
	local step = to - from
	local len2 = step:Dot(step)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= orb.caster then
			local ch = other.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local along = len2 > 1e-6 and math.clamp((root.Position - from):Dot(step) / len2, 0, 1) or 0
				local wide = math.max(root.Size.X, root.Size.Z) / 2
				if (root.Position - (from + step * along)).Magnitude <= radius + wide then
					return other
				end
			end
		end
	end
	return nil
end

--- Whatever solid is in an orb's path this step: the centre, cast as a ray, against anything
--- that collides. Bodies are left out -- bodyInPath() has them -- and so is anything a player can
--- walk through, so a trigger volume or a decoration nobody collides with does not stop a shot.
--- The centre, not the whole ball: a full charge is six studs across and would catch the ground
--- it is flying over.
local function wallInPath(orb, from, to)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip = { orb.part }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(skip, p.Character) end
	end
	params.FilterDescendantsInstances = skip
	params.RespectCanCollide = true
	return workspace:Raycast(from, to - from, params)
end

local function flyOrbs(dt)
	for i = #orbs, 1, -1 do
		local orb = orbs[i]
		orb.t += dt
		local grow = math.clamp(orb.t / ORB_GROW, 0, 1)
		local to = orb.from + orb.dir * (ORB_SPEED * orb.t)
		local done = orb.t >= ORB_LIFE or not orb.part.Parent
		if not done then
			-- A body first, then a wall, along the same stretch: somebody standing in front of a
			-- wall is hit before the wall is.
			local victim = bodyInPath(orb, orb.at, to, orb.size * grow / 2)
			if victim then
				-- Knocked back only by a shot that kills or a full charge -- and then as hard as the
				-- BFS 9000 throws, read off its row so retuning one retunes both. An ordinary shot
				-- only stings; a blow that finishes somebody should look like one, and a full
				-- charge is the thing they were warned about. Thrown by a wizard -- the hat on when
				-- it left the cane -- every shot throws that hard.
				local hum = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
				local lethal = hum ~= nil and hum.Health <= orb.half
				Health.hit(victim, orb.caster, orb.half, (lethal or orb.full or orb.wizard) and HITS["BFS 9000"].shove or 0)
				done = true
			elseif wallInPath(orb, orb.at, to) then
				done = true
			end
		end
		if done then
			orb.part:Destroy()
			table.remove(orbs, i)
		else
			local across = Vector3.one * math.max(0.05, orb.size * grow)
			if orb.mesh then orb.mesh.Scale = across else orb.part.Size = across end
			local axis = orb.dir:Cross(Vector3.yAxis)
			orb.part.CFrame = CFrame.new(to) * CFrame.fromAxisAngle(axis, -ORB_SPIN * orb.t) * orb.facing
			orb.at = to
		end
	end
end

--- How much of the off-hand grip is in effect. Nought at both ends, because the spoon is
--- carried one-handed and the second hand only comes across for the technique.
local function gripWeight(a)
	if a <= 0.04 or a >= 0.96 then return 0 end
	if a < 0.18 then return ease((a - 0.04) / 0.14) end
	if a > 0.80 then return ease((0.96 - a) / 0.16) end
	return 1
end

--- Poses all three joints at once. Absolute, not composed onto whatever was there: a swing
--- that multiplied onto the previous frame value would drift a little further from rest on
--- every click and never quite hand the arm back.
---
--- The right arm and the waist go first and the off hand last, because a two-handed swing
--- aims the off hand at where the other two have just put the shaft.
local function apply(j, v, ch, kind, a)
	if j.right and j.right.Parent then j.right.Transform = CFrame.Angles(v[1], v[2], v[3]) end
	if j.waist and j.waist.Parent then j.waist.Transform = CFrame.Angles(v[7], v[8], v[9]) end
	if j.left and j.left.Parent then
		if kind and TWO_HANDED[kind] and ch then
			j.left.Transform = offHand(ch, j, gripWeight(a))
		else
			j.left.Transform = CFrame.Angles(v[4], v[5], v[6])
		end
	end
end

--- Where a technique stops cutting: the end of its last stroke. After this the arm is only
--- coming home, and there is nothing left worth protecting.
local function recoveryAt(kind)
	local last = 0
	for _, w in ipairs(STRIKE[kind] or {}) do
		if w[2] > last then last = w[2] end
	end
	return last
end

--- Begins the next technique in the weapon's cycle.
local function startSwing(player, name, cycle)
	local j = joints(player)
	if not j or not j.right then return false end
	local i = nextIndex[player] or 1
	if i > #cycle then i = 1 end
	local kind = cycle[i]
	nextIndex[player] = i % #cycle + 1
	local old = swinging[player]
	if old and old.chargeSound then dropVoice(old.chargeSound) end
	local swing = { joints = j, kind = kind, t = 0, character = player.Character,
		weapon = name, hit = {}, rang = {} }
	swinging[player] = swing
	-- Said on the body, for the one who is swinging: their controls face them forward for the
	-- stroke even while they are running some other way (Controls.client.luau).
	if swing.character then swing.character:SetAttribute("Swinging", true) end
	if kind == "cast" then
		if held[player] then
			-- The button is down: this may be a click or a hold, and nobody knows yet. It starts
			-- as a charge carrying on from whatever was kept; release() decides which it was.
			swing.charging = true
			swing.charged = kept[player] or 0   -- seconds of charge, standing still with the arm up
			swing.pressAt = held[player]
		else
			-- Already let go by the time it started (a queued click): a click, throwing the kept.
			swing.charge = kept[player] or 0
		end
		kept[player] = nil
	end
	remote:FireClient(player, kind)
	return true
end

--- The button came up. Let go before the arm was up and it was a click: it carries on into the
--- lunge and throws whatever charge there is, none or some or full. Otherwise it was a hold: the
--- charge is kept, not fired, and the arm comes down.
local function release(player)
	held[player] = nil
	local swing = swinging[player]
	if not swing or not swing.charging then return end
	swing.charging = false
	if swing.chargeSound then
		dropVoice(swing.chargeSound)
		swing.chargeSound = nil
	end
	local click = not swing.reachedTop and os.clock() - (swing.pressAt or 0) < CLICK
	if click then
		swing.charge = math.min(swing.charged, CHARGE_FULL)
	else
		if swing.charged > 0 then kept[player] = math.min(swing.charged, CHARGE_FULL) end
		swing.lowering = true
	end
end

--- Drops whatever is in flight for a player, and its charge sound with it.
local function dropSwing(player)
	local swing = swinging[player]
	if swing and swing.chargeSound then dropVoice(swing.chargeSound) end
	if swing and swing.character then swing.character:SetAttribute("Swinging", nil) end
	swinging[player] = nil
end

remote.OnServerEvent:Connect(function(player, what)
	-- The button coming up. Only a charged weapon cares.
	if what == "release" then
		release(player)
		return
	end
	-- The client asks; the server decides. Asking without a weapon gets nothing.
	local name, cycle = heldWeapon(player)
	if not name then return end
	if WEAPONS.charged[name] then held[player] = os.clock() end
	-- Still drawing it. Said out loud rather than dropped, so the click reads as refused
	-- rather than as a click the game missed.
	if os.clock() - (drawnAt[player] or 0) < DRAW then
		remote:FireClient(player, "drawing")
		return
	end
	local swing = swinging[player]
	if swing and swing.lowering then
		-- The arm coming down from a kept charge is not a swing to wait for: the press starts over,
		-- to be a click that throws what is kept or a hold that carries on charging it.
		dropSwing(player)
		swing = nil
	end
	if swing then
		-- Held, not dropped and not obeyed on the spot. Refusing outright made the spoon
		-- feel dead -- every click inside half a second went nowhere. Obeying on the spot
		-- was worse: each new click cut the previous stroke off wherever it had got to, so
		-- fast clicking produced a series of fragments and never a whole cut.
		--
		-- So the click waits, and the loop below spends it the moment this stroke stops
		-- cutting. Every stroke is seen in full and there is no pause between them.
		swing.queued = true
		return
	end
	startSwing(player, name, cycle)
end)

-- One loop for every swing in flight.
RunService.Heartbeat:Connect(function(dt)
	flyOrbs(dt)
	-- What everyone is holding, so that picking something up starts its draw. Watched here
	-- rather than told: the wardrobe is what changes it, a pet summon changes it, a respawn
	-- changes it, and a weapon that only knew about one of those would let the others
	-- through.
	for _, player in ipairs(Players:GetPlayers()) do
		-- A weapon that has just gone on is the one in the hand, whatever else is worn.
		local worn = wornWeapons(player)
		local was = lastWorn[player] or {}
		local newest = nil
		for n in pairs(worn) do if not was[n] then newest = n end end
		lastWorn[player] = worn
		local name = newest or heldWeapon(player)
		if holding[player] ~= name then
			holding[player] = name
			drawnAt[player] = name and os.clock() or nil
			kept[player] = nil        -- a kept charge is the cane's, and goes when it is put away
		end
		local swing = swinging[player]
		blink(player, (swing ~= nil and swing.charging and swing.charged >= CHARGE_FULL)
			or (kept[player] or 0) >= CHARGE_FULL)
	end
	for player, swing in pairs(swinging) do
		local j = swing.joints
		if not j.right or not j.right.Parent then
			dropSwing(player)
		elseif (swing.charging or swing.lowering) and heldWeapon(player) ~= swing.weapon then
			-- Put away mid-charge: no shot, and the arm comes down.
			apply(j, REST)
			dropSwing(player)
		elseif swing.lowering then
			-- Let go of a charge: the arm comes down the way it went up, and nothing fires.
			swing.t = math.max(0, swing.t - dt)
			if swing.t <= 0 then
				apply(j, REST)
				dropSwing(player)
			else
				local a = math.clamp(swing.t / SWING[swing.kind], 0, 1)
				apply(j, poseAt(SWINGS[swing.kind], a), swing.character, swing.kind, a)
			end
		else
			swing.t += dt
			if swing.charging then
				local top = RAISED * SWING[swing.kind]
				local hum = swing.character and swing.character:FindFirstChildOfClass("Humanoid")
				local walking = hum ~= nil and hum.MoveDirection.Magnitude > STILL
				if walking then
					-- No charging pose on the move: the arm comes back down, and once it is home
					-- the walk has it again.
					swing.t = math.max(0, swing.t - 2 * dt)
				else
					swing.t = math.min(swing.t, top)
				end
				-- It builds only with the arm all the way up and his feet still.
				if not walking and swing.t >= top then swing.reachedTop = true end
				local building = not walking and swing.t >= top and swing.charged < CHARGE_FULL
				if building then swing.charged = math.min(swing.charged + dt, CHARGE_FULL) end
				-- The charge sound is the charge: it starts when the charge does, stops with it
				-- and picks up where it left off -- an AudioPlayer's Stop keeps its place -- and
				-- moves as it builds (retuneVoice). Its own note of who stopped it, not IsPlaying,
				-- which is also false of a clip that has simply finished.
				if building then
					if not swing.chargeSound then
						local root = swing.character and swing.character:FindFirstChild("HumanoidRootPart")
						swing.chargeSound = chargeVoice(root, swing.charged)
					else
						if swing.chargeSound.held then
							swing.chargeSound.held = false
							swing.chargeSound.player:Play()
						end
						retuneVoice(swing.chargeSound, swing.charged)
					end
				elseif swing.chargeSound and not swing.chargeSound.held and swing.charged < CHARGE_FULL then
					swing.chargeSound.held = true
					swing.chargeSound.player:Stop()
				end
				if swing.t <= 0 then
					-- Home, walking: the joint left at rest so the walk animates the arm.
					apply(j, REST)
					continue
				end
			end
			local a = math.clamp(swing.t / SWING[swing.kind], 0, 1)
			apply(j, poseAt(SWINGS[swing.kind], a), swing.character, swing.kind, a)
			-- Only while the head is travelling through the cut, and only after the pose
			-- for this frame has been written: the sweep reads the joints back.
			local stroke = strikeIndex(swing.kind, a)
			if stroke then
				-- One sound per stroke, as the stroke starts. On the cut rather than on the
				-- click: the wind-up takes a fifth of a second, and a whoosh that arrives
				-- before the arm has moved belongs to a different swing.
				if not swing.rang[stroke] and SWING_SFX[swing.kind] then
					swing.rang[stroke] = true
					local root = swing.character and swing.character:FindFirstChild("HumanoidRootPart")
					-- Everyone close enough hears it, not just the one swinging: a fight
					-- nobody else can hear is a fight happening somewhere else.
					if root then Health.soundNear(root.Position, SWING_SFX[swing.kind], EARSHOT) end
				end
				-- A cast lets its orb go once, as the lunge begins.
				if swing.kind == "cast" and not swing.cast then
					swing.cast = true
					castOrb(player, swing)
				end
				sweep(player, swing)
			end
			-- A click held during the stroke is spent as soon as the cutting is done, which
			-- is before the arm has finished coming home: that overlap is what makes a
			-- flurry read as a flurry rather than as a queue.
			if swing.queued and a >= recoveryAt(swing.kind) then
				local name, cycle = heldWeapon(player)
				if name and startSwing(player, name, cycle) then
					-- startSwing has replaced the entry; this one is finished with.
					continue
				end
				swing.queued = false
			end
			if a >= 1 then
				-- Home exactly, not nearly: the renderer hands a limb back to the walk
				-- animation only once its joint chain is the identity again, so a swing
				-- that stopped a degree short would leave him locked out of his own gait.
				apply(j, REST)
				dropSwing(player)
			end
		end
	end
end)
-- After the strokes have been read for the frame: the balls follow the bodies and a
-- finished swing takes its ghost with it.
RunService.Heartbeat:Connect(keepHitboxes)

-- A new body has new joints, and the old ones are gone. Anything mid-swing is dropped
-- rather than left holding a reference to a limb that no longer exists.
-- A kept charge dies with the body that held it.
local function newBody(player)
	dropSwing(player)
	kept[player] = nil
	blink(player, false)
end
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function() newBody(player) end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(function() newBody(player) end)
end
Players.PlayerRemoving:Connect(function(player)
	newBody(player)
	held[player] = nil
	nextIndex[player] = nil
	lastWorn[player] = nil
	drawnAt[player] = nil
	holding[player] = nil
end)

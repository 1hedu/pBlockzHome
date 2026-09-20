-- Emotes, built in code.
--
-- The demo keeps its animations as `.rbxmx` files saved out of Studio. This town cannot: it
-- is published to the chain as Luau and nothing else, so an animation that lives in a file
-- is an animation that never arrives. Everything else here is built the same way -- a cape,
-- an Engram badge, a PNG -- so a KeyframeSequence is no different.
--
-- ---- what a Pose is named after --------------------------------------------------------
-- The LIMB, not the joint. A Pose called "Right Arm" drives whichever Motor6D has the right
-- arm as its Part1, which on an R6 rig is the Right Shoulder. That is Roblox's own
-- convention and it is what the engine matches on.
--
-- A Pose's CFrame is a DELTA from the rest pose, not a place to stand. `CFrame.Angles(0, 0,
-- -2)` on an arm swings it two radians about the shoulder from wherever the shoulder is;
-- it does not put the arm anywhere in particular.
--
-- ---- what the six parts can say --------------------------------------------------------
-- R6 has a torso, a head, two arms and two legs, and no spine, no elbows and no knees. Big
-- shapes read; detail does not. Every pose here is a whole limb swung about one joint,
-- because that is the entire vocabulary the rig has.
--
-- Posing the Torso moves everything: the head, the arms and the legs all hang off it. That
-- is what /lay uses -- one rotation lays the whole body down.
local Emotes = {}

local ARM_L, ARM_R = "Left Arm", "Right Arm"
local LEG_L, LEG_R = "Left Leg", "Right Leg"

local function poseInto(keyframe: Instance, limb: string, cf: CFrame)
	local p = Instance.new("Pose")
	p.Name = limb
	p.CFrame = cf
	-- Cubic, so a hand slows as it reaches the top of a wave instead of arriving at full
	-- speed and stopping dead. Linear reads as clockwork on a six-part body.
	p.EasingStyle = Enum.PoseEasingStyle.Cubic
	p.Parent = keyframe
	return p
end

--- Builds a KeyframeSequence. `frames` is a list of `{ t = seconds, pose = { limb = CFrame } }`
--- in order; a limb a frame does not mention keeps whatever the frames around it say.
function Emotes.sequence(name: string, opts, frames): Instance
	local seq = Instance.new("KeyframeSequence")
	seq.Name = name
	seq.Loop = opts.loop == true
	seq.Priority = opts.priority or Enum.AnimationPriority.Action
	for i, f in ipairs(frames) do
		local k = Instance.new("Keyframe")
		k.Name = f.name or ("Frame" .. tostring(i))
		k.Time = f.t
		k.Parent = seq
		for limb, cf in pairs(f.pose) do poseInto(k, limb, cf) end
	end
	return seq
end

-- ---- which way a limb swings ------------------------------------------------------------
--
-- Measured, not reasoned about. A Pose's CFrame is a delta about the joint, and the axes do
-- not mean what the names suggest -- so each was rotated on a live body and the result read
-- off the drawn limb (tests/emote_test.gd checks the ones that matter):
--
--   X   the frontal plane: splays a leg out sideways, raises an arm out from the body
--   Y   a twist about the limb's own length; a leg keeps pointing where it pointed
--   Z   the sagittal plane: swings a limb FORWARD and back
--
-- ---- and the two sides are MIRRORED ----------------------------------------------------
--
-- This is the one that keeps costing. A limb's Pose is a delta in ITS OWN joint's frame, and
-- the left and right joints of an R6 rig face opposite ways -- so the same angle swings the
-- right leg forward and the left leg BACKWARD. Give both legs the same Z and you have not
-- sat down, you have done the splits, which is exactly what /sit looked like.
--
-- So every pose here that names a pair gives them opposite Z. Measured on a live body:
-- the right leg goes forward on positive Z, the left on negative.
--
-- The character faces -Z, so forward is -Z in the body's own frame.

-- ---- the emotes ------------------------------------------------------------------------
--
-- `hold` is how far the body drops while the emote runs, in studs of HipHeight. Sitting on
-- the ground is not a pose on its own: pose the legs forward without lowering the body and
-- the character sits in mid air with its feet through the floor. The pose says what the body
-- is doing; the drop says where it is.

Emotes.DEFS = {
	-- One arm up, rocking twice, then down. Not looped: a wave is a thing you do, not a
	-- thing you are, which is why WoW lets you keep walking through it.
	wave = {
		hold = 0,
		loop = false,
		blurb = "wave",
		frames = {
			{ t = 0.0, pose = { [ARM_R] = CFrame.new() } },
			{ t = 0.3, pose = { [ARM_R] = CFrame.Angles(-2.3, 0, 0) } },
			{ t = 0.55, pose = { [ARM_R] = CFrame.Angles(-2.3, 0, -0.4) } },
			{ t = 0.8, pose = { [ARM_R] = CFrame.Angles(-2.3, 0, 0.15) } },
			{ t = 1.05, pose = { [ARM_R] = CFrame.Angles(-2.3, 0, -0.4) } },
			{ t = 1.4, pose = { [ARM_R] = CFrame.new() } },
		},
	},

	-- Sitting on the ground where you stand: legs straight out in front, leaning back on your
	-- hands. Looped and held, because sitting IS a thing you are.
	sit = {
		hold = 2.2,
		loop = true,
		blurb = "sit down",
		frames = {
			{
				t = 0,
				pose = {
					-- Leaning back a touch, the way anybody sitting on the floor does.
					Torso = CFrame.Angles(-0.2, 0, 0),
					-- Out in FRONT -- both of them. Opposite Z, because the hips are mirrored
					-- and the same sign sends one leg forward and the other back. With both
					-- at +1.5 this was a man doing the splits, which is a thing you can see
					-- from across the square and could not see in any number the test read.
					[LEG_L] = CFrame.Angles(0.1, 0, -1.5),
					[LEG_R] = CFrame.Angles(-0.1, 0, 1.5),
					-- Propping: straight back, and nothing else. The few degrees of splay
					-- these had is a rotation in the frontal plane, so an arm that was also
					-- swung back came out on a diagonal -- crooked, and obviously so up
					-- close. Two rotations on one straight limb is one too many when the
					-- limb has no elbow to absorb it.
					[ARM_L] = CFrame.Angles(0, 0, 0.55),
					[ARM_R] = CFrame.Angles(0, 0, -0.55),
				},
			},
		},
	},

	-- Flat out. One rotation of the Torso lays everything down, because the head, both arms
	-- and both legs all hang off it -- and the body drops to the floor with it.
	--
	-- Which way UP is the other half, and it is a separate rotation: a quarter turn lays you
	-- down, and a half turn about the length of your own body decides whether the sky or the
	-- grass is in your face. `/lay` puts you on your back and `/roll` turns you over, because
	-- lying down and lying face down are two different things to want.
	lay = {
		hold = 2.6,
		loop = true,
		blurb = "lie down",
		frames = {
			{
				t = 0,
				pose = {
					-- Laid down, and rolled half a turn about the length of the body.
					--
					-- The quarter turn on its own puts you FACE DOWN, which is not what
					-- anybody typing "lie down" means. The half turn has to go on the LEFT:
					-- on the right it is a yaw about the vertical, which spins you round on
					-- the spot still face down -- head where your feet were and no better
					-- off. Composed this way it turns you over.
					Torso = CFrame.Angles(0, math.pi, 0) * CFrame.Angles(1.5708, 0, 0),
					-- Arms down by your sides. Posed out in the frontal plane they ended up
					-- folded across the chest, because "out to the side" of a body that is
					-- lying down is straight up in the air.
					[ARM_L] = CFrame.new(),
					[ARM_R] = CFrame.new(),
				},
			},
		},
	},

	-- The same thing, the other way up. Not a command of its own: `/roll` turns you from one
	-- into the other, and only while you are already down -- rolling over is something you do
	-- when you are lying there, not a way to get there.
	belly = {
		hold = 2.6,
		loop = true,
		hidden = true,
		blurb = "roll over",
		frames = {
			{
				t = 0,
				pose = {
					Torso = CFrame.Angles(1.5708, 0, 0),
					[ARM_L] = CFrame.new(),
					[ARM_R] = CFrame.new(),
				},
			},
		},
	},
}

return Emotes

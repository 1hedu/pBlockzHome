-- The town's mixer: one master, and music and effects on their own channels under it.
--
-- Every Sound here -- the five 2A03 voices, the menu clicks, the fight -- is parented to
-- SoundService and put in a group. A SoundGroup's volume multiplies its Sounds', so one
-- number turns the whole town up and down without any of them needing to know about each
-- other, and without the engine having to walk its channels and rewrite five volumes every
-- time somebody moves a slider.
--
-- Music and effects are not the same channel. They were, and the fight came out faint under
-- the jukebox: a spoon landing and a bass line were competing for the same fader, so the
-- only way to hear a hit was to turn the music up with it. Groups nest, so Music and Sfx sit
-- under Town and are balanced against each other once, here, while the slider still moves
-- everything together.
--
-- It is not a substitute for the limiter on the master bus, which is the host's and catches
-- peaks. This is the part you are allowed to have an opinion about.
local SoundService = game:GetService("SoundService")

local Mixer = {}

-- How the two sit against each other. Effects play at full and the music sits under them,
-- because an effect is information -- how much health you have left -- and the music is not.
--
-- SFX was 1.35, set by ear against clips that spanned 17 dB: the quiet ones needed the lift
-- and the loud ones were already too much. They are levelled now (scripts/audio-levels.js,
-- every effect at -18 dB rms, none past -1 dBFS), so the lift is no longer paying for
-- anything and all it buys is less room before the master limiter.
--
-- 1.0 is the number that keeps the town at the loudness it already had. Measured, not
-- guessed: the typical effect used to reach the ears at -21.6 dB and now reaches them at
-- -21.1. What moves is only what was wrong -- a sword swing comes up 8 dB from inaudible,
-- the familiar and the menu blip come down 7 and 9 from startling -- and no single effect
-- peaks above -5 dBFS any more, so the limiter is left for sums rather than sitting on
-- every loud clip.
local MUSIC = 0.35
local SFX = 1.35

local function group(name: string, volume: number, parent: Instance?)
	local host = SoundService or workspace
	local g = (parent or host):FindFirstChild(name)
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = host
	end
	g.Volume = volume
	return g
end

local town = group("Town", 0.7)
local music = group("Music", MUSIC)
local sfx = group("Sfx", SFX)
-- Under the master, so the slider still governs both.
music.SoundGroup = town
sfx.SoundGroup = town

Mixer.group = town
Mixer.musicGroup = music
Mixer.sfxGroup = sfx

--- Everything, as a fraction of full. The slider moves this and the balance below it holds.
function Mixer.set(v: number)
	town.Volume = math.clamp(v, 0, 1)
	return town.Volume
end

function Mixer.get(): number
	return town.Volume
end

--- How much of the music is let through, on top of everything else.
---
--- Its own number rather than a write to the group's volume, because the group's volume is
--- the balance the town was mixed at -- MUSIC above -- and something that wanted to fade the
--- tune in would otherwise have to know that number and hand it back afterwards. This
--- multiplies it and leaves it alone. The slider still governs the lot.
---
--- The intro is what it is for: the tune comes up from nothing across the card and the dark
--- and is at its proper level by the time you can see anything.
local duck = 1

function Mixer.duckMusic(v: number)
	duck = math.clamp(v, 0, 1)
	music.Volume = MUSIC * duck
	return duck
end

function Mixer.musicDuck(): number
	return duck
end

--- Puts a Sound on the music channel.
function Mixer.music(sound: Instance)
	sound.SoundGroup = music
	return sound
end

--- Puts a Sound on the effects channel: clicks, and the fight.
function Mixer.sfx(sound: Instance)
	sound.SoundGroup = sfx
	return sound
end

--- Anything that has not said which it is. Effects, because that is what almost everything
--- here is, and because a stray sound is better too loud than inaudible.
function Mixer.adopt(sound: Instance)
	return Mixer.sfx(sound)
end

return Mixer

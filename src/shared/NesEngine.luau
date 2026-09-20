-- The 2A03's four voices, played from samples.
--
-- One Sound per channel, looping a single cycle of the waveform, pitched by PlaybackSpeed.
-- That is not a trick: it is what the chip does. A pulse channel's timer register only ever
-- decides how fast the same eight-step duty sequence is stepped through, so playing one
-- cycle faster or slower reproduces it exactly rather than approximating it.
--
-- The alternative -- summing sine harmonics to build a square -- needs a dozen voices per
-- channel to stop sounding like an organ, and still cannot make noise at all.
--
-- Waveforms come from scripts/prep-nes.js, generated from the hardware's definition, and
-- arrive as published assets; the host leaves their local paths in ReplicatedStorage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Mixer = require(script.Parent.Mixer)

local NesEngine = {}

-- Every pulse and triangle sample is one cycle of 64 samples at 44100, so it loops at
-- exactly this. Playback speed is simply the note divided by it.
local BASE_HZ = 44100 / 64
-- The noise sample is one full turn of the shift register, one sample per step, written at
-- 44100. Its "frequency" is the rate the register is clocked at, so the speed is that over
-- the file's own rate.
local NOISE_HZ = 44100

local VOICES = {
	pulse12 = "NesPulse12", pulse25 = "NesPulse25",
	pulse50 = "NesPulse50", pulse75 = "NesPulse75",
	triangle = "NesTriangle", noise = "NesNoise",
}

local channels = {}
local paths = {}
-- Five voices, each its own Sound, summing in the mixer rather than in a chip: at 0.35
-- apiece a full arrangement peaked around 1.75, which is where the loudness and the
-- clipping came from. This leaves headroom for all five, and the limiter on the master bus
-- catches what is left rather than doing the work.
local master = 0.18

--- Resolves the published waveforms. Safe to call before they have arrived.
local function assetFor(voice: string): string?
	local want = VOICES[voice]
	if not want then return nil end
	if paths[want] then return paths[want] end
	local folder = ReplicatedStorage:FindFirstChild("PlaceAssets")
	local v = folder and folder:FindFirstChild(want)
	if v and v.Value ~= "" then
		paths[want] = v.Value
		return v.Value
	end
	return nil
end

function NesEngine.setMaster(v: number)
	master = math.clamp(v, 0, 1)
	for _, ch in pairs(channels) do
		if ch.sound then ch.sound.Volume = ch.volume * master end
	end
end

--- A voice. `mix` says which channel it belongs to and defaults to the music, because
--- almost everything played on a 2A03 here is the tune.
---
--- Not everything. The intro's rocket is a 2A03 noise sweep and it is an effect, not music:
--- on the music channel it sat under the same fade that brings the tune up from silence, and
--- was inaudible for exactly the beat it exists for.
function NesEngine.createChannel(id: string, mix: string?)
	if channels[id] then return channels[id] end
	local sound = Instance.new("Sound")
	sound.Name = "Nes_" .. id
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService or workspace
	-- Either way it is under the master, so the slider still governs it.
	if mix == "sfx" then Mixer.sfx(sound) else Mixer.music(sound) end
	channels[id] = { sound = sound, voice = nil, volume = 0, playing = false }
	return channels[id]
end

--- Which waveform this channel is playing. Changing it mid-note keeps the note.
function NesEngine.setInstrument(id: string, voice: string)
	local ch = channels[id] or NesEngine.createChannel(id)
	if ch.voice == voice then return end
	local asset = assetFor(voice)
	if not asset then return end
	ch.voice = voice
	ch.sound.SoundId = asset
	-- A SoundId set while playing restarts it; the note is re-established by whoever
	-- changed the instrument, which for a duty change is the same frame.
	if ch.playing then ch.sound:Play() end
end

--- Speed for a wanted frequency, which depends on what the sample holds.
local function speedFor(ch, freq: number): number
	if ch.voice == "noise" then
		return math.clamp(freq / NOISE_HZ, 0.002, 4)
	end
	return math.clamp(freq / BASE_HZ, 0.002, 16)
end

function NesEngine.noteOn(id: string, freq: number, volume: number)
	local ch = channels[id]
	if not ch or not ch.voice then return end
	if freq <= 0 then
		NesEngine.noteOff(id)
		return
	end
	ch.volume = math.clamp(volume or 0, 0, 1)
	ch.sound.PlaybackSpeed = speedFor(ch, freq)
	ch.sound.Volume = ch.volume * master
	if not ch.playing then
		ch.playing = true
		ch.sound:Play()
	end
end

function NesEngine.setPitch(id: string, freq: number)
	local ch = channels[id]
	if not ch or not ch.voice or freq <= 0 then return end
	ch.sound.PlaybackSpeed = speedFor(ch, freq)
end

function NesEngine.setVolume(id: string, volume: number)
	local ch = channels[id]
	if not ch then return end
	ch.volume = math.clamp(volume or 0, 0, 1)
	ch.sound.Volume = ch.volume * master
end

--- Silences a channel without stopping it.
---
--- Stopping and starting a looping sample on every note gives a click at each edge, and the
--- APU does not restart its sequence for a new note either -- it only gates the output.
function NesEngine.noteOff(id: string)
	local ch = channels[id]
	if not ch then return end
	ch.volume = 0
	ch.sound.Volume = 0
end

function NesEngine.stopAll()
	for _, ch in pairs(channels) do
		ch.volume = 0
		ch.sound.Volume = 0
		ch.sound:Stop()
		ch.playing = false
	end
end

--- True once the waveforms have arrived and a note would actually be audible.
function NesEngine.ready(): boolean
	return assetFor("pulse12") ~= nil and assetFor("noise") ~= nil
end

return NesEngine

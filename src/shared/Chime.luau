-- The chime: a quick climb up a major chord on the town's 2A03 (shared/NesEngine.luau), out of the
-- waveforms that are already published -- no clip of its own to make or publish.
--
-- A thin pulse with the classic NES echo, the same notes a step behind on the other pulse, quieter
-- and an octave down, which is how a two-voice chip makes one voice sound bigger. The top note rings
-- and falls away. Played for a kill streak (Combat.client.luau), and whenever something comes into
-- your bag -- a fish caught, a rod handed over, a thing bought (ItemChime.client.luau).
--
-- Client-side: sound is heard by the machine it is played on. One chime at a time; a second one
-- mid-chime starts it again.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local NesEngine = require(ReplicatedStorage:WaitForChild("NesEngine"))

local Chime = {}

local LEAD, ECHO = "streakLead", "streakEcho"
local STEP = 0.055                                        -- seconds a note
local NOTES = { 523.25, 659.25, 783.99, 1046.50, 1318.51, 1567.98, 2093.00 }   -- C5 E5 G5 C6 E6 G6 C7
local RING = 0.35                                         -- how long the top note takes to fall away

local startedAt = nil                                     -- when the chime playing now started
local lift = 1                                            -- how far the chime playing now is transposed
local stepping = nil

local function ready()
	if not NesEngine.ready() then return false end
	NesEngine.createChannel(LEAD, "sfx")
	NesEngine.createChannel(ECHO, "sfx")
	NesEngine.setInstrument(LEAD, "pulse25")
	NesEngine.setInstrument(ECHO, "pulse12")
	return true
end

-- Stepped every frame rather than on timers, so a second chime mid-chime simply starts it again.
local function step()
	if not startedAt then return end
	local t = os.clock() - startedAt
	local n = #NOTES
	local run = n * STEP
	if t < run then
		local i = math.floor(t / STEP) + 1
		local within = (t % STEP) / STEP
		NesEngine.noteOn(LEAD, NOTES[i] * lift, 1 - 0.35 * within)
	elseif t < run + RING then
		local u = (t - run) / RING
		NesEngine.noteOn(LEAD, NOTES[n] * lift, (1 - u) ^ 2)
	else
		NesEngine.noteOff(LEAD)
	end
	-- The echo, a step behind.
	local e = t - STEP
	if e >= 0 and e < run then
		local i = math.floor(e / STEP) + 1
		NesEngine.noteOn(ECHO, NOTES[i] * lift / 2, 0.45)
	elseif e >= run and e < run + RING then
		local u = (e - run) / RING
		NesEngine.noteOn(ECHO, NOTES[n] * lift / 2, 0.45 * (1 - u) ^ 2)
	elseif e >= run + RING then
		NesEngine.noteOff(ECHO)
		startedAt = nil
	end
end

--- Plays the chime, `semitones` up (or down) from its own key.
function Chime.play(semitones)
	if not ready() then return end
	lift = 2 ^ ((tonumber(semitones) or 0) / 12)
	startedAt = os.clock()
	if not stepping then stepping = RunService.Heartbeat:Connect(step) end
end

return Chime

-- A VGM player for the NES APU.
--
-- VGM is a log of writes to a sound chip with waits between them, so playing one is not
-- synthesis -- it is replaying the register writes at the right times and asking the chip
-- what note that means. The chip here is NesEngine, which plays the real waveforms.
--
-- Only the 2A03 is handled. VGM covers dozens of chips and a general player is mostly
-- branches for chips a given file never mentions; this reads the header, refuses anything
-- that is not a 2A03 log, and stays small enough to follow.
local Vgm = {}

local CPU_HZ = 1789773          -- the NTSC 2A03 clock, from the file's own header
local SAMPLE_HZ = 44100         -- VGM measures every wait in 44100ths of a second
local MAX_BEHIND = SAMPLE_HZ // 2       -- half a second; past that, let the gap go
local CATCHING_UP = SAMPLE_HZ // 20     -- 50ms: more than three frames, so not an ordinary one
local GUARD = 40000                     -- enough iterations to spend MAX_BEHIND in one go

-- The noise channel's sixteen periods, in CPU cycles. NTSC values.
local NOISE_PERIOD = { 4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068 }

-- ---- base64 ------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local INV = {}
for i = 1, #B64 do INV[string.byte(B64, i)] = i - 1 end

--- Decodes base64 to a byte string.
---
--- Built in chunks with table.concat rather than by appending to a string: Luau strings are
--- immutable, so appending in a loop over fifty thousand bytes copies the whole thing every
--- time and turns a fast job into a visible freeze.
function Vgm.decode(text: string): string
	local out, n = {}, 0
	local acc, bits = 0, 0
	for i = 1, #text do
		local c = INV[string.byte(text, i)]
		if c then
			acc = acc * 64 + c
			bits += 6
			if bits >= 8 then
				bits -= 8
				local byte = math.floor(acc / (2 ^ bits)) % 256
				-- Drop the bits just taken. Without this the accumulator grows by six bits
				-- per character for fifty thousand characters, leaves the range a double
				-- holds exactly, and starts handing back fractions -- which string.char
				-- rejects outright, several kilobytes into the file.
				acc = acc % (2 ^ bits)
				n += 1
				out[n] = string.char(byte)
			end
		end
	end
	return table.concat(out)
end

-- ---- the player --------------------------------------------------------------------------

local Player = {}
Player.__index = Player

local function u32(d: string, at: number): number
	local a, b, c, e = string.byte(d, at, at + 3)
	return a + b * 256 + c * 65536 + e * 16777216
end

--- Reads the header and gets ready to play. Returns nil and a reason if it is not for us.
function Vgm.new(data: string, engine)
	if #data < 0x40 or string.sub(data, 1, 4) ~= "Vgm " then
		return nil, "not a VGM file"
	end
	local nesClock = #data >= 0x88 and u32(data, 0x85) or 0
	if nesClock == 0 then
		return nil, "no NES APU in this log"
	end
	local dataOffset = u32(data, 0x35)
	local start = dataOffset > 0 and (0x34 + dataOffset) or 0x40
	local loopOffset = u32(data, 0x1d)
	local self = setmetatable({
		data = data,
		engine = engine,
		start = start + 1,                      -- Luau strings index from 1
		loop = loopOffset > 0 and (0x1c + loopOffset + 1) or (start + 1),
		pos = start + 1,
		owed = 0,                               -- samples still to wait through
		backlog = 0,                            -- ... and time a long frame could not spend
		playing = false,
		regs = {},                              -- $4000..$4017 as last written
		enable = 0,
		state = {
			pulse1 = { id = "p1", timer = 0, duty = 0, vol = 0, on = false },
			pulse2 = { id = "p2", timer = 0, duty = 0, vol = 0, on = false },
			triangle = { id = "tri", timer = 0, on = false },
			noise = { id = "noise", idx = 0, vol = 0, on = false },
		},
	}, Player)
	for _, ch in pairs(self.state) do engine.createChannel(ch.id) end
	engine.setInstrument("tri", "triangle")
	engine.setInstrument("noise", "noise")
	engine.setInstrument("p1", "pulse12")
	engine.setInstrument("p2", "pulse12")
	return self
end

local DUTY_VOICE = { [0] = "pulse12", [1] = "pulse25", [2] = "pulse50", [3] = "pulse75" }

--- Turns the register file into notes.
function Player:refresh()
	local e, st = self.engine, self.state

	for name, bit, base in (function()
		local list = { { "pulse1", 1, 0x00 }, { "pulse2", 2, 0x04 } }
		local i = 0
		return function()
			i += 1
			if list[i] then return list[i][1], list[i][2], list[i][3] end
			return nil
		end
	end)() do
		local ch = st[name]
		local r0 = self.regs[base] or 0
		local lo = self.regs[base + 2] or 0
		local hi = self.regs[base + 3] or 0
		ch.timer = (hi % 8) * 256 + lo
		ch.duty = math.floor(r0 / 64)
		-- Bit 4 is "constant volume"; with it clear the low nibble is an envelope period
		-- rather than a level, and the envelope starts at full. Treating that as full volume
		-- is close enough here -- the decay is a per-frame ramp we do not model, and every
		-- note in this track is re-triggered often enough that it never gets far.
		ch.vol = (r0 % 16) / 15
		if math.floor(r0 / 16) % 2 == 0 then ch.vol = 1 end
		local live = (self.enable % (2 ^ bit)) >= (2 ^ (bit - 1)) and ch.timer >= 8
		e.setInstrument(ch.id, DUTY_VOICE[ch.duty] or "pulse12")
		if live then
			e.noteOn(ch.id, CPU_HZ / (16 * (ch.timer + 1)), ch.vol)
		else
			e.noteOff(ch.id)
		end
	end

	do
		local ch = st.triangle
		ch.timer = ((self.regs[0x0b] or 0) % 8) * 256 + (self.regs[0x0a] or 0)
		local live = self.enable % 8 >= 4 and ch.timer >= 2 and (self.regs[0x08] or 0) > 0
		if live then
			-- The triangle has no volume control on the chip: it is on or it is off.
			e.noteOn(ch.id, CPU_HZ / (32 * (ch.timer + 1)), 0.9)
		else
			e.noteOff(ch.id)
		end
	end

	do
		local ch = st.noise
		local r = self.regs[0x0e] or 0
		ch.idx = r % 16
		local r0 = self.regs[0x0c] or 0
		ch.vol = (r0 % 16) / 15
		if math.floor(r0 / 16) % 2 == 0 then ch.vol = 1 end
		local live = self.enable % 16 >= 8
		if live then
			e.noteOn(ch.id, CPU_HZ / NOISE_PERIOD[ch.idx + 1], ch.vol * 0.8)
		else
			e.noteOff(ch.id)
		end
	end
end

--- Runs commands until the next wait, or until the log ends.
function Player:step(): boolean
	local d, n = self.data, #self.data
	while self.pos <= n do
		local c = string.byte(d, self.pos)
		if c == 0xB4 then                       -- write to the 2A03
			local reg = string.byte(d, self.pos + 1)
			local val = string.byte(d, self.pos + 2)
			self.pos += 3
			if reg == 0x15 then self.enable = val else self.regs[reg] = val end
			self.dirty = true
		elseif c == 0x61 then                   -- wait n samples
			self.owed += string.byte(d, self.pos + 1) + string.byte(d, self.pos + 2) * 256
			self.pos += 3
			return true
		elseif c == 0x62 then
			self.owed += 735
			self.pos += 1
			return true
		elseif c == 0x63 then
			self.owed += 882
			self.pos += 1
			return true
		elseif c >= 0x70 and c <= 0x7F then
			self.owed += (c - 0x70) + 1
			self.pos += 1
			return true
		elseif c == 0x66 then                   -- end of the log
			self.pos = self.loop
			return true
		elseif c == 0x67 then                   -- a data block we have no use for
			self.pos += 7 + u32(d, self.pos + 3)
		elseif c == 0x50 then
			self.pos += 2
		elseif c == 0x52 or c == 0x53 or c == 0xB3 or c == 0xB5 then
			self.pos += 3
		else
			self.pos += 1
		end
	end
	self.pos = self.loop
	return true
end

function Player:play()
	self.playing = true
	self.backlog = 0        -- nothing is owed from before you pressed play
end

function Player:stop()
	self.playing = false
	self.engine.stopAll()
end

--- Advances the log by dt seconds.
---
--- Time that will not fit in one call is carried, not dropped. This used to give up after
--- a fixed number of iterations and throw the rest away, and the caller clamped dt on top
--- of that -- so every long frame moved the whole rest of the track later, and the music
--- drifted further behind the longer a session ran.
function Player:update(dt: number)
	if not self.playing then return end
	local budget = dt * SAMPLE_HZ + self.backlog
	-- Past about half a second there is nothing worth catching up to, and pretending
	-- otherwise would fast-forward through a bar after every stall. Let it go on purpose.
	if budget > MAX_BEHIND then budget = MAX_BEHIND end
	-- Catching up rather than playing along. refresh() reads the whole of its answer out
	-- of self.regs, so applying it once at the end of a burst gives the same registers as
	-- applying it after every write -- without retriggering every note in the gap, which
	-- is what made a caught-up frame arrive as noise.
	local catching = budget > CATCHING_UP
	local pending = false
	local guard = 0
	while budget > 0 and guard < GUARD do
		guard += 1
		if self.owed > 0 then
			local take = math.min(self.owed, budget)
			self.owed -= take
			budget -= take
		else
			self.dirty = false
			self:step()
			if self.dirty then
				if catching then pending = true else self:refresh() end
			end
		end
	end
	if pending then self:refresh() end
	self.backlog = math.max(budget, 0)
end

return Vgm

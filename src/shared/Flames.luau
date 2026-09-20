-- What a fire is made of: a picture, and a set of colours.
--
-- Shared because two very different things burn now -- the braziers around the square and
-- the torches you can carry -- and a PLSX flame has to be the same PLSX flame in both. The
-- caller supplies the emitter; this says what colour it is and, when a fire is more than one
-- colour, how many emitters that actually takes.
--
-- ---- why several emitters ------------------------------------------------------------
-- A ColorSequence runs over a particle's lifetime, so one emitter is a fire that *changes*
-- colour as it rises -- never several colours burning together. Every gradient tried that
-- way washed into one smear. For colours standing side by side each tongue has to be flat
-- and the mixing has to happen in the air, and in Roblox that is one emitter per colour in
-- the same part, each taking a share of the rate. `light()` below does the cloning.
--
-- ---- why the colours are not the logos' -----------------------------------------------
-- Fire is partly additive (LightEmission), so a few hundred overlapping tongues climb the
-- low channels until the high one clips: a colour desaturates towards white on its way. Each
-- entry here is therefore a little deeper in its weak channels than the file it came off,
-- and stacks back up to the mark's own colour. Sampled from scripts/logos/*.png, not guessed.
local Flames = {}

-- Fires that really do change colour as they rise. One emitter each. Kept as stops rather
-- than as built ColorSequences so that the first colour of one can still be read back --
-- something has to be painted the colour of the fire it holds.
Flames.ramps = {
	-- Cold: what the brazier this cage came from was burning.
	ice = { {0, 220,255,255}, {0.12, 120,235,255}, {0.3, 40,190,255},
	        {0.6, 20,120,240}, {1, 40,40,200} },
	-- An ordinary fire, for anyone who wants one.
	ember = { {0, 255,240,190}, {0.12, 255,200,60}, {0.3, 255,130,30},
	          {0.6, 220,60,20}, {1, 90,20,10} },
	-- INC has no gradient -- it is the greenest logo in crypto and that is the point.
	--
	-- Its strokes measure #00FF55 to #00FF99, which is spring green: green with real blue in
	-- it. Taking that blue back out to make it "greener" is what stopped it reading as INC at
	-- all -- pure #00FF00 is a different colour. So this is the mark's own green, flat the
	-- whole way up the way the logo is flat, with only the last tenth going white where the
	-- tongues thin out and burn through.
	inc = { {0, 0,255,30}, {0.92, 0,255,42}, {1, 245,255,250} },
}

-- Fires of several colours at once. One flat emitter per entry, sharing the rate.
Flames.tongues = {
	-- hex.com's own banner: amber into red into pink into magenta, weighted to the red end
	-- because that is the half of the banner that reads as HEX.
	hex = { {255,140,0}, {240,55,15}, {235,15,45}, {248,5,100}, {255,0,160} },
	-- The sweep this engine paints its characters in.
	pulse = { {255,10,60}, {245,10,150}, {150,20,245}, {40,50,255}, {0,190,245} },
	-- An X of two solid strokes, one green and one red, with nothing in between them -- so
	-- there is nothing in between them here either.
	pulsex = { {0,255,60}, {255,0,32} },
	-- ProveX's five, in the mark's own order.
	provex = { {250,80,4}, {222,30,150}, {138,18,232}, {30,40,255}, {0,175,240} },
}

local function sequence(stops)
	local kp = {}
	for _, s in ipairs(stops) do
		table.insert(kp, ColorSequenceKeypoint.new(s[1], Color3.fromRGB(s[2], s[3], s[4])))
	end
	return ColorSequence.new(kp)
end

--- The one colour that stands for a fire: what to paint the thing that is burning.
function Flames.mark(key)
	local solids = Flames.tongues[key]
	if solids then
		local c = solids[1]
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	local stops = Flames.ramps[key]
	if stops then
		local c = stops[1]
		return Color3.fromRGB(c[2], c[3], c[4])
	end
	return Color3.fromRGB(255, 160, 40)
end

--- True if anything here burns in that colour at all.
function Flames.known(key)
	return Flames.ramps[key] ~= nil or Flames.tongues[key] ~= nil
end

--- Lights one emitter: gives it the sprite and the colours the key asks for.
---
--- Returns how many emitters the fire ended up as, which is one for a ramp and one per
--- colour for the rest. The emitter passed in is always the first of them; the others are
--- clones of it beside it, so whatever the map or the item authored -- rate, size, squash,
--- lifetime -- is what every tongue is made of.
function Flames.light(emitter, key, texture)
	if texture and texture ~= "" then emitter.Texture = texture end
	local solids = Flames.tongues[key]
	if solids then
		local each = math.max(1, math.floor(emitter.Rate / #solids + 0.5))
		local into = emitter.Parent
		for i, rgb in ipairs(solids) do
			local e = i == 1 and emitter or emitter:Clone()
			e.Color = ColorSequence.new(Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
			e.Rate = each
			if i > 1 then e.Parent = into end
		end
		return #solids
	end
	local stops = Flames.ramps[key]
	if stops then
		emitter.Color = sequence(stops)
		return 1
	end
	return 0
end

--- Every emitter named "Flame" under `model`, lit in the colour its `Flame` attribute names.
function Flames.lightModel(model, texture)
	local key = model:GetAttribute("Flame")
	if key == nil then return 0 end
	key = tostring(key)
	if not Flames.known(key) then
		warn(("flames: %s asks for a %s flame and there is no such thing"):format(model.Name, key))
		return 0
	end
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		-- Sparks keep the engine's round spot and their own colours: a spark is a spark, and
		-- a tongue of flame drawn a sixteenth of a stud across is a blur.
		if d:IsA("ParticleEmitter") and d.Name == "Flame" then
			n += Flames.light(d, key, texture)
		end
	end
	return n
end

return Flames

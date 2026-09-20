-- Which accessories can be swung, and what each one does when it is.
--
-- Shared because both ends need it and they need to agree. The server decides what a click
-- actually does; the client only needs to know whether the thing in your hand is worth
-- sending a click about at all, and a client that says it is armed proves nothing either
-- way. Kept in two lists, they drifted the first time a weapon was added: the candles went
-- in on the server and not on the client, so clicking with one did nothing at all and
-- nothing said why.
--
-- The value is the cycle of techniques a repeated click walks, so a weapon with one
-- technique simply does it every time. Their timings, damage and sounds are the server's
-- business and live in Weapons.server.luau.
local TORCHES = { "PLS Torch", "PLSX Torch", "HEX Torch", "PRVX Torch", "INC Torch" }

local Weapons = {
	-- Held like a dagger, so it swings like one: slash, then thrust, alternating.
	["Spoonie"] = { "slash", "thrust" },
	-- Five studs of shaped steel, cutting the eight a stroke a click: down to his left, then
	-- back down to his right, alternating.
	["BFS 9000"] = { "hachimonji", "hachimonjiBack" },
	-- One swing each, and then they are spent.
	["Red Candle"] = { "candle" },
	["Green Candle"] = { "candle" },
	-- The Gold-Topped Cane is a magic wand: raise it, lunge, and a ball of colour leaves the tip.
	["Cane"] = { "cast" },
}

-- Every torch swings the same. They differ in what colour the burn they leave is.
for _, name in ipairs(TORCHES) do
	Weapons[name] = { "firethrust" }
end

Weapons.torches = TORCHES

-- Which ones charge: the button held down charges it and letting go fires it, so the client sends
-- the release as well as the press. Not in the table above, which is weapon -> cycle and is
-- walked as such.
Weapons.charged = { ["Cane"] = true }

return Weapons

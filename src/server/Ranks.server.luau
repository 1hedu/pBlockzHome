-- What the five tokens are actually worth to anybody, read off DexScreener.
--
-- The braziers around the square burn one fire each -- PLS, PLSX, HEX, PRVX, INC -- and the
-- five torches are those same fires on a stick. This decides how tall each fire stands and
-- how fast its torch burns, from the volume that token traded against real money in the last
-- six hours. Brazier.server.luau and Weapons.server.luau read the ranks through Ranks.luau.
--
-- ---- why a rank and not the number ----------------------------------------------------
-- Sizing a flame in proportion to volume would mean two tokens a few per cent apart looked
-- identical and one an order of magnitude ahead was off the top of the screen. So the five
-- are RANKED and the ranks are evenly spaced: a rank above always looks a rank above,
-- whatever the numbers did overnight, and the square reads as a chart you can stand in.
--
-- ---- why this is a place script, and not the client's --------------------------------
-- It used to be Dex.gd, GDScript on the host, because nothing inside the sandbox could reach
-- the network. That made the town's braziers a feature of the CLIENT: load this place with
-- any other client and the fires stood flat, because the thing that ranked them shipped with
-- the program rather than with the place. A place has to carry its own rules.
--
-- HttpService is what Roblox gives you for exactly this, with exactly the restrictions that
-- make it safe, and now so do we: the SERVER only, and only when whoever runs it has turned
-- it on. So it is here, in the place, where it travels with the town -- and a client still
-- cannot reach the network, which is the part that was never negotiable.
--
-- It holds nothing. The ranks are re-read every few minutes, published as an attribute, and
-- forgotten when the process stops.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ranks = require(ReplicatedStorage:WaitForChild("Ranks"))

local API = "https://api.dexscreener.com/latest/dex/tokens/"
-- Six hours of volume moves over hours, not seconds -- but faster than a day's does, which
-- is the point of using it.
local EVERY = 300

-- Which token each fire stands for, by contract address on PulseChain. These lived in
-- dex-tokens.json when this was GDScript, to keep an address out of a program that had to be
-- rebuilt. A place script IS data -- it is published to the chain and fetched by content
-- hash -- so there is nothing left for the indirection to buy.
--
-- PLS is WPLS: the native coin does not trade as itself on a DEX, and its wrapper is what
-- every pair is actually against.
local TOKENS = {
	pulse  = "0xA1077a294dDE1B09bB078844df40758a5D0f9a27",
	pulsex = "0x95B303987A60C71504D99Aa1b13B4DA07b0790ab",
	hex    = "0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39",
	provex = "0xF6f8Db0aBa00007681F8fAF16A0FDa1c9B030b11",
	inc    = "0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d",
}

--- The last six hours' volume on this token's deepest pool.
---
--- Six hours rather than twenty-four because the square is meant to read as what is busy
--- NOW. A day's volume is most of yesterday for most of today, so the flames would spend
--- the morning describing the evening before.
---
--- Deepest by LIQUIDITY, not by volume: a pool with a thousand dollars in it can report an
--- enormous day because the same dollar went round it a hundred times, and that is not a
--- market. The deepest pool is the one a price actually means something on.
---
--- Whatever it is quoted in. This used to insist on a stablecoin pair, on the grounds that
--- only a price in dollars is comparable -- but on PulseChain the real depth for most of
--- these is against WPLS, so the rule threw away the honest pools and kept the thin ones,
--- and a token with no stablecoin pair at all ranked last no matter how heavily it traded.
--- DexScreener reports both liquidity and volume in USD regardless of the quote token, so
--- the comparison holds without the filter and the filter only ever cost us accuracy.
---
--- Returns nil when there are no pools at all, which is not zero: a token nobody has
--- paired has no measurable volume, where zero would say it traded nothing.
local function volumeOf(address)
	local ok, body = pcall(function() return HttpService:GetAsync(API .. address) end)
	if not ok then
		warn("[ranks] could not read " .. address .. ": " .. tostring(body))
		return nil
	end
	local parsed, doc = pcall(function() return HttpService:JSONDecode(body) end)
	if not parsed or type(doc) ~= "table" or type(doc.pairs) ~= "table" then return nil end
	local best, deepest = nil, -1
	for _, pair in ipairs(doc.pairs) do
		if type(pair) == "table" then
			local liq = type(pair.liquidity) == "table" and tonumber(pair.liquidity.usd) or 0
			if liq > deepest then
				deepest = liq
				best = type(pair.volume) == "table" and tonumber(pair.volume.h6) or 0
			end
		end
	end
	return best
end

--- Five volumes to five ranks, 1 for the busiest. Anything without a pair sits at the bottom
--- rank rather than being left out: a brazier at the height every flame used to be is simply
--- a brazier, where a brazier with no fire at all is a fault.
local function rank(volumes)
	local order = {}
	for key in pairs(volumes) do table.insert(order, key) end
	table.sort(order, function(a, b) return volumes[a] > volumes[b] end)
	local out = {}
	for _, key in ipairs(Ranks.FIRES) do out[key] = Ranks.LAST end
	for i, key in ipairs(order) do out[key] = i end
	return out
end

local function same(a, b)
	for _, key in ipairs(Ranks.FIRES) do if a[key] ~= b[key] then return false end end
	return true
end

local last = {}
while true do
	local volumes = {}
	local any = false
	for _, key in ipairs(Ranks.FIRES) do
		local address = TOKENS[key]
		if address then
			local v = volumeOf(address)
			if v then volumes[key] = v; any = true end
		end
	end
	if any then
		local ranked = rank(volumes)
		if not same(ranked, last) then
			last = ranked
			-- Onto the same node Ranks.luau reads, as JSON, so nothing here reaches into a
			-- script and every reader goes through one door.
			Ranks.node():SetAttribute("Ranks", HttpService:JSONEncode(ranked))
			local said = {}
			for _, key in ipairs(Ranks.FIRES) do
				table.insert(said, string.format("%s=%d", key, ranked[key]))
			end
			print("[ranks] ranks by six hours' volume on each token's deepest pool: "
				.. table.concat(said, ", "))
		end
	end
	task.wait(EVERY)
end

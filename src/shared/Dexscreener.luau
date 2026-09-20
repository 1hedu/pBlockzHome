-- Reading pools off DexScreener, and shaping them into rows a board can draw.
--
-- This lived in the client -- a hundred and thirty lines of it in Wallet.gd, with its own
-- copy of the endpoint and its own idea of what a row is. Same mistake as the brazier
-- ranking and the eighteen hardcoded actions: a place's feature built into the program that
-- happens to load it, so it worked in this client and nowhere else. A town that wants a
-- screener should carry one.
--
-- Server only, and not by politeness: HttpService refuses a client outright. That is the
-- right shape anyway -- thirty players standing at one board should be one request, not
-- thirty, and the number they are looking at should be the same number.
local HttpService = game:GetService("HttpService")

local Dex = {}

Dex.BY_TOKEN = "https://api.dexscreener.com/latest/dex/tokens/"
-- There is a /search?q= endpoint and this deliberately does not use it.
--
-- A search box wired to it would make every keystroke a request from the operator's box,
-- on their bandwidth and against their API quota: thirty people at the board searching
-- different things is thirty requests, where the board itself is one request serving all
-- thirty. Worse, it turns the server into a proxy for whatever a place decides to ask
-- for, with the operator's address on it and nothing but the place's good manners
-- deciding how often.
--
-- So searching filters what has already been fetched. It costs no requests, adds no
-- failure of its own -- it cannot break separately from the board, because it is only
-- reading what the board already holds -- and it cannot be aimed at anything. If the
-- board is empty because the fetch failed, search finds nothing, which is correct: there
-- is nothing to find.

--- 1234567.8 -> "1.23M". Thousands of dollars at full width are a column nobody reads.
function Dex.compact(v)
	v = tonumber(v) or 0
	local sign = v < 0 and "-" or ""
	v = math.abs(v)
	if v >= 1e9 then return ("%s%.2fB"):format(sign, v / 1e9) end
	if v >= 1e6 then return ("%s%.2fM"):format(sign, v / 1e6) end
	if v >= 1e3 then return ("%s%.1fK"):format(sign, v / 1e3) end
	return ("%s%.0f"):format(sign, v)
end

--- A price at whatever precision it actually needs. A token worth 0.0000086 rounded to two
--- places is zero, and zero is not a price.
function Dex.price(text)
	local v = tonumber(text) or 0
	if v == 0 then return "-" end
	if v >= 1 then return ("$%.4f"):format(v) end
	if v >= 0.0001 then return ("$%.6f"):format(v) end
	return ("$%.10f"):format(v)
end

function Dex.age(ms)
	ms = tonumber(ms) or 0
	if ms <= 0 then return "-" end
	local secs = math.floor(os.time() - ms / 1000)
	if secs < 0 then return "-" end
	if secs < 3600 then return ("%dm"):format(math.max(1, math.floor(secs / 60))) end
	if secs < 86400 then return ("%dh"):format(math.floor(secs / 3600)) end
	if secs < 86400 * 365 then return ("%dd"):format(math.floor(secs / 86400)) end
	return ("%dy"):format(math.floor(secs / (86400 * 365)))
end

--- One pair as the board wants it, or nil for anything not on this chain.
function Dex.row(p, chain)
	if type(p) ~= "table" then return nil end
	if chain and tostring(p.chainId) ~= chain then return nil end
	local base = type(p.baseToken) == "table" and p.baseToken or {}
	local quote = type(p.quoteToken) == "table" and p.quoteToken or {}
	local liq = type(p.liquidity) == "table" and p.liquidity or {}
	local vol = type(p.volume) == "table" and p.volume or {}
	local chg = type(p.priceChange) == "table" and p.priceChange or {}
	local txns = type(p.txns) == "table" and p.txns or {}
	local day = type(txns.h24) == "table" and txns.h24 or {}
	return {
		pair = ("%s / %s"):format(tostring(base.symbol or "?"), tostring(quote.symbol or "?")),
		dex = tostring(p.dexId or ""),
		price = Dex.price(p.priceUsd),
		price_raw = tonumber(p.priceUsd) or 0,
		age = Dex.age(p.pairCreatedAt),
		buys = tonumber(day.buys) or 0,
		sells = tonumber(day.sells) or 0,
		volume = Dex.compact(vol.h24),
		liquidity = Dex.compact(liq.usd),
		liquidity_raw = tonumber(liq.usd) or 0,
		fdv = Dex.compact(p.fdv),
		m5 = tonumber(chg.m5) or 0,
		h1 = tonumber(chg.h1) or 0,
		h6 = tonumber(chg.h6) or 0,
		h24 = tonumber(chg.h24) or 0,
		url = tostring(p.url or ""),
	}
end

--- Fetch one url and hand back its `pairs`, or nil. Never raises: DexScreener being down
--- is a quiet board, not a broken town.
function Dex.pairs(url)
	local ok, body = pcall(function() return HttpService:GetAsync(url) end)
	if not ok then return nil, tostring(body) end
	local parsed, doc = pcall(function() return HttpService:JSONDecode(body) end)
	if not parsed or type(doc) ~= "table" then return nil, "unreadable answer" end
	if type(doc.pairs) == "table" then return doc.pairs end
	return {}
end

--- Rows from several urls at once, de-duplicated by pool and sorted deepest first.
---
--- Deepest first because a price with nothing behind it is the number that gets people
--- hurt, and it is the column everybody skips.
---
--- One request per token rather than the comma-separated form: the endpoint takes a list,
--- but caps what it returns across the WHOLE answer -- three tokens asked separately gave
--- 81 pairs and the same three together gave 29. A board missing two thirds of the market
--- is not worth the saved round trips.
function Dex.rows(urls, chain, limit)
	local rows, seen = {}, {}
	for _, url in ipairs(urls) do
		local pairs_ = Dex.pairs(url)
		for _, p in ipairs(pairs_ or {}) do
			local addr = type(p) == "table" and tostring(p.pairAddress or ""):lower() or ""
			-- The same pool comes back under both of its tokens.
			if addr ~= "" and not seen[addr] then
				local row = Dex.row(p, chain)
				if row then
					seen[addr] = true
					table.insert(rows, row)
				end
			end
		end
	end
	table.sort(rows, function(a, b) return a.liquidity_raw > b.liquidity_raw end)
	if limit and #rows > limit then
		for i = #rows, limit + 1, -1 do rows[i] = nil end
	end
	return rows
end

--- Rows matching a typed query: the pair, either symbol, or the exchange.
---
--- Over what is already on the board, never a fresh request. An empty query is every
--- row, so clearing the box puts the board back rather than emptying it.
function Dex.filter(rows, query)
	local q = tostring(query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if q == "" then return rows end
	local out = {}
	for _, r in ipairs(rows or {}) do
		local hay = (tostring(r.pair) .. " " .. tostring(r.dex)):lower()
		if hay:find(q, 1, true) then table.insert(out, r) end
	end
	return out
end

return Dex

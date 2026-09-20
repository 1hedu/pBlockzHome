-- Doug, at the far end of the trading house counter: the pair screener.
--
-- Rebh next door quotes you one route and points at app.pulsex.com to trade it. Doug
-- does the other half of the job -- every pool at once, sorted, so you can see which
-- of them has anything in it. Neither of them is an exchange and neither pretends to
-- be: the numbers are read straight off the pairs, and the trading happens elsewhere.
--
-- Depth is the column that matters and the one people skip. A pool with nothing in it
-- will quote you a beautiful price and then take your money, so it is sorted on
-- liquidity by default rather than on price.
--
-- ---- why this is the place's job now ------------------------------------------------
-- The board used to be built in the client: a hundred and thirty lines of Wallet.gd with
-- its own copy of the endpoint, its own idea of a row, and its own list of tokens. That
-- made Doug a feature of the PROGRAM -- load this town with any other client and the
-- counter stands empty, because the thing that filled it shipped with the binary. Same
-- mistake as the brazier ranking, and the same fix: a place carries its own rules.
--
-- ---- one fetch, not one per player ---------------------------------------------------
-- The rows are fetched here, on the server, on a timer, and everyone at the counter reads
-- the same set. Thirty people standing at the board is one request, not thirty -- and the
-- number two people are looking at is the same number.
--
-- Searching does NOT fetch. It filters what is already here. A search box wired to the
-- /search endpoint would make every keystroke a request from the operator's box, on their
-- bandwidth and against their quota, and would turn the server into a proxy aimed by
-- whoever is typing. See shared/Dexscreener.luau, which says so at more length.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Ledger = require(script.Parent.Ledger)
local Dexscreener = require(ReplicatedStorage:WaitForChild("Dexscreener"))

local remote = Instance.new("RemoteEvent")
local NAME = "Doug - Dexscreener"

remote.Name = "ScreenerRemote"
remote.Parent = ReplicatedStorage

local watching = {}        -- players with the board open, so it refreshes in place
local queries = {}         -- what each of them has typed; theirs alone
local rows = {}            -- the last good fetch, shared by everybody
local note = ""            -- why the board is empty, when it is
local fetched = false

-- Which pools to show. Named by the place, because which market a screener screens is an
-- editorial choice about this town rather than something its client should decide.
local WATCH = {
	"0x95B303987A60C71504D99Aa1b13B4DA07b0790ab",   -- PLSX
	"0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39",   -- HEX
	"0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d",   -- INC
	"0x6B175474E89094C44Da98b954EedeAC495271d0F",   -- pDAI
	"0xA1077a294dDE1B09bB078844df40758a5D0f9a27",   -- WPLS
}
local EVERY = 120          -- pools move over minutes, and this is thirty people's one look
local KEEP = 40            -- more rows than anybody reads down a screen

local function board(player)
	if not fetched then
		return { loading = true, rows = {} }
	end
	local shown = Dexscreener.filter(rows, queries[player])
	return {
		loading = false,
		rows = shown,
		query = queries[player] or "",
		matched = #shown,
		total = #rows,
		source = "dexscreener.com",
		network = "PulseChain mainnet",
		note = (#rows > 0 and #shown == 0)
			and ("Nothing here matches \"%s\"."):format(tostring(queries[player]))
			or note,
		site = "app.pulsex.com",
	}
end

local function push(player)
	remote:FireClient(player, "board", board(player))
end

local function pushAll()
	for player in pairs(watching) do
		if player.Parent then push(player) end
	end
end

-- E opens it, and E closes it again. It used to push a fresh board every time, so
-- pressing it at an open window looked like a flicker and the only way out was to walk
-- away -- which is not what a key that opened something should do.
Ledger.onTalk("Screener", function(player)
	if watching[player] then
		watching[player] = nil
		remote:FireClient(player, "shut")
		return
	end
	watching[player] = true
	push(player)
end)

remote.OnServerEvent:Connect(function(player, action, arg)
	if action == "open" then
		watching[player] = true
		push(player)
	elseif action == "close" then
		watching[player] = nil
	elseif action == "search" then
		-- One person's search is one person's business: it changes what THEY see and
		-- costs nothing, because it only re-reads rows already fetched.
		queries[player] = tostring(arg or "")
		push(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	watching[player] = nil
	queries[player] = nil
end)

-- The fetch. Server-side because HttpService refuses a client outright, which is also the
-- shape that makes sense: one request serving everyone at the counter.
task.spawn(function()
	local urls = {}
	for _, address in ipairs(WATCH) do
		table.insert(urls, Dexscreener.BY_TOKEN .. address)
	end
	while true do
		local got = Dexscreener.rows(urls, "pulsechain", KEEP)
		if #got > 0 then
			rows = got
			note = "Mainnet, where the volume is. Rebh trades on this testnet."
			print(("board: %d pool(s), deepest %s at %s"):format(
				#rows, tostring(rows[1].pair), tostring(rows[1].liquidity)))
		elseif not fetched then
			note = "DexScreener did not answer."
		end
		fetched = true
		pushAll()
		task.wait(EVERY)
	end
end)

-- Ledger.onTalk already announces the desk; a second line here reads as two desks.

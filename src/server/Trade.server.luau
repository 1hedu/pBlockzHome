-- Rebh, at the trading house: PulseX, on this chain, for real.
--
-- The previous version of this read mainnet PulseX over a second RPC and then told you
-- to go and trade somewhere else, which made it a poster rather than an exchange. PulseX
-- is deployed on testnet v4 too, at its own addresses, so the swap here settles with the
-- same testnet PLS you buy hats with.
--
-- Two things people actually do on PulseX: swap, and run liquidity. Both are here, and
-- so is pasting in a token by address, because a list somebody else curates is not a
-- market. This script owns none of it -- every number is read off the pools by the player's
-- own machine, and every quote, swap and position is asked of the player's own wallet, which
-- shows them the transaction and signs it and pays for it, or doesn't.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ledger = require(script.Parent.Ledger)

local remote = Instance.new("RemoteEvent")
remote.Name = "TradeRemote"
remote.Parent = ReplicatedStorage

local watching = {}       -- players with the panel open
local waiting = {}        -- request number -> { player, kind }

local function market(d)
	if not d or Ledger.loading(d) then
		return { loading = true }
	end
	local px = d.pulsex
	if type(px) ~= "table" then
		return { loading = false, tokens = {}, note = "The pools did not answer." }
	end
	-- Everything the panel needs to draw itself: what can be traded, and what it is
	-- worth right now. The quote for any particular amount is asked for separately,
	-- because it depends on what has been typed.
	local tokens = {}
	for _, t in ipairs(px.tokens or {}) do
		table.insert(tokens, {
			symbol = t.symbol, address = t.address or "",
			decimals = t.decimals, name = t.name or t.symbol,
			custom = t.custom == true,
			-- What this player holds of it, read by their own machine. The card shows it over
			-- the amount box and Max fills the box from it; without it the balance line was
			-- blank and Max did nothing at all.
			balance = t.balance or "", balance_units = t.balance_units or "",
		})
	end
	local depth = {}
	for _, q in ipairs(px.quotes or {}) do
		depth[q.symbol] = { out = q.out, liquidity = q.liquidity or "", pair = q.pair or "" }
	end
	return {
		loading = false,
		tokens = tokens,
		depth = depth,
		probe = px.probe or "",
		chain_id = px.chain_id,
		router = px.router or "",
		site = px.site or "app.pulsex.com",
		gas = d.gas or "",
		can_sign = d.can_buy == true,
	}
end

local function push(player)
	remote:FireClient(player, "market", market(Ledger.data(player)))
end

-- Anything that needs their wallet: a quote, a swap, a position, a token. All of it is the
-- player's own -- their pools read at their own node, their positions, their custom tokens, their
-- signature -- so all of it goes to their machine, and the reply comes back only to them.
-- `tag` is whatever the client sent to tell this answer from the others it is waiting on: two
-- quotes for the same card can cross in flight, and the panel has to know which is the latest.
local function ask(player, kind, request, tag)
	waiting[Ledger.askFor(player, request)] = { player = player, kind = kind, tag = tag }
end

Ledger.onResult(function(n, res)
	local entry = waiting[n]
	waiting[n] = nil
	if not entry or not entry.player.Parent then return end
	if entry.tag ~= nil then res.tag = entry.tag end
	remote:FireClient(entry.player, entry.kind, res)
	-- A trade that landed changes the balances the panel is showing.
	if res.ok and (entry.kind == "swapped" or entry.kind == "pooled") then
		push(entry.player)
		ask(entry.player, "positions", { action = "positions" })
	end
end)

-- E opens it, and E closes it again. It used to push a fresh board every time, so
-- pressing it at an open window looked like a flicker and the only way out was to walk
-- away -- which is not what a key that opened something should do.
Ledger.onTalk("Trader", function(player)
	if watching[player] then
		watching[player] = nil
		remote:FireClient(player, "shut")
		return
	end
	watching[player] = true
	push(player)
	ask(player, "positions", { action = "positions" })
end)

remote.OnServerEvent:Connect(function(player, action, a, b, c, d, e)
	if type(action) ~= "string" then return end

	if action == "open" then
		watching[player] = true
		push(player)
		ask(player, "positions", { action = "positions" })

	elseif action == "close" then
		watching[player] = nil

	elseif action == "quote" then
		-- from, to, amount, slippage. Reads only; nothing is signed to price a trade.
		if type(a) ~= "string" or type(b) ~= "string" or type(c) ~= "string" then return end
		ask(player, "quoted", { action = "quote", from = a, to = b, amount = c,
			slippage = tonumber(d) or 50 })

	elseif action == "swap" then
		if type(a) ~= "string" or type(b) ~= "string" or type(c) ~= "string" then return end
		ask(player, "swapped", { action = "swap", from = a, to = b, amount = c,
			slippage = tonumber(d) or 50 })

	elseif action == "add_token" then
		if type(a) ~= "string" then return end
		ask(player, "token_added", { action = "add_token", address = a })

	elseif action == "forget_token" then
		if type(a) ~= "string" then return end
		ask(player, "token_added", { action = "forget_token", address = a })

	elseif action == "positions" then
		ask(player, "positions", { action = "positions" })

	-- The Add Liquidity card's numbers, as typed: which side was typed and how much, and the
	-- other side, the balances, the prices and the pool share come back. Reads only.
	elseif action == "pool_quote" then
		if type(a) ~= "string" or type(b) ~= "string" then return end
		ask(player, "pool_quoted", { action = "pool_quote", token = a, token_b = b,
			amount = type(c) == "string" and c or "", side = d == "b" and "b" or "a" }, tonumber(e))

	-- Both sides of the pair now, not a token and an assumed PLS. `d` is the second token,
	-- and an empty string still means the native coin, so the old PLS pairs are unchanged.
	elseif action == "add_liquidity" then
		if type(a) ~= "string" or type(b) ~= "string" then return end
		ask(player, "pooled", { action = "add_liquidity", token = a, amount = b,
			slippage = tonumber(c) or 100, token_b = type(d) == "string" and d or "" })

	elseif action == "remove_liquidity" then
		if type(a) ~= "string" then return end
		ask(player, "pooled", { action = "remove_liquidity", token = a,
			percent = tonumber(b) or 100, slippage = tonumber(c) or 100,
			token_b = type(d) == "string" and d or "" })
	end
end)

-- The pools move without anyone asking, so an open panel keeps up with its own player's reading.
Ledger.onChanged(function(who)
	for player in pairs(watching) do
		if player.Parent and (who == nil or who == player) then push(player) end
	end
end)

game:GetService("Players").PlayerRemoving:Connect(function(player) watching[player] = nil end)

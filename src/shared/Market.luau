-- Asking the market, from the client that is asking.
--
-- The board Doug keeps is one fetch on a timer, made by the server, shared by everybody at
-- the counter -- which is right: it is the same numbers for everyone and it should be read
-- once, not thirty times.
--
-- A search is not that. It is one person's question about the whole market, and it belongs
-- on the machine of the person asking: their bandwidth, their moment, nobody else's board
-- changed by it. So this is a CLIENT channel. A client script's attribute write stays on
-- that client -- it does not replicate upward -- so each player's own host answers their own
-- searches and a hosted town's operator is not in it at all.
--
-- The client owns where the answer comes from; this only says what is wanted. There is no
-- verb here that takes a URL, and a place that does not want a market never asks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Market = {}

-- Longer than the wallet's, because a search is a round trip to somebody else's server and
-- the answer is worth waiting a moment for.
local FORGET = 60

local outstanding = {}
local order = {}
local watching = false

local function node()
	local chain = ReplicatedStorage:FindFirstChild("Chain")
	if not chain then
		chain = Instance.new("Configuration")
		chain.Name = "Chain"
		chain.Parent = ReplicatedStorage
	end
	return chain
end

local function flush()
	local out = {}
	for _, n in ipairs(order) do
		local r = outstanding[n]
		if r then table.insert(out, r) end
	end
	node():SetAttribute("AskMarket", HttpService:JSONEncode(out))
end

local function settle(n)
	if outstanding[n] == nil then return end
	outstanding[n] = nil
	for i, m in ipairs(order) do
		if m == n then table.remove(order, i) break end
	end
	flush()
end

local function watchOnce(chain)
	if watching then return end
	watching = true
	chain:GetAttributeChangedSignal("MarketResult"):Connect(function()
		local raw = chain:GetAttribute("MarketResult")
		if type(raw) ~= "string" or raw == "" then return end
		local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and type(res) == "table" and res.n then settle(res.n) end
	end)
end

--- Asks, and calls `handler(result)` when it lands. Returns the number it was given.
---
--- A queue rather than one slot, for the same reason everything else here is: two questions
--- in the same breath must not wipe each other out, and typing is nothing but that.
function Market.search(query: string, handler)
	local chain = node()
	local n = (chain:GetAttribute("MarketSeq") or 0) + 1
	chain:SetAttribute("MarketSeq", n)
	watchOnce(chain)
	outstanding[n] = { n = n, search = query }
	table.insert(order, n)
	flush()
	local conn
	conn = chain:GetAttributeChangedSignal("MarketResult"):Connect(function()
		local raw = chain:GetAttribute("MarketResult")
		if type(raw) ~= "string" or raw == "" then return end
		local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and type(res) == "table" and res.n == n then
			conn:Disconnect()
			handler(res)
		end
	end)
	task.delay(FORGET, function()
		settle(n)
		pcall(function() conn:Disconnect() end)
	end)
	return n
end

return Market

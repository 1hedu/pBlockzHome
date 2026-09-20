-- This player's own wallet, asked from this player's own machine.
--
-- A player is their wallet (they signed in with it at the door), and the wallet lives on their
-- machine. So everything that touches it goes from here: reading their own balances and holdings,
-- and every write -- a purchase, a transfer, a published item, a swap, a flag -- which their own
-- wallet puts in front of them to confirm, pays for, and sends. The server holds no key and never
-- signs; when a desk on the server wants something of a player's wallet it asks that player's
-- machine (Ledger.askPlayer, and WalletBridge.client.luau carries it here).
--
-- The `Ask` channel, like the scan's and the market's: a client script's attribute write reaches
-- its own host and no further, so the request is heard by this machine's Wallet.gd alone. The
-- vocabulary is the wallet's own -- read, write, store, fetch, who, and the PulseX actions -- and
-- whatever asks, the wallet's confirm prompt reads what it is about to sign off the chain, not off
-- whatever the asking script claimed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local OwnWallet = {}

-- Longer than a person takes to read a prompt and decide.
local FORGET = 300

local outstanding = {}
local order = {}

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
	node():SetAttribute("AskWallet", HttpService:JSONEncode(out))
end

local function settle(n)
	if outstanding[n] == nil then return end
	outstanding[n] = nil
	for i, m in ipairs(order) do
		if m == n then table.remove(order, i) break end
	end
	flush()
end

local watching = false
local function watchOnce(chain)
	if watching then return end
	watching = true
	chain:GetAttributeChangedSignal("WalletResult"):Connect(function()
		local raw = chain:GetAttribute("WalletResult")
		if type(raw) ~= "string" or raw == "" then return end
		local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and type(res) == "table" and res.n then settle(res.n) end
	end)
end

--- Asks this machine's wallet, and calls `handler(result)` when it answers.
function OwnWallet.ask(request, handler)
	local chain = node()
	local n = (chain:GetAttribute("WalletSeq") or 0) + 1
	chain:SetAttribute("WalletSeq", n)
	watchOnce(chain)
	local req = table.clone(request)
	req.n = n
	outstanding[n] = req
	table.insert(order, n)
	local conn
	conn = chain:GetAttributeChangedSignal("WalletResult"):Connect(function()
		local raw = chain:GetAttribute("WalletResult")
		if type(raw) ~= "string" or raw == "" then return end
		local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and type(res) == "table" and res.n == n then
			conn:Disconnect()
			if handler then handler(res) end
		end
	end)
	flush()
	task.delay(FORGET, function()
		settle(n)
		pcall(function() conn:Disconnect() end)
	end)
	return n
end

--- Asks, and waits here for the answer. Nil if none comes inside `timeout` seconds.
function OwnWallet.request(request, timeout)
	local answer = nil
	OwnWallet.ask(request, function(res) answer = res end)
	local waited = 0
	local limit = timeout or FORGET
	while answer == nil and waited < limit do
		waited += task.wait(0.1)
	end
	return answer
end

return OwnWallet

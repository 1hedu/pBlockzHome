-- Asking the block explorer, from the client that is reading it.
--
-- Reading an explorer is a public act: no key, no signature, nothing written. On the real
-- site you browse it without connecting anything, and this is the same -- a page you asked
-- for, fetched by your own machine.
--
-- ---- why this moved off the server -----------------------------------------------------
-- It used to go the other way: the client asked the server, the server wrote the request,
-- and whichever host ran the place's server scripts went and fetched. In one process that is
-- the same machine and nobody noticed. Hosted, it means the operator fetches every page
-- every visitor opens -- their bandwidth, their address in the explorer's logs, for
-- somebody else's browsing.
--
-- The `Ask` channel is what makes the other arrangement possible: a client script's
-- attribute write reaches its own host and no further. So the page you open is read by your
-- machine, and the town's server is not in it at all.
--
-- What still belongs to the server is what the server is for: opening the window when you
-- ask Unger for it, and cutting an Engram, which is a thing about YOU rather than a page.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Scan = {}

-- A page is a couple of round trips to somebody else's indexer; a token page is three.
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
	node():SetAttribute("AskScan", HttpService:JSONEncode(out))
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
	chain:GetAttributeChangedSignal("ScanResult"):Connect(function()
		local raw = chain:GetAttribute("ScanResult")
		if type(raw) ~= "string" or raw == "" then return end
		local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and type(res) == "table" and res.n then settle(res.n) end
	end)
end

--- Asks for one page and calls `handler(page)` when it lands.
---
--- A queue rather than one slot: pressing Open on somebody's Engram is "put the window up"
--- and "go to this page" in the same breath, and one must not wipe out the other.
function Scan.page(view: string, id: string?, handler)
	local chain = node()
	local n = (chain:GetAttribute("ScanSeq") or 0) + 1
	chain:SetAttribute("ScanSeq", n)
	watchOnce(chain)
	outstanding[n] = { n = n, view = view, id = id or "" }
	table.insert(order, n)
	flush()
	local conn
	conn = chain:GetAttributeChangedSignal("ScanResult"):Connect(function()
		local raw = chain:GetAttribute("ScanResult")
		if type(raw) ~= "string" or raw == "" then return end
		local ok, res = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and type(res) == "table" and res.n == n then
			conn:Disconnect()
			handler(res)
		end
	end)
	task.delay(FORGET, function()
		-- Answered already: the page landed, settle cleared it and conn called the handler.
		if outstanding[n] == nil then return end
		settle(n)
		pcall(function() conn:Disconnect() end)
		-- A caller learns that it is no longer waiting from its handler and from nothing
		-- else, so a page that never came is handed the shape a refused page has. Dropping
		-- it silently leaves the window on "Loading..." and it never asks again.
		handler({ ok = false, message = "The explorer didn't answer in time." })
	end)
	return n
end

return Scan

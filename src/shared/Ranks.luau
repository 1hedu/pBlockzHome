-- Where each of the five tokens stands today, and what that buys it.
--
-- Dex.gd asks DexScreener what PLS, PLSX, HEX, PRVX and INC traded against real money in the
-- last six hours, on each one's deepest stablecoin pair, and publishes the ORDER as
-- ReplicatedStorage.Dex.Ranks. Rank 1 is the busiest. Nothing here reaches the network -- a
-- creator's script cannot, which is the point of the sandbox -- so this only reads what the
-- host put in the tree.
--
-- ---- why ranks and not the numbers -----------------------------------------------------
-- Sizing anything in proportion to volume would make two tokens a few per cent apart look
-- identical and put one that is an order of magnitude ahead off the top of the screen. Five
-- ranks, evenly spaced, means a rank above always LOOKS a rank above whatever the numbers did
-- overnight -- and the square becomes a chart you can stand in rather than a chart you have
-- to squint at.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Ranks = {}

Ranks.FIRES = { "pulse", "pulsex", "hex", "provex", "inc" }
Ranks.LAST = #Ranks.FIRES

--- The node the host publishes onto, made here if it has not arrived yet, so that reading
--- before the first fetch is an ordinary empty answer rather than a crash.
function Ranks.node()
	local node = ReplicatedStorage:FindFirstChild("Ranks")
	if not node then
		node = Instance.new("Configuration")
		node.Name = "Ranks"
		node.Parent = ReplicatedStorage
	end
	return node
end

--- Every fire's rank, 1 for the busiest. Anything the host has not ranked -- no address
--- configured, no stablecoin pair, the fetch not back yet -- comes out at the bottom rank,
--- which is the height every flame used to be and the slowest a torch burns. An unranked
--- token showing as the smallest fire is honest; showing as the biggest would not be.
function Ranks.all()
	local raw = Ranks.node():GetAttribute("Ranks")
	local out = {}
	for _, key in ipairs(Ranks.FIRES) do
		out[key] = Ranks.LAST
	end
	if type(raw) ~= "string" or raw == "" then return out end
	local ok, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(decoded) ~= "table" then return out end
	for key, rank in pairs(decoded) do
		local n = tonumber(rank)
		if n and out[key] ~= nil then
			out[key] = math.clamp(math.floor(n + 0.5), 1, Ranks.LAST)
		end
	end
	return out
end

function Ranks.of(key)
	return Ranks.all()[tostring(key)] or Ranks.LAST
end

--- 0 at the bottom rank, 1 at the top. What anything scaled by rank multiplies.
function Ranks.share(rank)
	if Ranks.LAST <= 1 then return 0 end
	return (Ranks.LAST - math.clamp(rank, 1, Ranks.LAST)) / (Ranks.LAST - 1)
end

--- Calls `fn()` now and again whenever the host republishes.
function Ranks.watch(fn)
	Ranks.node():GetAttributeChangedSignal("Ranks"):Connect(fn)
	task.spawn(fn)
end

return Ranks

-- Showing somebody a thing you are holding.
--
-- The block used to carry a BillboardGui with the hash printed on it, which announced
-- itself to the whole square whether or not anybody had asked. That is a placard. A
-- record is worth more when it is shown to one person who is arguing with you, so this
-- is the other shape: you pick the thing, you pick the person, and a window opens on
-- their screen. It closes when one of you walks off.
--
-- The client picks a target by clicking their character, which means the client is
-- naming both the item and the person -- so both are checked here. You can only show
-- what the chain says you hold, and only to somebody standing next to you.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ledger = require(script.Parent.Ledger)
local Engrams = require(script.Parent.Engrams)

local remote = Instance.new("RemoteEvent")
remote.Name = "ShowcaseRemote"
remote.Parent = ReplicatedStorage

local REACH = 24        -- studs; a conversation, not a billboard

local function distanceBetween(a, b)
	local ca, cb = a.Character, b.Character
	local ra = ca and ca:FindFirstChild("HumanoidRootPart")
	local rb = cb and cb:FindFirstChild("HumanoidRootPart")
	if not ra or not rb then return math.huge end
	return (ra.Position - rb.Position).Magnitude
end

-- The item, as the chain describes it -- looked up here rather than taken from the
-- client, so what the viewer reads is what the holder actually owns.
local function held(player, id)
	-- An Engram first, because it is not on the chain to be found: it is a link the server
	-- is holding for this player while they are here. What the viewer gets is the link, so
	-- they can go and read the page themselves -- which is the entire point of showing one.
	local engram = Engrams.find(player, id)
	if engram then
		return {
			name = engram.name,
			blurb = engram.blurb,
			thumb = "",
			tx = "",
			block = "",
			view = engram.view,
			page = engram.page,
			explorer = (Ledger.data(player) or {}).explorer or "",
		}
	end
	-- What the town read from its own contracts for this player's address -- not anything their
	-- machine said about itself.
	local d = Ledger.data(player)
	for _, item in ipairs(Ledger.holdings(player) or {}) do
		if tostring(item.id) == tostring(id) then
			return {
				name = (item.name and item.name ~= "") and item.name or ("#" .. tostring(item.id)),
				blurb = item.blurb or "",
				thumb = item.thumb or "",
				tx = item.tx or "",
				block = item.block or "",
				explorer = (d and d.explorer) or "",
			}
		end
	end
	return nil
end

remote.OnServerEvent:Connect(function(player, action, id, targetName)
	if action ~= "show" then return end
	if type(id) ~= "string" and type(id) ~= "number" then return end
	if type(targetName) ~= "string" then return end

	local target = Players:FindFirstChild(targetName)
	if not target or target == player then return end
	if distanceBetween(player, target) > REACH then
		remote:FireClient(player, "note", "Too far away. Stand next to them.")
		return
	end

	local card = held(player, id)
	if not card then
		remote:FireClient(player, "note", "You are not holding that.")
		return
	end

	card.from = player.Name
	card.reach = REACH
	card.view = card.view or ""
	card.page = card.page or ""
	remote:FireClient(target, "card", card)
	remote:FireClient(player, "note", ("Showing %s to %s."):format(card.name, target.Name))
	print(("showcase: %s showed %s to %s"):format(player.Name, card.name, target.Name))
end)

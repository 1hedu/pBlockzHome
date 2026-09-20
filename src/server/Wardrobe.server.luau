-- Wear what you own.
--
-- Nothing in this project contains a top hat, or a duck, or a tux. The models are on
-- PulseChain: the host reads them, verifies each against its content hash, and hands
-- them to the world as ReplicatedStorage.OnChain.<Name>. All this script does is put
-- them on with Humanoid:AddAccessory, the same call any Roblox place would use.
--
-- Ownership is decided by the chain, not by this script and not by the client. Every
-- request from a client is checked against what the town read from its own contracts for
-- the address that player signed in with: asking to wear something you do not hold gets you
-- nothing. Keeping an outfit or destroying a thing is asked of the player's own wallet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ledger = require(script.Parent.Ledger)
local Contracts = require(game:GetService("ReplicatedStorage"):WaitForChild("Contracts"))
local HttpService = game:GetService("HttpService")
local Png = require(ReplicatedStorage:WaitForChild("Png"))
local Pets = require(script.Parent.Pets)
local Handouts = require(script.Parent.Handouts)
local Engrams = require(script.Parent.Engrams)
local Angling = require(script.Parent.Angling)
local ItemActions = require(script.Parent.ItemActions)
local Bar = require(script.Parent.ActionBar)
local WEAPONS = require(game:GetService("ReplicatedStorage"):WaitForChild("Weapons"))   -- every weapon is a main-hand item


local remote = Instance.new("RemoteEvent")
remote.Name = "WardrobeRemote"
remote.Parent = ReplicatedStorage

-- How something one-use says it has been used. A weapon that is spent has to come off the
-- character AND out of the list of what to put back on -- and what a player is wearing is
-- this script's to decide, so the weapon says so rather than doing it. Destroying the
-- accessory from the other side would put it straight back on at the next respawn.
local spent = Instance.new("BindableEvent")
spent.Name = "ItemConsumed"
spent.Parent = ReplicatedStorage

local saving = {}   -- request number -> who asked to have their outfit kept
local dropping = {}  -- request number -> who asked to destroy something
local worn = {}      -- player -> { [modelName] = {Accessory} }, what is on right now
local wanted = {}    -- player -> { [modelName] = true }, what they asked for; survives respawns
local greeted = {}   -- players who have been dressed in their existing wardrobe once
local chosen = {}    -- player -> { [modelName] = true (put on) / false (took off) }, said by the player themselves

-- Everything the wallet holds that has a model the host managed to mount, plus anything the
-- server is carrying for this player.
--
-- The candles are the second kind. They are spent the moment they land and recording that on
-- chain would be a signature in the middle of a fight, so the holding is one bit on the
-- server -- see Handouts.luau. Their models are published like everything else; it is only
-- ownership that is not.
--- What the chain says you own, plus what the server is holding for you.
---
--- The two halves are independent, and this used to return {} for BOTH the moment the chain
--- half was not ready -- so a candle you were holding and an Engram you had just cut
--- disappeared out of your bag while the wallet was still reading, or for as long as the RPC
--- was down. Nothing the server hands out has anything to do with whether the chain
--- answered, and a bag that empties itself because a read is slow is a bag nobody trusts.
local function owned(who)
	local out = {}
	for _, item in ipairs((who and Ledger.holdings(who)) or {}) do
		-- `model` is set only once the host has fetched and verified the model itself.
		-- Anything the server serves is the server's to say you have. A candle registered on
		-- chain and never spent would otherwise appear twice, and worse, would still be
		-- yours after you had used it.
		if item.model and item.model ~= "" and not Handouts.serves(item.model)
			and (item.kind == "accessory" or item.kind == "pet") then
			table.insert(out, {
				id = item.id,
				qty = tonumber(item.qty) or 1,
				model = item.model,
				name = (item.name and item.name ~= "") and item.name or ("#" .. tostring(item.id)),
				thumb = item.thumb or "",
				-- Set from the item's on-chain metadata. Anything published before the
				-- field existed comes back "" and is treated as slotless: it can always
				-- be worn and never evicts anything -- except a weapon, which is always in
				-- the hand: the cane and a spoon were published before slots and went on
				-- together, and a body cannot hold two things in one hand any more than it
				-- can wear two hats. The catalogue names their slot now; this covers what
				-- is already published.
				slot = (item.slot and item.slot ~= "") and item.slot or (WEAPONS[item.model] and "mainhand" or ""),
				kind = item.kind or "accessory",
				tier = item.tier or 0,
				tier_name = item.tier_name or "",
			})
		end
	end
	if who then
		for _, item in ipairs(Handouts.owned(who)) do
			table.insert(out, item)
		end
		-- And the links you are carrying. Session-lived and never minted -- see
		-- Engrams.luau -- but a thing in your bag like any other, because that is what
		-- holding one means.
		for _, item in ipairs(Engrams.owned(who)) do
			table.insert(out, item)
		end
		-- And what fishing gave you: the rod Funmaster Mike handed over, and every fish the
		-- Fishing contract says you caught. See Angling.luau.
		for _, item in ipairs(Angling.owned(who)) do
			table.insert(out, item)
		end
	end
	return out
end

--- The template for a model name.
---
--- OnChain is where the host mounts what it fetched and verified. Made is what the town
--- built for itself -- one badge, worn by every Engram under its own name, so the wardrobe
--- can tell two of them apart. Anything past a "#" is which one, not what it is.
local function source(modelName)
	local name = tostring(modelName)
	local chain = ReplicatedStorage:FindFirstChild("OnChain")
	local found = chain and chain:FindFirstChild(name)
	if found then return found end
	local made = ReplicatedStorage:FindFirstChild("Made")
	found = made and made:FindFirstChild(name)
	if found then return found end
	local hash = name:find("#", 1, true)
	if hash and made then return made:FindFirstChild(name:sub(1, hash - 1)) end
	return nil
end

-- Puts one thing on, and returns every Accessory it actually added.
--
-- Most items are a single Accessory. Some are a Model holding several, because an
-- Accessory follows exactly one limb: trousers need one per leg or they stay welded
-- to the torso and slide through your legs as you walk.
local function put(character, humanoid, template, kind)
	-- A pet is not worn. It goes in the world beside you and keeps station, so it never
	-- touches AddAccessory and never welds to a limb.
	if kind == "pet" then
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return {} end
		-- Which gait, decided by what the thing IS rather than what it is called. This
		-- used to test the name against "Steven"; renaming him to Familiar silently
		-- dropped him to the ground and he walked around like the dog.
		-- How it moves, from what it is made of. A part called Wing means it flies; one
		-- called Chassis means it drives. Anything else walks, which is what a pet did
		-- before there was more than one kind.
		local gait = "walk"
		for _, d in ipairs(template:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name:match("^Wing") then gait = "float" break end
				if d.Name:match("^Chassis") then gait = "glide" break end
			end
		end
		local model = Pets.summon(player, template, gait)
		return model and { model } or {}
	end
	local copy = template:Clone()
	if copy:IsA("Accoutrement") then
		copy.Parent = character
		humanoid:AddAccessory(copy)
		return { copy }
	end
	local added = {}
	for _, child in ipairs(copy:GetChildren()) do
		if child:IsA("Accoutrement") then
			child.Parent = character
			humanoid:AddAccessory(child)
			table.insert(added, child)
		end
	end
	copy:Destroy()          -- the container itself is not worn; only its pieces are
	return added
end

-- One thing per slot. You have two hats and ten capes; wearing them all at once put
-- ten capes through each other on the same attachment, which is what "everything
-- loads" looked like. Slotless items (older metadata, no `slot` field) are exempt.
local function evict(player, slot, keepModel)
	if slot == "" then return end
	local want = wanted[player]
	if not want then return end
	for _, other in ipairs(owned(player)) do
		if other.slot == slot and other.model ~= keepModel then
			want[other.model] = nil
		end
	end
end

-- Puts the character in exactly the set `wanted[player]` names, adding what is missing
-- and taking off what is not wanted any more.
local function sync(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then return end

	worn[player] = worn[player] or {}
	wanted[player] = wanted[player] or {}
	local have = worn[player]
	local want = wanted[player]

	local tookOff = false
	for name, pieces in pairs(have) do
		if not want[name] then
			for _, piece in ipairs(pieces) do
				if piece and piece.Parent then piece:Destroy() end
			end
			have[name] = nil
			tookOff = true
		end
	end
	-- A frame between taking one off and putting the next on.
	--
	-- Swapping weapons destroys one accessory and adds another in the same tick, and both
	-- hang off the same RightGripAttachment. Done in one breath the new Handle sometimes
	-- fails to find the hand at all and is left lying at the world origin, fifty-odd studs
	-- away -- which is what "I have to equip the spoon a few times before it shows up" was.
	-- It is a race in the host's own bookkeeping and this does not cure it, but it stops the
	-- game handing it the one arrangement that trips it.
	if tookOff then task.wait() end
	if not player.Character or player.Character ~= character then return end
	-- A pet that is no longer wanted leaves the world. Pets owns it, so Pets takes it
	-- away: destroying whatever happened to be in `have` would leave it hovering.
	local keepsPet = false
	for _, item in ipairs(owned(player)) do
		if item.kind == "pet" and want[item.model] then keepsPet = true end
	end
	if not keepsPet and Pets.has(player) then Pets.dismiss(player) end
	for _, item in ipairs(owned(player)) do
		if want[item.model] and not have[item.model] then
			local template = source(item.model)
			if template then
				local added = put(character, humanoid, template, item.kind)
				if #added > 0 then
					have[item.model] = added
					print(("wardrobe: %s put on %s, straight off the chain"):format(player.Name, item.name))
				end
			end
		end
	end
end

-- What the inventory panel draws.
local function inventory(player)
	local out = {}
	local want = wanted[player] or {}
	for _, item in ipairs(owned(player)) do
		table.insert(out, { id = item.id, name = item.name, model = item.model, qty = item.qty or 1,
			thumb = item.thumb, slot = item.slot, tier = item.tier, tier_name = item.tier_name,
			worn = want[item.model] == true,
			-- What it does when you click it, if anything. Sent so the panel knows which
			-- tiles are worth clicking: one that does nothing should not click back at you
			-- as though it had, and the tooltip can say what the click is for.
			acts = ItemActions.of(item),
			-- And whether showing it to somebody means anything. Only an Engram: it IS a
			-- link, and showing one hands the link over so they can go and read the page.
			-- Everything else is a thing you are wearing, which they can already see.
			shows = item.engram == true })
	end
	return out
end

-- Which rung the wallet is on, so the panel can name it beside the character: their PLS
-- balance against the contract's own ladder.
local function standing(player)
	local d = Ledger.data(player)
	local h = d and d.holder or nil
	if type(h) ~= "table" then return { name = "", tier = 0 } end
	return { name = h.name or "", tier = h.tier or 0 }
end

local function push(player)
	local items = inventory(player)
	-- The bar's ten squares go with the list, because they are names out of it: the panel
	-- looks each one up to draw it. An untouched bar is the first ten; once it is arranged it
	-- is whatever was arranged, gaps and all.
	-- And whether the chain has answered yet, because an empty list means two different
	-- things. Before the ledger lands, owned() has nothing to give and the panel used to
	-- say "Nothing yet -- Finch's stall is west of the square", which is a sentence about
	-- somebody who owns nothing being told where to go and buy something. They may own
	-- plenty; nobody has looked yet.
	remote:FireClient(player, "items", items, standing(player), Bar.showing(player, items),
		Ledger.addressOf(player) ~= nil and Ledger.holdings(player) == nil)
end

-- The outfit you last saved, as a set of model names.
--
-- An outfit is an ordinary inventory entry whose kind is "outfit" rather than "accessory",
-- so owned() -- which returns only what can be worn -- never offers it as a thing to put
-- on. Saving twice leaves two of them on chain; the newest by its own stamp wins.
local function savedOutfit(player)
	local best, at = nil, -1
	for _, item in ipairs(Ledger.holdings(player) or {}) do
		if item.kind == "outfit" and type(item.worn) == "table" and (item.at or 0) > at then
			best, at = item.worn, item.at or 0
		end
	end
	if not best then return nil end
	local set = {}
	for _, name in ipairs(best) do set[name] = true end
	return set
end

-- The first time someone's wardrobe is known, put all of it on: you have just bought
-- these things and the point is to see them. After that their choices stand.
local function dressOnce(player)
	if greeted[player] then return end
	local items = owned(player)
	if #items == 0 then return end
	wanted[player] = wanted[player] or {}
	-- Not greeted until the chain has said what they hold. The town's own handouts -- the rod,
	-- back from the DataStore the moment they sign in -- land seconds before the chain does, and
	-- a first dress made of those alone counted as the greeting: the saved outfit was never
	-- looked at when the real holdings arrived. Until then the handouts simply go on.
	if Ledger.holdings(player) == nil then
		-- One per slot, here as everywhere. This put every handout on at once, and a rod
		-- and a candle are both for the main hand.
		local held = {}
		for _, item in ipairs(items) do
			if item.slot == "" or not held[item.slot] then
				if item.slot ~= "" then held[item.slot] = true end
				wanted[player][item.model] = true
			end
		end
		sync(player)
		push(player)
		return
	end
	greeted[player] = true
	-- The chain can take a quarter of a minute to say what someone holds, and they are not
	-- waiting for it: the rod is handed out at once, and by the time the answer lands they may
	-- be standing at the edge with a line out. What they put on or took off themselves in
	-- that time is their choice and it stands, slot and all -- the saved outfit's cane does
	-- not take the rod out of a hand that is fishing with it. Only what went on by itself,
	-- the handouts, is the outfit's to replace.
	local said = chosen[player] or {}
	local taken = {}
	for _, item in ipairs(items) do
		if said[item.model] and item.slot ~= "" then taken[item.slot] = true end
	end
	-- What you saved, if you ever did. Only things you still hold: an outfit is a list of
	-- names, and the chain is what says whether they are yours.
	local saved = savedOutfit(player)
	if saved then
		-- The outfit is the whole of what goes on. Anything put on before the chain answered --
		-- the rod, handed out first -- comes off unless the outfit names it, or the cane and the
		-- rod were both in the hand.
		-- One per slot even here: an outfit saved with two things for one hand -- possible
		-- while the slot was unknown -- puts on the first of them, not both.
		local any = false
		for _, item in ipairs(items) do
			if said[item.model] ~= nil then
				wanted[player][item.model] = said[item.model] or nil
				any = any or said[item.model]
			elseif saved[item.model] and (item.slot == "" or not taken[item.slot]) then
				if item.slot ~= "" then taken[item.slot] = true end
				wanted[player][item.model] = true
				any = true
			elseif wanted[player][item.model] then
				wanted[player][item.model] = nil
			end
		end
		if any then
			sync(player)
			push(player)
			return
		end
	end
	-- Nothing saved, so: first of each slot, not all of them. The point is still to see
	-- what you bought, but a body can only wear one hat. Slotless items all go on.
	--
	-- This is a guess, and with two things for one slot it is decided by whichever id the
	-- registry hands over first. Saving an outfit is how you stop it guessing.
	-- From a clean body, not on top of whatever went on while the chain was answering. This
	-- only ever ADDED the first of each free slot, and the handouts put on a moment earlier
	-- were neither cleared nor counted as holding their slot: with no outfit saved you
	-- arrived with the rod and the cane in one hand and a fish and the duck in the other.
	-- (With an outfit saved, the branch above cleared them, which is why it looked fixed.)
	for _, item in ipairs(items) do
		if said[item.model] == nil then wanted[player][item.model] = nil end
	end
	for _, item in ipairs(items) do
		if said[item.model] ~= nil then
			wanted[player][item.model] = said[item.model] or nil
		elseif item.slot == "" then
			wanted[player][item.model] = true
		elseif not taken[item.slot] then
			taken[item.slot] = true
			wanted[player][item.model] = true
		end
	end
	sync(player)
	push(player)
end

-- Something one-use has been used: off the body and out of the server's hands.
--
-- Nothing is signed and nothing is burned. What was spent was a bit the server was holding
-- for this player, and getting another is a walk back across the square -- which is the whole
-- of the rule and the reason it is not on chain.
spent.Event:Connect(function(player, modelName)
	if not player or not player.Parent or type(modelName) ~= "string" then return end
	Handouts.take(player, modelName)
	if wanted[player] then wanted[player][modelName] = nil end
	sync(player)
	push(player)
	remote:FireClient(player, "note", ("Your %s is spent. Finch has more."):format(modelName))
end)

local function watch(player)
	wanted[player] = wanted[player] or {}
	player.CharacterAdded:Connect(function()
		worn[player] = {}          -- a new body wears nothing until we say so
		task.wait(0.2)             -- let the rig finish assembling
		sync(player)
		push(player)
	end)
	if player.Character then
		task.wait(0.2)
		dressOnce(player)
		sync(player)
	end
end

Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(watch, player)
end
Players.PlayerRemoving:Connect(function(player)
	worn[player] = nil
	wanted[player] = nil
	greeted[player] = nil
	chosen[player] = nil
end)

Ledger.onResult(function(n, res)
	local who = saving[n] or dropping[n]
	if not who then return end
	local destroyed = dropping[n] ~= nil
	saving[n] = nil
	dropping[n] = nil
	if not who.Parent then return end
	remote:FireClient(who, "note", tostring(res.message or (destroyed and "Gone." or "Saved.")))
	-- What you hold has changed, so the list the panel is showing is out of date. The
	-- chain's own update will say so too, in its own time; this is so it does not sit
	-- there offering you a thing you just destroyed.
	if destroyed and res.ok then push(who) end
end)

-- Keeping what you are wearing: a list of names, stored, then recorded as a thing you
-- hold. Two signatures and no pictures -- an outfit is a reference to things already on
-- the chain, so there is nothing new to draw.
local function saveOutfit(player, names)
	local function note(text) remote:FireClient(player, "note", text) end
	local count = ("%d thing%s"):format(#names, #names == 1 and "" or "s")

	local described = Ledger.requestFor(player, {
		action = "store",
		bytes = Png.base64(HttpService:JSONEncode({
			name = "Outfit", kind = "outfit", blurb = count .. " worn.",
			license = "CC0-1.0", source = "the wardrobe",
			model = "", thumbnail = "",
			worn = names, at = os.time(),
		})),
		mime = "application/json",
		note = ("Keep what you are wearing: %s"):format(count),
	}, 120)
	if not described or not described.ok then
		note("The outfit didn't store: " .. tostring(described and described.message or "no answer"))
		return
	end

	local recorded = Ledger.requestFor(player, {
		action = "write", to = Contracts.Inventory,
		-- keep, not add: an outfit is a note about things already held, and add is the ladder's
		-- gate for taking things. Saving one used to need the bottom rung's five PLS in the wallet,
		-- and reverted for anyone under it.
		fn = "keep(bytes32)", args = { described.hash },
		note = "Record the outfit as yours",
	}, 120)
	if not recorded or not recorded.ok then
		note("It's stored, but the record didn't take: "
			.. tostring(recorded and recorded.message or "no answer"))
		return
	end
	note(("Saved - %s."):format(count))
end

remote.OnServerEvent:Connect(function(player, action, modelName)
	if action == "list" then
		push(player)
		return
	end
	if action == "save" then
		-- Only their own wallet can sign. This asks it; they confirm it there.
		local names = {}
		for name in pairs(wanted[player] or {}) do table.insert(names, name) end
		table.sort(names)
		if #names == 0 then
			remote:FireClient(player, "note", "You are not wearing anything to save.")
			return
		end
		remote:FireClient(player, "note", "Saving...")
		task.spawn(saveOutfit, player, names)
		return
	end
	if action == "destroy" then
		-- The client names a model, never a chain id: what goes to the wallet is the
		-- bytes32 off the list the chain gave us, so nothing can ask to destroy a thing
		-- by naming an id it made up.
		if type(modelName) ~= "string" then return end
		local found = nil
		for _, item in ipairs(owned(player)) do
			if item.model == modelName then found = item break end
		end
		if not found then
			push(player)
			return
		end
		-- Off first. If it is the last one, the body should not be left wearing something
		-- that no longer exists while the transaction is in flight.
		if found.qty <= 1 and wanted[player] then
			wanted[player][modelName] = nil
			sync(player)      -- the same pair the remove action uses
			push(player)
		end
		dropping[Ledger.askFor(player, {
			action = "write",
			to = Contracts.Inventory,
			fn = "drop(bytes32,uint32)",
			args = { found.id, 1 },
			note = ("Destroy %s. It is gone for good -- not sold, not sent."):format(found.name),
		})] = player
		remote:FireClient(player, "note", ("Destroying %s - confirm it in the wallet."):format(found.name))
		return
	end
	-- Which square holds what. It decides nothing about what you have -- every square is drawn
	-- from what the chain says you own -- so the worst a made-up name can do is name a thing
	-- that draws as an empty square.
	if action == "arrange" then
		if Bar.set(player, modelName) then push(player) end
		return
	end

	-- Doing what a thing does, as against putting it on. Same ownership rule as everything
	-- else here: the client names a model and only what the chain says you hold is honoured.
	if action == "act" then
		if type(modelName) ~= "string" then return end
		for _, item in ipairs(owned(player)) do
			if item.model == modelName then
				local note = ItemActions.run(player, item)
				if note then remote:FireClient(player, "note", note) end
				return
			end
		end
		push(player)
		return
	end
	if action ~= "wear" and action ~= "remove" then return end
	if type(modelName) ~= "string" then return end
	-- The client may ask for anything; only what the chain says you hold is honoured.
	local allowed = false
	for _, item in ipairs(owned(player)) do
		if item.model == modelName then allowed = true break end
	end
	if not allowed then
		push(player)
		return
	end
	wanted[player] = wanted[player] or {}
	chosen[player] = chosen[player] or {}
	chosen[player][modelName] = action == "wear"
	if action == "wear" then
		local slot = ""
		for _, item in ipairs(owned(player)) do
			if item.model == modelName then slot = item.slot break end
		end
		evict(player, slot, modelName)
	end
	wanted[player][modelName] = action == "wear" or nil
	sync(player)
	-- Said, like the outfit is: which slot it took, so two things in one hand shows in the log.
	local slot = ""
	for _, item in ipairs(owned(player)) do if item.model == modelName then slot = item.slot break end end
	print(("wardrobe: %s %s %s%s"):format(player.Name, action == "wear" and "put on" or "took off", modelName, slot ~= "" and (" (" .. slot .. ")") or ""))
	push(player)
end)

-- The models may arrive after the players do: the town reads each player's holdings once they
-- sign in, and again after their wallet changes something.
Ledger.onChanged(function(who)
	for _, player in ipairs(who and { who } or Players:GetPlayers()) do
		if player.Parent then
			dressOnce(player)
			sync(player)
			push(player)
		end
	end
end)

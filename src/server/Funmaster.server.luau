-- The Funmaster, who stands in the square and asks whether you want to have fun.
--
-- Duelling is his desk and nobody else's. It sat at the bank for a while and a teller is not
-- who you ask about a fight; he is in the square, where the fight actually happens, so turning
-- it on is something you do on your way past rather than an errand.
--
-- On for everyone to begin with. A town where you have to opt in to being hit is a town where
-- nobody is ever hit -- and contracts/Duelling.sol defaults the same way, so a wallet that has
-- never touched it reads as in and nobody has to transact to join a game.
--
-- The flag is the one thing about a fight that is on chain, and it is on chain because it
-- outlives the session: say once that you would rather be left alone and every town that
-- reads the contract knows it, including ones nobody has written yet. Everything else -- who
-- hit whom, hearts, the streak, who is carrying a candle -- is the server's, because it is
-- true for four seconds and only the thing holding both players can judge it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ledger = require(script.Parent.Ledger)
local Contracts = require(game:GetService("ReplicatedStorage"):WaitForChild("Contracts"))
local Health = require(script.Parent.Health)
local Duels = require(script.Parent.Duels)
local Angling = require(script.Parent.Angling)
local Players = game:GetService("Players")

local remote = Instance.new("RemoteEvent")
remote.Name = "FunRemote"
remote.Parent = ReplicatedStorage

local MENU = {
	{ id = "on", label = "PvP On" },
	{ id = "off", label = "PvP Off" },
	{ id = "ranked", label = "Ranked Duel" },
}

--- His menu for this player: the fight, and space fishing -- asking about it until he has given you
--- a rod, and the leaderboard after.
local function menuFor(player)
	local menu = table.clone(MENU)
	if Angling.hasRod(player) then
		table.insert(menu, { id = "fishboard", label = "Space Fishing Leaderboard" })
	else
		table.insert(menu, { id = "fishing", label = "Space Fishing?" })
	end
	return menu
end

--- Where he is up to with you.
local function lines(player)
	local on = Health.fights(player)
	local out = {}
	if on then
		table.insert(out, "You're in. Anyone with a spoon, a torch or a candle can have a")
		table.insert(out, "go at you, and you at them.")
		table.insert(out, "")
		table.insert(out, "Your hearts show over your head while you're in. Theirs show")
		table.insert(out, "over theirs.")
	else
		table.insert(out, "You're out of it. Nobody can touch you, and you can't touch")
		table.insert(out, "them.")
		table.insert(out, "")
		table.insert(out, "Someone can still put hearts back into you with a green candle.")
	end
	table.insert(out, "")
	table.insert(out, "Nothing you carry is at stake, either way.")
	return out
end


local answers = {}

--- Whether the duel record contract is deployed: until it is, nothing about a result can be signed
--- or sent, and he does not say it can.
local function onChainOpen()
	return Contracts.DuelRecords ~= nil and Contracts.DuelRecords ~= ""
end

--- Sets it here, and asks the player's own wallet to write it down.
---
--- Here first, because the answer should be true the moment he says it rather than a block
--- later; the chain is where it is remembered, not where it is decided this session. The write is
--- theirs -- their wallet, their confirm, their gas -- because the flag is theirs; the town holds no
--- key. If they wave it off, or it fails, the setting still stands for this session and the next
--- join reads the old value back, which is the right way round for a preference.
local said = {}   -- player -> they have chosen this session, so a late chain read does not undo it

local function set(player, on, line)
	said[player] = true
	Health.setFights(player, on)
	task.spawn(function()
		local answer = Ledger.askPlayer(player, {
			action = "write",
			to = Contracts.Duelling,
			fn = "setFighting(bool)",
			args = { on },
			note = on and "Let other people duel you" or "Stop other people duelling you",
		})
		print(("funmaster: %s's flag %s -- %s"):format(player.Name, on and "on" or "off",
			answer and (answer.ok and "written" or tostring(answer.message)) or "no answer"))
	end)
	local out = lines(player)
	table.insert(out, 1, line)
	table.insert(out, 2, "Your wallet will ask to keep that on chain for next time. Your gas.")
	table.insert(out, 3, "")
	return out
end

function answers.on(_d, player)
	return set(player, true, "Mind yourself out there.")
end

function answers.off(_d, player)
	return set(player, false, "Suit yourself. Nobody can hit you.")
end

-- What the chain already had to say about it. A player who opted out on another server
-- yesterday should not have to say so again here.
--
-- Each player's own flag, read for their own address once they have signed in with it -- the
-- Duelling contract is the town's game state, and the server reads it like anybody would, to
-- know whom it may let hit whom. A guest has no address and plays by the town's default, in.
local function readFlag(player)
	local address = Ledger.addressOf(player)
	if not address then return end
	local answer = Ledger.request({
		action = "read",
		to = Contracts.Duelling,
		fn = "fighting(address)",
		args = { address },
		returns = { "bool" },
	})
	if not answer or not answer.ok or not player.Parent then return end
	local on = answer.words and answer.words[1]
	if on == nil or said[player] then return end
	Health.setFights(player, on == true)
end

local function watch(player)
	player:GetAttributeChangedSignal("WalletAddress"):Connect(function() task.spawn(readFlag, player) end)
	if Ledger.addressOf(player) then task.spawn(readFlag, player) end
end

Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerRemoving:Connect(function(player) said[player] = nil end)

-- ---- ranked duels ------------------------------------------------------------------------
-- One against one or two against two, first team to a number of frags, and nobody else can get
-- in the way. The rules are in Duels.luau; this is the asking.

local RANKED_MENU = {
	{ id = "mode", arg = "1v1", label = "1v1" },
	{ id = "mode", arg = "2v2", label = "2v2" },
	{ id = "leaderboard", label = "Leaderboard" },
	{ id = "mine", label = "My duels" },
	{ id = "back", label = "Back" },
}

local drafts = {}   -- player -> { mode, size, mate, foes }

local function rankedMenu(player)
	local menu = table.clone(RANKED_MENU)
	if Duels.busyWith(player) then
		table.insert(menu, 1, { id = "giveup", label = "Give up this duel" })
	end
	return menu
end

local function say(player, lines, menu, input)
	if player.Parent then
		remote:FireClient(player, "say", { lines = lines, menu = menu or rankedMenu(player), thumb = "", input = input })
	end
end

function answers.ranked(d, player)
	if not Ledger.addressOf(player) then
		return { "Ranked is for people signed in with a wallet: a result is about",
			"addresses, and I've nothing to put yours under." }, menuFor(player)
	end
	return {
		"Ranked. Pick one against one or two against two, pick who, and pick how",
		"many frags wins it. Everybody you pick has to say yes.",
		"",
		"The leaderboard goes by kills in ranked duels, whatever the match was to.",
		"",
		"While it's on, nobody outside it can touch any of you, and you can't",
		"touch them. Only your own side can mend you.",
		"",
		table.unpack(onChainOpen() and {
			"When it's over everybody signs to agree how it went, free. If a side",
			"won't, everybody else here is asked to witness it. Once it's agreed or",
			"witnessed, any of you can put it on chain, and whoever does pays.",
		} or {
			"I keep the results, on the town's record. Putting them on chain isn't",
			"open yet.",
		}),
	}, rankedMenu(player)
end

function answers.back(_d, player)
	drafts[player] = nil
	return lines(player), menuFor(player)
end

--- Everybody who could be asked: signed in, here, not in a duel, and not already picked.
local function pickable(player, draft)
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local taken = p == player or p == draft.mate
		for _, f in ipairs(draft.foes) do if f == p then taken = true end end
		if not taken and Duels.free(p) then table.insert(out, p) end
	end
	table.sort(out, function(a, b) return a.Name < b.Name end)
	return out
end

local function pickFrom(player, draft, id, question)
	local menu = {}
	for _, p in ipairs(pickable(player, draft)) do
		table.insert(menu, { id = id, arg = p.Name, label = ("%s  (%s)"):format(p.Name, Ledger.short(Ledger.addressOf(p))) })
	end
	if #menu == 0 then
		drafts[player] = nil
		return { "There's nobody free and signed in to ask right now." }, rankedMenu(player)
	end
	table.insert(menu, { id = "ranked", label = "Never mind" })
	return { question }, menu
end

local function askLimit(player)
	return { "First to how many frags?", "", ("Anything from %d to %d."):format(Duels.MIN_LIMIT, Duels.MAX_LIMIT) },
		{ { id = "challenge", label = "Send the challenge" }, { id = "ranked", label = "Never mind" } },
		{ placeholder = "5", text = "5" }
end

function answers.mode(_d, player, mode)
	if not Ledger.addressOf(player) then return answers.ranked(nil, player) end
	if Duels.busyWith(player) then return { "You're already in one." }, rankedMenu(player) end
	local size = mode == "2v2" and 2 or 1
	local draft = { mode = size == 2 and "2v2" or "1v1", size = size, foes = {} }
	drafts[player] = draft
	if size == 2 then
		return pickFrom(player, draft, "mate", "Who's on your side?")
	end
	return pickFrom(player, draft, "foe", "Who are you taking on?")
end

local function named(name)
	local p = type(name) == "string" and Players:FindFirstChild(name)
	return p and p:IsA("Player") and p or nil
end

function answers.mate(_d, player, name)
	local draft = drafts[player]
	local p = named(name)
	if not draft or draft.size ~= 2 or not p or not Duels.free(p) or p == player then
		return { "I lost track of that. Start again?" }, rankedMenu(player)
	end
	draft.mate = p
	return pickFrom(player, draft, "foe", ("You and %s. Who are you up against?"):format(p.Name))
end

function answers.foe(_d, player, name)
	local draft = drafts[player]
	local p = named(name)
	if not draft or not p or not Duels.free(p) or p == player or p == draft.mate then
		return { "I lost track of that. Start again?" }, rankedMenu(player)
	end
	for _, f in ipairs(draft.foes) do if f == p then return askLimit(player) end end
	table.insert(draft.foes, p)
	if #draft.foes < draft.size then
		return pickFrom(player, draft, "foe", ("%s, and who else?"):format(p.Name))
	end
	return askLimit(player)
end

function answers.challenge(_d, player, _arg, typed)
	local draft = drafts[player]
	if not draft or #draft.foes ~= draft.size then return { "I lost track of that. Start again?" }, rankedMenu(player) end
	local teamA = { player }
	if draft.mate then table.insert(teamA, draft.mate) end
	local c, why = Duels.challenge(teamA, draft.foes, tonumber(typed))
	if not c then
		if tostring(why):find("First to") then
			local l, m, input = askLimit(player)
			table.insert(l, 1, why)
			return l, m, input
		end
		drafts[player] = nil
		return { why }, rankedMenu(player)
	end
	drafts[player] = nil
	local others = {}
	for _, p in ipairs(teamA) do if p ~= player then table.insert(others, p) end end
	for _, p in ipairs(draft.foes) do table.insert(others, p) end
	local vs = {}
	for _, p in ipairs(draft.foes) do table.insert(vs, p.Name) end
	local us = draft.mate and (player.Name .. " & " .. draft.mate.Name) or player.Name
	local them = table.concat(vs, " & ")
	for _, p in ipairs(others) do
		local ask
		if p == draft.mate then
			ask = ("%s wants you on their side in a ranked %s against %s"):format(player.Name, c.mode, them)
		elseif draft.mate then
			ask = ("%s challenge %s to a ranked %s"):format(us, them, c.mode)
		else
			ask = ("%s challenges you to a ranked %s"):format(player.Name, c.mode)
		end
		remote:FireClient(p, "open", { title = "Funmaster Mike  <Ranked Duel>", npc = "",
			greeting = ("%s, first to %d frags. Nobody else can touch you while it's on. You've a minute to say."):format(
				ask, c.limit),
			menu = { { id = "accept", arg = c.id, label = "I'm in" }, { id = "decline", arg = c.id, label = "No thanks" } } })
	end
	return { ("Sent. %s against %s, first to %d."):format(
		draft.mate and (player.Name .. " & " .. draft.mate.Name) or player.Name, table.concat(vs, " & "), c.limit),
		"", "They've a minute to say yes. It starts the moment everybody has." }, rankedMenu(player)
end

function answers.accept(_d, player, id)
	local c = Duels.pending(tostring(id))
	if not c or not Duels.accept(c, player) then
		return { "That challenge isn't open any more." }, menuFor(player)
	end
	if Duels.pending(c.id) then return { "You're in. Waiting on the rest." }, {} end
	return { "Everybody's in. Go!" }, {}
end

function answers.decline(_d, player, id)
	local c = Duels.pending(tostring(id))
	if c then Duels.decline(c, player) end
	return { "Fair enough." }, {}
end

function answers.giveup(_d, player)
	if Duels.forfeit(player) then return { "Done. The other side has it." }, rankedMenu(player) end
	return { "You're not in one." }, rankedMenu(player)
end

function answers.leaderboard(_d, player)
	local top = Duels.leaderboard(10)
	if #top == 0 then return { "Nobody's fought a ranked duel here yet." }, rankedMenu(player) end
	local out = { "Most kills in ranked duels in this town:", "" }
	for i, row in ipairs(top) do
		table.insert(out, ("%2d. %s  %d kill%s  (%d won, %d lost)  %s"):format(i, row.name, row.kills,
			row.kills == 1 and "" or "s", row.wins, row.losses, Ledger.short(row.address)))
	end
	return out, rankedMenu(player)
end

local function scoreLine(r, address)
	local mine = Duels.teamOf(r, address)
	local us, them = mine == 1 and r.teamA or r.teamB, mine == 1 and r.teamB or r.teamA
	local function who(side)
		local n = {}
		for _, one in ipairs(side) do table.insert(n, one.name) end
		return table.concat(n, " & ")
	end
	local ours, theirs = mine == 1 and r.fragsA or r.fragsB, mine == 1 and r.fragsB or r.fragsA
	return ("%s vs %s, %d - %d%s"):format(r.winner == mine and "Won" or "Lost", who(them), ours, theirs,
		r.forfeit and " (walked out)" or ""), who(us)
end

function answers.mine(_d, player)
	local address = Ledger.addressOf(player)
	if not address then return answers.ranked(nil, player) end
	local recent = Duels.recent(player)
	if #recent == 0 then return { "You've no ranked duels on the town's record yet." }, rankedMenu(player) end
	local out = { "Your last ranked duels:", "" }
	local menu = {}
	for i, r in ipairs(recent) do
		local line = scoreLine(r, address)
		local state = r.onChain and "on chain"
			or (not onChainOpen() and "on the town's record")
			or (not Duels.signedBy(r, address) and "needs your ok")
			or (Duels.agreedByBoth(r) and "agreed")
			or (r.witnessedOnChain and "witnessed, on chain")
			or (Duels.witnessed(r) and "witnessed")
			or "waiting on the other side"
		table.insert(out, ("  %s  [%s]"):format(line, state))
		if not r.onChain and onChainOpen() and #menu < 6 then
			if not Duels.signedBy(r, address) then
				table.insert(menu, { id = "agree", arg = r.id, label = ("Agree: %s"):format(line) })
			elseif Duels.agreedByBoth(r) or (Duels.witnessed(r) and not r.witnessedOnChain) then
				table.insert(menu, { id = "onchain", arg = r.id, label = ("Put on chain: %s"):format(line) })
			end
		end
		if i >= 10 then break end
	end
	for _, m in ipairs(rankedMenu(player)) do table.insert(menu, m) end
	return out, menu
end

local sending = {}   -- player -> already putting one on chain

function answers.onchain(_d, player, id)
	if sending[player] then return { "Still working on the last one." }, rankedMenu(player) end
	sending[player] = true
	task.spawn(function()
		local ok, result = pcall(Duels.putOnChain, player, tostring(id), function(text) say(player, { text }) end)
		sending[player] = nil
		if not ok then
			warn("funmaster: " .. tostring(result))
			result = { message = "Something went wrong on my side. Sorry." }
		end
		say(player, { tostring(result.message) })
	end)
	return { "Right. Let me see who can sign for it." }, rankedMenu(player)
end

--- Agreeing to a result later: after walking out, waving the prompt off, or not being there.
function answers.agree(_d, player, id)
	if sending[player] then return { "Still working on the last one." }, rankedMenu(player) end
	local r = Duels.result(tostring(id))
	if type(r) ~= "table" then return { "I can't find that duel." }, rankedMenu(player) end
	sending[player] = true
	task.spawn(function()
		local ok, result = pcall(Duels.agree, player, r)
		sending[player] = nil
		if not ok then
			warn("funmaster: " .. tostring(result))
			result = { message = "Something went wrong on my side. Sorry." }
		end
		say(player, { result.ok and "Agreed. It's on the town's record with your name to it." or ("Not agreed: " .. tostring(result.message)) })
	end)
	return { "Your wallet will show you the result to sign." }, rankedMenu(player)
end

Players.PlayerRemoving:Connect(function(player)
	drafts[player] = nil
	sending[player] = nil
end)

-- ---- space fishing -----------------------------------------------------------------------
-- He hands out the rod. Casting is a transaction from your own wallet (contracts/Fishing.sol),
-- so a guest gets told so instead of a rod they could never use.

function answers.fishing(_d, player)
	if Angling.hasRod(player) then return answers.fishboard(_d, player) end
	local ok = Angling.giveRod(player)
	if not ok then
		return { "Space fishing's done with your own wallet -- every cast is yours, and",
			"so is every fish. Sign in with one and come see me." }, menuFor(player)
	end
	ReplicatedStorage:WaitForChild("Notify"):FireClient(player, { Title = "Dysnomia Rod", Text = "You got a Dysnomia Rod from Funmaster Mike." })
	return { "Turn the other cheek kinda guy? Here you go, the space fishing is",
		"excellent right now. Just throw a cast anywhere off the edge of the map." }, menuFor(player)
end

--- The leaderboard is read by the player's own machine, straight off the Fishing contract -- he
--- only points at it.
function answers.fishboard(_d, player)
	remote:FireClient(player, "close")
	remote:FireClient(player, "fishboard")
	return nil
end

Ledger.onTalk("Funmaster", function(player)
	remote:FireClient(player, "open", { title = "Funmaster Mike", npc = "Funmaster",
		greeting = ("It's a game, %s. A profound life experience."):format(player.DisplayName ~= "" and player.DisplayName or player.Name),
		menu = menuFor(player) })
end)

remote.OnServerEvent:Connect(function(player, action, arg, typed)
	local fn = answers[tostring(action)]
	if not fn then return end
	local ok, said, menu, input = pcall(fn, Ledger.data(player), player, arg, typed)
	if not ok then
		warn("funmaster: " .. tostring(said))
		said, menu, input = { "Something went wrong on my side. Sorry." }, nil, nil
	end
	if said == nil then return end   -- he has opened something else and has nothing to say
	remote:FireClient(player, "say", { lines = said, menu = menu or menuFor(player), thumb = "", input = input })
end)

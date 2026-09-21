-- Penn, the bank teller. Wallet services only: what you hold, what you own, and
-- where the numbers come from. Buying happens across the square at the shop.
--
-- This script cannot reach the network. What it knows about you is `Ledger.data(player)`: your
-- balances as your own machine read them, what you own as the town read it from its contracts.
-- Anything that moves money is asked of YOUR wallet (Ledger.askFor), which shows it to you and
-- signs it or doesn't. The teller holds no key.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ledger = require(script.Parent.Ledger)
local Contracts = require(game:GetService("ReplicatedStorage"):WaitForChild("Contracts"))
-- An amount typed in a box is a person's amount; a token contract wants it in its own units,
-- and the two are eighteen zeroes apart. Never through a number: that is somebody's money.
local Units = require(ReplicatedStorage:WaitForChild("Units"))

local remote = Instance.new("RemoteEvent")
remote.Name = "BankRemote"
remote.Parent = ReplicatedStorage

local MENU = {
	{ id = "balance", label = "What am I holding?" },
	{ id = "items", label = "Show me my items" },
	{ id = "receive", label = "What's my address?" },
	{ id = "ask_send", label = "Send someone money" },
	{ id = "donate", label = "Make a donation" },
	{ id = "about", label = "Where does this data come from?" },
}

-- Sending takes three answers now -- who, what, how much -- so what has been said so far is
-- kept here while they go on to the next box. Cleared as soon as it is used, or when they
-- start again.
local sending = {}      -- player -> { to = address, token = { symbol, address, decimals } }
local waiting = {}      -- request number -> player

--- Everything this player can send: PLS and every token their own machine knows about.
---
--- The same list the trading house shows, imports and all, because it is the same list --
--- their wallet reads it and publishes it, and a token somebody pasted in by address is
--- theirs to send like any other. Only what they actually hold some of is offered: a menu of
--- things you have none of is a menu of mistakes.
local function sendable(d)
	local out = {}
	local px = d and d.pulsex
	if type(px) ~= "table" then return out end
	for _, t in ipairs(px.tokens or {}) do
		local units = tostring(t.balance_units or "")
		if units ~= "" and units ~= "0" then
			table.insert(out, {
				symbol = t.symbol, address = t.address or "",
				decimals = t.decimals or 18, balance = t.balance or "",
				balance_units = units, custom = t.custom == true,
			})
		end
	end
	return out
end

local function greeting(d)
	if not d then
		return "Morning. The vault line is down, so I can't read the chain right now - try me again in a moment."
	elseif Ledger.loading(d) then
		return "Morning. Give me a moment, I'm reading the ledger - this window will fill in by itself."
	elseif Ledger.guest(d) then
		return "Morning. You haven't signed in with a wallet, so there's no account of yours for me to show."
	end
	return ("Morning. You're %s, and I can see your account on %s."):format(Ledger.short(d.address), d.network or "chain")
end


local answers = {}

function answers.balance(d)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if Ledger.guest(d) then return Ledger.noWallet() end
	return {
		("%s holds %s PLS."):format(Ledger.short(d.address), d.gas or "?"),
	}
end

function answers.items(d)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if Ledger.guest(d) then return Ledger.noWallet() end
	local items = d.items or {}
	if #items == 0 then
		return {
			"You don't hold anything from this registry yet.",
			"Finch runs the stall across the square. Take something off his shelf and",
			"it shows up here, against your address in the inventory contract.",
		}
	end
	local lines = { ("You own %d item%s:"):format(#items, #items == 1 and "" or "s") }
	for _, it in ipairs(items) do
		table.insert(lines, ("  %s  x%s  (#%s)"):format(Ledger.nameOf(it, it.id), tostring(it.qty), tostring(it.id)))
	end
	table.insert(lines, "")
	table.insert(lines, "Press I to open your wardrobe and put any of it on.")
	return lines
end

-- ---- donations ------------------------------------------------------------------
-- A gift, and said so plainly enough that nobody can mistake it for a purchase.
--
-- Nothing comes back for it. No item, no rank, no supporter badge, no place in a list --
-- because the moment a donation buys something it IS a purchase, and a purchase should have
-- a price on it and sit on Finch's shelf with everything else. Keeping the two apart is the
-- only way either of them stays honest.
--
-- Penn's desk rather than the square, because it is a wallet operation and this is the
-- wallet counter: the same place you read your balance and send somebody money.
function answers.donate(d)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	local to = d.donations
	if type(to) ~= "string" or to == "" then
		return {
			"Nobody's said where a donation would go, so I can't take one.",
		}
	end
	if not d.can_buy then
		return { "I'd take one gladly, but you've no wallet signed in that can sign." }
	end
	return {
		"You get nothing for it. No item, no rank, no badge, nothing unlocked,",
		"and no refund.",
		"",
		"It goes here:",
		"",
		("  %s"):format(to),
		"",
		"Native PLS, straight from your wallet. You'll see the amount and where",
		"it's going before anything is signed.",
		"",
		"Type an amount below.",
	}, {
		{ id = "give", label = "Send it" },
		table.unpack(MENU),
	}, { placeholder = "amount in PLS, e.g. 5" }
end

function answers.give(d, player, _arg, typed)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if type(typed) ~= "string" or typed:gsub("%s", "") == "" then
		return { "I need an amount. Type one in the box." }, nil, { placeholder = "amount in PLS, e.g. 5" }
	end
	typed = typed:gsub("%s", "")
	if not typed:match("^%d+%.?%d*$") or (tonumber(typed) or 0) <= 0 then
		return { "That isn't an amount. A number of PLS, like 5 or 0.5." }, nil, { placeholder = "amount in PLS, e.g. 5", text = typed }
	end
	-- A gift is a plain transfer: an address, an amount, no contract and no call. The
	-- wallet says so on the prompt rather than showing a blank where a function goes.
	local n = Ledger.askFor(player, {
		action = "write",
		to = Contracts.Donations,
		value = typed,
		note = "A gift. You get nothing for it and there is no refund.",
	})
	waiting[n] = player
	return {
		("%s PLS, as a gift."):format(typed),
		"",
		"Your wallet will show you the address and the amount before it signs.",
	}
end

function answers.about(d)
	if Ledger.loading(d) then return Ledger.notYet(d) end
	return {
		"Everything I just read is on PulseChain testnet v4.",
		d and ("Registry " .. Ledger.short(d.registry or "")) or "Registry unavailable.",
		d and ("Marketplace " .. Ledger.short(d.marketplace or "")) or "",
		"No account here and no balance we keep: what you hold is read straight",
		"off the chain. Your wallet shows you every transaction first, you approve",
		"it, and you pay the gas.",
	}
end

-- ---- wallet services ------------------------------------------------------------
function answers.receive(d)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if Ledger.guest(d) then return Ledger.noWallet() end
	return {
		"This is you:",
		"",
		("  %s"):format(d.address or "?"),
		"",
		"Anyone can send to it. There's no account here to open and nothing for",
		"me to freeze.",
		"",
		("Everything it has ever done is on %s."):format(d.network or "chain"),
	}
end

function answers.ask_send(d, player)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	if not d.can_buy then
		return { "I can't move anything for you: you've no wallet signed in that can sign." }
	end
	sending[player] = nil
	return {
		"Who's it going to?",
		"",
		"Type their address below - 0x and forty hex characters. I'll ask for the",
		"amount next, and your wallet will show you both before anything is signed.",
		"",
		"Once it's sent there's no reversing it.",
	}, {
		{ id = "send_to", label = "That's the address" },
		table.unpack(MENU),
	}, { placeholder = "0x0000000000000000000000000000000000000000" }
end

function answers.send_to(d, player, _arg, typed)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	local to = type(typed) == "string" and typed:gsub("%s", "") or ""
	if #to ~= 42 or to:sub(1, 2) ~= "0x" then
		return { "That isn't an address. They're 0x and forty hex characters." },
			{ { id = "send_to", label = "Try again" }, table.unpack(MENU) },
			{ placeholder = "0x...", text = to }
	end
	sending[player] = { to = to }
	-- What to send, before how much. It used to be PLS and nothing else, which is a bank that
	-- can only move one of the things it holds for you.
	local list = sendable(d)
	-- Nothing read yet is not nothing held. The wallet leaves pulsex out until a read of the
	-- pools has answered, and telling somebody their money is gone is worse than telling them
	-- to wait a moment.
	if type(d.pulsex) ~= "table" then
		return { ("To %s."):format(Ledger.short(to)), "",
			"I haven't got your balances back yet. Ask me again in a moment." }, MENU
	end
	if #list == 0 then
		return { ("To %s."):format(Ledger.short(to)), "",
			"You've nothing to send: every balance I can see is empty." }, MENU
	end
	local menu = {}
	for _, t in ipairs(list) do
		table.insert(menu, {
			id = "send_token", arg = t.address,
			label = ("%s   %s%s"):format(t.symbol, t.balance, t.custom and "   (yours)" or ""),
		})
	end
	for _, item in ipairs(MENU) do table.insert(menu, item) end
	return {
		("To %s."):format(Ledger.short(to)),
		"",
		"What are you sending them?",
	}, menu
end

--- Which token, chosen off the menu. Then the amount.
function answers.send_token(d, player, arg, _typed)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	local pending = sending[player]
	if not pending or not pending.to then
		return { "I've lost track of who that was going to. Start again?" }, MENU
	end
	local want = type(arg) == "string" and arg or ""
	local chosen = nil
	for _, t in ipairs(sendable(d)) do
		-- By address, which is what a token IS. Two tokens can call themselves the same thing
		-- and one of them can be something somebody pasted in this afternoon.
		if (t.address or "") == want then chosen = t break end
	end
	if not chosen then
		return { "I can't see that one in your holdings any more. Which is it?" }, MENU
	end
	pending.token = chosen
	return {
		("%s to %s."):format(chosen.symbol, Ledger.short(pending.to)),
		"",
		("You're holding %s. How much of it? Type the amount below."):format(chosen.balance),
	}, {
		{ id = "send", label = "Send it" },
		table.unpack(MENU),
	}, { placeholder = ("amount in %s, e.g. 5"):format(chosen.symbol) }
end

function answers.send(d, player, _arg, typed)
	if not d or Ledger.loading(d) then return Ledger.notYet(d) end
	local pending = sending[player]
	if not pending or not pending.to or not pending.token then
		return { "I've lost track of that one. Start again?" }, MENU
	end
	local to, token = pending.to, pending.token
	local box = { placeholder = ("amount in %s, e.g. 5"):format(token.symbol) }
	if type(typed) ~= "string" or typed:gsub("%s", "") == "" then
		return { "I need an amount. Type one in the box." }, nil, box
	end
	typed = typed:gsub("%s", "")
	if not typed:match("^%d+%.?%d*$") or (tonumber(typed) or 0) <= 0 then
		box.text = typed
		return { ("That isn't an amount. A number of %s, like 5 or 0.5."):format(token.symbol) }, nil, box
	end
	local units = Units.toUnits(typed, token.decimals)
	if units == "" or units == "0" then
		box.text = typed
		return { ("That comes to nothing in %s. It goes to %d decimal places."):format(token.symbol, token.decimals) },
			nil, box
	end
	-- Said here rather than at the wallet prompt, which would have to refuse it after the
	-- reading: more than you hold is not a thing to sign and then have the chain turn down.
	if Units.lessThan(token.balance_units, units) then
		box.text = typed
		return { ("You're holding %s %s. That's more than that."):format(token.balance, token.symbol) }, nil, box
	end
	sending[player] = nil
	local n
	if (token.address or "") == "" then
		-- The native coin: a plain transfer, the same as a donation. An address and an amount,
		-- no contract and no call.
		n = Ledger.askFor(player, {
			action = "write",
			to = to,
			value = typed,
			note = ("Send %s PLS to %s"):format(typed, Ledger.short(to)),
		})
	else
		-- A token: the token's own contract moves it, and the amount is in its own units. The
		-- wallet reads the call for itself and shows what it read, whatever this note says.
		n = Ledger.askFor(player, {
			action = "write",
			to = token.address,
			fn = "transfer(address,uint256)",
			args = { to, units },
			note = ("Send %s %s to %s"):format(typed, token.symbol, Ledger.short(to)),
		})
	end
	waiting[n] = player
	return {
		("%s %s to %s."):format(typed, token.symbol, Ledger.short(to)),
		"",
		"Your wallet will show you the address and the amount before it signs.",
	}
end

Ledger.onResult(function(n, res)
	local player = waiting[n]
	waiting[n] = nil
	if not player or not player.Parent then return end
	remote:FireClient(player, "say", { lines = { tostring(res.message or "Done.") }, menu = MENU, thumb = "" })
end)

Ledger.onTalk("Teller", function(player)
	remote:FireClient(player, "open", { title = "Penn  <Teller>", npc = "Teller", greeting = greeting(Ledger.data(player)), menu = MENU })
end)

remote.OnServerEvent:Connect(function(player, action, arg, typed)
	if type(action) ~= "string" then return end
	local fn = answers[action]
	if not fn then return end
	local d = Ledger.data(player)
	local ok, lines, menu, input = pcall(fn, d, player, arg, typed)
	if not ok then
		warn("bank: " .. tostring(lines))
		lines = { "Something went wrong on my side. Sorry." }
		menu, input = nil, nil
	end
	-- Words only: the pictures are on Finch's shelf and in your bag.
	remote:FireClient(player, "say", { lines = lines, menu = menu or MENU, thumb = "", input = input })
end)

-- The dialog reads the data once, when it opens. If it opened while their picture was
-- still loading, the window would sit on "give me a moment" forever, so push the new
-- greeting out the moment it lands; the client only applies it if its dialog is actually
-- open and pointed at us.
Ledger.onReady(function(player, d)
	print(("bank: %s's picture is in (%s PLS, %d items, %d listings)"):format(player.Name, tostring(d.gas or "?"), #(d.items or {}), #(d.listings or {})))
	remote:FireClient(player, "update", { greeting = greeting(d), menu = MENU })
end)

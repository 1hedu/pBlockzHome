-- The trading house floor: PulseX, laid out the way PulseX lays it out.
--
-- Two tabs, because there are two things people do here. Swap is the card everyone
-- knows -- From over To, a rate, and the row of numbers that says what the trade will
-- actually cost you. Liquidity is the other half of a V2 exchange and the half that
-- usually gets left out: your share of a pool, what it is worth, and the way back out.
--
-- The labels are PulseX's own, taken from its interface rather than from memory:
-- "Slippage Tolerance", "Minimum received", "Price Impact", "Route", and a button that
-- walks Enter an amount -> Insufficient X balance -> Swap.
--
-- Nothing here signs. Every number is read by the host off the pools and every
-- transaction goes through the wallet prompt, which shows what it read rather than what
-- this panel claimed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("TradeRemote")

local W, H = 780, 620
local CLOSE_DISTANCE = 16

-- ---- state ----------------------------------------------------------------------------
local tokens = {}          -- everything tradeable, from the host
local depth = {}           -- symbol -> { out, liquidity, pair }
local positions = {}
local fromToken, toToken = nil, nil
local slippageBps = 50
local quote = nil
local canSign = false
local picking = nil        -- which slot the token list is filling, if it is up
-- Declared here because setToken is defined before the pool tab is built and has to
-- be able to set these; without it, picking a token for a pool quietly set the swap
-- tab's destination instead, which is where the old "pool" case ended up.
local poolToken, poolTokenB, addToken, addTokenB
local tab = "swap"
--- What Max keeps back on the PLS side, in PLS.
---
--- The native coin pays for the transaction as well as being in it, so the whole of it is never
--- sendable and a Max that fills in every last one is a trade that cannot be sent. This is some
--- hundreds of times what a swap costs on this chain, and still leaves all but a hundredth.
local PLS_RESERVE = 0.01
--- The two pool-side balances as the last quote reported them, in units, for Max.
local poolBalances = { a_units = "", a_decimals = 18, b_units = "", b_decimals = 18 }

local screen = Instance.new("ScreenGui")

-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "PulseX"
screen.Enabled = false
screen.ResetOnSpawn = false
screen.Parent = gui

local panel, panelWindow = Theme.window(screen, UDim2.new(0, 780, 0, 620), UDim2.new(0.5, -390, 0.5, -310))

-- Drawn at 780 by 620. A little small rather than unreadable, so this lifts it to suit
-- the window without touching a single position inside it.
-- Steps this window through its sizes. Per window rather than one control for all
-- of them, because every panel's chrome is a different shape and the corner each
-- one can spare is not the same corner.
Theme.scaleButton(screen, panel, UDim2.new(0, 230, 0, 16))

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 200, 0, 26)
title.Position = UDim2.new(0, 18, 0, 14)
title.BackgroundTransparency = 1
title.TextColor3 = Theme.c.accent
title.TextSize = Theme.t.title
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "PulseX"
Theme.face(title)
title.Parent = panel

local chainLabel = Instance.new("TextLabel")
chainLabel.Size = UDim2.new(0, 240, 0, 26)
chainLabel.Position = UDim2.new(1, -258, 0, 14)
chainLabel.BackgroundTransparency = 1
chainLabel.TextColor3 = Theme.c.dim
chainLabel.TextSize = Theme.t.small
chainLabel.TextXAlignment = Enum.TextXAlignment.Right
chainLabel.Text = ""
Theme.face(chainLabel)
chainLabel.Parent = panel

-- ---- tabs -----------------------------------------------------------------------------
local tabButtons = {}
-- Each as wide as its own word. "Liquidity" is 120-odd pixels at this size and the tab was
-- 96, so the word ran out of both ends of the lit tab.
local function makeTab(key, label, x, w)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 0, 40)
	b.Position = UDim2.new(0, x, 0, 46)
	b.BackgroundColor3 = Theme.c.card
	b.TextColor3 = Theme.c.dim
	b.TextSize = Theme.t.body
	b.AutoButtonColor = false
	b.Text = label
	Theme.face(b)
	b.Parent = panel
	Theme.corner(b, 6)
	tabButtons[key] = b
	return b
end

local swapPage = Instance.new("Frame")
swapPage.Size = UDim2.new(1, 0, 1, -84)
swapPage.Position = UDim2.new(0, 0, 0, 84)
swapPage.BackgroundTransparency = 1
swapPage.Parent = panel

local poolPage = Instance.new("Frame")
poolPage.Size = UDim2.new(1, 0, 1, -84)
poolPage.Position = UDim2.new(0, 0, 0, 84)
poolPage.BackgroundTransparency = 1
poolPage.Visible = false
poolPage.Parent = panel

local function showTab(which)
	tab = which
	swapPage.Visible = which == "swap"
	poolPage.Visible = which == "pool"
	for key, b in pairs(tabButtons) do
		b.BackgroundColor3 = key == which and Theme.c.accent or Theme.c.card
		b.TextColor3 = key == which and Theme.c.ink or Theme.c.dim
	end
	-- Not asked for again here: the open asked, and so does every trade that lands. Asking on
	-- every tab click ran a second sweep of every pair, with the quote under the typing behind it.
end

makeTab("swap", "Swap", 18, 96).Activated:Connect(function() showTab("swap") end)
makeTab("pool", "Liquidity", 122, 160).Activated:Connect(function() showTab("pool") end)

-- Slippage, in the corner where the gear lives on every exchange.
local slipButton = Instance.new("TextButton")
slipButton.Size = UDim2.new(0, 150, 0, 28)
slipButton.Position = UDim2.new(1, -168, 0, 46)
slipButton.BackgroundColor3 = Theme.c.card
slipButton.TextColor3 = Theme.c.dim
slipButton.TextSize = Theme.t.small
slipButton.AutoButtonColor = false
slipButton.Text = "Swap Slippage  0.5%"
Theme.face(slipButton)
slipButton.Parent = panel
Theme.corner(slipButton, 6)

-- ---- the swap card --------------------------------------------------------------------

local function panelBox(parent, y, height)
	local box = Instance.new("Frame")
	box.Size = UDim2.new(1, -36, 0, height)
	box.Position = UDim2.new(0, 18, 0, y)
	box.BackgroundColor3 = Theme.c.card
	box.BackgroundTransparency = 0.3
	box.Parent = parent
	Theme.corner(box, 8)
	return box
end

--- One side of the trade: a label, a balance, an amount and the token button.
local function side(parent, y, label, editable)
	local box = panelBox(parent, y, 74)

	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.new(0, 120, 0, 16)
	tag.Position = UDim2.new(0, 12, 0, 8)
	tag.BackgroundTransparency = 1
	tag.TextColor3 = Theme.c.faint
	tag.TextSize = Theme.t.small
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.Text = label
	Theme.face(tag)
	tag.Parent = box

	local balance = Instance.new("TextLabel")
	balance.Size = UDim2.new(0, 240, 0, 16)
	balance.Position = UDim2.new(1, -252, 0, 8)
	balance.BackgroundTransparency = 1
	balance.TextColor3 = Theme.c.faint
	balance.TextSize = Theme.t.small
	balance.TextXAlignment = Enum.TextXAlignment.Right
	balance.Text = ""
	Theme.face(balance)
	balance.Parent = box

	local amount
	if editable then
		amount = Instance.new("TextBox")
		amount.ClearTextOnFocus = false
		amount.PlaceholderText = "0.0"
	else
		amount = Instance.new("TextLabel")
	end
	amount.Size = UDim2.new(1, -288, 0, 32)
	amount.Position = UDim2.new(0, 12, 0, 30)
	amount.BackgroundTransparency = 1
	amount.TextColor3 = Theme.c.ink
	amount.TextSize = Theme.t.title
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.Text = ""
	Theme.face(amount)
	amount.Parent = box

	-- Wide enough for its own label. "Select a token" measures 164 pixels in Reactor7 at
	-- text size 32 and the button was 110, so the words ran out of both ends of it -- and a
	-- GuiObject does not clip its text, so the part that spilled was not clickable either.
	-- The rest is room for a token symbol, which an imported ERC-20 can make long.
	local pick = Instance.new("TextButton")
	pick.Size = UDim2.new(0, 200, 0, 40)
	pick.Position = UDim2.new(1, -212, 0, 30)
	pick.BackgroundColor3 = Theme.c.button
	pick.TextColor3 = Theme.c.ink
	pick.TextSize = Theme.t.body
	pick.Text = "Select a token"
	Theme.face(pick)
	pick.Parent = box
	Theme.corner(pick, 6)

	return { box = box, balance = balance, amount = amount, pick = pick }
end

local from = side(swapPage, 6, "From", true)
local to = side(swapPage, 108, "To", false)

-- The flip, sitting between the two the way it does everywhere.
local flip = Instance.new("TextButton")
flip.Size = UDim2.new(0, 30, 0, 40)
flip.Position = UDim2.new(0.5, -15, 0, 84)
flip.BackgroundColor3 = Theme.c.tile
flip.TextColor3 = Theme.c.dim
flip.TextSize = Theme.t.body
flip.Text = "v"
Theme.face(flip)
flip.Parent = swapPage
Theme.corner(flip, 15)

local maxButton = Instance.new("TextButton")
maxButton.Size = UDim2.new(0, 40, 0, 20)
maxButton.Position = UDim2.new(1, -268, 0, 36)
maxButton.BackgroundColor3 = Theme.c.tile
maxButton.TextColor3 = Theme.c.accent
maxButton.TextSize = Theme.t.small
maxButton.Text = "Max"
Theme.face(maxButton)
maxButton.Parent = from.box
Theme.corner(maxButton, 4)

-- The rows underneath: the numbers that say what the trade costs.
local details = panelBox(swapPage, 190, 96)
local detailRows = {}
local DETAIL_KEYS = { "Price", "Minimum received", "Price Impact", "Route" }
for i, key in ipairs(DETAIL_KEYS) do
	local y = 8 + (i - 1) * 21
	local left = Instance.new("TextLabel")
	left.Size = UDim2.new(0, 150, 0, 18)
	left.Position = UDim2.new(0, 12, 0, y)
	left.BackgroundTransparency = 1
	left.TextColor3 = Theme.c.faint
	left.TextSize = Theme.t.small
	left.TextXAlignment = Enum.TextXAlignment.Left
	left.Text = key
	Theme.face(left)
	left.Parent = details

	local right = Instance.new("TextLabel")
	right.Size = UDim2.new(1, -180, 0, 18)
	right.Position = UDim2.new(0, 168, 0, y)
	right.BackgroundTransparency = 1
	right.TextColor3 = Theme.c.ink
	right.TextSize = Theme.t.small
	right.TextXAlignment = Enum.TextXAlignment.Right
	right.TextTruncate = Enum.TextTruncate.AtEnd
	right.Text = "-"
	Theme.face(right)
	right.Parent = details
	detailRows[key] = right
end

local action = Instance.new("TextButton")
action.Size = UDim2.new(1, -36, 0, 44)
action.Position = UDim2.new(0, 18, 0, 300)
action.BackgroundColor3 = Theme.c.muted
action.TextColor3 = Theme.c.dim
action.TextSize = Theme.t.heading
action.AutoButtonColor = false
action.Text = "Enter an amount"
Theme.face(action)
action.Parent = swapPage
Theme.corner(action, 8)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -36, 0, 60)
status.Position = UDim2.new(0, 18, 0, 352)
status.BackgroundTransparency = 1
status.TextColor3 = Theme.c.dim
status.TextSize = Theme.t.small
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Text = ""
Theme.face(status)
status.Parent = swapPage

-- ---- helpers --------------------------------------------------------------------------

local function symbolOf(t) return t and t.symbol or nil end

local function balanceOf(t)
	-- The host reports PLS separately from the ERC-20s; the panel only needs to show it.
	if not t then return "" end
	return ""
end

local function setToken(which, t)
	if which == "pool" then
		poolToken = t
		if addToken then addToken.Text = t and t.symbol or "Select a token" end
		return
	elseif which == "poolB" then
		poolTokenB = t
		if addTokenB then addTokenB.Text = t and t.symbol or "PLS" end
		return
	end
	if which == "from" then fromToken = t else toToken = t end
	local target = which == "from" and from or to
	target.pick.Text = t and t.symbol or "Select a token"
	-- What you hold of it, over the box. The label was made and never written to, so it sat
	-- empty on both sides and Max -- which fills the box from whatever is on this line -- had
	-- nothing to read and did nothing when pressed.
	target.balance.Text = (t and t.balance and t.balance ~= "") and ("Balance: %s"):format(t.balance) or ""
end

local function quoteNow()
	quote = nil
	detailRows["Price"].Text = "-"
	detailRows["Minimum received"].Text = "-"
	detailRows["Price Impact"].Text = "-"
	detailRows["Route"].Text = "-"
	to.amount.Text = ""
	local amt = from.amount.Text
	if not fromToken or not toToken then
		action.Text = "Select a token"
		action.BackgroundColor3 = Theme.c.muted
		action.TextColor3 = Theme.c.dim
		return
	end
	if amt == "" or tonumber(amt) == nil or tonumber(amt) <= 0 then
		action.Text = "Enter an amount"
		action.BackgroundColor3 = Theme.c.muted
		action.TextColor3 = Theme.c.dim
		return
	end
	action.Text = "Fetching best price..."
	action.BackgroundColor3 = Theme.c.muted
	action.TextColor3 = Theme.c.dim
	remote:FireServer("quote", fromToken.address, toToken.address, amt, slippageBps)
end

local function applyQuote(res)
	if not res.ok then
		to.amount.Text = ""
		action.Text = res.message or "Cannot find a valid swap route"
		action.BackgroundColor3 = Theme.c.muted
		action.TextColor3 = Theme.c.dim
		return
	end
	quote = res
	to.amount.Text = res.out
	detailRows["Minimum received"].Text = ("%s %s"):format(res.min_received, res.to_symbol)
	detailRows["Price Impact"].Text = res.impact
	detailRows["Route"].Text = res.route
	local inAmt = tonumber(from.amount.Text) or 0
	local outAmt = tonumber(res.out) or 0
	if inAmt > 0 then
		detailRows["Price"].Text = ("1 %s = %.6f %s"):format(res.from_symbol, outAmt / inAmt, res.to_symbol)
	end
	-- Impact is coloured because it is the number that quietly costs people money.
	local bps = res.impact_bps or 0
	detailRows["Price Impact"].TextColor3 =
		bps >= 500 and Color3.fromRGB(226, 112, 108)
		or bps >= 100 and Theme.c.warnInk
		or Theme.c.figure

	if not canSign then
		action.Text = "No key loaded"
		action.BackgroundColor3 = Theme.c.muted
		action.TextColor3 = Theme.c.dim
	elseif bps >= 1500 then
		action.Text = "Swap Anyway"
		action.BackgroundColor3 = Theme.c.danger
		action.TextColor3 = Theme.c.ink
		action.AutoButtonColor = true
	else
		action.Text = "Swap"
		action.BackgroundColor3 = Theme.c.good
		action.TextColor3 = Theme.c.ink
		action.AutoButtonColor = true
	end
end

from.amount:GetPropertyChangedSignal("Text"):Connect(quoteNow)

flip.Activated:Connect(function()
	local a, b = fromToken, toToken
	setToken("from", b)
	setToken("to", a)
	quoteNow()
end)

--- Units as the whole decimal, however many places that takes.
---
--- The balance line is rounded to four places because that is what reads; Max has to fill the
--- box with all of it, or asking to swap everything quietly leaves dust behind. Done on the
--- digits rather than through a number: a balance in wei is past what a double holds exactly,
--- and rounding somebody's money to fifteen significant figures is not this button's to do.
local function wholeOf(units, decimals)
	units = tostring(units or "")
	if units == "" or units:match("%D") then return "" end
	decimals = tonumber(decimals) or 18
	if decimals <= 0 then return units end
	while #units <= decimals do units = "0" .. units end
	local w = units:sub(1, #units - decimals)
	local f = (units:sub(#units - decimals + 1):gsub("0+$", ""))
	return f == "" and w or (w .. "." .. f)
end

--- Everything you hold of the side you are selling, in the box.
---
--- It used to read the number back out of the balance label, which was never written to on this
--- card -- the label was made and left empty -- so the button did nothing at all, on every token,
--- every time. It takes the figure from the token now, which is where it actually is.
maxButton.Activated:Connect(function()
	if not fromToken then return end
	local all = wholeOf(fromToken.balance_units, fromToken.decimals)
	if all == "" then
		status.Text = "Your balance has not been read yet. It fills itself in."
		return
	end
	if (fromToken.address or "") == "" then
		-- The native coin pays for the transaction as well as travelling in it, so the whole of
		-- it is never sendable: the fee has to come from somewhere, and a swap of every last
		-- PLS is refused for want of the gas to send it. A hundredth of a PLS is some hundreds
		-- of times what a swap costs on this chain.
		local n = tonumber(all)
		if not n then return end
		if n <= PLS_RESERVE then
			status.Text = ("There is not enough PLS here to swap and still pay the fee (%s PLS)."):format(all)
			return
		end
		all = (("%.6f"):format(n - PLS_RESERVE):gsub("0+$", ""):gsub("%.$", ""))
	end
	from.amount.Text = all
end)

slipButton.Activated:Connect(function()
	-- 0.5 -> 1 -> 3 -> 0.1, the presets every exchange offers.
	local order = { [50] = 100, [100] = 300, [300] = 10, [10] = 50 }
	slippageBps = order[slippageBps] or 50
	slipButton.Text = ("Swap Slippage  %s%%"):format(slippageBps / 100)
	quoteNow()
end)

action.Activated:Connect(function()
	if not quote or not quote.ok or not canSign then return end
	action.Text = "Confirm this transaction in your wallet"
	action.BackgroundColor3 = Theme.c.muted
	action.AutoButtonColor = false
	remote:FireServer("swap", fromToken.address, toToken.address, from.amount.Text, slippageBps)
end)

-- ---- the token list -------------------------------------------------------------------

local picker = Instance.new("Frame")
picker.Size = UDim2.new(1, -36, 1, -60)
picker.Position = UDim2.new(0, 18, 0, 46)
picker.BackgroundColor3 = Theme.c.panel
picker.Visible = false
picker.ZIndex = 5
picker.Parent = panel
Theme.corner(picker, 10)

local pickTitle = Instance.new("TextLabel")
pickTitle.Size = UDim2.new(1, -24, 0, 24)
pickTitle.Position = UDim2.new(0, 12, 0, 10)
pickTitle.BackgroundTransparency = 1
pickTitle.TextColor3 = Theme.c.ink
pickTitle.TextSize = Theme.t.heading
pickTitle.TextXAlignment = Enum.TextXAlignment.Left
pickTitle.Text = "Select a Token"
pickTitle.ZIndex = 6
Theme.face(pickTitle)
pickTitle.Parent = picker

local pasteBox = Instance.new("TextBox")
pasteBox.Size = UDim2.new(1, -144, 0, 30)
pasteBox.Position = UDim2.new(0, 12, 0, 40)
pasteBox.BackgroundColor3 = Theme.c.field
pasteBox.TextColor3 = Theme.c.ink
pasteBox.TextSize = Theme.t.small
pasteBox.PlaceholderText = "Paste any token address (0x...)"
pasteBox.ClearTextOnFocus = false
pasteBox.Text = ""
pasteBox.ZIndex = 6
Theme.face(pasteBox)
pasteBox.Parent = picker
Theme.corner(pasteBox, 6)

local importButton = Instance.new("TextButton")
importButton.Size = UDim2.new(0, 110, 0, 44)
importButton.Position = UDim2.new(1, -122, 0, 40)
importButton.BackgroundColor3 = Theme.c.button
importButton.TextColor3 = Theme.c.ink
importButton.TextSize = Theme.t.body
importButton.Text = "Import"
importButton.ZIndex = 6
Theme.face(importButton)
importButton.Parent = picker
Theme.corner(importButton, 6)

local pickNote = Instance.new("TextLabel")
pickNote.Size = UDim2.new(1, -24, 0, 30)
pickNote.Position = UDim2.new(0, 12, 0, 88)
pickNote.BackgroundTransparency = 1
pickNote.TextColor3 = Theme.c.faint
pickNote.TextSize = Theme.t.small
pickNote.TextWrapped = true
pickNote.TextXAlignment = Enum.TextXAlignment.Left
pickNote.Text = "Anything with a PulseX pool can be traded. Names come off the token itself."
pickNote.ZIndex = 6
Theme.face(pickNote)
pickNote.Parent = picker

local pickList = Instance.new("ScrollingFrame")
pickList.Position = UDim2.new(0, 12, 0, 124)
pickList.Size = UDim2.new(1, -24, 1, -188)
pickList.BackgroundTransparency = 1
pickList.ScrollBarThickness = 6
pickList.ScrollBarImageColor3 = Theme.c.scrollbar
pickList.AutomaticCanvasSize = Enum.AutomaticSize.Y
pickList.CanvasSize = UDim2.new(0, 0, 0, 0)
pickList.ZIndex = 6
pickList.Parent = picker
local pickLayout = Instance.new("UIListLayout")
pickLayout.Padding = UDim.new(0, 4)
pickLayout.Parent = pickList

local pickClose = Instance.new("TextButton")
pickClose.Size = UDim2.new(0, 90, 0, 40)
pickClose.Position = UDim2.new(1, -102, 1, -52)
pickClose.BackgroundColor3 = Theme.c.button
pickClose.TextColor3 = Theme.c.ink
pickClose.TextSize = Theme.t.body
pickClose.Text = "Close"
pickClose.ZIndex = 6
Theme.face(pickClose)
pickClose.Parent = picker
Theme.corner(pickClose, 6)

pickClose.Activated:Connect(function() picker.Visible = false; picking = nil end)

local function drawPicker()
	for _, child in ipairs(pickList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	for _, t in ipairs(tokens) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, 40)
		row.BackgroundColor3 = Theme.c.card
		row.BackgroundTransparency = 0.35
		row.ZIndex = 6
		row.Parent = pickList
		Theme.corner(row, 5)

		-- The whole row is the target, so it has to sit above the row's own labels: a
		-- label is not transparent to the pointer, and the symbol and the name cover most
		-- of the button. Above them, not merely level with them -- at equal ZIndex the one
		-- made last wins, and the labels are made after this.
		local hit = Instance.new("TextButton")
		hit.Size = UDim2.new(1, -70, 1, 0)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = 9
		Theme.face(hit)
		hit.Parent = row

		local sym = Instance.new("TextLabel")
		sym.Size = UDim2.new(0, 90, 1, 0)
		sym.Position = UDim2.new(0, 10, 0, 0)
		sym.BackgroundTransparency = 1
		sym.TextColor3 = Theme.c.ink
		sym.TextSize = Theme.t.body
		sym.TextXAlignment = Enum.TextXAlignment.Left
		sym.Text = t.symbol
		sym.ZIndex = 7
		Theme.face(sym)
		sym.Parent = row

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -190, 1, 0)
		name.Position = UDim2.new(0, 104, 0, 0)
		name.BackgroundTransparency = 1
		name.TextColor3 = Theme.c.faint
		name.TextSize = Theme.t.small
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local d = depth[t.symbol]
		name.Text = t.custom and (t.name .. "  (yours)") or t.name
		name.ZIndex = 7
		Theme.face(name)
		name.Parent = row

		if d and d.liquidity ~= "" then
			local liq = Instance.new("TextLabel")
			liq.Size = UDim2.new(0, 120, 1, 0)
			liq.Position = UDim2.new(1, -132, 0, 0)
			liq.BackgroundTransparency = 1
			liq.TextColor3 = Theme.c.figure
			liq.TextSize = Theme.t.small
			liq.TextXAlignment = Enum.TextXAlignment.Right
			liq.Text = d.liquidity .. " PLS"
			liq.ZIndex = 7
			Theme.face(liq)
			liq.Parent = row
		end

		hit.Activated:Connect(function()
			if picking then setToken(picking, t) end
			picker.Visible = false
			picking = nil
			quoteNow()
		end)

		-- Something you pasted in, you can take back out.
		if t.custom then
			local drop = Instance.new("TextButton")
			drop.Size = UDim2.new(0, 24, 0, 24)
			drop.Position = UDim2.new(1, -30, 0, 8)
			drop.BackgroundColor3 = Theme.c.danger
			drop.TextColor3 = Theme.c.ink
			drop.TextSize = Theme.t.small
			drop.Text = "x"
			drop.ZIndex = 8
			Theme.face(drop)
			drop.Parent = row
			Theme.corner(drop, 4)
			drop.Activated:Connect(function()
				remote:FireServer("forget_token", t.address)
			end)
		end
	end
end

from.pick.Activated:Connect(function() picking = "from"; drawPicker(); picker.Visible = true end)
to.pick.Activated:Connect(function() picking = "to"; drawPicker(); picker.Visible = true end)

importButton.Activated:Connect(function()
	local addr = pasteBox.Text:gsub("%s", "")
	if addr == "" then return end
	pickNote.Text = "Reading the token..."
	remote:FireServer("add_token", addr)
end)

-- ---- liquidity ------------------------------------------------------------------------
--
-- Laid out the way PulseX's Add Liquidity page is, because that is the page people know:
-- two inputs, a balance over each with a Max beside it, type on either side and the other
-- fills in from the pool's ratio, then "Prices and pool share" -- the two prices and the
-- share of the pool you would hold -- and a Supply button that walks Select a token ->
-- Enter an amount -> Insufficient X balance -> Supply. What you would get is said in the
-- wallet prompt, as it is in PulseX's confirm: the LP tokens and the share they are.

local poolTitle = Instance.new("TextLabel")
poolTitle.Size = UDim2.new(1, -36, 0, 20)
poolTitle.Position = UDim2.new(0, 18, 0, 6)
poolTitle.BackgroundTransparency = 1
poolTitle.TextColor3 = Theme.c.ink
poolTitle.TextSize = Theme.t.heading
poolTitle.TextXAlignment = Enum.TextXAlignment.Left
poolTitle.Text = "Your Liquidity"
Theme.face(poolTitle)
poolTitle.Parent = poolPage

-- One word over the column of quarter buttons, as a section label: the buttons say how
-- much, this says what of.
local removeHead = Instance.new("TextLabel")
removeHead.Size = UDim2.new(0, 178, 0, 16)
removeHead.Position = UDim2.new(1, -214, 0, 12)
removeHead.BackgroundTransparency = 1
removeHead.TextColor3 = Theme.c.faint
removeHead.TextSize = Theme.t.small
removeHead.TextXAlignment = Enum.TextXAlignment.Center
removeHead.Text = "Remove"
removeHead.Visible = false
Theme.face(removeHead)
removeHead.Parent = poolPage

local poolList = Instance.new("ScrollingFrame")
poolList.Position = UDim2.new(0, 18, 0, 32)
poolList.Size = UDim2.new(1, -36, 0, 150)
poolList.BackgroundTransparency = 1
poolList.ScrollBarThickness = 6
poolList.ScrollBarImageColor3 = Theme.c.scrollbar
poolList.AutomaticCanvasSize = Enum.AutomaticSize.Y
poolList.CanvasSize = UDim2.new(0, 0, 0, 0)
poolList.Parent = poolPage
local poolLayout = Instance.new("UIListLayout")
poolLayout.Padding = UDim.new(0, 6)
poolLayout.Parent = poolList

local poolEmpty = Instance.new("TextLabel")
poolEmpty.Size = UDim2.new(1, -36, 0, 40)
poolEmpty.Position = UDim2.new(0, 18, 0, 36)
poolEmpty.BackgroundTransparency = 1
poolEmpty.TextColor3 = Theme.c.dim
poolEmpty.TextSize = Theme.t.body
poolEmpty.TextWrapped = true
poolEmpty.TextXAlignment = Enum.TextXAlignment.Left
poolEmpty.TextYAlignment = Enum.TextYAlignment.Top
-- Until the first answer it says it is reading: the sweep of every pair takes this node a
-- while, and a blank list read as "no pools" before the question had been answered.
poolEmpty.Text = "Reading your pools..."
poolEmpty.Visible = true
Theme.face(poolEmpty)
poolEmpty.Parent = poolPage

local addBox = panelBox(poolPage, 190, 272)

local addTitle = Instance.new("TextLabel")
addTitle.Size = UDim2.new(1, -24, 0, 18)
addTitle.Position = UDim2.new(0, 12, 0, 8)
addTitle.BackgroundTransparency = 1
addTitle.TextColor3 = Theme.c.ink
addTitle.TextSize = Theme.t.body
addTitle.TextXAlignment = Enum.TextXAlignment.Left
addTitle.Text = "Add Liquidity"
Theme.face(addTitle)
addTitle.Parent = addBox

--- One side of the pair, as on the swap card: a tag, "Balance: x", the amount, Max, and the
--- token button.
local function poolSide(y, tag, defaultToken)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 120, 0, 16)
	label.Position = UDim2.new(0, 12, 0, y)
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.c.faint
	label.TextSize = Theme.t.small
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = tag
	Theme.face(label)
	label.Parent = addBox

	local balance = Instance.new("TextLabel")
	balance.Size = UDim2.new(0, 300, 0, 16)
	balance.Position = UDim2.new(1, -312, 0, y)
	balance.BackgroundTransparency = 1
	balance.TextColor3 = Theme.c.faint
	balance.TextSize = Theme.t.small
	balance.TextXAlignment = Enum.TextXAlignment.Right
	balance.Text = ""
	Theme.face(balance)
	balance.Parent = addBox

	local amount = Instance.new("TextBox")
	amount.Size = UDim2.new(1, -284, 0, 36)
	amount.Position = UDim2.new(0, 12, 0, y + 18)
	amount.BackgroundColor3 = Theme.c.field
	amount.TextColor3 = Theme.c.ink
	amount.TextSize = Theme.t.body
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.PlaceholderText = "0.0"
	amount.ClearTextOnFocus = false
	amount.Text = ""
	Theme.face(amount)
	amount.Parent = addBox
	Theme.corner(amount, 6)

	local max = Instance.new("TextButton")
	max.Size = UDim2.new(0, 44, 0, 24)
	max.Position = UDim2.new(1, -266, 0, y + 24)
	max.BackgroundColor3 = Theme.c.tile
	max.TextColor3 = Theme.c.accent
	max.TextSize = Theme.t.small
	max.Text = "Max"
	Theme.face(max)
	max.Parent = addBox
	Theme.corner(max, 4)

	local pick = Instance.new("TextButton")
	pick.Size = UDim2.new(0, 200, 0, 36)
	pick.Position = UDim2.new(1, -212, 0, y + 18)
	pick.BackgroundColor3 = Theme.c.button
	pick.TextColor3 = Theme.c.ink
	pick.TextSize = Theme.t.body
	pick.Text = defaultToken
	Theme.face(pick)
	pick.Parent = addBox
	Theme.corner(pick, 6)

	return { balance = balance, amount = amount, max = max, pick = pick }
end

local sideA = poolSide(30, "Input", "Select a token")

local plus = Instance.new("TextLabel")
plus.Size = UDim2.new(1, -24, 0, 16)
plus.Position = UDim2.new(0, 12, 0, 88)
plus.BackgroundTransparency = 1
plus.TextColor3 = Theme.c.dim
plus.TextSize = Theme.t.small
plus.Text = "+"
Theme.face(plus)
plus.Parent = addBox

local sideB = poolSide(106, "Input", "PLS")
addToken = sideA.pick
addTokenB = sideB.pick

-- "Prices and pool share", the three figures PulseX prints under the inputs.
local prices = Instance.new("Frame")
prices.Size = UDim2.new(1, -24, 0, 50)
prices.Position = UDim2.new(0, 12, 0, 168)
prices.BackgroundColor3 = Theme.c.tile
prices.Parent = addBox
Theme.corner(prices, 6)

local priceCells = {}
for i = 1, 3 do
	local value = Instance.new("TextLabel")
	value.Size = UDim2.new(1 / 3, -8, 0, 18)
	value.Position = UDim2.new((i - 1) / 3, 4, 0, 6)
	value.BackgroundTransparency = 1
	value.TextColor3 = Theme.c.figure
	value.TextSize = Theme.t.small
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.Text = "-"
	Theme.face(value)
	value.Parent = prices

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1 / 3, -8, 0, 16)
	caption.Position = UDim2.new((i - 1) / 3, 4, 0, 27)
	caption.BackgroundTransparency = 1
	caption.TextColor3 = Theme.c.faint
	caption.TextSize = Theme.t.small
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.Text = ({ "per", "per", "Share of Pool" })[i]
	Theme.face(caption)
	caption.Parent = prices
	priceCells[i] = { value = value, caption = caption }
end

local addGo = Instance.new("TextButton")
addGo.Size = UDim2.new(1, -24, 0, 40)
addGo.Position = UDim2.new(0, 12, 0, 226)
addGo.BackgroundColor3 = Theme.c.muted
addGo.TextColor3 = Theme.c.dim
addGo.TextSize = Theme.t.body
addGo.AutoButtonColor = false
addGo.Text = "Select a token"
Theme.face(addGo)
addGo.Parent = addBox
Theme.corner(addGo, 8)

local poolStatus = Instance.new("TextLabel")
poolStatus.Size = UDim2.new(1, -36, 0, 60)
poolStatus.Position = UDim2.new(0, 18, 0, 470)
poolStatus.BackgroundTransparency = 1
poolStatus.TextColor3 = Theme.c.dim
poolStatus.TextSize = Theme.t.small
poolStatus.TextWrapped = true
poolStatus.TextXAlignment = Enum.TextXAlignment.Left
poolStatus.TextYAlignment = Enum.TextYAlignment.Top
poolStatus.Text = ""
Theme.face(poolStatus)
poolStatus.Parent = poolPage

-- An empty address is the native coin, so this starts out exactly where the panel used to.
poolTokenB = { symbol = "PLS", address = "" }
local typedSide = "a"      -- which input was typed last: that one is sent, the other is derived
local filling = false      -- set while this script fills a box, so it does not quote itself
local poolQuoted = nil     -- the last answer, so Supply knows whether it may go
local canSupply = false
local poolSeq = 0          -- numbers the quotes, so an older answer landing late is ignored

local function supplyState(text, live)
	addGo.Text = text
	canSupply = live == true
	addGo.BackgroundColor3 = canSupply and Theme.c.good or Theme.c.muted
	addGo.TextColor3 = canSupply and Theme.c.ink or Theme.c.dim
	addGo.AutoButtonColor = canSupply
end

local function clearPrices()
	for i = 1, 3 do priceCells[i].value.Text = "-" end
	priceCells[1].caption.Text = "per"
	priceCells[2].caption.Text = "per"
end

local function poolQuote(side)
	if side then typedSide = side end
	poolQuoted = nil
	local other = typedSide == "a" and sideB or sideA
	local typed = typedSide == "a" and sideA or sideB
	if not poolToken or not poolTokenB then
		clearPrices()
		supplyState("Select a token")
		return
	end
	if poolToken.address == poolTokenB.address then
		clearPrices()
		supplyState("Those are the same token")
		return
	end
	local amt = typed.amount.Text
	if amt == "" or tonumber(amt) == nil or tonumber(amt) <= 0 then
		filling = true
		other.amount.Text = ""
		filling = false
		amt = ""
		supplyState("Enter an amount")
	else
		supplyState("Reading the pool...")
	end
	poolSeq += 1
	remote:FireServer("pool_quote", poolToken.address, poolTokenB.address, amt, typedSide, poolSeq)
end

local function applyPoolQuote(res)
	-- Picking a token and typing an amount both ask; the two answers can land in either order.
	if res.tag ~= nil and res.tag ~= poolSeq then return end
	if not res.ok then
		clearPrices()
		supplyState(res.message or "The pool did not answer.")
		return
	end
	sideA.balance.Text = res.a_balance ~= "" and ("Balance: %s"):format(res.a_balance) or ""
	sideB.balance.Text = res.b_balance ~= "" and ("Balance: %s"):format(res.b_balance) or ""
	-- Kept as they came, in units: what Max fills the box with.
	poolBalances.a_units, poolBalances.a_decimals = res.a_balance_units, res.a_decimals
	poolBalances.b_units, poolBalances.b_decimals = res.b_balance_units, res.b_decimals
	if not res.pool then
		clearPrices()
		supplyState(res.message or "There is no pool for that pair.")
		return
	end
	priceCells[1].value.Text = res.price_ab ~= "" and res.price_ab or "-"
	priceCells[1].caption.Text = ("%s per %s"):format(res.b_symbol, res.a_symbol)
	priceCells[2].value.Text = res.price_ba ~= "" and res.price_ba or "-"
	priceCells[2].caption.Text = ("%s per %s"):format(res.a_symbol, res.b_symbol)
	priceCells[3].value.Text = res.share ~= "" and res.share or "-"
	if res.a_amount == "" or res.b_amount == "" then
		supplyState("Enter an amount")
		return
	end
	filling = true
	if typedSide == "a" then sideB.amount.Text = res.b_amount else sideA.amount.Text = res.a_amount end
	filling = false
	poolQuoted = res
	if res.a_short then
		supplyState(("Insufficient %s balance"):format(res.a_symbol))
	elseif res.b_short then
		supplyState(("Insufficient %s balance"):format(res.b_symbol))
	elseif not canSign then
		supplyState("No key loaded")
	else
		supplyState("Supply", true)
	end
end

sideA.amount:GetPropertyChangedSignal("Text"):Connect(function()
	if filling then return end
	poolQuote("a")
end)
sideB.amount:GetPropertyChangedSignal("Text"):Connect(function()
	if filling then return end
	poolQuote("b")
end)

--- Everything you hold of one side of the pair, in that side's box.
---
--- Off the units the quote sends, not off the balance line: the line is rounded to four places
--- for reading, and filling the box from it supplies four places' worth and leaves the rest.
--- The PLS side keeps back what the transaction costs, the same as the swap card's Max.
local function fillMax(side, units, decimals, isNative)
	local all = wholeOf(units, decimals)
	if all == "" then
		poolStatus.Text = "That balance has not been read yet. It fills itself in."
		return
	end
	if isNative then
		local n = tonumber(all)
		if not n then return end
		if n <= PLS_RESERVE then
			poolStatus.Text = ("There is not enough PLS here to supply and still pay the fee (%s PLS)."):format(all)
			return
		end
		all = (("%.6f"):format(n - PLS_RESERVE):gsub("0+$", ""):gsub("%.$", ""))
	end
	side.amount.Text = all
end

sideA.max.Activated:Connect(function()
	fillMax(sideA, poolBalances.a_units, poolBalances.a_decimals, (poolToken and poolToken.address or "") == "")
end)
sideB.max.Activated:Connect(function()
	fillMax(sideB, poolBalances.b_units, poolBalances.b_decimals, (poolTokenB and poolTokenB.address or "") == "")
end)

addToken.Activated:Connect(function()
	picking = "pool"
	drawPicker()
	picker.Visible = true
end)
addTokenB.Activated:Connect(function()
	picking = "poolB"
	drawPicker()
	picker.Visible = true
end)

addGo.Activated:Connect(function()
	if not canSupply or not poolQuoted or not poolToken or not poolTokenB then return end
	supplyState("Confirm this transaction in your wallet")
	-- Whichever side was typed is the one sent exactly; the wallet derives the other from the
	-- pool at signing time, the same way this card just did. slippageBps, not a hardcoded 100:
	-- the control in the corner governs this tab too.
	if typedSide == "b" then
		remote:FireServer("add_liquidity", poolTokenB.address, sideB.amount.Text, slippageBps, poolToken.address)
	else
		remote:FireServer("add_liquidity", poolToken.address, sideA.amount.Text, slippageBps, poolTokenB.address)
	end
end)

local function drawPositions()
	for _, child in ipairs(poolList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	poolEmpty.Text = "You are not in any pool yet. Adding liquidity earns you a cut of every trade through it."
	poolEmpty.Visible = #positions == 0
	poolList.Visible = #positions > 0
	removeHead.Visible = #positions > 0
	for _, p in ipairs(positions) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -6, 0, 62)
		row.BackgroundColor3 = Theme.c.card
		row.BackgroundTransparency = 0.3
		row.Parent = poolList
		Theme.corner(row, 6)

		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0, 200, 0, 20)
		name.Position = UDim2.new(0, 12, 0, 8)
		name.BackgroundTransparency = 1
		name.TextColor3 = Theme.c.ink
		name.TextSize = Theme.t.body
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = ("%s / %s"):format(p.symbol, p.symbol_b or "PLS")
		Theme.face(name)
		name.Parent = row

		-- What PulseX lists for a position: the two pooled amounts, your pool tokens, your share.
		local holding = Instance.new("TextLabel")
		holding.Size = UDim2.new(1, -212, 0, 16)   -- stops short of the buttons, or a long share ran under them
		holding.Position = UDim2.new(0, 12, 0, 30)
		holding.TextTruncate = Enum.TextTruncate.AtEnd
		holding.BackgroundTransparency = 1
		holding.TextColor3 = Theme.c.faint
		holding.TextSize = Theme.t.small
		holding.TextXAlignment = Enum.TextXAlignment.Left
		holding.Text = ("Pooled %s %s  +  %s %s   .   %s LP tokens   .   %s of the pool"):format(
			p.token_amount, p.symbol, p.pls_amount, p.symbol_b or "PLS", p.lp or "?", p.share)
		Theme.face(holding)
		holding.Parent = row

		-- Out in quarters, which is how everyone actually takes a position off. What comes back
		-- for that quarter is said in the wallet prompt before anything is signed.
		local x = 0
		for _, pct in ipairs({ 25, 50, 75, 100 }) do
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(0, 42, 0, 40)
			b.Position = UDim2.new(1, -190 + x, 0, 6)
			b.BackgroundColor3 = Theme.c.button
			b.TextColor3 = Theme.c.ink
			b.TextSize = Theme.t.small
			b.Text = pct .. "%"
			Theme.face(b)
			b.Parent = row
			Theme.corner(b, 4)
			b.Activated:Connect(function()
				poolStatus.Text = "Confirm it in your wallet."
				remote:FireServer("remove_liquidity", p.address, pct, slippageBps, p.address_b or "")
			end)
			x += 46
		end
	end
end

-- ---- wiring ---------------------------------------------------------------------------

remote.OnClientEvent:Connect(function(kind, payload)
	-- The desk says to put it away: pressing E at an open window is asking for it to go.
	if kind == "shut" then
		screen.Enabled = false
		return
	end
	if kind == "market" then
		Theme.takeOver(gui)
		screen.Enabled = true
		if payload.loading then
			status.Text = "Reading the pools. This fills itself in."
			return
		end
		tokens = payload.tokens or {}
		depth = payload.depth or {}
		canSign = payload.can_sign == true
		chainLabel.Text = ("chain %s   .   %s"):format(tostring(payload.chain_id or "?"), payload.site or "")
		status.Text = ("Swaps settle on PulseX's own router on this chain. %s"):format(
			canSign and "" or "No key is loaded, so nothing can be signed.")
		-- Open on PLS, which is what everyone is holding.
		if not fromToken then
			for _, t in ipairs(tokens) do
				if t.symbol == "PLS" then setToken("from", t) end
			end
		end
		-- The sides already chosen point at entries from the last list, and the balances on
		-- this one have moved -- a swap or a withdrawal is exactly when they do. Point them at
		-- the new entry for the same address so the lines say what is held now.
		for _, side in ipairs({ { "from", fromToken }, { "to", toToken } }) do
			if side[2] then
				for _, t in ipairs(tokens) do
					if (t.address or "") == (side[2].address or "") then
						setToken(side[1], t)
						break
					end
				end
			end
		end
		if picker.Visible then drawPicker() end

	elseif kind == "quoted" then
		applyQuote(payload)

	elseif kind == "swapped" then
		status.Text = payload.message or ""
		action.Text = payload.ok and "Swap" or "Swap"
		action.BackgroundColor3 = payload.ok and Theme.c.good or Theme.c.danger
		action.AutoButtonColor = true
		if payload.ok then
			from.amount.Text = ""
			to.amount.Text = ""
		end

	elseif kind == "token_added" then
		pickNote.Text = payload.message or ""
		if payload.ok then pasteBox.Text = "" end
		remote:FireServer("open")

	elseif kind == "positions" then
		positions = payload.positions or {}
		drawPositions()
		-- The balances over the inputs move with every trade, so the card re-reads with the list.
		poolQuote()

	elseif kind == "pool_quoted" then
		applyPoolQuote(payload)

	elseif kind == "pooled" then
		poolStatus.Text = payload.message or ""
		if payload.ok then
			filling = true
			sideA.amount.Text = ""
			sideB.amount.Text = ""
			filling = false
		end
		poolQuote()
		remote:FireServer("positions")
	end
end)

-- The pool tab's token button shares the picker, so it needs its own landing.
local realSetToken = setToken
setToken = function(which, t)
	if which == "pool" then
		poolToken = t
		addToken.Text = t and t.symbol or "Select a token"
		poolQuote()
		return
	elseif which == "poolB" then
		poolTokenB = t
		addTokenB.Text = t and t.symbol or "PLS"
		poolQuote()
		return
	end
	realSetToken(which, t)
end

showTab("swap")

RunService.Heartbeat:Connect(function()
	if not screen.Enabled then return end
	local map = workspace:FindFirstChild("Map")
	local npc = map and map:FindFirstChild("Trader")
	local torso = npc and npc:FindFirstChild("Torso")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not torso or not root then return end
	if (root.Position - torso.Position).Magnitude > CLOSE_DISTANCE then
		screen.Enabled = false
		picker.Visible = false
		remote:FireServer("close")
	end
end)

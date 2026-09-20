-- Doug's board: every PulseChain pool worth looking at, sorted by depth.
--
-- The first version of this had two columns derived from getReserves, because I built
-- it without checking what was available. DexScreener publishes all of it -- price in
-- dollars, 24h volume, the change over five minutes to a day, buys against sells, FDV,
-- and how old the pool is -- for one HTTP call and no key.
--
-- The split worth being straight about: this is mainnet, where the volume is. Rebh's
-- counter trades on this testnet. Both are said on the board rather than blurred,
-- because a screener that implies you can act on its numbers is the same mistake the
-- trading house just came out of.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("ScreenerRemote")
local Market = require(ReplicatedStorage:WaitForChild("Market"))
-- The board's own row builder, used on searched pools too so both look the same.
local Dex = require(ReplicatedStorage:WaitForChild("Dexscreener"))

-- Declared up here because the search box is built before the drawing is, and a local
-- declared after the closure that calls it is a different variable -- the closure gets the
-- global, which is nil.
local draw
-- The last board the server sent. Kept so a market answer can be drawn into it without
-- waiting for the next refresh to come round.
local lastBoard = nil
-- What the market found for the word currently in the box.
local marketRows = {}

local W, H = 1080, 620
local ROW = 34
local CLOSE_DISTANCE = 16

local UP = Color3.fromRGB(96, 214, 128)
local DOWN = Color3.fromRGB(226, 112, 108)

local screen = Instance.new("ScreenGui")


-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "Screener"
screen.Enabled = false
screen.ResetOnSpawn = false
screen.Parent = gui

local panel, panelWindow = Theme.window(screen, UDim2.new(0, 1080, 0, 620), UDim2.new(0.5, -540, 0.5, -310))

-- Dense columns of small figures, drawn at 1080 by 620 and correct at that size -- just
-- far too small on a real screen. So the whole thing is magnified to suit the window
-- rather than laid out larger: every column keeps its proportions and its place.
-- Steps this window through its sizes. Per window rather than one control for all
-- of them, because every panel's chrome is a different shape and the corner each
-- one can spare is not the same corner.
Theme.scaleButton(screen, panel, UDim2.new(0, 450, 0, 16))

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0, 420, 0, 26)
title.Position = UDim2.new(0, 18, 0, 14)
title.BackgroundTransparency = 1
title.TextColor3 = Theme.c.accent
title.TextSize = Theme.t.title
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Doug  <Dexscreener>"
Theme.face(title)
title.Parent = panel

local sourceLabel = Instance.new("TextLabel")
sourceLabel.Size = UDim2.new(0, 400, 0, 26)
sourceLabel.Position = UDim2.new(1, -418, 0, 14)
sourceLabel.BackgroundTransparency = 1
sourceLabel.TextColor3 = Theme.c.dim
sourceLabel.TextSize = Theme.t.small
sourceLabel.TextXAlignment = Enum.TextXAlignment.Right
sourceLabel.Text = ""
Theme.face(sourceLabel)
sourceLabel.Parent = panel

local sub = Instance.new("TextLabel")
sub.Size = UDim2.new(1, -36, 0, 16)
sub.Position = UDim2.new(0, 18, 0, 42)
sub.BackgroundTransparency = 1
sub.TextColor3 = Theme.c.faint
sub.TextSize = Theme.t.small
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Text = ""
Theme.face(sub)
sub.Parent = panel

-- Column geometry in one place, so a heading and its column cannot drift apart.
local COLUMNS = {
	{ key = "n",         label = "#",         x = 10,  w = 26,  align = Enum.TextXAlignment.Left },
	{ key = "pair",      label = "PAIR",      x = 40,  w = 150, align = Enum.TextXAlignment.Left },
	{ key = "price",     label = "PRICE",     x = 194, w = 108, align = Enum.TextXAlignment.Right },
	{ key = "age",       label = "AGE",       x = 306, w = 46,  align = Enum.TextXAlignment.Right },
	{ key = "txns",      label = "TXNS",      x = 356, w = 76,  align = Enum.TextXAlignment.Right },
	{ key = "volume",    label = "VOLUME",    x = 436, w = 84,  align = Enum.TextXAlignment.Right },
	{ key = "m5",        label = "5M",        x = 524, w = 58,  align = Enum.TextXAlignment.Right },
	{ key = "h1",        label = "1H",        x = 586, w = 58,  align = Enum.TextXAlignment.Right },
	{ key = "h6",        label = "6H",        x = 648, w = 58,  align = Enum.TextXAlignment.Right },
	{ key = "h24",       label = "24H",       x = 710, w = 58,  align = Enum.TextXAlignment.Right },
	{ key = "liquidity", label = "LIQUIDITY", x = 772, w = 84,  align = Enum.TextXAlignment.Right },
	{ key = "fdv",       label = "FDV",       x = 860, w = 76,  align = Enum.TextXAlignment.Right },
}

local head = Instance.new("Frame")
head.Size = UDim2.new(1, -36, 0, 24)
head.Position = UDim2.new(0, 18, 0, 64)
head.BackgroundColor3 = Theme.c.card
head.BackgroundTransparency = 0.35
head.Parent = panel
Theme.corner(head, 4)

for _, col in ipairs(COLUMNS) do
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, col.w, 1, 0)
	label.Position = UDim2.new(0, col.x, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.c.faint
	label.TextSize = Theme.t.small
	label.TextXAlignment = col.align
	label.Text = col.label
	Theme.face(label)
	label.Parent = head
end

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.new(0, 18, 0, 92)
list.Size = UDim2.new(1, -36, 0, H - 92 - 60)
list.BackgroundTransparency = 1
list.ScrollBarThickness = 6
list.ScrollBarImageColor3 = Theme.c.scrollbar
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 2)
layout.Parent = list

-- A search box, and it searches.
--
-- Two halves, and it does both. Filtering the board's own rows is instant and free and
-- happens on every keystroke -- but the board watches five tokens this town chose, so a box
-- that ONLY filters those says "nothing here" about most of the market, which is not a
-- search, it is a lie with a text field in front of it.
--
-- The whole market follows a moment later and lands underneath. What kept that out was the
-- worry about spending the operator's bandwidth on whoever is typing -- and the answer is
-- that it is not the operator's request. It is made from HERE, by this client, on this
-- machine: shared/Market.luau writes a client-only channel and the player's own host
-- answers it. Nobody else's board changes and nobody else's quota is touched.
local search = Instance.new("TextBox")
search.Size = UDim2.new(0, 240, 0, 22)
search.Position = UDim2.new(1, -258, 0, 38)
search.BackgroundColor3 = Theme.c.well or Theme.c.panel
search.BackgroundTransparency = 0.25
search.BorderSizePixel = 0
search.TextColor3 = Theme.c.figure
search.PlaceholderText = "filter: pair, token or exchange"
search.PlaceholderColor3 = Theme.c.faint
search.TextSize = Theme.t.small
search.TextXAlignment = Enum.TextXAlignment.Left
search.ClearTextOnFocus = false
search.Text = ""
Theme.face(search)
Theme.corner(search, 3)
search.Parent = panel

-- As you type, not on Enter. Filtering is free, so making somebody commit to a word before
-- seeing whether it matches anything is a delay with nothing behind it.
--
-- The market behind it is NOT free, so it waits for a pause. Holding a key down should not
-- be a question per character, and nobody has finished typing after one letter.
local typing = false
local QUIET = 0.35         -- seconds of not typing before the market is asked
local MIN = 2              -- letters; one matches half the market and is nobody's question
local wanted = ""          -- the word being asked about, so a late answer to an old one is dropped

search:GetPropertyChangedSignal("Text"):Connect(function()
	typing = true
	local q = search.Text
	remote:FireServer("search", q)          -- the filter, now, on this keystroke
	wanted = q
	marketRows = {}
	if #q < MIN then
		draw(lastBoard)
		return
	end
	task.delay(QUIET, function()
		-- Still the same word? Otherwise this keystroke has been overtaken by a later one.
		if search.Text ~= q or wanted ~= q then return end
		Market.search(q, function(res)
			if wanted ~= q then return end
			-- Through the same Dex.row the board's own rows go through, so a searched pool
			-- has all twelve columns rather than the four the search happens to name. The
			-- host hands them over in DexScreener's own shape for exactly this.
			marketRows = {}
			for _, p in ipairs((res and res.ok and res.rows) or {}) do
				local built = Dex.row(p)
				if built then
					built.address = tostring(p.address or p.pairAddress or "")
					table.insert(marketRows, built)
				end
			end
			draw(lastBoard)
		end)
	end)
end)
search.FocusLost:Connect(function() typing = false end)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -36, 0, 44)
status.Position = UDim2.new(0, 18, 0, 100)
status.BackgroundTransparency = 1
status.TextColor3 = Theme.c.dim
status.TextSize = Theme.t.body
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.TextWrapped = true
status.Text = ""
status.Visible = false
Theme.face(status)
status.Parent = panel

local footer = Instance.new("TextLabel")
footer.Size = UDim2.new(1, -150, 0, 30)
footer.Position = UDim2.new(0, 18, 1, -44)
footer.BackgroundTransparency = 1
footer.TextColor3 = Theme.c.faint
footer.TextSize = Theme.t.small
footer.TextWrapped = true
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text = ""
Theme.face(footer)
footer.Parent = panel

local closeButton = Theme.button(panel, "Close")
closeButton.Size = UDim2.new(0, 100, 0, 30)
closeButton.Position = UDim2.new(1, -118, 1, -42)

local function clear()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
end

local function cell(parent, col, text, colour)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, col.w, 1, 0)
	label.Position = UDim2.new(0, col.x, 0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = colour or Theme.c.ink
	label.TextSize = Theme.t.small
	label.TextXAlignment = col.align
	label.TextTruncate = Enum.TextTruncate.AtEnd
	-- A cell draws what it is given, and "-" for nothing. It used to take whatever came and
	-- hand it straight to a TextLabel, so one missing number anywhere in a row took the whole
	-- board down with "invalid argument #3 to 'Text'" -- which is a panel that will not open
	-- because one pool has no volume figure.
	label.Text = text ~= nil and tostring(text) or "-"
	Theme.face(label)
	label.Parent = parent
	return label
end

--- A percentage, signed and coloured. This is the column people read first.
local function change(parent, col, value)
	local text = value >= 0 and ("+%.2f%%"):format(value) or ("%.2f%%"):format(value)
	if value == 0 then text = "0.00%" end
	cell(parent, col, text, value > 0 and UP or (value < 0 and DOWN or Theme.c.faint))
end

local function row(entry, n)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -8, 0, ROW)
	frame.BackgroundColor3 = n % 2 == 0 and Theme.c.card or Theme.c.tile
	frame.BackgroundTransparency = 0.6
	frame.Parent = list

	cell(frame, COLUMNS[1], tostring(n), Theme.c.faint)
	cell(frame, COLUMNS[2], entry.pair, Theme.c.ink)
	cell(frame, COLUMNS[3], entry.price, Theme.c.ink)
	cell(frame, COLUMNS[4], entry.age, Theme.c.faint)
	-- Buys against sells, which says more about a pool than either alone.
	cell(frame, COLUMNS[5], ("%d/%d"):format(entry.buys or 0, entry.sells or 0), Theme.c.faint)
	cell(frame, COLUMNS[6], entry.volume, Theme.c.dim)
	change(frame, COLUMNS[7], entry.m5 or 0)
	change(frame, COLUMNS[8], entry.h1 or 0)
	change(frame, COLUMNS[9], entry.h6 or 0)
	change(frame, COLUMNS[10], entry.h24 or 0)
	cell(frame, COLUMNS[11], entry.liquidity, Theme.c.figure)
	cell(frame, COLUMNS[12], entry.fdv, Theme.c.dim)
	return frame
end

local function close()
	screen.Enabled = false
	remote:FireServer("close")
end

closeButton.Activated:Connect(close)

remote.OnClientEvent:Connect(function(kind, payload)
	-- The desk says to put it away: pressing E at an open window is asking for it to go.
	if kind == "shut" then
		screen.Enabled = false
		return
	end
	if kind ~= "board" then return end
	lastBoard = payload
	draw(payload)
end)

draw = function(payload)
	if not payload then return end
	clear()
	Theme.takeOver(gui)
	screen.Enabled = true

	if payload.loading then
		status.Visible = true
		status.Text = "Reading the market. This board fills itself in."
		footer.Text = ""
		return
	end
	-- The box keeps whatever the server last agreed it was, except while somebody is
	-- typing into it -- a refresh landing mid-word must not rewrite the word.
	if not typing and payload.query ~= nil and search.Text ~= payload.query then
		search.Text = payload.query
	end
	-- The board's own rows first, then anything the market turned up that was not already
	-- here. The board is what this town watches and is the answer to most questions; the
	-- rest of the market is the answer to the others, and the order says which is which.
	local rows = {}
	local seen = {}
	for _, r in ipairs(payload.rows or {}) do
		seen[tostring(r.address or r.pair):lower()] = true
		table.insert(rows, r)
	end
	local extra = 0
	for _, r in ipairs(marketRows) do
		local key = tostring(r.address or r.pair):lower()
		if not seen[key] then
			seen[key] = true
			extra += 1
			table.insert(rows, r)
		end
	end
	payload = table.clone(payload)
	payload.rows = rows
	payload.found = extra

	if #payload.rows == 0 then
		status.Visible = true
		-- "nothing matched" and "nothing came back" look identical on an empty board and
		-- are opposite problems: one means try another word, the other means the market
		-- is unreachable. The note the server sends already says which.
		status.Text = payload.note or "No pairs came back."
		footer.Text = ""
		return
	end

	status.Visible = false
	sourceLabel.Text = ("%s   .   %s"):format(payload.network or "", payload.source or "")
	if payload.query and payload.query ~= "" then
		sub.Text = (payload.found or 0) > 0
			and ("%d of %d on the board, and %d more found on %s, matching \"%s\".")
				:format(payload.matched or 0, payload.total or 0, payload.found, "dexscreener.com", payload.query)
			or ("Showing %d of %d pools matching \"%s\". Sorted by liquidity.")
				:format(payload.matched or #payload.rows, payload.total or #payload.rows, payload.query)
	else
		sub.Text = ("%d pools, sorted by liquidity. Prices in dollars, straight from the pairs.")
			:format(payload.total or #payload.rows)
	end
	for i, entry in ipairs(payload.rows) do
		row(entry, i)
	end
	footer.Text = ("%s Trade at %s, or at Rebh's counter next door, which settles on this testnet.")
		:format(payload.note or "", payload.site or "app.pulsex.com")
end

-- Walking away shuts it, the same as every other counter in town.
RunService.Heartbeat:Connect(function()
	if not screen.Enabled then return end
	local map = workspace:FindFirstChild("Map")
	local npc = map and map:FindFirstChild("Screener")
	local torso = npc and npc:FindFirstChild("Torso")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not torso or not root then return end
	if (root.Position - torso.Position).Magnitude > CLOSE_DISTANCE then
		close()
	end
end)

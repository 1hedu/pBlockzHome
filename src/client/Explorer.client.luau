-- The Hall of Records, drawn as the website it is standing in for.
--
-- Unger used to read the explorer's front page out loud, one line at a time, which is the
-- wrong shape for it: an address is a thing you scan with your eyes and copy, not a
-- thing you listen to. So this is a browser -- chrome, an address bar with the real host
-- in it, and pages you can walk between.
--
-- It is a browser over one site rather than a pretend one. Every page here is a page the
-- real explorer serves, under the same name it serves it: /block/25337983 in this window
-- is /block/25337983 in a real one, and the numbers on it came off that API through the
-- host. Nothing in this script reaches the network; it asks the server, which asks the
-- host, which is the only thing here allowed outside.
--
-- The panel draws whatever shape it is handed -- some cards, some labelled rows, some
-- tables -- without knowing which page it is looking at. That is what lets a block, an
-- address and a token list all come down the same wire.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("ExplorerRemote")
-- Pages come from this machine, not from the town's server. See shared/Scan.luau: reading
-- an explorer needs no key and signs nothing, so there is no reason for somebody else's
-- server to do it -- and on a hosted town every reason for it not to.
local HttpService = game:GetService("HttpService")
local Scan = require(ReplicatedStorage:WaitForChild("Scan"))

-- ---- this town shows its own transactions -------------------------------------------------
-- The client's transaction notification opens a browser by default, which every client can
-- do and which is what a wallet does. This town has a scan in it, so it says so and takes
-- them: click the card and the panel opens on that transaction instead of a window landing on
-- your desktop.
--
-- Said once, rather than answered each time. A place either shows transactions or it does
-- not, and it knows which the moment it loads. The doing of it is at the bottom of this
-- file, where the panel and its `ask` exist -- a closure written up here would capture the
-- globals of those names, which are nil.

local W, H = 940, 620
local CHROME_H = 42          -- the browser bar across the top
local FOOTER_H = 56          -- where "take this page" lives
local EDGE = 18              -- margin down both sides of a page
local CONTENT = W - EDGE * 2 - 10        -- ... less room for the scrollbar
local CLOSE_DISTANCE = 16

local INK, DIM, FAINT = Theme.c.ink, Theme.c.dim, Theme.c.faint

local screen = Instance.new("ScreenGui")

-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "Explorer"
screen.Enabled = false
screen.ResetOnSpawn = false
screen.Parent = gui

local window, windowWindow = Theme.window(screen, UDim2.new(0, W, 0, H),
	UDim2.new(0.5, -W / 2, 0.5, -H / 2))

-- Drawn at 940 by 620, which is a small browser on a big screen. Magnified as a whole,
-- so a page keeps the proportions of the site it is standing in for.

-- ---- browser chrome -------------------------------------------------------------------

local chrome = Instance.new("Frame")
chrome.Size = UDim2.new(1, 0, 0, CHROME_H)
chrome.BackgroundColor3 = Theme.c.card
chrome.Parent = window
Theme.corner(chrome, 10)

-- The corner rounds all four sides, so a plain strip squares off the bottom two and
-- the chrome joins the page instead of floating above it.
local chromeFoot = Instance.new("Frame")
chromeFoot.Size = UDim2.new(1, 0, 0, 12)
chromeFoot.Position = UDim2.new(0, 0, 1, -12)
chromeFoot.BackgroundColor3 = Theme.c.card
chromeFoot.BorderSizePixel = 0
chromeFoot.Parent = chrome

-- Three dots, because every window in the world has them and the eye reads them as
-- "this is a browser" before it reads a single word.
for i, tint in ipairs({ Color3.fromRGB(224, 96, 92), Color3.fromRGB(224, 184, 88), Color3.fromRGB(112, 200, 112) }) do
	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 10, 0, 10)
	dot.Position = UDim2.new(0, 4 + i * 16, 0, 16)
	dot.BackgroundColor3 = tint
	dot.BackgroundTransparency = 0.25
	dot.Parent = chrome
	Theme.corner(dot, 5)
end

local backButton = Theme.button(chrome, "<")
backButton.Size = UDim2.new(0, 34, 0, 26)
backButton.Position = UDim2.new(0, 70, 0, 8)
backButton.TextSize = Theme.t.small

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, -420, 0, 26)   -- the wallet button takes the end of this row
bar.Position = UDim2.new(0, 112, 0, 8)
bar.BackgroundColor3 = Theme.c.field
bar.Parent = chrome
Theme.corner(bar, 13)

local lock = Instance.new("TextLabel")
lock.Size = UDim2.new(0, 22, 1, 0)
lock.Position = UDim2.new(0, 8, 0, 0)
lock.BackgroundTransparency = 1
lock.TextColor3 = Theme.c.figure
lock.TextSize = Theme.t.small
lock.Text = "[o]"
Theme.face(lock)
lock.Parent = bar

local url = Instance.new("TextLabel")
url.Size = UDim2.new(1, -40, 1, 0)
url.Position = UDim2.new(0, 32, 0, 0)
url.BackgroundTransparency = 1
url.TextColor3 = DIM
url.TextSize = Theme.t.small
url.TextXAlignment = Enum.TextXAlignment.Left
url.TextTruncate = Enum.TextTruncate.AtEnd
url.Text = ""
Theme.face(url)
url.Parent = bar

-- There is no Connect button here, and there should never have been one.
--
-- You do not connect a wallet to a block explorer. Nothing on this window reads an account,
-- spends anything or signs anything: it is pages of public numbers, the same numbers anybody
-- gets by typing the address into a browser. Connecting a wallet to look at a scan is a
-- thing nobody does anywhere, and asking for it before an Engram made even less sense --
-- the Engram is a memory of a PUBLIC page, and the thing that guards the signature is the
-- wallet's own prompt, which appears when the transaction is real and which no script in
-- this place can reach, dismiss or fake.
--
-- So the button was ceremony: a state this window invented, checked against itself, and let
-- you clear by pressing it. It gated nothing that was not already gated properly one layer
-- down. Take Engram now goes straight to the host, and the host asks you, out here, once.
local closeButton = Theme.button(chrome, "Close")
closeButton.Size = UDim2.new(0, 84, 0, 26)
closeButton.Position = UDim2.new(1, -94, 0, 8)
closeButton.TextSize = Theme.t.small

-- ---- the page ---------------------------------------------------------------------------

local page = Instance.new("ScrollingFrame")
page.Position = UDim2.new(0, 0, 0, CHROME_H)
page.Size = UDim2.new(1, 0, 1, -(CHROME_H + FOOTER_H))
page.BackgroundTransparency = 1
page.ScrollBarThickness = 8
page.ScrollBarImageColor3 = Theme.c.scrollbar
page.AutomaticCanvasSize = Enum.AutomaticSize.Y
page.CanvasSize = UDim2.new(0, 0, 0, 0)
page.Parent = window

local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, 0, 0, FOOTER_H)
footer.Position = UDim2.new(0, 0, 1, -FOOTER_H)
footer.BackgroundTransparency = 1
footer.Parent = window

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -380, 0, 24)   -- stops short of the size button
status.Position = UDim2.new(0, EDGE, 0, 16)
status.BackgroundTransparency = 1
status.TextColor3 = FAINT
status.TextSize = Theme.t.small
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = ""
Theme.face(status)
status.Parent = footer


-- Which page is on screen, and which thing it is of. That is the whole of what the take
-- button needs to know: whether what you are looking at is ONE thing, which is the only
-- kind of thing an Engram can be a memory of.
local shownView = ""
local shownId = ""

-- "Take Engram", not "Take this page". It cuts an Engram, and Unger offers exactly that word
-- from her desk -- a button that names the same thing differently is a button nobody finds.
local takeButton = Theme.button(footer, "Take Engram", Theme.c.good)
takeButton.Size = UDim2.new(0, 240, 0, 34)
takeButton.Position = UDim2.new(1, -258, 0, 11)
takeButton.TextSize = Theme.t.small
-- The one action on this window you come away holding something from.
takeButton:SetAttribute("Sfx", "item")
-- Always on the panel, from the moment it opens.
--
-- It used to appear only once you had navigated into a block or an address, which meant the
-- scan's front page -- the page you get when you walk up to Unger and ask for the scan -- had
-- no button and nothing saying there could be one. So the only way to find out an Engram can
-- be cut from the scan was to already know. Twice now that has been the answer to "I cannot
-- see any way to get an Engram", and both times the feature was there and invisible.
--
-- Shown and refusing is a thing you can learn from. Hidden is not.
takeButton.Visible = true

-- Steps this window through its sizes. Per window rather than one control for all of them,
-- because every panel's chrome is a different shape and the corner each can spare is not
-- the same corner. Below the footer's own row, which is where this one has space.
Theme.scaleButton(screen, footer, UDim2.new(1, -320, 0, 17))

-- ---- where we are ------------------------------------------------------------------------
-- A browser is a stack of places you have been. Keeping one is what makes the back
-- button mean anything, and it is the whole of the navigation model.
local here = { view = "home", id = "" }
local trail = {}
local waiting = false
local loaded = false
-- Opened by something other than standing at Unger's desk -- a transaction card, say. The
-- walk-away rule does not apply to it: you did not walk away from anything, and a panel that
-- shuts the same frame it opens looks like a click that did nothing.
local summoned = false

-- The pages an Engram can be cut from: the ones that name ONE thing. "The latest
-- transactions" is a different list every ten seconds, so an Engram of it would go on
-- claiming to be a page that changed out from under it -- the one thing an Engram must never
-- do. Engrams.take refuses the rest; this is the same list, so the button can say so
-- before you press it rather than after.
local HOLDABLE = { transaction = true, tx = true, block = true, address = true, token = true }

-- Wired below the button it writes into: a closure written up beside it would capture the
-- global of that name, which is nil.
--
-- Two states now, not three. Lit on a page that is one thing; dim on a page that is not.
-- Pressing a dim one says so.
local function showTake()
	takeButton.Text = "Take Engram"
	takeButton.BackgroundColor3 = HOLDABLE[shownView] and Theme.c.good or Theme.c.button
end

--- Shows one page. Asked for and answered here; nothing crosses to the server.
local showPage
local function ask(view, id)
	waiting = true
	status.Text = "Loading..."
	Scan.page(view, id or "", function(page) showPage(page) end)
end

local function go(view, id)
	table.insert(trail, { view = here.view, id = here.id })
	ask(view, id)
end

local function back()
	local prev = table.remove(trail)
	if not prev then return end
	ask(prev.view, prev.id)
end

backButton.Activated:Connect(back)

-- Another script on this machine opening a page here -- a shown Engram's "Open the page". A
-- BindableEvent, because it is one client script talking to another; the server has no part in it.
local goTo = Instance.new("BindableEvent")
goTo.Name = "Go"
goTo.Parent = screen
goTo.Event:Connect(function(view, id)
	-- Summoned, as a notification's card does: there is no Unger to walk away from.
	Theme.takeOver(gui)
	screen.Enabled = true
	loaded = true
	summoned = true
	go(tostring(view or "home"), tostring(id or ""))
end)

-- ---- drawing whatever came back -----------------------------------------------------------

local function clear()
	for _, child in ipairs(page:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

local function text(parent, x, y, w, h, s, colour, size, align)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(0, w, 0, h)
	l.Position = UDim2.new(0, x, 0, y)
	l.BackgroundTransparency = 1
	l.TextColor3 = colour
	l.TextSize = size
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = s
	Theme.face(l)
	l.Parent = parent
	return l
end

-- A row you can click. The cells are labels, and a label is not transparent to the
-- pointer -- so the thing that takes the click is a bare button laid over the whole row,
-- above them. Above, not merely level: at equal ZIndex the one made last wins, and the
-- cells are made after this.
local function clickable(parent, w, h, view, id)
	local hit = Instance.new("TextButton")
	hit.Size = UDim2.new(0, w, 0, h)
	hit.Position = UDim2.new(0, 0, 0, 0)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 9
	-- Opening a page is a menu action, and the whole scan is menu actions: it was the one
	-- place in town playing the item clip, on every row, for walking from one page to
	-- another. The item clip means you picked something up.
	hit:SetAttribute("Sfx", "menu")
	Theme.face(hit)
	hit.Parent = parent
	hit.Activated:Connect(function()
		if view and view ~= "" and id and id ~= "" then go(view, id) end
	end)
	return hit
end

local function drawStats(cards, y)
	local gap = 8
	local w = math.floor((CONTENT - gap * (#cards - 1)) / math.max(#cards, 1))
	for i, c in ipairs(cards) do
		local card = Instance.new("Frame")
		card.Size = UDim2.new(0, w, 0, 58)
		card.Position = UDim2.new(0, EDGE + (i - 1) * (w + gap), 0, y)
		card.BackgroundColor3 = Theme.c.card
		card.BackgroundTransparency = 0.25
		card.Parent = page
		Theme.corner(card, 6)
		text(card, 10, 8, w - 20, 16, c.label, FAINT, Theme.t.small)
		text(card, 10, 26, w - 20, 24, c.value, Theme.c.figure, Theme.t.small)
	end
	return y + 58 + 16
end

local function drawRows(rows, y)
	for _, r in ipairs(rows) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(0, CONTENT, 0, 28)
		row.Position = UDim2.new(0, EDGE, 0, y)
		row.BackgroundTransparency = 1
		row.Parent = page
		local linked = r.view ~= nil and r.view ~= "" and r.id ~= nil and r.id ~= ""
		if linked then clickable(row, CONTENT, 28, r.view, r.id) end
		text(row, 0, 4, 240, 20, r.label, DIM, Theme.t.small)
		text(row, 248, 4, CONTENT - 248, 20, r.value,
			linked and Theme.c.figure or INK, Theme.t.small)
		y += 28
	end
	return y + 12
end

local function drawTable(t, y)
	if t.title and t.title ~= "" then
		text(page, EDGE, y, CONTENT, 26, t.title, Theme.c.accent, Theme.t.heading)
		y += 34
	end
	local cols = t.columns or {}
	local n = math.max(#cols, 1)
	local gap = 10
	local w = math.floor((CONTENT - gap * (n - 1)) / n)

	local head = Instance.new("Frame")
	head.Size = UDim2.new(0, CONTENT, 0, 22)
	head.Position = UDim2.new(0, EDGE, 0, y)
	head.BackgroundTransparency = 1
	head.Parent = page
	for i, c in ipairs(cols) do
		text(head, (i - 1) * (w + gap), 2, w, 18, string.upper(c), FAINT, Theme.t.small)
	end
	y += 24

	local rows = t.rows or {}
	if #rows == 0 then
		-- "Nothing here" is a claim about the chain. When the explorer simply did not
		-- answer, it is a claim we cannot make, so the page says which one it is.
		text(page, EDGE, y, CONTENT, 24, t.note or "Nothing here.", FAINT, Theme.t.small)
		return y + 32
	end
	for _, r in ipairs(rows) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(0, CONTENT, 0, 30)
		row.Position = UDim2.new(0, EDGE, 0, y)
		row.BackgroundColor3 = Theme.c.card
		row.BackgroundTransparency = 0.55
		row.Parent = page
		Theme.corner(row, 4)
		clickable(row, CONTENT, 30, r.view, r.id)
		for i, cell in ipairs(r.cells or {}) do
			text(row, 8 + (i - 1) * (w + gap), 5, w - 8, 20, tostring(cell),
				i == 1 and Theme.c.figure or INK, Theme.t.small)
		end
		y += 34
	end
	return y + 12
end

-- The site's own top-level places, so you can get to them without owning a transaction.
local NAV = {
	{ label = "Home", view = "home" },
	{ label = "Blocks", view = "blocks" },
	{ label = "Transactions", view = "txs" },
	{ label = "Tokens", view = "tokens" },
}

-- Kept between redraws: the page is torn down and rebuilt on every navigation, so a box
-- made inside drawNav would lose what you had typed the moment a result came back.
local searchText = ""

local function search(term)
	term = (term or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if term == "" then return end
	searchText = term
	go("search", term)
end

local function drawNav(y)
	local x = EDGE
	for _, n in ipairs(NAV) do
		local b = Theme.button(page, n.label)
		b.Size = UDim2.new(0, 148, 0, 28)
		b.Position = UDim2.new(0, x, 0, y)
		b.TextSize = Theme.t.small
		if n.view == here.view then b.BackgroundColor3 = Theme.c.good end
		b.Activated:Connect(function() go(n.view, "") end)
		x += 156
	end

	-- How anyone actually uses an explorer: paste a thing, go to it. One endpoint takes
	-- an address, a block number, a transaction or a token and says which it found.
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(0, CONTENT - (x - EDGE) - 76, 0, 28)
	box.Position = UDim2.new(0, x, 0, y)
	box.BackgroundColor3 = Theme.c.field
	box.TextColor3 = INK
	box.PlaceholderColor3 = FAINT
	box.PlaceholderText = "Address, block, transaction or token"
	box.TextSize = Theme.t.small
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.Text = searchText
	Theme.face(box)
	box.Parent = page
	Theme.corner(box, 6)
	box.FocusLost:Connect(function(enter)
		if enter then search(box.Text) end
	end)

	local find = Theme.button(page, "Find")
	find.Size = UDim2.new(0, 68, 0, 28)
	find.Position = UDim2.new(0, EDGE + CONTENT - 68, 0, y)
	find.TextSize = Theme.t.small
	find:SetAttribute("Sfx", "menu")
	find.Activated:Connect(function() search(box.Text) end)
	return y + 40
end

local function draw(v)
	clear()
	here = { view = v.view or "home", id = v.id or "" }
	url.Text = (v.host or "") .. (v.url or "/")
	backButton.Text = #trail > 0 and "<" or "-"

	local y = 14
	y = drawNav(y)
	if v.title and v.title ~= "" then
		text(page, EDGE, y, CONTENT, 34, v.title, Theme.c.accent, Theme.t.title)
		y += 38
	end
	if v.subtitle and v.subtitle ~= "" then
		text(page, EDGE, y, CONTENT, 22, v.subtitle, DIM, Theme.t.small)
		y += 28
	end
	if v.stats and #v.stats > 0 then y = drawStats(v.stats, y) end
	if v.rows and #v.rows > 0 then y = drawRows(v.rows, y) end
	for _, t in ipairs(v.tables or {}) do y = drawTable(t, y) end

	local note = text(page, EDGE, y + 4, CONTENT, 44,
		("Everything on this page is public and none of it is this town's. Paste any of it into %s and you will read the same numbers.")
			:format(v.host or "the explorer"), FAINT, Theme.t.small)
	note.TextWrapped = true
	note.TextTruncate = Enum.TextTruncate.None
	note.TextYAlignment = Enum.TextYAlignment.Top
	page.CanvasPosition = Vector2.new(0, 0)
end

showPage = function(payload)
	waiting = false
	if not payload or payload.ok == false then
		status.Text = (payload and payload.message) or "The explorer isn't answering."
		return
	end
	status.Text = ""
	loaded = true
	draw(payload)
	-- Off the payload rather than `here`: `here` is only updated inside draw, so
	-- reading it first asks about the page you just left.
	shownView = tostring(payload.view or "")
	shownId = tostring(payload.id or "")
	showTake()
end

remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "note" then
		status.Text = tostring(payload)
		-- A word from the town is an answer, whatever it says. The button goes back to
		-- offering itself: leaving it on "Asking..." while the status line explains why it
		-- did not work is two halves of the window disagreeing about what just happened.
		if takeButton.Text == "Asking..." then takeButton.Text = "Take Engram" end
	elseif kind == "page" then
		-- Talking to Unger opens the window, and the server re-sends this every time the
		-- chain moves. Opening is all it means now, because the pages themselves are
		-- fetched -- and a refresh must not throw away where you had navigated to.
		screen.Enabled = true
		if not loaded and not waiting then
			trail = {}
			ask("home", "")
		end
	end
end)

takeButton.Activated:Connect(function()
	-- A dim button still answers. Saying nothing is how somebody decides the feature is
	-- broken rather than that they are on the wrong page.
	if not HOLDABLE[shownView] then
		status.Text = "An Engram is a memory of one thing. Open a block, a transaction or an "
			.. "address first, then take one of that."
		return
	end
	-- `shownView` and `shownId`, not `here`: both are set from the payload that drew this
	-- page, and the guard above tested the first of that pair. Sending `here` meant the
	-- button could test one page and ask for another.
	status.Text = "Asking the wallet..."
	takeButton.Text = "Asking..."
	remote:FireServer("keep", shownView, shownId)
	-- Whatever comes back, the button stops saying "Asking..." -- including nothing coming
	-- back at all. It used to be cleared only by the next page load, so a request that died
	-- on the way left the button stuck on that word forever, saying the town was busy on
	-- your behalf when it had never heard of you. Three signatures and two waits for a
	-- block is the honest ceiling.
	local mine = shownView .. "/" .. shownId
	task.delay(150, function()
		if takeButton.Text == "Asking..." and mine == shownView .. "/" .. shownId then
			takeButton.Text = "Take Engram"
			if status.Text == "Asking the wallet..." then
				status.Text = "No answer from the wallet. Nothing was signed and nothing was spent."
			end
		end
	end)
end)

-- Declared before it is used. A local declared after the closure that calls it is a
-- different variable, and the closure gets the global -- which is nil.
local function close()
	screen.Enabled = false
	loaded = false
	summoned = false
	remote:FireServer("close")
end
closeButton.Activated:Connect(close)

-- Walking away shuts it, the same as every other window in town -- unless it was summoned
-- from somewhere else, in which case there is nothing to walk away from.
RunService.Heartbeat:Connect(function()
	if not screen.Enabled or summoned then return end
	local map = workspace:FindFirstChild("Map")
	local npc = map and map:FindFirstChild("Archivist")
	local torso = npc and npc:FindFirstChild("Torso")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not torso or not root then return end
	if (root.Position - torso.Position).Magnitude > CLOSE_DISTANCE then
		close()
	end
end)

-- WAITED for, never created. The server makes this node and it replicates down; a client
-- that makes its own because it looked a moment too early ends up with TWO children called
-- Chain, watching the one nobody writes to. That is the same trap that has bitten the
-- animations and the emote folders here, and it fails silently every time -- the attribute
-- is set, on the wrong node, and nothing happens.
local chainNode = nil
task.spawn(function()
	chainNode = ReplicatedStorage:WaitForChild("Chain", 30)
	if not chainNode then return end
	chainNode:SetAttribute("AskScanHandles", true)
	-- And when the notification asks, the panel comes up on that transaction -- opening
	-- itself if it was shut, because a card you clicked is a request to SEE something.
	chainNode:GetAttributeChangedSignal("ShowScan"):Connect(function()
		local raw = chainNode:GetAttribute("ShowScan")
		if type(raw) ~= "string" or raw == "" then return end
		local ok, want = pcall(function() return HttpService:JSONDecode(raw) end)
		if not ok or type(want) ~= "table" then return end
		screen.Enabled = true
		loaded = true
		summoned = true
		trail = {}
		ask(tostring(want.view or "tx"), tostring(want.id or ""))
	end)
end)

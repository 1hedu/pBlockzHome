-- The space fishing leaderboard.
--
-- Read by this machine, straight off the Fishing contract (contracts/Fishing.sol) -- not handed
-- over by the server. Every catch is counted there against whoever caught it, and the list of
-- everybody who has ever cast is there too, so the board is calls and nothing else: who has cast,
-- what each of them has caught, and whether the Everliving Fish has been found and by whom.
--
-- A row per colour, with the fish beside it and the three who have caught the most of it. Above
-- them a row for the Everliving Fish: a question mark until somebody finds it, and then its
-- picture and the name of whoever did.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Fish = require(ReplicatedStorage:WaitForChild("Fish"))
local OwnWallet = require(ReplicatedStorage:WaitForChild("OwnWallet"))
local Contracts = require(ReplicatedStorage:WaitForChild("Contracts"))
local ModelPicture = require(ReplicatedStorage:WaitForChild("ModelPicture"))

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local fun = ReplicatedStorage:WaitForChild("FunRemote")

local LEADERS = 3
local PAGE = 192                    -- calls to a read; the wallet takes up to 384

local ROW_H, ROW_GAP, TOP, FOOT = 50, 6, 84, 70
local ROWS = 10
local W, H = 760, TOP + ROWS * (ROW_H + ROW_GAP) + FOOT

local screen = Instance.new("ScreenGui")
screen.IgnoreGuiInset = true
screen.Name = "FishBoard"
screen.Enabled = false
screen.ResetOnSpawn = false
screen.Parent = gui

local panel, window = Theme.window(screen, UDim2.new(0, W, 0, H))

--- Every row if the screen has room for them, and a scrolling list in a shorter window. Measured
--- when it opens, off the ScreenGui, because at load the screen reports a size it is not.
local function fit()
	local tall = screen.AbsoluteSize.Y
	local h = (tall > 0) and math.min(H, tall - 32) or H
	window.Size = UDim2.new(0, W, 0, h)
	Theme.centre(window, W, h)
end

Theme.label(panel, "Space Fishing", { colour = Theme.c.accent, size = Theme.t.title,
	size2 = UDim2.new(1, -40, 0, 40), pos = UDim2.new(0, 20, 0, 12) })
local note = Theme.label(panel, "", { colour = Theme.c.dim, size = Theme.t.small,
	size2 = UDim2.new(1, -40, 0, 20), pos = UDim2.new(0, 20, 0, 54) })

local closeButton = Theme.button(panel, "Close")
closeButton.Size = UDim2.new(0, 168, 0, 46)
closeButton.Position = UDim2.new(1, -188, 1, -58)
closeButton.MouseButton1Click:Connect(function() screen.Enabled = false end)

-- ---- the pictures ------------------------------------------------------------------------

--- A fish, side on, in a square: the town's own model, drawn (shared/ModelPicture.luau).
local function fishPicture(parent, species)
	local tile = Instance.new("Frame")
	tile.Size = UDim2.new(0, ROW_H - 6, 0, ROW_H - 6)
	tile.Position = UDim2.new(0, 3, 0, 3)
	tile.BackgroundColor3 = Theme.c.tile
	tile.Parent = parent
	Theme.corner(tile, 4)
	local made = ReplicatedStorage:WaitForChild("Made", 10)
	local template = made and made:WaitForChild(Fish.nameOf(species), 10)
	if template then ModelPicture.frame(tile, template) end
	return tile
end

--- The Everliving Fish's own picture once there is one to show, and the model until it is published.
local function everlivingPicture(parent)
	local assets = ReplicatedStorage:FindFirstChild("PlaceAssets")
	local thumb = assets and assets:FindFirstChild("EverlivingFishThumb")
	if thumb and thumb.Value ~= "" then
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.new(0, ROW_H - 6, 0, ROW_H - 6)
		image.Position = UDim2.new(0, 3, 0, 3)
		image.BackgroundColor3 = Theme.c.tile
		image.Image = thumb.Value
		image.Parent = parent
		Theme.corner(image, 4)
		return image
	end
	return fishPicture(parent, Fish.EVERLIVING)
end

local function unknownPicture(parent)
	local tile = Instance.new("Frame")
	tile.Size = UDim2.new(0, ROW_H - 6, 0, ROW_H - 6)
	tile.Position = UDim2.new(0, 3, 0, 3)
	tile.BackgroundColor3 = Theme.c.tile
	tile.Parent = parent
	Theme.corner(tile, 4)
	Theme.label(tile, "?", { colour = Theme.c.ink, size = Theme.t.title, align = Enum.TextXAlignment.Center,
		size2 = UDim2.new(1, 0, 1, 0) })
	return tile
end

-- ---- the rows ----------------------------------------------------------------------------

local rows = {}     -- species -> { frame, picture, name, leaders }

-- Scrolls, for a window too short to show all ten; on most screens it simply fits.
local list = Instance.new("ScrollingFrame")
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.new(0, 16, 0, TOP)
list.Size = UDim2.new(1, -32, 1, -TOP - FOOT)
list.CanvasSize = UDim2.new(0, 0, 0, ROWS * (ROW_H + ROW_GAP))
list.ScrollBarThickness = 8
list.ScrollBarImageColor3 = Theme.c.scrollbar
list.Parent = panel

local function row(index, species)
	local frame = Instance.new("Frame")
	frame.Name = "Row" .. species
	frame.BackgroundColor3 = Theme.c.card
	frame.BackgroundTransparency = 0.35
	frame.Position = UDim2.new(0, 0, 0, index * (ROW_H + ROW_GAP))
	frame.Size = UDim2.new(1, -14, 0, ROW_H)
	frame.Parent = list
	Theme.corner(frame, 4)
	local name = Theme.label(frame, species == Fish.EVERLIVING and "???" or Fish.nameOf(species),
		{ size = Theme.t.small, size2 = UDim2.new(0, 190, 0, 22), pos = UDim2.new(0, ROW_H + 8, 0, 4) })
	local sub = Theme.label(frame, "", { colour = Theme.c.dim, size = Theme.t.small,
		size2 = UDim2.new(0, 190, 0, 20), pos = UDim2.new(0, ROW_H + 8, 0, 26) })
	local leaders = Theme.label(frame, "", { colour = Theme.c.figure, size = Theme.t.small,
		size2 = UDim2.new(1, -(ROW_H + 210), 1, 0), pos = UDim2.new(0, ROW_H + 200, 0, 0) })
	rows[species] = { frame = frame, name = name, sub = sub, leaders = leaders }
	return rows[species]
end

--- Sets a label and the shadow Theme drew under it.
local function set(label, text)
	label.Text = text
	for _, child in ipairs(label.Parent:GetChildren()) do
		if child.Name == "Shadow" and child.Position.X.Offset == label.Position.X.Offset + 1
			and child.Position.Y.Offset == label.Position.Y.Offset + 1 then
			child.Text = text
		end
	end
end

row(0, Fish.EVERLIVING)
for species = 0, #Fish.COLOURS - 1 do
	local r = row(species + 1, species)
	fishPicture(r.frame, species)
end

local everlivingShown = nil   -- "unknown" or "found", whichever picture the top row has

local function showEverliving(found)
	local want = found and "found" or "unknown"
	if everlivingShown == want then return end
	everlivingShown = want
	local r = rows[Fish.EVERLIVING]
	local old = r.frame:FindFirstChild("Picture")
	if old then old:Destroy() end
	local picture = found and everlivingPicture(r.frame) or unknownPicture(r.frame)
	picture.Name = "Picture"
	set(r.name, found and Fish.EVERLIVING_NAME or "???")
end
showEverliving(false)

-- ---- reading the chain -------------------------------------------------------------------

--- Somebody's name if they are in the town right now, and their short address otherwise.
local function whoIs(address)
	local want = tostring(address):lower()
	for _, p in ipairs(Players:GetPlayers()) do
		local a = p:GetAttribute("WalletAddress")
		if type(a) == "string" and a:lower() == want then return p.Name end
	end
	return want:sub(1, 6) .. ".." .. want:sub(-4)
end

local function read(calls)
	local answer = OwnWallet.request({ action = "read", calls = calls }, 60)
	if not answer or not answer.ok or type(answer.results) ~= "table" then return nil end
	return answer.results
end

--- Who has cast, and what each of them has caught. Nil and a reason if the chain did not answer.
local function readBoard()
	local to = Contracts.Fishing
	local head = read({
		{ to = to, fn = "discoverer()", args = {}, returns = { "address" } },
		{ to = to, fn = "anglerCount()", args = {}, returns = { "uint256" } },
	})
	if not head or not head[1].ok or not head[2].ok then return nil end
	local discoverer = tostring(head[1].words[1] or "")
	if discoverer:match("^0x0+$") then discoverer = "" end
	local count = tonumber(head[2].words[1]) or 0

	local anglers = {}
	for from = 0, count - 1, PAGE do
		local calls = {}
		for i = from, math.min(from + PAGE, count) - 1 do
			table.insert(calls, { to = to, fn = "anglers(uint256)", args = { i }, returns = { "address" } })
		end
		local got = read(calls)
		if not got then return nil end
		for _, one in ipairs(got) do
			if one.ok then table.insert(anglers, tostring(one.words[1])) end
		end
	end

	local tallies = {}
	local returns = {}
	for i = 1, 10 do returns[i] = "uint32" end
	for from = 1, #anglers, PAGE do
		local calls = {}
		for i = from, math.min(from + PAGE - 1, #anglers) do
			table.insert(calls, { to = to, fn = "caughtOf(address)", args = { anglers[i] }, returns = returns })
		end
		local got = read(calls)
		if not got then return nil end
		for k, one in ipairs(got) do
			if one.ok then
				local counts = {}
				for species = 0, Fish.EVERLIVING do counts[species] = tonumber(one.words[species + 1]) or 0 end
				tallies[anglers[from + k - 1]] = counts
			end
		end
	end
	return { discoverer = discoverer, tallies = tallies }
end

local function draw(board)
	showEverliving(board.discoverer ~= "")
	set(rows[Fish.EVERLIVING].sub, board.discoverer ~= "" and ("found by " .. whoIs(board.discoverer)) or "not found yet")
	for species = 0, Fish.EVERLIVING do
		local ranked = {}
		for address, counts in pairs(board.tallies) do
			if (counts[species] or 0) > 0 then table.insert(ranked, { address = address, n = counts[species] }) end
		end
		table.sort(ranked, function(a, b)
			if a.n ~= b.n then return a.n > b.n end
			return a.address < b.address
		end)
		local bits = {}
		for i = 1, math.min(LEADERS, #ranked) do
			table.insert(bits, ("%d. %s  %d"):format(i, whoIs(ranked[i].address), ranked[i].n))
		end
		local total = 0
		for _, one in ipairs(ranked) do total += one.n end
		if species ~= Fish.EVERLIVING then
			set(rows[species].sub, ("%d caught"):format(total))
		end
		set(rows[species].leaders, #bits > 0 and table.concat(bits, "     ") or "")
	end
end

local reading = false

local function refresh()
	if reading then return end
	if not Contracts.Fishing or Contracts.Fishing == "" then
		set(note, "The fishing isn't open yet. Nothing has been caught.")
		set(rows[Fish.EVERLIVING].sub, "not found yet")
		return
	end
	reading = true
	set(note, "Reading the catch off the chain...")
	local ok, board = pcall(readBoard)
	reading = false
	if not ok or not board then
		set(note, "The chain didn't answer. Try again in a moment.")
		return
	end
	draw(board)
	set(note, "Every catch is counted on chain against whoever caught it.")
end

fun.OnClientEvent:Connect(function(kind)
	if kind ~= "fishboard" then return end
	Theme.takeOver(gui)
	screen.Enabled = true
	fit()
	task.spawn(refresh)
end)

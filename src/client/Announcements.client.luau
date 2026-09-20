-- The town owner's announcements, read off the Announcements contract by this machine.
--
-- The newest goes in chat, in gold, when you arrive and whenever a newer one is posted -- as a
-- system message marked "Announcement", which the chat window shows one at a time
-- (Chat.client.luau). The owner can pin one to keep it up: it comes in marked "PinnedAnnouncement",
-- just before the newest, so it sits above it. The Hall of Records' Announcement History opens the
-- whole list, newest first.
--
-- Read here, not handed over by the server: announcements are public chain data, and every player's
-- own client reads its own.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local OwnWallet = require(ReplicatedStorage:WaitForChild("OwnWallet"))
local Contracts = require(ReplicatedStorage:WaitForChild("Contracts"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

--- How often to look for a newer one.
local POLL = 60
--- How soon to try again when the chain did not answer.
local RETRY = 5
--- How many a page of the history reads at once.
local PAGE = 100

local GOLD = require(ReplicatedStorage:WaitForChild("TownOwner")).COLOUR

local function open()
	return Contracts.Announcements ~= nil and Contracts.Announcements ~= ""
end

--- How many there are, and the pinned one's index (0-based) or nil when none is pinned.
local function countAndPinned()
	local answer = OwnWallet.request({ action = "read", calls = {
		{ to = Contracts.Announcements, fn = "count()", args = {}, returns = { "uint256" } },
		{ to = Contracts.Announcements, fn = "pinned()", args = {}, returns = { "bool", "uint256" } },
	} }, 30)
	local results = answer and answer.ok and type(answer.results) == "table" and answer.results
	local first = results and results[1]
	if not (first and first.ok and first.words) then return nil, nil end
	local pin = results[2]
	local isPinned = pin and pin.ok and pin.words and (pin.words[1] == true or tostring(pin.words[1]) == "true")
	return tonumber(first.words[1]), isPinned and tonumber(pin.words[2]) or nil
end

--- Announcements `from` to `to` (0-based, inclusive), oldest first, as { text, at }.
local function read(from, to)
	local out = {}
	for first = from, to, PAGE do
		local calls = {}
		for i = first, math.min(first + PAGE - 1, to) do
			table.insert(calls, { to = Contracts.Announcements, fn = "announcement(uint256)", args = { i },
				returns = { "string", "uint64" } })
		end
		local answer = OwnWallet.request({ action = "read", calls = calls }, 60)
		if not answer or not answer.ok or type(answer.results) ~= "table" then return nil end
		for _, one in ipairs(answer.results) do
			if one.ok and one.words then
				table.insert(out, { text = tostring(one.words[1] or ""), at = tonumber(one.words[2]) or 0 })
			end
		end
	end
	return out
end

-- ---- the newest, in chat ----------------------------------------------------------------------

local shown = -1        -- how many there were when the newest was last put in chat
local shownPin = false  -- which was pinned then: an index, or nil for none (false: not yet looked)

local function post(text, metadata)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local general = channels and channels:FindFirstChild("RBXGeneral")
	if general then
		pcall(function() general:DisplaySystemMessage(text, metadata) end)
	end
	if text ~= "" then print(("%s: %s"):format(metadata == "PinnedAnnouncement" and "pinned" or "announcement", text)) end
end

--- The pinned one then the newest, both again whenever either changes, so the pinned one stays
--- directly above the newest. A pin on the newest itself shows it once, as the newest.
--- Returns whether the chain answered.
local function refresh()
	local n, pin = countAndPinned()
	if not n then return false end
	if n == 0 or (n == shown and pin == shownPin) then return true end
	local newest = read(n - 1, n - 1)
	local pinnedText = ""
	if pin and pin < n - 1 then
		local one = read(pin, pin)
		if not one or not one[1] then return false end
		pinnedText = one[1].text
	end
	if not newest or not newest[1] then return false end
	shown, shownPin = n, pin
	post(pinnedText, "PinnedAnnouncement")
	post(newest[1].text, "Announcement")
	return true
end

task.spawn(function()
	TextChatService:WaitForChild("TextChannels", 30)
	while true do
		-- A read that went unanswered -- the wallet still signing in, as it is on arrival -- is tried
		-- again in a few seconds, not a minute.
		task.wait((open() and not refresh()) and RETRY or POLL)
	end
end)

-- ---- the history, from the Hall of Records ------------------------------------------------------

local W, H = 720, 520
local screen = Instance.new("ScreenGui")
screen.Name = "AnnouncementHistory"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen.Enabled = false
screen.Parent = gui

local panel, window = Theme.window(screen, UDim2.new(0, W, 0, H))
Theme.centre(window, W, H)

Theme.label(panel, "Announcement History", { colour = Theme.c.accent, size = Theme.t.title,
	size2 = UDim2.new(1, -40, 0, 40), pos = UDim2.new(0, 20, 0, 12) })
local note = Instance.new("TextLabel")
note.Name = "Note"
note.BackgroundTransparency = 1
note.Position = UDim2.new(0, 20, 0, 54)
note.Size = UDim2.new(1, -40, 0, 20)
note.TextColor3 = Theme.c.dim
note.TextSize = Theme.t.small
note.TextXAlignment = Enum.TextXAlignment.Left
note.Text = ""
Theme.face(note)
note.Parent = panel

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.new(0, 20, 0, 84)
list.Size = UDim2.new(1, -40, 1, -154)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.ScrollBarThickness = 8
list.ScrollBarImageColor3 = Theme.c.scrollbar
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 10)
layout.Parent = list

local closeButton = Theme.button(panel, "Close")
closeButton.Size = UDim2.new(0, 168, 0, 46)
closeButton.Position = UDim2.new(1, -188, 1, -58)
closeButton.MouseButton1Click:Connect(function() screen.Enabled = false end)

local function clear()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

local function entry(order, a, isPinned)
	local row = Instance.new("TextLabel")
	row.Name = "Announcement" .. order
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -14, 0, 20)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.TextColor3 = GOLD
	row.TextSize = Theme.t.small
	row.TextWrapped = true
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Text = ("%s%s   %s"):format(isPinned and "Pinned   " or "", a.at > 0 and os.date("!%Y-%m-%d", a.at) or "", a.text)
	Theme.face(row)
	row.Parent = list
end

local reading = false

local function showHistory()
	screen.Enabled = true
	if reading then return end
	reading = true
	clear()
	if not open() then
		note.Text = "There are no announcements yet."
		reading = false
		return
	end
	note.Text = "Reading them off the chain..."
	local n, pin = countAndPinned()
	local all = n and n > 0 and read(0, n - 1) or (n == 0 and {} or nil)
	reading = false
	if not all then
		note.Text = "The chain didn't answer. Try again in a moment."
		return
	end
	note.Text = #all == 0 and "There are no announcements yet."
		or ("%d announcement%s, newest first."):format(#all, #all == 1 and "" or "s")
	for i = #all, 1, -1 do
		entry(#all - i + 1, all[i], pin == i - 1)
	end
end

ReplicatedStorage:WaitForChild("RecordsRemote").OnClientEvent:Connect(function(kind)
	if kind == "announcements" then
		Theme.takeOver(gui)
		task.spawn(showHistory)
	end
end)

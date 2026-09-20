-- The town's chat, in the town's own clothes.
--
-- The engine draws one of its own -- a flat black box with a stock LineEdit in it, in a
-- font nothing else here uses. It is the only window left that looks like it came from
-- somewhere else. So this turns it off the way anything does, with
-- SetCoreGuiEnabled(CoreGuiType.Chat, false), and draws the same thing out of Theme.
--
-- Nothing is reimplemented underneath: messages still go through TextChatService, still
-- arrive on RBXGeneral, and are still the engine's to filter and deliver. This is the
-- window and only the window.
--
-- Both halves stay up, the way a chat window does. An earlier version hid the log when it
-- went quiet, on the theory that it would eat clicks meant for the world -- it does not.
-- PASS does not consume the event, so it goes on to the world's own picking; PASS only
-- takes a click from another control it is laid over, which nothing here is.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local TownOwner = require(ReplicatedStorage:WaitForChild("TownOwner"))
local Squelch = require(ReplicatedStorage:WaitForChild("Squelch"))

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

local W = 340
local LIST_H = 150
local KEEP = 40          -- lines held; the rest are let go rather than grown forever

pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false) end)

local screen = Instance.new("ScreenGui")

-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "TownChat"
screen:SetAttribute("Hud", true)     -- always on; not a window anything should defer to
screen.ResetOnSpawn = false
screen.Parent = gui

-- Above the window rather than in it, so it is still there to press once the window it
-- hides is gone. Kept to the right-hand end of that row: the engine's own menu button
-- sits in the corner, and two things in one corner is one too many.
local toggle = Theme.button(screen, "Hide")
toggle.Size = UDim2.new(0, 60, 0, 24)
toggle.Position = UDim2.new(0, 12 + W - 60, 0, 18)
toggle.TextSize = Theme.t.small
toggle:SetAttribute("Sfx", "menu")

-- A window like every other window here, bevel and all. Built by hand it had none of
-- that, which is the whole of what "make it match" means.
local logPanel, logWindow = Theme.window(screen, UDim2.new(0, W, 0, LIST_H), UDim2.new(0, 12, 0, 46))

local log = Instance.new("ScrollingFrame")
log.Position = UDim2.new(0, 0, 0, 0)
log.Size = UDim2.new(1, 0, 1, 0)
log.BackgroundTransparency = 1
log.BorderSizePixel = 0
log.ScrollBarThickness = 6
log.ScrollBarImageColor3 = Theme.c.scrollbar
log.AutomaticCanvasSize = Enum.AutomaticSize.Y
log.CanvasSize = UDim2.new(0, 0, 0, 0)
log.Parent = logPanel

local stack = Instance.new("UIListLayout")
stack.Padding = UDim.new(0, 2)
stack.SortOrder = Enum.SortOrder.LayoutOrder
stack.Parent = log

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingBottom = UDim.new(0, 6)
pad.Parent = log

-- Always there, the way a chat bar is: it is what you click when you want to say
-- something, so hiding it would leave nothing to aim at but a keyboard shortcut.
local inputPanel, inputWindow = Theme.window(screen, UDim2.new(0, W, 0, 34), UDim2.new(0, 12, 0, 46 + LIST_H + 6))

local input = Instance.new("TextBox")
input.Position = UDim2.new(0, 0, 0, 0)
input.Size = UDim2.new(1, 0, 1, 0)
input.BackgroundTransparency = 1
input.TextColor3 = Theme.c.ink
input.PlaceholderColor3 = Theme.c.faint
input.PlaceholderText = "Press / to say something"
input.TextSize = Theme.t.small
input.TextXAlignment = Enum.TextXAlignment.Left
input.ClearTextOnFocus = false
input.Text = ""
Theme.face(input)
input.Parent = inputPanel

local padIn = Instance.new("UIPadding")
padIn.PaddingLeft = UDim.new(0, 8)
padIn.PaddingRight = UDim.new(0, 8)
padIn.Parent = input

-- ---- what the engine hands over ---------------------------------------------------------
-- PrefixText is Roblox rich text -- <font color="#01A2FF">Ada</font> -- and a script's
-- TextLabel here is a plain Godot Label with no RichText on it at all, so the tags can
-- only ever show up as themselves. The colour is the point of them, so it is read out and
-- becomes the line's colour; the rest comes off.
local function unrich(rich: string): (string, Color3?)
	local colour: Color3? = nil
	local hex = rich:match('color%s*=%s*"#(%x%x%x%x%x%x)"')
	if hex then
		colour = Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
	end
	local plain = rich:gsub("<[^>]*>", "")
	plain = plain:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&")
	return plain, colour
end

-- ---- the log --------------------------------------------------------------------------
local order = 0

local function line(prefix: string, text: string, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	order += 1
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, 18)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.TextColor3 = colour
	l.TextSize = Theme.t.small
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = prefix ~= "" and (prefix .. " " .. text) or text
	Theme.face(l)
	l.Parent = log

	local kids = log:GetChildren()
	local labels = {}
	for _, c in ipairs(kids) do
		if c:IsA("TextLabel") then table.insert(labels, c) end
	end
	if #labels > KEEP then
		table.sort(labels, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for i = 1, #labels - KEEP do labels[i]:Destroy() end
	end
	-- Newest at the bottom, which is where the eye already is.
	log.CanvasPosition = Vector2.new(0, 1e6)
	return l
end

-- ---- announcements ------------------------------------------------------------------------
-- The town owner's, off the Announcements contract (Announcements.client.luau sends them in as
-- system messages marked "Announcement"). Gold, and one at a time: a newer announcement takes the
-- place of the one before rather than stacking up under the conversation. The one the owner has
-- pinned comes in marked "PinnedAnnouncement" just before the newest, so it sits directly above it;
-- an empty one means nothing is pinned.
local GOLD = TownOwner.COLOUR
local shownAnnouncement: TextLabel? = nil
local shownPinned: TextLabel? = nil

-- ---- messages ---------------------------------------------------------------------------
-- The service's signal, not each channel's: the runtime fires both for the same message, so
-- listening to each would say everything twice -- and the service's arrives for every
-- channel, which is what a whisper needs. It used to be RBXGeneral's, which was fine while
-- that was the only channel anybody spoke in.
local channels = TextChatService:WaitForChild("TextChannels", 10)
local general = channels and channels:WaitForChild("RBXGeneral", 10)

--- The prefix for a line, where a whisper says who it is between.
---
--- Roblox's wording: [To Bob] on the way out and [From Bob] on the way back. Which end you
--- are is read off the message's own TextSource -- the channel has exactly two people in it,
--- so if the speaker is not you the speaker is the other one, and if it is you the other one
--- is whoever else is in the channel.
local function whisperPrefix(msg): string?
	local channel = msg.TextChannel
	if not channel or not tostring(channel.Name):match("^RBXWhisper") then return nil end
	local from = msg.TextSource
	if from and from.UserId ~= player.UserId then
		return "[From " .. tostring(from.Name) .. "]"
	end
	for _, s in ipairs(channel:GetChildren()) do
		if s:IsA("TextSource") and s.UserId ~= player.UserId then
			return "[To " .. tostring(s.Name) .. "]"
		end
	end
	return "[Whisper]"
end

TextChatService.MessageReceived:Connect(function(msg)
	-- Squelched, and the one place that decides it: every channel comes through here, so
	-- there is none that can be forgotten. A system line has no TextSource and is never
	-- anybody's, which is what lets /squelch itself answer you.
	local from = msg.TextSource
	if from and Squelch.has(from.UserId) then return end
	if not from and tostring(msg.Metadata or "") == "PinnedAnnouncement" then
		if shownPinned then shownPinned:Destroy() end
		shownPinned = nil
		local text = unrich(tostring(msg.Text or ""))
		if text ~= "" then
			shownPinned = line("", text, GOLD)
			shownPinned.Name = "PinnedAnnouncement"
		end
		return
	end
	if not from and tostring(msg.Metadata or "") == "Announcement" then
		if shownAnnouncement then shownAnnouncement:Destroy() end
		shownAnnouncement = line("", unrich(tostring(msg.Text or "")), GOLD)
		shownAnnouncement.Name = "Announcement"
		return
	end
	local prefix, colour = unrich(tostring(msg.PrefixText or ""))
	local body = unrich(tostring(msg.Text or ""))
	local quiet = whisperPrefix(msg)
	if quiet then
		-- The name is already in the bracket, so the ordinary prefix would say it twice.
		-- Dimmer than the room, because that is what it is.
		line(quiet, body, Theme.c.faint)
		return
	end
	-- The town's owner speaks in gold, by the address they signed in with.
	local speaker = from and Players:GetPlayerByUserId(from.UserId)
	if speaker and TownOwner.is(speaker) then colour = TownOwner.COLOUR end
	line(prefix, body, colour or Theme.c.ink)
end)

local function send()
	local text = input.Text
	input.Text = ""
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return end
	if not general then
		line("", "There is nobody to say that to right now.", Theme.c.faint)
		return
	end
	local ok, why = pcall(function() general:SendAsync(text) end)
	if not ok then line("", "That did not send: " .. tostring(why), Theme.c.faint) end
end

input.FocusLost:Connect(function(enter)
	if enter then send() end
end)

-- Both halves go together: an input bar with no log above it is a box floating on the
-- screen, which is what it looked like before there was anything to close.
local shown = true
local function setShown(on: boolean)
	shown = on
	logWindow.Visible = on
	inputWindow.Visible = on
	toggle.Text = on and "Hide" or "Chat"
	if not on and input:IsFocused() then input:ReleaseFocus(false) end
end

toggle.Activated:Connect(function() setShown(not shown) end)

-- ---- pulling it bigger ---------------------------------------------------------------
-- A chat window is the one that always wants more room, and how much is a matter of what
-- you are doing rather than something to be decided once. So the bottom-right corner is a
-- handle: pull it and the log grows, and the input bar follows it down and out.
--
-- Held rather than clicked, and read from the pointer every frame while held. That only
-- works because motion now reaches the runtime whatever it is over -- a drag spends all of
-- its time over the very window it is resizing, so a position that stops at the panel's
-- edge is a drag that stops with it.
-- Steps the whole window through its sizes, the text with it. The handle below gives you
-- more room; this makes what is in it bigger. They are different wants and it takes both.
local sizeButton = Theme.scaleButton(screen, screen, UDim2.new(0, 12 + W - 112, 0, 18))
local uiScale = screen:FindFirstChildOfClass("UIScale")

local MIN_W, MIN_H = 220, 90
local MAX_W, MAX_H = 900, 520

local grip = Instance.new("TextButton")
grip.Size = UDim2.new(0, 16, 0, 16)
grip.Position = UDim2.new(1, -18, 1, -18)
grip.BackgroundColor3 = Theme.c.bevelLight
grip.BackgroundTransparency = 0.35
grip.AutoButtonColor = false
grip.Text = ""
grip.ZIndex = 20
Theme.face(grip)
grip.Parent = logPanel
Theme.corner(grip, 3)

local mouse = player:GetMouse()
local dragging = false
local grabbed = Vector2.new(0, 0)
local startW, startH = W, LIST_H

local function layout(w: number, h: number)
	W, LIST_H = w, h
	logWindow.Size = UDim2.new(0, w, 0, h)
	inputWindow.Size = UDim2.new(0, w, 0, 34)
	inputWindow.Position = UDim2.new(0, 12, 0, 46 + h + 6)
	toggle.Position = UDim2.new(0, 12 + w - 60, 0, 18)
	sizeButton.Position = UDim2.new(0, 12 + w - 112, 0, 18)
end

grip.MouseButton1Down:Connect(function()
	dragging = true
	grabbed = Vector2.new(mouse.X, mouse.Y)
	startW, startH = W, LIST_H
end)

local function release()
	dragging = false
end
grip.MouseButton1Up:Connect(release)

RunService.RenderStepped:Connect(function()
	if not dragging then return end
	-- Let go anywhere: a drag that only ends on the handle is a window stuck to the pointer.
	if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		release()
		return
	end
	-- The pointer moves in screen pixels; the window is measured in its own. At 1.5x a
	-- hundred pixels of pointer is sixty-something of window, and without this the corner
	-- runs away from the cursor by exactly the scale.
	local k = (uiScale and uiScale.Scale > 0) and uiScale.Scale or 1
	local w = math.clamp(startW + (mouse.X - grabbed.X) / k, MIN_W, MAX_W)
	local h = math.clamp(startH + (mouse.Y - grabbed.Y) / k, MIN_H, MAX_H)
	-- Only on a change. A GuiObject write re-lays out the window it is in, and doing that
	-- every frame of a drag that has not moved is the bill this codebase has paid before.
	w, h = math.floor(w), math.floor(h)
	if w == W and h == LIST_H then return end
	layout(w, h)
end)

ContextActionService:BindAction("TownChat", function(_, state)
	if state ~= Enum.UserInputState.Begin then return end
	-- Asking to talk is asking for it back, so this brings it out of hiding rather than
	-- putting the cursor in a box nobody can see.
	if not shown then setShown(true) end
	input:CaptureFocus()
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.Slash)

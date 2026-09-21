-- What a fight sounds like.
--
-- The server decides who hears what and says so, because the same blow is two different
-- sounds depending on which end of it you are: whoever swung hears one land, whoever took it
-- hears themselves hurt. Neither client can work that out from its own side, and a client
-- that guessed would have both players hearing the same clip.
--
-- Held here rather than in Assets.client.luau, which owns the town's UI clicks. These are a
-- separate set with a separate trigger and nothing to say to each other.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Mixer = require(ReplicatedStorage:WaitForChild("Mixer"))

-- Role, and the place asset it arrives as. The names are Zelda's, from the files: "link" is
-- whoever is holding the controller and "enemy" is whoever they are fighting.
local CLIPS = {
	sword1 = "SfxSword1",         -- the crude spoon's slash
	sword2 = "SfxSword2",         -- and its thrust
	master = "SfxMaster",         -- BFS 9000
	fire = "SfxFire",             -- a torch
	enemyhit = "SfxEnemyHit",     -- you landed one
	enemydies = "SfxEnemyDies",   -- you finished them
	stronghit = "SfxStrongHit",   -- a blow landed out of the air, heard at both ends
	hurt = "SfxHurt",             -- you took one
	dies = "SfxDies",             -- you were finished
	lowhp = "SfxLowHp",           -- one container left
	fall = "SfxFall",             -- over the edge
	item = "SfxItem",             -- a candle mended somebody, heard at both ends
}

local sounds = {}

local function load(role, path)
	local s = Instance.new("Sound")
	s.Name = "Sfx" .. role
	s.SoundId = path
	s.Volume = 1
	s.Parent = SoundService or workspace
	Mixer.sfx(s)
	sounds[role] = s
end

--- A voice per trigger, thrown away on a timer.
---
--- Retriggering one Sound is what the town's UI clicks do, and it is wrong here: restarting
--- a clip that is still sounding chops it to a blip, and the hachimonji's two strokes are
--- 0.28s apart with a 0.36s clip, so the second always cut the first.
---
--- Cleaned up by the clock, not by Ended. An earlier attempt hung Destroy off that signal
--- and the sound played exactly once per session: a fresh clone that reports finishing
--- before it is audible destroys itself on the spot. Three seconds is longer than the
--- longest clip here, so nothing is cut and nothing accumulates.
local KEEP = 3

local function play(role, speed)
	local s = sounds[role]
	if not s then return end
	local voice = s:Clone()
	voice.Parent = s.Parent
	-- PlaybackSpeed, which on Roblox is pitch and speed together: a fishing cast rings higher the
	-- harder it was thrown.
	if type(speed) == "number" and speed > 0 then voice.PlaybackSpeed = speed end
	Mixer.sfx(voice)
	voice:Play()
	task.delay(KEEP, function()
		if voice and voice.Parent then voice:Destroy() end
	end)
end

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("PlaceAssets", 60)
	if not folder then
		warn("combat: no place assets, so the fight is silent")
		return
	end
	local n, want = 0, 0
	for role, asset in pairs(CLIPS) do
		want += 1
		local v = folder:WaitForChild(asset, 60)
		if v and v.Value ~= "" then
			load(role, v.Value)
			n += 1
		end
	end
	print(("combat: %d of %d sounds"):format(n, want))
end)

-- Dying puts the screen out briefly.
--
-- Not for drama: the body is gone and the camera is left looking at whatever it was pointed
-- at, which after a fall is empty sky a long way under the town. A moment of black covers the
-- gap between the death and the new body, and the respawn is 1.6 seconds, so it is short.
local player = Players.LocalPlayer
local black = Instance.new("ScreenGui")

-- This town was laid out before the GUI inset existed, so it keeps the whole screen
-- and everything stays where it was put. A place written against Roblox wants the
-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.
black.IgnoreGuiInset = true
black.Name = "Blackout"
black.ResetOnSpawn = false
black.DisplayOrder = 100
black:SetAttribute("Hud", true)     -- not a window; nothing should defer to it
black.Parent = player:WaitForChild("PlayerGui")

-- Hidden whenever it is not being used, which matters more than it sounds.
--
-- A full-screen Frame is still a control even at full transparency, and a control here does
-- not let a click through to another control underneath: it takes it. Left visible, this one
-- covered the whole screen above everything and quietly ate every button in the town -- the
-- inventory could not be clicked at all. Visible only while there is something to see.
local veil = Instance.new("Frame")
veil.BackgroundColor3 = Color3.new(0, 0, 0)
veil.BackgroundTransparency = 1
veil.Size = UDim2.new(1, 0, 1, 0)
veil.BorderSizePixel = 0
veil.Visible = false
veil.Parent = black

local fadeTo = 1                    -- where the veil is heading: 0 is black, 1 is clear
RunService.RenderStepped:Connect(function(dt)
	local at = veil.BackgroundTransparency
	if at == fadeTo then
		-- Clear and staying clear: out of the way entirely.
		if fadeTo == 1 and veil.Visible then veil.Visible = false end
		return
	end
	veil.Visible = true
	-- Down fast, up slow: the cut to black should feel like the blow that caused it, and the
	-- return should not.
	local rate = fadeTo < at and 4.5 or 1.8
	local step = rate * dt
	veil.BackgroundTransparency = math.abs(fadeTo - at) <= step and fadeTo
		or at + (fadeTo > at and step or -step)
end)

player.CharacterAdded:Connect(function()
	-- A beat on black after the new body lands, so the world does not snap in mid-fade.
	task.wait(0.15)
	fadeTo = 1
end)

-- A streak, as the town announces it, twice over: a system line in the chat, the way a Roblox
-- place says something to everybody that nobody in particular said -- which stays, for anybody who
-- looks back -- and a banner across the top of the screen for a few seconds, for everybody who
-- was busy looking at the fight.
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local TweenService = game:GetService("TweenService")

local BANNER_TOP = 124       -- under the duel score, which sits at 46 and is 64 tall
local BANNER_H = 56
local BANNER_HOLD = 3.5      -- seconds on screen before it goes
local CHAR_W = 12            -- roughly what one character of the town's face takes at body size

local bannerGui = Instance.new("ScreenGui")
bannerGui.Name = "CombatBanner"
bannerGui.IgnoreGuiInset = true
bannerGui.ResetOnSpawn = false
-- Not the menu click, either way: it has a chime of its own (below), and a banner going away is
-- not news.
bannerGui:SetAttribute("SfxOpen", "none")
bannerGui:SetAttribute("SfxClose", "none")
bannerGui.Enabled = false
bannerGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local bannerContent, banner = Theme.window(bannerGui, UDim2.new(0, 400, 0, BANNER_H), UDim2.new(0, 0, 0, -BANNER_H - 8))
local bannerText = Theme.label(bannerContent, "", { size2 = UDim2.new(1, -16, 1, 0), pos = UDim2.new(0, 8, 0, 0),
	colour = Theme.c.warnInk, align = Enum.TextXAlignment.Center })
local shown = 0              -- which announcement is up, so an old one's timer does not take down a new one

local function setBannerText(text)
	for _, child in ipairs(bannerContent:GetChildren()) do
		if child:IsA("TextLabel") then child.Text = text end
	end
end

local function across(width)
	local size = bannerGui.AbsoluteSize
	if size.X <= 0 then
		local cam = workspace.CurrentCamera
		size = cam and cam.ViewportSize or size
	end
	-- Centred, but never over the chat window, which sits in the top left down past this height.
	local chat = bannerGui.Parent:FindFirstChild("TownChat")
	local right = 0
	if chat and chat.Enabled then
		for _, child in ipairs(chat:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible and child.AbsolutePosition.Y < BANNER_TOP + BANNER_H then
				right = math.max(right, child.AbsolutePosition.X + child.AbsoluteSize.X)
			end
		end
	end
	return math.max(math.floor((size.X - width) / 2), right + 12)
end

-- ---- the chime ------------------------------------------------------------------------------
-- A streak's fanfare is the town's chime (shared/Chime.luau), in the streak's key.
local Chime = require(ReplicatedStorage:WaitForChild("Chime"))

-- Which key a streak's chime is in, in semitones from the 5-kill chime: a fourth below it for
-- on fire, and a fourth higher for each five after -- 10 up a fourth, 15 up a seventh, and so on,
-- stopping two octaves up, past which the top note is a whistle.
local CHIME_FOURTH = 5
local CHIME_HIGHEST = 24

local function chimeSemitones(streak)
	streak = tonumber(streak) or 5
	if streak < 5 then return -CHIME_FOURTH end
	return math.min(CHIME_HIGHEST, (math.floor(streak / 5) - 1) * CHIME_FOURTH)
end

local function chime(streak)
	Chime.play(chimeSemitones(streak))
end

local function announce(text, streak)
	shown += 1
	chime(streak)
	local mine = shown
	local width = math.max(360, #text * CHAR_W + 48)
	banner.Size = UDim2.new(0, width, 0, BANNER_H)
	setBannerText(text)
	local x = across(width)
	-- Down from above the top edge, or straight back into place when one is already up.
	if not bannerGui.Enabled then banner.Position = UDim2.new(0, x, 0, -BANNER_H - 8) end
	bannerGui.Enabled = true
	TweenService:Create(banner, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, x, 0, BANNER_TOP) }):Play()
	task.delay(BANNER_HOLD, function()
		if shown ~= mine then return end
		local out = TweenService:Create(banner, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0, x, 0, -BANNER_H - 8) })
		out:Play()
		task.delay(0.3, function()
			if shown == mine then bannerGui.Enabled = false end
		end)
	end)
end

task.spawn(function()
	local newsRemote = ReplicatedStorage:WaitForChild("CombatNews", 60)
	if not newsRemote then return end
	local TextChatService = game:GetService("TextChatService")
	newsRemote.OnClientEvent:Connect(function(text, streak)
		if type(text) ~= "string" then return end
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general then pcall(function() general:DisplaySystemMessage(text) end) end
		announce(text, streak)
	end)
end)

ReplicatedStorage:WaitForChild("CombatSfx").OnClientEvent:Connect(function(role, speed)
	play(role, speed)
	if role == "dies" then fadeTo = 0 end
end)

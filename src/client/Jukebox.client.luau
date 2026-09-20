-- The town's music.
--
-- A VGM log of NES register writes, replayed through NesEngine's sampled 2A03 voices. The
-- log is 49.7 seconds and loops; nothing here decides what the notes are, it only replays
-- what the chip was told at the times it was told it.
--
-- Waits until the waveforms have actually arrived. They are published assets fetched off
-- the chain, so for the first second or two of a session there is nothing to play with, and
-- starting anyway would silently drop the opening bars.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local Mixer = require(ReplicatedStorage:WaitForChild("Mixer"))
local Vgm = require(ReplicatedStorage:WaitForChild("Vgm"))
local NesEngine = require(ReplicatedStorage:WaitForChild("NesEngine"))
local TheMoon = require(ReplicatedStorage:WaitForChild("TheMoon"))

local player: any = nil
local wanted = true          -- whether music should be playing at all

task.spawn(function()
	-- The waveforms come off the chain; give them a while, then give up quietly rather
	-- than leaving a dead update loop running for the session.
	-- Long enough for a cold start. These are published assets fetched off the chain, and
	-- on a slow read they can be a minute in arriving; giving up at ten seconds meant the
	-- town was silent for the whole session with no clue as to why.
	local waited = 0
	while not NesEngine.ready() and waited < 120 do
		task.wait(0.25)
		waited += 0.25
	end
	if not NesEngine.ready() then
		warn("jukebox: the 2A03 waveforms never arrived, so there is nothing to play")
		return
	end

	local bytes = Vgm.decode(TheMoon)
	local made, why = Vgm.new(bytes, NesEngine)
	if not made then
		warn("jukebox: " .. tostring(why))
		return
	end
	player = made
	if wanted then player:play() end
	print(("jukebox: The Moon, %d bytes of 2A03 log"):format(#bytes))

	-- Heartbeat rather than RenderStepped on purpose: this is the last thing in a step,
	-- after the frame's work, so dt is the whole of the time that actually passed.
	--
	-- Not clamped any more. Clamping here threw away everything past 100ms, and update()
	-- threw away whatever it could not spend -- so a hitch did not delay the music, it
	-- deleted a piece of it, and the track ran permanently later afterwards. The player
	-- carries what it cannot spend and catches up without retriggering the gap.
	RunService.Heartbeat:Connect(function(dt)
		player:update(dt)
	end)
end)

--- M mutes and unmutes.
local function toggle(_, state)
	if state ~= Enum.UserInputState.Begin then return end
	wanted = not wanted
	if not player then return end
	if wanted then player:play() else player:stop() end
	print("jukebox: " .. (wanted and "on" or "off"))
end
ContextActionService:BindAction("Jukebox", toggle, false, Enum.KeyCode.M)

-- ---- how loud any of it is ---------------------------------------------------------
-- Bottom left, which is the corner nothing else uses: the chat is top left and every
-- panel in town is centred.
--
-- It moves the SoundGroup, not the music engine, so it covers the menu clicks and
-- anything a creator's script plays as well as the tune -- one number for the whole town
-- rather than five channel volumes that something else could overwrite on the next note.
local localPlayer = Players.LocalPlayer
local gui = localPlayer:WaitForChild("PlayerGui")
local mouse = localPlayer:GetMouse()

local screen = Instance.new("ScreenGui")


-- This town was laid out before the GUI inset existed, so it keeps the whole screen

-- and everything stays where it was put. A place written against Roblox wants the

-- default -- 36 pixels kept clear at the top for the topbar -- and gets it.

screen.IgnoreGuiInset = true
screen.Name = "Volume"
screen:SetAttribute("Hud", true)     -- always on; not a window anything should defer to
screen.ResetOnSpawn = false
screen.Parent = gui

-- Stood up on its end, in the corner. Along the bottom it ran across the width the action
-- bar and the hearts want, and a volume control is not what the middle of the screen is for;
-- upright it takes a strip of the left edge and nothing else has to move out of its way.
local TRACK_H = 132
-- A window like every other panel in the town, rather than a plain rounded rectangle. The
-- bevel is not decoration here: it is what says this is a thing you operate. A flat card
-- with a coloured strip in it reads as a readout, and the slider had been sitting there
-- looking like one.
--
-- Theme.window spends 7 pixels a side on the three bands and the clipping content frame, so
-- the box is 14 bigger in both directions than the old one and sits 7 further out -- which
-- leaves the track and the button exactly where they have always been on screen.
local bar = Theme.window(screen, UDim2.new(0, 46 + 14, 0, TRACK_H + 40 + 14),
	UDim2.new(0, 5, 1, -(TRACK_H + 66)))

local muteButton = Theme.button(bar, "Sound")
muteButton.Size = UDim2.new(0, 36, 0, 24)
muteButton.Position = UDim2.new(0, 5, 1, -29)
muteButton.TextSize = Theme.t.small
muteButton:SetAttribute("Sfx", "menu")

local track = Instance.new("TextButton")
track.Size = UDim2.new(0, 18, 0, TRACK_H)
track.Position = UDim2.new(0, 14, 0, 8)
track.BackgroundColor3 = Theme.c.field
track.AutoButtonColor = false
track.Text = ""
Theme.face(track)
track.Parent = bar
Theme.corner(track, 4)

-- Anchored at the bottom, because loud is up.
local fill = Instance.new("Frame")
fill.AnchorPoint = Vector2.new(0, 1)
fill.Position = UDim2.new(0, 0, 1, 0)
fill.Size = UDim2.new(1, 0, Mixer.get(), 0)
-- The bevel's own highlight, not Theme.c.good. `good` is RGB(0,0,151), which is exactly
-- fillTop -- the top of the window's gradient -- so the moment this sat inside a window the
-- column and the wall behind it were the same blue and the level could not be read at all.
-- Silver rising out of a dark well is the one pairing this palette has that always shows.
fill.BackgroundColor3 = Theme.c.accent
fill.BorderSizePixel = 0
fill.Parent = track
Theme.corner(fill, 4)

local restore = Mixer.get() > 0 and Mixer.get() or 0.7

local function showVolume()
	local v = Mixer.get()
	fill.Size = UDim2.new(1, 0, v, 0)
	muteButton.Text = v > 0 and "Sound" or "Muted"
	muteButton.BackgroundColor3 = v > 0 and Theme.c.button or Theme.c.muted
end

local function setFromPointer()
	local h = track.AbsoluteSize.Y
	if h <= 0 then return end
	local was = Mixer.get()
	-- Measured down from the top and turned over, so the top of the track is full.
	local now = Mixer.set(1 - (mouse.Y - track.AbsolutePosition.Y) / h)
	-- Only when it actually moved. A GuiObject write sets the whole GUI dirty, and the
	-- next sync restyles every object in the tree -- so writing the same value on every
	-- frame of a drag costs a full restyle per frame and changes nothing.
	if now == was then return end
	if now > 0 then restore = now end
	showVolume()
end

-- Held rather than clicked, so it drags, and the drag lasts until the button is let go --
-- anywhere, not just over the track.
--
-- It used to end on MouseLeave as well, which made the thing nearly unusable: the track is a
-- narrow strip, the pointer slides off it sideways within a few pixels of ordinary hand
-- movement, and the drag died there. The next press then jumped the volume to wherever the
-- cursor happened to be, which near the far end is silence -- so it read as a slider that
-- ignored you and muted itself.
local dragging = false
track.MouseButton1Down:Connect(function()
	dragging = true
	setFromPointer()
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

-- RenderStepped rather than Heartbeat: this is a per-frame redraw that follows the
-- pointer, and it runs before the frame is drawn rather than after the step's work.
RunService.RenderStepped:Connect(function()
	if dragging then setFromPointer() end
end)

muteButton.Activated:Connect(function()
	if Mixer.get() > 0 then Mixer.set(0) else Mixer.set(restore) end
	showVolume()
end)

showVolume()

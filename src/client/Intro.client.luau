-- Arriving.
--
-- The card, a fade to black, a rocket going up in the dark, and then the town. Four beats,
-- and the third one is doing real work: a cold start is fetching the skybox, the rocket, the
-- tree and every sound off a chain, and without something over the top you watch a bare grey
-- field assemble itself. So the black is held until the world is actually finished rather
-- than for a fixed count -- the noise covers it, and it lifts on a world that is already
-- there.
--
-- Everything but the bag. What you own arrives from the wallet on its own schedule and can
-- be minutes behind on a bad connection; nobody should sit in the dark for that, and the
-- action bar filling in a moment after you land reads as the bag arriving rather than as the
-- game still loading.
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Mixer = require(ReplicatedStorage:WaitForChild("Mixer"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local NesEngine = require(ReplicatedStorage:WaitForChild("NesEngine"))

local CARD = 3.2              -- how long the card holds before it goes
local FADE = 0.9              -- card to black
local ROAR = 2.3              -- black, with the engine
local LIFT = 1.1              -- black to the town
-- Coming down, and then sitting there.
--
-- Two numbers rather than one. The fall is what it was -- long enough to hear, where four
-- tenths read as a switch being thrown -- and the rumble after it is time spent at the
-- bottom before the cut, which is the part that makes it a thing that has gone rather than
-- a thing that stopped. The half second it takes comes out of the roar rather than being
-- added on the end, so the whole intro finishes where it did.
local DROP = 1.1              -- the engine falling back to the note it lit on
local RUMBLE = 0.5            -- and sitting on it, before it is cut
local PATIENCE = 40           -- most seconds the black will ever wait, however well it is going
-- And how long it will wait with NOTHING arriving. The black is a courtesy while the town
-- turns up, not a contract to wait for all of it: something that has not moved in three
-- seconds is not on its way, it is missing, and a missing prop in a far corner is not worth
-- a black screen. The town comes up without it and it appears when it appears.
--
-- The flat forty was the whole wait whenever anything at all was absent -- and something is
-- absent whenever a mesh has been built but not yet published, which is most of a working
-- afternoon.
local STALLED = 3

--- And how long it waits once the host has said it is FINISHED fetching. Everything the
--- black waits for comes out of the place's manifest, so when the host has been through it
--- whatever is missing is missing for good -- a mesh built but not yet published, most
--- often. That is not a stall, it is an answer, and waiting three seconds for it was three
--- seconds off every single load. This is only the beat a prop needs to have the MeshId it
--- was just handed actually applied to it.
local SETTLED = 0.35

-- The tune comes up from nothing across the whole of it and is at its proper level the moment
-- you can see. Not a fade over the last beat: a slow one, the length of the arrival, so it
-- reads as something you were always heading towards rather than as music starting.
--
-- Squared, because loudness is not linear -- a straight ramp is most of the way up by the
-- time it is a third along, and then appears to sit still.
local function tune(a)
	Mixer.duckMusic(math.clamp(a, 0, 1) ^ 2)
end
tune(0)

-- What has to be there before the black lifts. Not everything in the place: the things whose
-- absence is visible from the spawn point, which is the skybox, the two meshes standing in
-- their corners and the picture the hearts are drawn with.
local NEEDED = { "SkyboxUp", "SkyboxDn", "SkyboxFt", "SkyboxBk", "SkyboxLf", "SkyboxRt",
                 "RocketMesh", "TreeMesh", "HeartIcon", "FlameSprite" }

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "Intro"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
-- Over everything, including the panels: this is the one thing in the town that is allowed
-- to be in the way, and while it is up nothing behind it should be clickable.
screen.DisplayOrder = 1000
screen.Parent = gui

local black = Instance.new("Frame")
black.Name = "Black"
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BorderSizePixel = 0
black.Size = UDim2.new(1, 0, 1, 0)
black.Parent = screen

local card = Instance.new("ImageLabel")
card.Name = "Card"
card.BackgroundColor3 = Color3.new(0, 0, 0)
card.BorderSizePixel = 0
card.Size = UDim2.new(1, 0, 1, 0)
-- Drawn to fill whatever shape the window is, with the overflow lost off the sides. A card
-- letterboxed into a black frame reads as a video that failed to load.
card.ScaleType = Enum.ScaleType.Crop
card.Image = ""
-- Not until it is its turn. The black behind it is the right thing to be looking at while the
-- title screen is up and the picture is still being fetched; an empty card over it is a frame
-- of nothing that has to be explained.
card.Visible = false
card.Parent = screen

--- Whether a prop has its mesh yet, whatever shape the prop is.
---
--- A Model as well as a MeshPart, because the tree became two parts -- a Wood trunk and a
--- Neon canopy -- the moment the canopy needed lighting on its own. This asked for a MeshPart
--- and nothing else, so the tree could never count as arrived: the bar stopped at twelve of
--- thirteen, which on a 420 pixel track is indistinguishable from full, and the dark then sat
--- there for the whole forty second patience every single start. A loading screen that says
--- 100% while it waits is worse than no loading screen.
local function propReady(prop)
	if not prop then return false end
	if prop:IsA("MeshPart") then return prop.MeshId ~= "" end
	for _, d in ipairs(prop:GetDescendants()) do
		if d:IsA("MeshPart") and d.MeshId ~= "" then return true end
	end
	return false
end

--- How much of what you can see from the spawn point has arrived, 0 to 1.
---
--- Counted rather than guessed at. Thirteen things: ten files the place waits on, the sky
--- once the server has built it out of its six faces, and the two meshes once their MeshId is
--- filled in -- all of which say "arrived" by existing rather than by any flag somebody has
--- to remember to set. A bar drawn off a timer is a lie about how long is left; this one is
--- the actual count, so it stops where the fetch stops and moves when the fetch moves.
--- How many of the two standing props have their mesh in, remembered between frames.
---
--- Each one is a recursive search of the whole workspace -- a prop is a model in the map now
--- rather than something a server script built at the top of it -- and a search for a thing
--- that is NOT there walks every instance in the town before it can say so. This is asked
--- twice a frame for the length of the black, so when the tree has not been published that
--- was something like nine hundred full walks of the town, on the same thread the fetching
--- and the mounting and the music are on. The black screen was competing with the loading it
--- is there to cover.
---
--- So: once a prop is found it is kept, once its mesh is in nothing looks again, and the
--- search for one that is still missing happens four times a second rather than a hundred
--- and twenty.
local propFound, propHasMesh, lookedAt = {}, {}, 0
local propCount = 0

local function propsIn()
	if propHasMesh.Rocket and propHasMesh.Tree then return 2 end
	local now = os.clock()
	if now - lookedAt < 0.25 then return propCount end
	lookedAt = now
	local done = 0
	for _, name in ipairs({ "Rocket", "Tree" }) do
		if propHasMesh[name] then
			done += 1
		else
			local prop = propFound[name]
			if prop == nil or prop.Parent == nil then
				prop = workspace:FindFirstChild(name, true)
				propFound[name] = prop
			end
			if propReady(prop) then
				propHasMesh[name] = true
				done += 1
			end
		end
	end
	propCount = done
	return done
end

-- The ten files, fetched onto THIS machine. PlaceAssets holds each one's uri, which the
-- server puts there the moment it has read the manifest -- so a uri being present says
-- nothing about whether its bytes are here yet. ContentProvider:PreloadAsync does: it
-- loads each one where it will be drawn from and says so, one at a time, as it lands.
local arrived, preloadDone = 0, false
task.spawn(function()
	local place = ReplicatedStorage:WaitForChild("PlaceAssets", 180)
	local list = {}
	if place then
		for _, name in ipairs(NEEDED) do
			local v = place:WaitForChild(name, 180)
			if v and v.Value ~= "" then table.insert(list, v.Value) end
		end
	end
	ContentProvider:PreloadAsync(list, function(_, status)
		if status == Enum.AssetFetchStatus.Success then arrived += 1 end
	end)
	preloadDone = true
end)

local function worldProgress()
	local done, total = arrived, #NEEDED + 3
	if Lighting:FindFirstChildOfClass("Sky") then done += 1 end
	return (done + propsIn()) / total
end

--- Has everything the black is waiting on either arrived or failed to?
local function fetchDone()
	return preloadDone
end

-- The engine, which is the noise channel and nothing else.
--
-- A 2A03 has no way to make a rocket and every game on it made one anyway: the noise channel
-- held open, its period swept down, is a roar. Started high and thin and dragged low, with
-- the volume up at the front and easing off, it is a thing leaving rather than a thing
-- running.
--
-- It lights under the card rather than after it, so the sweep has the fade to black as well
-- as the dark to run in -- longer without a second more of black, which is the right trade:
-- the black was already the right length and the engine was over before it had gone anywhere.
-- Then it carries on through the lift as well, so the tail of it is under the first of the
-- town.
-- The noise channel's "frequency" is not a pitch. It is the rate the sample is read at, and
-- NesEngine divides it by the sample's own 44,100 to get a playback speed -- so the numbers
-- that mean anything here are tens of thousands, not hundreds.
--
-- The first version swept 2,400 down to 250, which reads the noise at a fortieth of its rate
-- and then a hundred-and-seventieth: that moves everything in it below hearing, and what is
-- left is a rumble you feel rather than a sound that lasts. It was not rolling off and the
-- sample does not decay -- scripts/sfx/nes-noise.wav is flat 20,000 RMS end to end, measured
-- -- it was pitched into the floor.
--
-- And it runs upward, not down. A rocket lights as a deep rumble and builds into a roar; a
-- sweep that starts bright and falls away is a thing landing.
-- Both low. The climb is a rocket getting further away, not a jet passing: the top of it
-- wants to still be a roar rather than a hiss, so the whole sweep sits in the bottom third of
-- what the sample can be read at.
--
-- The bottom is as far down as it can go and still be a sound. Reading the noise at a
-- fourteenth of its rate puts what was three kilohertz in it at about two hundred -- bass you
-- hear. A tenth of that, which is where this started, puts the same content at fifteen hertz:
-- felt, not heard, which is why it seemed to stop.
local FROM, TO = 3200, 15000

-- How much of the burn is spent down at the bottom before the climb starts. Ignition is a
-- rumble that sits there and then goes somewhere; a climb that begins on the first frame is a
-- thing already in flight.
--
-- Getting on for a third of it, which is about three quarters of a second -- most of the way
-- to twice the sixth it was. It eats into the climb rather than being added on the front, so
-- the drop, the rumble under it and the cut all still land where they do.
local IGNITE = 0.28

local ROCKET = "intro"

--- The engine falling back to where it started, quickly, at the same level.
---
--- Pitch only: it drops to the rumble it lit as and is then cut, which lands as the thing
--- receding rather than as somebody turning a sound off. A fade would do the same job and be
--- wrong for the same reason a fade always is here -- it spends the end of the sound getting
--- rid of it instead of ending it.
local function settling(u)
	if not NesEngine.ready() then return end
	NesEngine.setPitch(ROCKET, TO + (FROM - TO) * (u ^ 0.6))
end

local function engine(a)
	if not NesEngine.ready() then return end
	local climb = math.clamp((a - IGNITE) / (1 - IGNITE), 0, 1)
	local freq = FROM + (TO - FROM) * (climb ^ 0.7)
	-- Up over the first fifth and then held. It used to ease off across the rest, which on
	-- top of a fade at the end meant the thing spent most of its length getting quieter --
	-- an engine that is running is running.
	local loud = a < 0.2 and (a / 0.2) or 1
	NesEngine.noteOn(ROCKET, freq, math.clamp(loud, 0, 1))
end

-- The card is this machine's own (Main.gd puts it in ReplicatedFirst, where a loading screen's
-- things live on Roblox), so it is up before anything of the server's has arrived.
task.spawn(function()
	local splash = game:GetService("ReplicatedFirst"):WaitForChild("SplashImage", 6)
	if splash and splash.Value ~= "" then
		card.Image = splash.Value
		return
	end
	-- Nobody put one there, which is what a joined player gets: the card is the host's, and a
	-- server has no screen to have made one for. So the town carries its own, among its assets
	-- like the font and the sounds, and every client can fetch it for itself. Six seconds of
	-- grace first, because a client that DOES get one should use that rather than this.
	local folder = ReplicatedStorage:WaitForChild("PlaceAssets", 20)
	local own = folder and folder:WaitForChild("Splash", 20)
	if own and own.Value ~= "" then card.Image = own.Value end
end)

-- The bar, in the dark: one of the town's own windows, with a word and a bar in it.
--
-- Theme.window, not a bevel built by hand. It is the same blue gradient in fourteen bands and
-- the same three-band white bevel every panel in the town has, so the very first interface
-- anybody sees is the interface they are about to be given -- and the first version of this,
-- which drew its own two-tone frame, looked like a progress bar somebody had dropped on top
-- of the game rather than a part of it.
--
-- White for the fill. It is the one lit thing on a black screen and there is nothing to
-- distinguish it from, so it may as well be the brightest thing the palette has.
--
-- Hidden until the card goes: a progress bar across a title card is a title card with a
-- progress bar across it.
local BAR_W, BAR_H = 420, 86

local loading, loadingFrame = Theme.window(screen, UDim2.new(0, BAR_W, 0, BAR_H))
loadingFrame.Name = "Loading"
loadingFrame.Visible = false
-- Where the action bar sits, placed the way the action bar places itself: anchored bottom
-- centre and left alone. There was a hand-rolled version of this measuring the ScreenGui and
-- re-measuring it forty times, on the strength of a comment saying AnchorPoint is not
-- honoured -- and the action bar has been anchoring itself the whole time, one line, correct
-- on every window shape.
local BOTTOM = 65
loadingFrame.AnchorPoint = Vector2.new(0.5, 1)
loadingFrame.Position = UDim2.new(0.5, 0, 1, -BOTTOM)

local word = Instance.new("TextLabel")
word.Name = "Word"
word.BackgroundTransparency = 1
word.Position = UDim2.new(0, Theme.pad, 0, 10)
word.Size = UDim2.new(1, -Theme.pad * 2, 0, 28)
word.Text = "Loading"
word.TextColor3 = Theme.c.ink
word.TextSize = Theme.t.small
word.TextXAlignment = Enum.TextXAlignment.Left
Theme.face(word)
word.Parent = loading

-- The well, the same navy a panel gives you to type into.
local track = Instance.new("Frame")
track.Name = "Track"
track.BackgroundColor3 = Theme.c.field
track.BorderSizePixel = 0
track.Position = UDim2.new(0, Theme.pad, 0, 46)
track.Size = UDim2.new(1, -Theme.pad * 2, 0, 18)
track.Parent = loading
Theme.corner(track)

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
fill.BorderSizePixel = 0
fill.Size = UDim2.new(0, 0, 1, 0)
fill.Parent = track
Theme.corner(fill)

--- The bar follows the count, and never goes backwards: a thing that has arrived cannot
--- un-arrive, and a bar that twitched down would read as a fault rather than as progress.
local shown = 0
local function drawProgress()
	shown = math.max(shown, worldProgress())
	fill.Size = UDim2.new(math.clamp(shown, 0, 1), 0, 1, 0)
end

--- True while the title screen is still up.
---
--- The host holds this rather than the world being delayed, so the chain read, the assets and
--- the map are all arriving while somebody decides which button to press: Start walks into a
--- town that is most of the way there rather than one that has not begun.
local function titleUp()
	local node = ReplicatedStorage:FindFirstChild("Title")
	return node ~= nil and node:GetAttribute("Waiting") == true
end

task.spawn(function()
	-- Nothing until a door has been chosen. A moment's grace first, in case the host has not
	-- put the flag up yet -- absent means go, and a race that starts the intro under the title
	-- screen would be worse than a beat of black.
	task.wait(0.4)
	while titleUp() do
		task.wait(0.1)
	end

	card.Visible = true

	-- The card, however long it takes to turn up. Black until then, which is the same black
	-- the next beat uses, so a slow picture shortens the card rather than showing a gap.
	local waited = 0
	while card.Image == "" and waited < 8 do
		task.wait(0.1)
		waited += 0.1
	end
	-- The tune is all the way up three quarters of the way through the roar, not on the frame
	-- the light comes back: arriving at full exactly as the picture does reads as the music
	-- being switched on with the world, where getting there in the dark means the town appears
	-- into something already playing.
	--
	-- But the card is nearly silent, and that is a separate thing from where it finishes.
	-- Spreading one ramp across the whole arrival and then shortening it to end earlier made
	-- it half up by the time the card went -- which is a tune playing over a title card, not a
	-- tune arriving. So the card gets a hint of it, a twelfth, enough that the swell afterwards
	-- is a swell and not a start; everything else happens in the dark.
	--
	-- The cold-start hold is in neither part -- it has no length until it happens -- so on a
	-- slow load the tune reaches full and waits there rather than creeping up through it.
	local UNDER_CARD = 0.08
	local SWELL = FADE + ROAR * 0.75
	local function tuneCard(a)
		tune(UNDER_CARD * math.clamp(a, 0, 1))
	end
	local function tuneDark(a)
		tune(UNDER_CARD + (1 - UNDER_CARD) * math.clamp(a, 0, 1))
	end
	local t = 0
	while t < CARD do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		tuneCard(t / CARD)
	end

	local swelled = 0
	local function swell(dt)
		swelled += dt
		tuneDark(swelled / SWELL)
	end

	-- On the effects channel, not the music. It is a noise sweep off the same 2A03, but it
	-- is an effect: on the music channel it sat under the fade that brings the tune up from
	-- silence and could not be heard at all during the one beat it exists for.
	NesEngine.createChannel(ROCKET, "sfx")
	NesEngine.setInstrument(ROCKET, "noise")

	-- It lights most of the way through the fade rather than at the start of it: at the start
	-- the card is still plainly there and the engine arrives on top of a picture, which is a
	-- sound effect happening rather than a thing leaving. Late in the fade the screen is
	-- nearly black and the rumble comes up out of it.
	local LEAD = FADE * 0.65
	local BURN = (FADE - LEAD) + ROAR
	local burnt = 0
	local lit = os.clock()

	t = 0
	while t < FADE do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		swell(dt)
		if t >= LEAD then
			burnt += dt
			engine(math.clamp(burnt / BURN, 0, 1))
		end
		card.ImageTransparency = math.clamp(t / FADE, 0, 1)
	end
	card.Visible = false
	loadingFrame.Visible = true
	drawProgress()

	t = 0
	while t < ROAR do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		swell(dt)
		burnt += dt
		engine(math.clamp(burnt / BURN, 0, 1))
		drawProgress()
	end
	-- On a cold start the world is still arriving, so the engine holds at its low note and
	-- the black stays. On a warm one this loop does not run at all.
	local held, still = 0, 0
	local was = shown
	while shown < 1 and held < PATIENCE and still < (fetchDone() and SETTLED or STALLED) do
		local dt = RunService.RenderStepped:Wait()
		held += dt
		engine(1)
		-- Once a frame, not twice. drawProgress works the figure out and keeps it in `shown`,
		-- which only ever goes up, so it answers both "are we there" and "has anything moved"
		-- without asking the town a second time.
		drawProgress()
		still = shown > was and 0 or still + dt
		was = shown
	end
	-- Full, whatever the count said: the wait is over either way, and a bar left at nine
	-- tenths as the light comes up is a bar that lied about being finished.
	shown = 1
	drawProgress()
	if held > 0 then
		print(("intro: held the dark %.1fs waiting for the world"):format(held))
	end

	t = 0
	while t < DROP + RUMBLE do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		settling(math.clamp(t / DROP, 0, 1))
	end

	-- Cut here, in the dark, before any light. A rocket does not get quieter as it goes and
	-- it should not still be going when the town arrives: it leaves, there is a moment of
	-- nothing, and then you are standing in the square. Carrying it into the fade -- or
	-- worse, fading it out under one -- spent the loudest part of it disappearing behind a
	-- picture, which is most of why it never sounded like much.
	NesEngine.noteOff(ROCKET)
	print(("intro: the engine ran %.1fs, the dark lasted %.1fs")
		:format(os.clock() - lit, os.clock() - lit - (FADE - LEAD)))

	-- In now, and not before. The character is made as the black starts to go, so the town
	-- comes up with you already standing in it -- and nobody could reach you while you were
	-- still looking at a title card or a loading bar (Arrival.server.luau).
	task.spawn(function()
		local arrivedEvent = ReplicatedStorage:WaitForChild("Arrived", 30)
		if arrivedEvent then arrivedEvent:FireServer() end
	end)

	t = 0
	while t < LIFT do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		swell(dt)
		local a = math.clamp(t / LIFT, 0, 1)
		black.BackgroundTransparency = a
		-- The window goes out with the black rather than sitting over the town for a beat.
		-- Every frame in it, because a bevel is four frames and fading only the top one
		-- leaves the white edge behind on the square.
		for _, part in ipairs(loadingFrame:GetDescendants()) do
			if part:IsA("Frame") then part.BackgroundTransparency = a end
		end
		loadingFrame.BackgroundTransparency = a
		word.TextTransparency = a
	end
	-- All the way up, exactly, whatever the frames added up to.
	tune(1)
	screen:Destroy()
end)

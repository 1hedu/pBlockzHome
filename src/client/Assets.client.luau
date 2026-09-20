-- The place's own font and sounds, once the host has fetched them.
--
-- They are published assets like anything else, so they arrive late: the host has to pull
-- them off the chain, check their hashes and write them somewhere the engine can open,
-- while the panels have already built themselves. So this waits for them and then applies
-- them backwards over what is already on screen -- which is what Theme.setFont is for.
--
-- Sounds are hung on every button in the town from one place rather than wired into nine
-- panels. A button says which sound it wants with a `Sfx` attribute; anything that does not
-- say is a menu button, because most of them are.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Mixer = require(game:GetService("ReplicatedStorage"):WaitForChild("Mixer"))

local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

local sounds = {}

--- One Sound per clip, reused. A fresh instance per click means a fresh decode per click.
local function loadSound(name: string, path: string)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = path
	s.Volume = 0.55
	s.Parent = SoundService or workspace
	Mixer.sfx(s)
	sounds[name] = s
end

--- A voice per click, thrown away on a timer.
---
--- This used to retrigger the one Sound, on the reasoning that a blip which will not
--- interrupt itself feels stuck. It does, but restarting a clip that is still sounding cuts
--- it to a fraction of itself, and clicking briskly through a panel chopped the menu blip
--- down to a tick. A voice each costs nothing at this length and every one is heard whole.
local KEEP = 2

local function play(kind: string)
	-- "none" is a real answer and not a missing one. A left-click on a bag tile asks the
	-- thing to do its trick, and most things have no trick -- so that click makes no sound,
	-- because nothing happened and a click that says otherwise is a lie about the state of
	-- the world. Saying so out loud beats relying on there being no clip by that name.
	if kind == "none" then return end
	local s = sounds[kind]
	if not s then return end
	local voice = s:Clone()
	voice.Parent = s.Parent
	Mixer.sfx(voice)
	voice:Play()
	task.delay(KEEP, function()
		if voice and voice.Parent then voice:Destroy() end
	end)
end

--- Everything clickable gets a voice.
---
--- On pressing, not on hovering. A cursor blip per option makes sense when a d-pad moves
--- the cursor one step at a time; a mouse sweeps across six of them on the way to the one
--- you want, and the same sound then reads as a rattle rather than as feedback.
---
--- Three gestures, three attributes. `Sfx` is the left-click and defaults to the menu blip
--- because most buttons are menu buttons. `SfxRight` and `SfxShiftRight` are silent unless a
--- panel says otherwise -- a right-click on something with no right-click behaviour should
--- not click. The bag is what they are for: it equips on right-click now, and putting
--- something on has always been the item clip while taking it off is a menu action.
---
--- Bound once per instance: the shop rebuilds its rows on every refresh, and a row bound
--- twice plays twice.
local function hook(inst: Instance)
	if not (inst:IsA("TextButton") or inst:IsA("ImageButton")) then return end
	if inst:GetAttribute("SfxBound") then return end
	inst:SetAttribute("SfxBound", true)
	inst.Activated:Connect(function()
		play(inst:GetAttribute("Sfx") or "menu")
	end)
	inst.MouseButton2Click:Connect(function()
		-- Read when it is clicked rather than when it is bound: which clip a right-click
		-- wants depends on whether the thing is on you, and that changes under the same
		-- button between one refresh and the next.
		local held = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local want = held and inst:GetAttribute("SfxShiftRight") or inst:GetAttribute("SfxRight")
		if want then play(want) end
	end)
end

--- A panel opening or closing is a menu action too.
---
--- A HUD is not, and says so: the same `Hud` attribute that stops Weapons.client.luau counting
--- one as an open window. Nobody opened it. The hearts were the phantom click at startup --
--- they come up when the server says you are in a fight and go again when the chain says the
--- town has fighting switched off, which is two clicks nobody clicked, over the title card,
--- every time the game started.
local function hookScreen(screen: Instance)
	if not screen:IsA("ScreenGui") then return end
	if screen:GetAttribute("Hud") then return end
	if screen:GetAttribute("SfxBound") then return end
	screen:SetAttribute("SfxBound", true)
	local was = screen.Enabled
	-- A screen may name its own sounds for opening and closing, SfxOpen and SfxClose, the way a
	-- button names its click with Sfx; "none" is silence. Unnamed, it is the menu sound both ways.
	screen:GetPropertyChangedSignal("Enabled"):Connect(function()
		if screen.Enabled ~= was then
			was = screen.Enabled
			play(screen:GetAttribute(was and "SfxOpen" or "SfxClose") or "menu")
		end
	end)
end

local function hookAll(root: Instance)
	for _, d in ipairs(root:GetChildren()) do
		hookScreen(d)
	end
	for _, d in ipairs(root:GetDescendants()) do
		hook(d)
	end
end

-- The host puts the resolved paths here, one StringValue each, once it has them.
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("PlaceAssets", 30)
	if not folder then
		warn("assets: the host never published the place's font and sounds")
		return
	end

	-- WaitForChild per value, not just the folder: the host makes the folder first and
	-- drops each asset in as its fetch comes back, so the folder exists long before
	-- anything is in it.
	local face = folder:WaitForChild("Reactor7", 25)
	if face and face.Value ~= "" then
		Theme.setFont(Font.new(face.Value))
	end

	local menu = folder:WaitForChild("SfxMenu", 25)
	local item = folder:WaitForChild("SfxItem", 25)
	if menu and menu.Value ~= "" then loadSound("menu", menu.Value) end
	if item and item.Value ~= "" then loadSound("item", item.Value) end

	hookAll(gui)
	gui.DescendantAdded:Connect(hook)
	gui.ChildAdded:Connect(hookScreen)
	-- Counted, not guessed: `sounds` is keyed by name, so # on it is always 0 and the
	-- line cheerfully said "0 sound(s)" with both of them loaded and working.
	local n = 0
	for _ in pairs(sounds) do n += 1 end
	print(("assets: font %s, %d sound(s)"):format(
		face and face.Value ~= "" and "on" or "missing", n))
end)

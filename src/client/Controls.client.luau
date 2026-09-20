-- The town's keyboard and mouse, WoW's way.
--
-- Roblox's default controls walk you the way the camera looks and turn you to face the way you
-- walk. That is kept for ordinary walking, and two drags are added, after World of Warcraft's --
-- except that WoW's left-drag becomes Ctrl + right-drag here, because the left button swings:
--
--   right-drag         the camera turns and your forward turns with it. Standing, you face where the
--                      view looks; W, A and D run you that way -- ahead, left, right -- turned to face
--                      where you are running, the way WoW and Roblox both do; S backs you up still
--                      facing ahead. And the moment you swing, you face ahead for the stroke,
--                      whichever way you were running. What aiming the cane wants.
--   Ctrl + right-drag  the camera looks around on its own. You keep your own facing: W and S walk
--                      you forward and back along it, A / D (or the arrows) turn you. WoW's
--                      left-drag.
--
-- Ctrl can go down or come up in the middle of a drag, and the drag changes with it.
--
-- Shift walks at half speed -- Humanoid.WalkSpeed halved while it is held, given back when it is
-- let go. The stride slows with it: the walk animation runs as fast as he actually moves, as
-- Roblox's Animate does. (The place turns off Roblox's own use of Shift, mouse lock, with
-- StarterPlayer.EnableMouseLockOption.)
--
-- Built the way Roblox builds a control scheme of its own: the place sets
-- StarterPlayer.DevComputerMovementMode to Scriptable, which "disables all default controls and
-- allows you to script your own", and this drives the character through the Humanoid the way
-- Roblox's own ControlModule does -- Humanoid:Move every frame, Humanoid.Jump while Space is held.
-- Facing the camera is UserGameSettings.RotationType CameraRelative, shift lock's setting; holding
-- your facing while you walk is Humanoid.AutoRotate off. The camera is still the engine's.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local settings = UserSettings():GetService("UserGameSettings")

-- How fast A / D turn you with the camera looking elsewhere: half a turn a second, WoW's rate.
local TURN = math.pi
-- How long a click faces you ahead before the server's word that a swing started arrives.
local ASKED_GRACE = 0.35
-- What Shift does to the walk.
local SLOW = 0.5
local slowed = nil              -- { humanoid, the WalkSpeed it had } while Shift has it slowed

local K = Enum.KeyCode
local held = {}                 -- the keys this script is steering by, down right now

local function down(...)
	for _, k in ipairs({ ... }) do
		if held[k] then return true end
	end
	return false
end

local function ctrlDown()
	return UserInputService:IsKeyDown(K.LeftControl) or UserInputService:IsKeyDown(K.RightControl)
end

local rightHeld = false
local mode = "free"             -- "free", "follow" (right-drag) or "hold" (Ctrl + right-drag)
local heldHumanoid = nil        -- the Humanoid whose AutoRotate "hold" turned off, to give it back

local function humanoid()
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

--- Right-drag's facing, decided every frame: ahead (CameraRelative, which turns you at once) while
--- standing, backing up or swinging; the way you run (MovementRelative) otherwise.
local function setRotation(camera)
	local want = camera and Enum.RotationType.CameraRelative or Enum.RotationType.MovementRelative
	if settings.RotationType ~= want then settings.RotationType = want end
end

local function swinging()
	local ch = player.Character
	if ch and ch:GetAttribute("Swinging") then return true end
	local asked = player:GetAttribute("SwingAskedAt")
	return type(asked) == "number" and os.clock() - asked < ASKED_GRACE
end

local function update()
	local want = not rightHeld and "free" or (ctrlDown() and "hold" or "follow")
	if want == mode then return end
	mode = want
	setRotation(want == "follow")
	if want == "hold" then
		local hum = humanoid()
		if hum and hum.AutoRotate then
			hum.AutoRotate = false
			heldHumanoid = hum
		end
	elseif heldHumanoid then
		heldHumanoid.AutoRotate = true
		heldHumanoid = nil
	end
end

local function isCtrl(input)
	return input.KeyCode == K.LeftControl or input.KeyCode == K.RightControl
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if processed then return end
		rightHeld = true
		update()
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		if isCtrl(input) then update() return end
		-- A key a text box took is typing, not walking.
		if processed then return end
		held[input.KeyCode] = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightHeld = false
		update()
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		held[input.KeyCode] = nil
		if isCtrl(input) then update() end
	end
end)

-- Starting to type lets go of everything; so does losing the window, which loses the releases.
local function letGo()
	table.clear(held)
	rightHeld = false
	update()
end
UserInputService.TextBoxFocused:Connect(letGo)
UserInputService.WindowFocusReleased:Connect(letGo)

player.CharacterAdded:Connect(function()
	heldHumanoid = nil
	letGo()
end)

RunService.RenderStepped:Connect(function(dt)
	local hum = humanoid()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end
	local forward = (down(K.W, K.Up) and 1 or 0) - (down(K.S, K.Down) and 1 or 0)
	local right = (down(K.D, K.Right) and 1 or 0) - (down(K.A, K.Left) and 1 or 0)
	if mode == "hold" then
		-- Your own facing: A / D turn it, W / S walk along it.
		if right ~= 0 then
			root.CFrame = root.CFrame * CFrame.Angles(0, -right * TURN * dt, 0)
		end
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		hum:Move(flat.Magnitude > 1e-3 and flat.Unit * forward or Vector3.zero, false)
	else
		-- The camera's: W is where it looks, A / D beside it.
		hum:Move(Vector3.new(right, 0, -forward), true)
		if mode == "follow" then
			local running = (right ~= 0 or forward > 0)
			setRotation(not running or forward < 0 or swinging())
		end
	end
	if down(K.Space) then hum.Jump = true end

	-- Shift: half the walk, for as long as it is held, and the humanoid's own speed back after.
	local slow = down(K.LeftShift, K.RightShift)
	if slowed and (not slow or slowed.humanoid ~= hum) then
		-- Given back only if it is still the halved speed. Something else may have set it since --
		-- a fishing line holding you where you stand, or letting you go -- and putting back what it
		-- was before would undo that.
		local h = slowed.humanoid
		if h.Parent and math.abs(h.WalkSpeed - slowed.speed * SLOW) < 1e-3 then h.WalkSpeed = slowed.speed end
		slowed = nil
	end
	if slow and not slowed then
		slowed = { humanoid = hum, speed = hum.WalkSpeed }
		hum.WalkSpeed = hum.WalkSpeed * SLOW
	end
end)

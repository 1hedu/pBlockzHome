-- Picking a thing up in one panel and putting it down in another.
--
-- Two problems, one place. The first is that a drag needs something to look at: without an
-- icon under the pointer, a drag that has hold of something and a drag that has hold of
-- nothing are the same picture, and the only way to find out which you have is to let go and
-- see what happened.
--
-- The second is that the bag and the action bar are separate ScreenGuis built by separate
-- scripts, and neither can see the other's buttons. A press begins in one and ends over the
-- other, so something has to sit between them: what is being carried, and where the pointer
-- was when it was let go.
--
-- Client-side and nothing to do with the server. A ModuleScript gives each side its own copy,
-- so this is one player's hands -- what they have hold of this instant. Where a thing ends up
-- is the server's business and goes through the wardrobe's remote like everything else.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Carry = {}

--- Fired when a carried thing is let go: (model, x, y, from) -- what it was, where the
--- pointer was, and which panel it came out of. Whoever is under that point decides whether
--- it means anything, and says so by calling Carry.claim().
Carry.dropped = Instance.new("BindableEvent")

--- Fired just after, and only if nobody claimed it: the same four things, for the panels that
--- care about a thing being dropped on NOTHING -- which is how you take something off.
---
--- Two events rather than one because the panels cannot see each other: the bag has no idea
--- where the action bar's squares are, so "not over anything of mine" is not the same as "not
--- over anything". Whoever took it says so; silence means it fell on the floor.
Carry.missed = Instance.new("BindableEvent")

local held = nil          -- { model = ..., from = ... } while something is being carried
local taken = false       -- whether anybody claimed the drop being handled right now
local ghost = nil
local screen = nil

local SIZE = 48
-- How far the pointer has to move before the icon appears. Every click is a press and a
-- release in the same place, so without this an ordinary click flashes a ghost for a frame.
-- A few pixels is the difference between a click and the start of a drag, and it is the same
-- few pixels every desktop uses for the same reason.
local WAKE = 6

local function make()
	if screen then return end
	local player = Players.LocalPlayer
	screen = Instance.new("ScreenGui")
	screen.Name = "Carrying"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	-- Over everything, and taking no input: this is a picture of what is in your hand, and a
	-- picture that ate clicks would stop the drop landing on whatever is underneath it.
	screen.DisplayOrder = 500
	screen:SetAttribute("Hud", true)
	screen.Parent = player:WaitForChild("PlayerGui")

	ghost = Instance.new("ImageLabel")
	ghost.Name = "Ghost"
	ghost.BackgroundTransparency = 1
	ghost.ImageTransparency = 0.25
	ghost.Size = UDim2.new(0, SIZE, 0, SIZE)
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Visible = false
	ghost.ZIndex = 10
	ghost.Parent = screen
end

--- Picks something up: the icon follows the pointer until it is put down.
function Carry.lift(model, image, source)
	make()
	local at = UserInputService:GetMouseLocation()
	held = { model = model, at = at, source = source or "" }
	ghost.Image = image or ""
	-- A thing with no thumbnail that the town built is carried as its model.
	local ModelPicture = require(script.Parent.ModelPicture)
	ModelPicture.clear(ghost)
	if (image == nil or image == "") then ModelPicture.show(ghost, model) end
	ghost.Visible = false
	ghost.Position = UDim2.fromOffset(at.X, at.Y)
end

--- What is being carried, if anything.
function Carry.held()
	return held and held.model or nil
end

--- Said by whoever handled the drop, so nobody treats it as having landed on nothing.
function Carry.claim()
	taken = true
end

--- Puts it down wherever the pointer is, and tells whoever is listening.
---
--- Always fires, even over nothing: a panel that was showing "this is where it would land"
--- has to hear that the drag is over, or it goes on showing it.
function Carry.release()
	local was = held
	held = nil
	if ghost then
		ghost.Visible = false
		ghost.Image = ""
		require(script.Parent.ModelPicture).clear(ghost)
	end
	-- Asked of the Mouse rather than of UserInputService. GetMouseLocation is the position
	-- of the last event the runtime saw, and an event that went through a GuiObject arrives
	-- in that object's own coordinates -- so after any click on a panel it answers with a
	-- point inside that panel. The engine was fixed to hand those over in screen space; this
	-- stays on the Mouse because it is the one that was right either way.
	local mouse = Players.LocalPlayer:GetMouse()
	local x, y = mouse.X, mouse.Y
	taken = false
	Carry.dropped:Fire(was and was.model or nil, x, y, was and was.source or "")
	-- A beat later, so every listener has had its say.
	task.defer(function()
		if not taken and was then
			Carry.missed:Fire(was.model, x, y, was.source)
		end
	end)
end

RunService.RenderStepped:Connect(function()
	if not held or not ghost then return end
	local at = UserInputService:GetMouseLocation()
	ghost.Position = UDim2.fromOffset(at.X, at.Y)
	if not ghost.Visible and ghost.Image ~= "" and (at - held.at).Magnitude > WAKE then
		ghost.Visible = true
	end
end)

-- Letting go anywhere at all ends it. Without this, releasing over the world leaves the icon
-- stuck to the pointer for ever, and the next click puts it somewhere nobody asked for.
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and held then
		Carry.release()
	end
end)

return Carry

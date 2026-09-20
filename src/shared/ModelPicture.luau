-- A picture of a model the town built for itself, drawn from the model.
--
-- Things off the chain come with a thumbnail. The fish and the rod do not: they are the town's own
-- (shared/Fish.luau, built into ReplicatedStorage.Made), and a picture of one would be one more
-- thing to publish and keep in step with the model. So wherever a tile would show a thumbnail it
-- shows the model itself instead, in a ViewportFrame, side on -- which is the model as it is today,
-- helmet and all.
--
-- By exact name only. An Engram wears the "Engram" badge under a name of its own ("Engram#3"), and
-- its tile keeps saying which link it is rather than showing twelve identical badges.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModelPicture = {}

local NAME = "ModelPicture"

--- The town-built model with this name, or nil.
function ModelPicture.template(modelName)
	local made = ReplicatedStorage:FindFirstChild("Made")
	return made and type(modelName) == "string" and made:FindFirstChild(modelName) or nil
end

--- A ViewportFrame filling `parent`, looking at a copy of `template` from its right side.
function ModelPicture.frame(parent, template)
	local frame = Instance.new("ViewportFrame")
	frame.Name = NAME
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 1
	frame.Active = false
	frame.Ambient = Color3.fromRGB(190, 190, 200)
	frame.LightColor = Color3.fromRGB(255, 255, 255)
	frame.LightDirection = Vector3.new(-1, -1, -0.5)
	frame.Parent = parent

	local copy = template:Clone()
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			if d.Transparency < 1 then
				local a, b = d.Position - d.Size / 2, d.Position + d.Size / 2
				lo = Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z))
				hi = Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z))
			end
		end
	end
	copy.Parent = frame
	if lo.X == math.huge then return frame end

	local centre = (lo + hi) / 2
	local reach = math.max(hi.Z - lo.Z, hi.Y - lo.Y, 0.5)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	-- From the right, a little ahead and above, so a helmet reads as a bubble over the head.
	camera.CFrame = CFrame.lookAt(centre + Vector3.new(reach * 2.1, reach * 0.4, -reach * 0.5), centre)
	camera.Parent = frame
	frame.CurrentCamera = camera
	return frame
end

--- Puts the model called `modelName` in `holder`, replacing whatever picture was there. True if
--- there was a model to show; false (and nothing shown) otherwise.
function ModelPicture.show(holder, modelName)
	ModelPicture.clear(holder)
	local template = ModelPicture.template(modelName)
	if not template then return false end
	ModelPicture.frame(holder, template)
	return true
end

function ModelPicture.clear(holder)
	local old = holder:FindFirstChild(NAME)
	if old then old:Destroy() end
end

return ModelPicture

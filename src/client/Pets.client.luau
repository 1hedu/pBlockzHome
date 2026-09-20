-- Every pet's wings, flapped here, on each screen, and nowhere on the wire.
--
-- The server used to swing them: two CFrames a wing, every frame, for every pet in the
-- town, replicated to everybody -- three thousand changes a second for one bird following
-- one player, a fifth of a megabyte a second down every client's link, for a pose each
-- client could work out for itself from the model and the clock. So it does. The server
-- moves the pet (its root, once a frame, which is what a pet needs from it); the wings are
-- each client's own, like a walk animation.
--
-- The rest pose is read once, the first time a pet is seen, before this script has moved
-- anything: read later it would be the flapped pose and the wings would wind open.
local RunService = game:GetService("RunService")

local FLAP_SPEED = 7.4         -- beats a second; fast enough to blur, slow enough to read
local FLAP_SWEEP = 0.62        -- radians either side of rest

local pets = {}   -- model -> { wings = { { part, rest, side } } }

local function forget(model)
	pets[model] = nil
end

local function watch(model)
	if pets[model] then return end
	local wings = {}
	local pivot = model:GetPivot()
	for _, d in ipairs(model:GetDescendants()) do
		-- The side is the letter straight after "Wing", not any R in the name: matching
		-- "R" loosely made WingLRim a right wing, because "Rim" has one in it.
		local side = d.Name:match("^Wing([LR])")
		if d:IsA("BasePart") and side then
			table.insert(wings, { part = d, rest = pivot:ToObjectSpace(d.CFrame), side = side == "R" and 1 or -1 })
		end
	end
	if #wings == 0 then return end
	pets[model] = { wings = wings }
end

local function consider(inst)
	if inst:IsA("Model") and inst.Name:match("^Pet_") then
		-- Its parts land after it does; the wings are read once they are all there.
		task.defer(watch, inst)
	end
end

for _, d in ipairs(workspace:GetChildren()) do consider(d) end
workspace.ChildAdded:Connect(consider)
workspace.ChildRemoved:Connect(function(inst) if inst:IsA("Model") then forget(inst) end end)

RunService.RenderStepped:Connect(function()
	local swing = math.sin(os.clock() * FLAP_SPEED) * FLAP_SWEEP
	for model, pet in pairs(pets) do
		if not model.Parent then
			pets[model] = nil
		else
			-- Each side swings the opposite way about the model's own vertical, so the pair
			-- opens and closes rather than twisting; the hinge is the middle of the head,
			-- which is where they root.
			local pivot = model:GetPivot()
			for _, w in ipairs(pet.wings) do
				if w.part.Parent then
					w.part.CFrame = pivot * CFrame.Angles(0, swing * w.side, 0) * w.rest
				end
			end
		end
	end
end)

-- The sky, off the chain.
--
-- Six 512s published like the font and the sounds: they arrive as paths under
-- ReplicatedStorage.PlaceAssets and a Sky with those six faces is what the renderer draws
-- a cubemap from. The Skybox properties have been on the class all along; until recently
-- nothing read them.
--
-- Waits for all six. Five faces and a hole is worse than the plain sky it replaces, so if
-- any one of them never arrives this leaves the default alone and says which.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local FACES = { "SkyboxRt", "SkyboxLf", "SkyboxUp", "SkyboxDn", "SkyboxBk", "SkyboxFt" }

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("PlaceAssets", 180)
	if not folder then
		warn("sky: no place assets, so no sky")
		return
	end

	local paths = {}
	for _, face in ipairs(FACES) do
		-- A cold start fetches two megabytes off the chain, so this is patient.
		local value = folder:WaitForChild(face, 180)
		if not value or value.Value == "" then
			warn(("sky: %s never arrived, so the sky is left as it was"):format(face))
			return
		end
		paths[face] = value.Value
	end

	for _, existing in ipairs(Lighting:GetChildren()) do
		if existing:IsA("Sky") then existing:Destroy() end
	end

	local sky = Instance.new("Sky")
	sky.Name = "MoonEarthSky"
	-- The backdrop has its own earth and its own stars painted into it; the engine's would
	-- be a second sun in somebody else's sky.
	sky.CelestialBodiesShown = false
	sky.StarCount = 0
	for _, face in ipairs(FACES) do
		sky[face] = paths[face]
	end
	sky.Parent = Lighting
	print("sky: the moon, in six faces off the chain")
end)

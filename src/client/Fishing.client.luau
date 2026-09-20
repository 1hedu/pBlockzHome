-- Casting and reeling, from your own wallet.
--
-- With the rod in hand, hold the button to wind up -- longer is further -- and let go aimed off the
-- edge of the map: he lunges, the float goes out into space, and your wallet casts on the Fishing
-- contract (contracts/Fishing.sol). The chain says when a fish bites --
-- a block or three later -- and this machine reads that off the contract itself, line by line
-- (lineOf). When it bites, click again: your wallet reels, and there are three blocks to land it in
-- before it gets away. What was on the end is the chain's to say; the server reads it and shows it.
--
-- And every float out in space, yours or anybody's, is flown out from its rod and bobbed here, on
-- this machine -- a float bobbing is not something the server needs to send twenty times a second.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Fish = require(ReplicatedStorage:WaitForChild("Fish"))
local SpaceFishing = require(ReplicatedStorage:WaitForChild("SpaceFishing"))
local OwnWallet = require(ReplicatedStorage:WaitForChild("OwnWallet"))
local Contracts = require(ReplicatedStorage:WaitForChild("Contracts"))
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("FishingRemote")

--- How often to ask the chain where the line is. Blocks are about ten seconds.
local POLL = 2
--- How long to wait for a cast that has confirmed to show up on the node we read from.
local SHOW_UP = 60

-- ---- what it says ------------------------------------------------------------------------

local screen = Instance.new("ScreenGui")
screen.Name = "FishingHud"
screen.IgnoreGuiInset = true
screen.ResetOnSpawn = false
screen:SetAttribute("Hud", true)
screen.Parent = gui

local words = Instance.new("TextLabel")
words.Name = "Words"
words.BackgroundTransparency = 1
words.Size = UDim2.new(1, 0, 0, 32)
words.Position = UDim2.new(0, 0, 1, -250)   -- above the hearts (Hearts.client.luau)
words.TextColor3 = Theme.c.ink
words.TextStrokeTransparency = 0.3
words.TextSize = Theme.t.body
words.Text = ""
Theme.face(words)
words.Parent = screen

-- Cancel: a line holds you where you stand until it is done with (Fishing.server.luau), and this is
-- how to walk away from one anyway. The line stays out on the chain -- nothing here can take it back
-- -- and is picked up again the next time you fish, if its window has not passed.
local cancelButton = Theme.button(screen, "Cancel")
cancelButton.Name = "Cancel"
cancelButton.Size = UDim2.new(0, 140, 0, 40)
cancelButton.Position = UDim2.new(0.5, -70, 1, -300)
cancelButton.Visible = false

local saidAt = 0
--- Puts a line on screen; `hold` seconds, or until something else is said when nil.
local function say(text, hold)
	saidAt += 1
	local mine = saidAt
	words.Text = text
	print("fishing: " .. text)
	if hold then
		task.delay(hold, function()
			if saidAt == mine then words.Text = "" end
		end)
	end
end

-- ---- your line ---------------------------------------------------------------------------

local state = "idle"      -- idle | casting | waiting | bite | reeling | landing
local verdict = nil       -- the town's answer to the last cast: "casting", or "refused"
-- (the Cancel button shows while a line is out and nothing is on its way to the chain)
local gen = 0             -- which cast this is; a loop from an older one stops when it sees a newer

local function holdingRod()
	local ch = player.Character
	local rod = ch and ch:FindFirstChild(Fish.ROD)
	return rod ~= nil and rod:IsA("Accoutrement")
end

local function windowOpen()
	for _, s in ipairs(gui:GetChildren()) do
		if s:IsA("ScreenGui") and s.Enabled and s.Name ~= "TownDialog" and not s:GetAttribute("Hud") then
			return true
		end
	end
	return false
end

local function finish(kind, text, hold)
	gen += 1
	state = "idle"
	cancelButton.Visible = false
	remote:FireServer(kind)
	if text then say(text, hold or 3) end
end

--- Where the line is, off the contract: out, the bite block, the last block, and the block now.
local function readLine()
	local address = player:GetAttribute("WalletAddress")
	if type(address) ~= "string" or address == "" then return nil end
	local answer = OwnWallet.request({ action = "read", to = Contracts.Fishing, fn = "lineOf(address)",
		args = { address }, returns = { "bool", "uint64", "uint64", "uint64" } }, 30)
	local w = answer and answer.ok and answer.words
	if type(w) ~= "table" then return nil end
	return { out = w[1] == true, bite = tonumber(w[2]) or 0, last = tonumber(w[3]) or 0, now = tonumber(w[4]) or 0 }
end

--- Watches the line from the cast until it is landed, gets away, or is put away.
local function watch(mine)
	local showed = os.clock()
	while gen == mine do
		local line = readLine()
		if gen ~= mine then return end
		if line then
			if state == "casting" then
				if line.out and line.bite > 0 and line.now < line.last + 1 then
					state = "waiting"
					remote:FireServer("waiting")
					say("Waiting for a bite...")
				elseif os.clock() - showed > SHOW_UP then
					finish("cancel", "The cast never showed up on the chain.")
					return
				end
			end
			if (state == "waiting" or state == "bite") and line.out then
				if line.now > line.last then
					finish("gone", "It got away.")
					return
				elseif state == "waiting" and line.now >= line.bite then
					state = "bite"
					remote:FireServer("bite")
					say("Something's biting! Click to reel it in!")
				end
			end
		end
		task.wait(POLL)
	end
end

local resumeOpenLine   -- below

local function castOut(point)
	-- A line already out on the chain -- left, cancelled, or its prompt waved off -- is picked up
	-- rather than cast over: casting again would only be refused.
	if Contracts.Fishing and Contracts.Fishing ~= "" then
		local open = readLine()
		if open and open.out and open.now <= open.last then
			resumeOpenLine()
			return
		end
	end
	gen += 1
	local mine = gen
	state = "casting"
	verdict = nil
	remote:FireServer("cast", point)
	if not Contracts.Fishing or Contracts.Fishing == "" then
		task.wait(1.5)
		if gen == mine then finish("cancel", "The space fishing isn't open yet.") end
		return
	end
	say("Casting...")
	-- The town first, the wallet second. The lunge takes a moment and the town can refuse the cast
	-- -- a line still coming in, a bad aim -- and the wallet was being asked to sign at the same
	-- time, so a refused cast still put a prompt up for a transaction the chain would reject.
	local waited = 0
	while gen == mine and verdict == nil and waited < 4 do waited += task.wait(0.1) end
	if gen ~= mine then return end
	if verdict ~= "casting" then
		if state == "casting" then finish("cancel", verdict == nil and "The cast never went out." or nil) end
		return
	end
	local answer = OwnWallet.request({ action = "write", to = Contracts.Fishing, fn = "cast()", args = {},
		note = "Cast your line into space" })
	if gen ~= mine then return end
	if not answer or not answer.ok then
		finish("cancel", tostring(answer and answer.message or "Your wallet didn't answer."))
		task.spawn(resumeOpenLine)
		return
	end
	watch(mine)
end

local function reelIn()
	local mine = gen
	state = "reeling"
	remote:FireServer("reel")
	say("Reeling in...")
	local answer = OwnWallet.request({ action = "write", to = Contracts.Fishing, fn = "reel()", args = {},
		note = "Reel in your line" })
	if gen ~= mine then return end
	if not answer or not answer.ok then
		-- Waved off, or it did not land: the fish may still be on, until its window closes.
		state = "bite"
		remote:FireServer("bite")
		say(tostring(answer and answer.message or "Your wallet didn't answer.") .. " Click to try again.")
		return
	end
	-- Landed on chain. The server reads what it was and says so (result), and until it does the
	-- line is still being landed: not idle, or a cast would go out over it and be refused.
	gen += 1
	state = "landing"
	remote:FireServer("landed")
end

local windingSince = nil   -- os.clock() the button went down to wind up a cast

--- Let go of a wind-up: where the aim and the charge put the float, and off it goes -- or, aimed at
--- the town, put down with nothing thrown.
local function letGo()
	local since = windingSince
	windingSince = nil
	if not since then return end
	local fraction = SpaceFishing.fraction(os.clock() - since)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not camera or state ~= "idle" or not holdingRod() then
		remote:FireServer("uncharge")
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local point = SpaceFishing.castPoint(ray.Origin, ray.Direction, root.Position, fraction,
		{ ch, workspace:FindFirstChild("SpaceFishing") })
	if not point then
		-- Nowhere to cast to: the lunge still goes, for the fun of it, and nothing is thrown.
		remote:FireServer("flourish")
		say("Cast off the edge of the map.", 2.5)
		return
	end
	task.spawn(castOut, point)
end

-- ---- picking an unfinished line back up ------------------------------------------------------
-- A line is on the chain from the cast until it is reeled in or its window passes -- whether or not
-- anybody is still holding the rod. Walk off, put the rod down, or leave, and it is still out there.
-- So when the rod is in hand again and nothing is going on, the chain is asked: a line still out is
-- picked up where it is -- waiting for its bite, or bitten and ready to reel.
resumeOpenLine = function()
	if state ~= "idle" or not holdingRod() or not Contracts.Fishing or Contracts.Fishing == "" then return end
	local line = readLine()
	if not line or not line.out or line.now > line.last or state ~= "idle" or not holdingRod() then return end
	gen += 1
	local mine = gen
	state = line.now >= line.bite and "bite" or "waiting"
	remote:FireServer("resume", state)
	say(state == "bite" and "Your line is still out, and something's biting! Click to reel it in!"
		or "Your line is still out. Waiting for a bite...")
	watch(mine)
end

task.spawn(function()
	-- Asked again whenever the rod comes back into the hand, and whenever the wallet signs in -- a
	-- rod put on before sign-in has nobody's line to look for yet.
	local had, signedAs = false, nil
	while true do
		local has = holdingRod()
		local address = player:GetAttribute("WalletAddress")
		if has and (not had or address ~= signedAs) then task.spawn(resumeOpenLine) end
		had, signedAs = has, address
		task.wait(1)
	end
end)

-- ---- the Everliving Fish's discovery --------------------------------------------------------
-- Catching it undiscovered gives the angler the right to claim the discovery -- the one token, their
-- name on it, and the species unlocked for everyone. Optional, and theirs: this asks, and their own
-- wallet claims it if they say so (contracts/Fishing.sol, claimDiscovery).
local offer = Instance.new("ScreenGui")
offer.Name = "EverlivingOffer"
offer.IgnoreGuiInset = true
offer.ResetOnSpawn = false
offer.Enabled = false
offer.DisplayOrder = 20
offer.Parent = gui

local OFFER_W, OFFER_H = 620, 420
local offerPanel, offerWindow = Theme.window(offer, UDim2.new(0, OFFER_W, 0, OFFER_H))
Theme.centre(offerWindow, OFFER_W, OFFER_H)

local offerTitle = Theme.label(offerPanel, "The Everliving Fish", { colour = Theme.c.accent, size = Theme.t.title,
	size2 = UDim2.new(1, -40, 0, 40), pos = UDim2.new(0, 20, 0, 14) })
local offerText = Instance.new("TextLabel")
offerText.Name = "Words"
offerText.BackgroundTransparency = 1
offerText.Position = UDim2.new(0, 20, 0, 62)
offerText.Size = UDim2.new(1, -40, 1, -140)
offerText.TextColor3 = Theme.c.ink
offerText.TextSize = Theme.t.small
offerText.TextWrapped = true
offerText.TextXAlignment = Enum.TextXAlignment.Left
offerText.TextYAlignment = Enum.TextYAlignment.Top
offerText.Text = ""
Theme.face(offerText)
offerText.Parent = offerPanel

local mintButton = Theme.button(offerPanel, "Mint it", Theme.c.good)
mintButton.Name = "Mint"
mintButton.Size = UDim2.new(0, 220, 0, 46)
mintButton.Position = UDim2.new(0, 20, 1, -64)
local laterButton = Theme.button(offerPanel, "Not now")
laterButton.Name = "NotNow"
laterButton.Size = UDim2.new(0, 220, 0, 46)
laterButton.Position = UDim2.new(1, -240, 1, -64)

local minting = false

local function offerFor(who)
	offerText.Text = ("Congratulations, you caught the Everliving Fish!\n\n"
		.. "This is a 1/1 NFT with no inherent value outside game progress, but it would serve as the immutable "
		.. "record that %s (%s) caught the 1 in 5555 odds Everliving Fish in pBlockz Home, and unlocked it for "
		.. "everyone. The chance to catch the Everliving Fish becomes slightly greater than to catch any other "
		.. "fish, henceforth.\n\n"
		.. "THIS IS COMPLETELY OPTIONAL. Should you choose not to mint, someone else will have to get lucky "
		.. "enough to catch it, and perform the unlock."):format(tostring(who.name), tostring(who.address))
	offer.Enabled = true
end

mintButton.MouseButton1Click:Connect(function()
	if minting then return end
	minting = true
	mintButton.Text = "Minting..."
	task.spawn(function()
		local answer = OwnWallet.request({ action = "write", to = Contracts.Fishing, fn = "claimDiscovery()", args = {},
			note = "Mint the Everliving Fish: the one token, and the unlock for everyone" })
		minting = false
		mintButton.Text = "Mint it"
		offer.Enabled = false
		if answer and answer.ok then
			remote:FireServer("claimed")
			say("The Everliving Fish is yours, and unlocked for everyone.", 5)
		else
			say(tostring(answer and answer.message or "Your wallet didn't answer.") .. " You can still mint it until someone else does.", 5)
		end
	end)
end)

laterButton.MouseButton1Click:Connect(function()
	offer.Enabled = false
	say("It's yours to mint until someone else does.", 4)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then letGo() end
end)
UserInputService.WindowFocusReleased:Connect(function()
	if windingSince then
		windingSince = nil
		remote:FireServer("uncharge")
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not holdingRod() or windowOpen() then return end
	if state == "idle" then
		-- Winding up: the server poses him (Fishing.server.luau), and letting go casts.
		windingSince = os.clock()
		remote:FireServer("charge")
	elseif state == "bite" then
		task.spawn(reelIn)
	elseif state == "waiting" or state == "casting" then
		say(state == "casting" and "Casting..." or "Nothing yet. Wait for a bite...", nil)
	end
end)

--- The camera goes to the fish you caught while it is held up in the air, then comes back.
local function showcase(holder, seconds)
	local camera = workspace.CurrentCamera
	if typeof(holder) ~= "Instance" or not camera then return end
	local wasType = camera.CameraType
	local startAt = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local ch = player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if not holder.Parent or t > (tonumber(seconds) or 3) or not root then
			conn:Disconnect()
			camera.CameraType = wasType
			return
		end
		local fishAt = holder:GetPivot().Position
		-- Between him and the fish, a little to one side and above: the fish is held side on to him
		-- (Fishing.server.luau), so this looks at its side with space behind it.
		local out = Vector3.new(fishAt.X - root.Position.X, 0, fishAt.Z - root.Position.Z)
		out = out.Magnitude > 1e-3 and out.Unit or Vector3.new(0, 0, -1)
		local across = out:Cross(Vector3.yAxis)
		local eye = fishAt - out * 10 + across * 2.5 + Vector3.new(0, 1.5, 0)
		local want = CFrame.lookAt(eye, fishAt)
		local u = math.clamp(t / 0.7, 0, 1)
		camera.CFrame = startAt:Lerp(want, u * u * (3 - 2 * u))
	end)
end

remote.OnClientEvent:Connect(function(kind, text, ...)
	if kind == "casting" then
		verdict = "casting"
	elseif kind == "refused" then
		verdict = "refused"
		gen += 1
		state = "idle"
		say(text == "landing" and "Your line is still coming in." or text == "out" and "Your line is still out."
			or "You can't cast there.", 2.5)
	elseif kind == "result" then
		if state == "landing" then gen += 1 state = "idle" end
		say(tostring(text), 4)
	elseif kind == "showcase" then
		task.spawn(showcase, text, select(1, ...))
	elseif kind == "discovery" then
		if type(text) == "table" and not minting then offerFor(text) end
	end
end)

cancelButton.MouseButton1Click:Connect(function()
	if state == "waiting" or state == "bite" or state == "casting" then
		finish("cancel", "You let the line go. Fish again to pick it back up.", 4)
	elseif state == "landing" then
		finish("cancel", "You let it go without looking.", 3)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.2)
		cancelButton.Visible = holdingRod() and (state == "waiting" or state == "bite" or state == "landing")
	end
end)

-- The rod put away or the body lost with a line out: the server takes the line in; this stops
-- watching it.
task.spawn(function()
	while true do
		task.wait(0.5)
		if state ~= "idle" and state ~= "reeling" and not holdingRod() then
			finish("cancel", "You put the rod away.", 2)
		end
		if windingSince and not holdingRod() then
			windingSince = nil
			remote:FireServer("uncharge")
		end
	end
end)

-- ---- every float out there -----------------------------------------------------------------

local THROW = 0.6          -- seconds from the rod to where it lands
local floats = {}          -- model -> { home = CFrame, start = clock }

local function track(model)
	-- Floats only: a line's model says whose it is. A caught fish held up in the same folder is the
	-- server's to move, and bobbing it here pinned it to where it came out of the water.
	if not model:IsA("Model") or floats[model] or model:GetAttribute("Angler") == nil then return end
	local primary = model.PrimaryPart or model:FindFirstChild("Float")
	if not primary then return end
	floats[model] = { home = primary.CFrame, start = os.clock() }
end

local folder = workspace:WaitForChild("SpaceFishing")
folder.ChildAdded:Connect(function(m) task.defer(track, m) end)
folder.ChildRemoved:Connect(function(m) floats[m] = nil end)
for _, m in ipairs(folder:GetChildren()) do track(m) end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for model, f in pairs(floats) do
		if not model.Parent then
			floats[model] = nil
		else
			local t = now - f.start
			local home = f.home.Position
			local at
			local from = model:GetAttribute("From")
			local throw = tonumber(model:GetAttribute("Throw")) or THROW
			if t < throw and typeof(from) == "Vector3" then
				-- Out from the rod in an arc, higher for a longer cast.
				local k = t / throw
				local rise = 3 + (from - home).Magnitude * 0.12
				at = from:Lerp(home, k) + Vector3.new(0, math.sin(k * math.pi) * rise, 0)
			else
				local s = model:GetAttribute("State")
				if s == "bite" then
					-- Yanked down and thrashing about, so it can be seen from across the town.
					at = home + Vector3.new(math.sin(now * 9) * 0.4, -1.2 + math.sin(now * 17) * 0.5, math.cos(now * 7) * 0.3)
				elseif s == "reel" then
					at = home + Vector3.new(0, math.sin(now * 20) * 0.1, 0)
				else
					at = home + Vector3.new(0, math.sin(now * 2.2) * 0.15, 0)
				end
			end
			model:PivotTo(CFrame.new(at))
			-- And it glows while something is on it. Only here, on this machine: it is how a bite looks.
			local float = model:FindFirstChild("FloatTop") or model.PrimaryPart
			local biting = model:GetAttribute("State") == "bite"
			if float and (float.Material == Enum.Material.Neon) ~= biting then
				float.Material = biting and Enum.Material.Neon or Enum.Material.SmoothPlastic
			end
		end
	end
end)

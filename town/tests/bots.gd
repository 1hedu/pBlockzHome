# Somebody to hit.
#
#   godot --path . -s res://tests/bots.gd
#
# add_player makes a Player with nobody behind it, so Health gives these hearts and they take
# hits like anyone else. One walks a circle, for a moving target; the rest stand in a row, one
# per weapon, each holding the thing it is named for -- Spoon keys off the accessory's Name, so
# a stick called "HEX Torch" burns like one. None of them swings back: Spoon takes input only
# through OnServerEvent, which only a client can fire.
extends SceneTree

const WEAPONS := ["Spoonie", "BFS 9000", "Red Candle", "Green Candle",
	"PLS Torch", "PLSX Torch", "HEX Torch", "PRVX Torch", "INC Torch"]

var world: PulseBlockzWorld
var t := 0.0
var made := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.confirm_place = false
	get_root().add_child(main)
	world = main.get_node("World")
	world.script_print.connect(func(n, txt): print("[%s] %s" % [n, txt]))
	world.script_error.connect(func(n, e): printerr("[%s] %s" % [n, e]))

func _process(delta: float) -> bool:
	t += delta
	# After the local player is in, or add_player queues them all as the one local join instead
	# of taking the headless path.
	if made or t < 6.0 or world.get_local_player_id() == 0:
		return false
	made = true
	world.add_player("Runner", 9000)
	for i in WEAPONS.size():
		world.add_player("Dummy%d" % (i + 1), 9001 + i)
	world.run_chunk("bots", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WEAPONS = { %s }

-- A weapon is an Accoutrement whose Name is in the list; Spoon looks for nothing else, so
-- a handle and the right name is a whole weapon as far as the fight is concerned.
local function arm(player, name)
	local ch = player.Character
	if not ch or ch:FindFirstChild(name) then return end
	local acc = Instance.new("Accessory")
	acc.Name = name
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 2.2, 0.4)
	handle.Parent = acc
	acc.Parent = ch
end

local function root(player)
	local ch = player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

-- Somewhere you will walk past, laid out relative to whoever is playing rather than at a
-- fixed spot: a row of dummies behind the scenery is a row nobody finds.
local me = Players:GetPlayers()[1]
local here = root(me) and root(me).Position or Vector3.new(0, 5, 0)

local ready = {}
task.spawn(function()
	while true do
		for _, p in ipairs(Players:GetPlayers()) do
			local r = root(p)
			if r and not ready[p] then
				local n = tonumber(p.Name:match("Dummy(%%d+)"))
				if n then
					arm(p, WEAPONS[n])
					r.CFrame = CFrame.new(here + Vector3.new(-8 + n * 2.2, 0, 10))
					ready[p] = true
					print(("bot %%s is holding a %%s"):format(p.Name, WEAPONS[n]))
				elseif p.Name == "Runner" then
					ready[p] = true
					print("bot Runner is walking a circle")
				end
			end
		end
		task.wait(1)
	end
end)

-- The circle. Moved rather than walked: a Humanoid pathing round a fountain is a second
-- thing that can be wrong when what is being tested is whether a cut lands on a body that
-- is not standing still.
local turned = 0
RunService.Heartbeat:Connect(function(dt)
	local runner
	for _, p in ipairs(Players:GetPlayers()) do if p.Name == "Runner" then runner = p end end
	local r = runner and root(runner)
	if not r then return end
	turned = turned + dt * 0.7
	r.CFrame = CFrame.new(here + Vector3.new(math.cos(turned) * 9, 0, math.sin(turned) * 9 + 6))
end)
""" % ", ".join(WEAPONS.map(func(w): return "\"%s\"" % w)))
	print("[bots] %d dummies and one runner" % WEAPONS.size())
	return false

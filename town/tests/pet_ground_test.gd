# A pet stands on the ground under the pet, not on the floor the player is standing on.
#
#   godot --headless --path . -s res://tests/pet_ground_test.gd
#
# Builds its own two floors four studs apart, well clear of the town so no town geometry is
# overhead or underfoot, and parks the player on the lower one with the pet's station over the
# upper one.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("pets and the ground under them")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, t): said.append(t))
	get_root().add_child(main)
	# Let players in as they join, with no intro (tests/Arrive.gd).
	Arrive.now(world)
	_run()

## Runs a chunk on the server and hands back every "N <name> <number>" line it printed.
func _read(body: String, wait := 0.8) -> Dictionary:
	said.clear()
	world.run_chunk("pet_ground", body)
	await create_timer(wait).timeout
	var out := {}
	for line in said:
		if line.begins_with("N "):
			var bits := line.substr(2).split(" ")
			if bits.size() >= 2:
				out[bits[0]] = float(bits[1])
	return out

# Shaped like a real pet: the driven part (PrimaryPart) sits above the lowest part of the model,
# and that gap is what `lift` accounts for. The part names are load-bearing -- Pets takes
# "Chassis" as the body, and the glide gait drives whatever matches "Wheel" off the body's frame.
const BUILD := '''
local ServerStorage = game:GetService("ServerStorage")
local made = Instance.new("Model")
made.Name = "TestPet"
local body = Instance.new("Part")
body.Name = "Chassis"
body.Size = Vector3.new(2, 1, 4)
body.Position = Vector3.new(0, 1, 0)
body.Anchored = true
body.Parent = made
for i = 1, 4 do
	local w = Instance.new("Part")
	w.Name = "Wheel" .. i
	w.Size = Vector3.new(0.3, 0.7, 0.7)
	w.Position = Vector3.new(i <= 2 and -0.9 or 0.9, 0.35, i % 2 == 0 and -1.2 or 1.2)
	w.Anchored = true
	w.Parent = made
end
made.PrimaryPart = body
made.Parent = ServerStorage
'''

func _run() -> void:
	await create_timer(4.0).timeout

	var set_up := await _read(BUILD + '''
local player = game:GetService("Players"):GetPlayers()[1]
local root = player.Character:FindFirstChild("HumanoidRootPart")
-- Clear of the town, so nothing of the town's is overhead or underfoot.
local at = root.Position + Vector3.new(0, 80, 0)

local pavement = Instance.new("Part")
pavement.Name = "TestPavement"
pavement.Anchored = true
pavement.Size = Vector3.new(30, 2, 30)
pavement.Position = Vector3.new(at.X, at.Y - 1, at.Z)
pavement.Parent = workspace

-- A kerb to its +X: the same floor, four studs up. This is the raised path.
local path = Instance.new("Part")
path.Name = "TestPath"
path.Anchored = true
path.Size = Vector3.new(30, 4, 30)
path.Position = Vector3.new(at.X + 17, at.Y + 2, at.Z)
path.Parent = workspace

-- Standing on the pavement, facing away from the path, so the spot a pet keeps station on --
-- which is behind you -- is over the path and you are not.
root.CFrame = CFrame.new(Vector3.new(at.X, at.Y + 3, at.Z),
	Vector3.new(at.X - 10, at.Y + 3, at.Z))
print("N floor " .. tostring(at.Y))
print("N top " .. tostring(at.Y + 4))
''')
	var floor: float = set_up.get("floor", NAN)
	var top: float = set_up.get("top", NAN)
	check(not is_nan(floor), "there is a floor to stand on: %.2f, with a path at %.2f" % [floor, top])

	world.run_chunk("pet_ground_car", '''
local Pets = require(game:GetService("ServerScriptService").Pets)
local player = game:GetService("Players"):GetPlayers()[1]
Pets.summon(player, game:GetService("ServerStorage").TestPet, "glide")
''')
	await create_timer(6.0).timeout
	var car := await _read('''
local player = game:GetService("Players"):GetPlayers()[1]
for _, m in ipairs(workspace:GetChildren()) do
	if m:IsA("Model") and m.Name:match("^Pet_") then
		local lo = math.huge
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then lo = math.min(lo, d.Position.Y - d.Size.Y / 2) end
		end
		print("N bottom " .. tostring(lo))
		print("N x " .. tostring(m.Chassis.Position.X - player.Character.HumanoidRootPart.Position.X))
	end
end
''')
	var bottom: float = car.get("bottom", NAN)
	check(car.has("x") and absf(car["x"]) > 2.0,
		"the car parks off to the side, over the path: %.1f studs along it" % car.get("x", 0.0))
	check(not is_nan(bottom) and bottom > top - 0.5,
		"and sits ON the path rather than inside it: its underside is at %.2f, the path's top at %.2f"
		% [bottom, top])
	check(not is_nan(bottom) and absf(bottom - top) < 0.6,
		"resting on it, not hovering over it: %.2f studs of daylight" % (bottom - top))
	check(not is_nan(bottom) and bottom > floor + 1.0,
		"and nowhere near the floor the PLAYER is standing on, which is where it used to go")

	world.run_chunk("pet_ground_pup", '''
local Pets = require(game:GetService("ServerScriptService").Pets)
local player = game:GetService("Players"):GetPlayers()[1]
Pets.dismiss(player)
Pets.summon(player, game:GetService("ServerStorage").TestPet, "walk")
''')
	await create_timer(6.0).timeout
	var pup := await _read('''
for _, m in ipairs(workspace:GetChildren()) do
	if m:IsA("Model") and m.Name:match("^Pet_") then
		local lo = math.huge
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then lo = math.min(lo, d.Position.Y - d.Size.Y / 2) end
		end
		print("N bottom " .. tostring(lo))
	end
end
''')
	var paws: float = pup.get("bottom", NAN)
	check(not is_nan(paws) and absf(paws - top) < 0.8,
		"the pup stands on the path too: paws at %.2f, path at %.2f" % [paws, top])

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

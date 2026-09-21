# Do the benches seat you?
#
#   godot --headless --path . -s res://tests/seat_test.gd
#
# A Roblox Seat takes whoever touches it: the Humanoid's SeatPart becomes the seat, the seat's
# Occupant becomes the Humanoid, and standing up clears both again.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
var world: PulseBlockzWorld
var t := 0.0
var phase := 0

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	# Nobody is watching the intro: let players in as they join.
	Arrive.now(world)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 6.0:
		phase = 1
		world.run_chunk("sit", """
local ok, bad = 0, 0
local function check(what, got, want)
	if got == want then ok += 1 else bad += 1 end
	print(("SEAT %-38s %-6s (wanted %s)%s"):format(what, tostring(got), tostring(want),
		got == want and "" or "   <-- WRONG"))
end

local map = workspace:FindFirstChild("Map")
local benches = { "BenchWest", "BenchEast", "BenchNorthWest", "BenchNorthEast" }
local seats = 0
for _, name in ipairs(benches) do
	for i = 1, 3 do
		local b = map and map:FindFirstChild(name .. i, true)
		if b and b.ClassName == "Seat" then seats += 1 end
	end
end
-- Three a bench, because a Seat takes one person.
check("every bench has three seats", seats, 12)

-- And they face across the bench rather than down it: the sitter is welded to the seat
-- without being turned, so the seat's own LookVector is where they end up looking. The west
-- pair should be looking east, the east pair west.
local west = map:FindFirstChild("BenchWest2", true)
local east = map:FindFirstChild("BenchEast2", true)
check("the west bench looks east", west and math.floor(west.CFrame.LookVector.X + 0.5), 1)
check("the east bench looks west", east and math.ceil(east.CFrame.LookVector.X - 0.5), -1)

task.spawn(function()
	local player = game:GetService("Players"):GetPlayers()[1]
	local ch = player.Character
	local hum = ch:FindFirstChildOfClass("Humanoid")
	local bench = map:FindFirstChild("BenchNorthWest2", true)
	-- Dropped onto it: a Seat takes whoever touches it.
	ch:PivotTo(CFrame.new(bench.Position + Vector3.new(0, 3.5, 0)))
	local sat = false
	for _ = 1, 200 do
		task.wait(0.05)
		if hum.SeatPart == bench then sat = true break end
	end
	check("sitting down puts you on the bench", sat, true)
	-- Facing the square, not along the plank. Read off the root part a moment later: the
	-- weld is what turns you, and asking on the frame it lands catches you mid-turn.
	task.wait(0.4)
	local root = ch:FindFirstChild("HumanoidRootPart")
	local look = root and root.CFrame.LookVector or Vector3.new()
	check("and you are turned to face the square", ("%.2f"):format(look.X), "1.00")
	check("and the bench knows who is on it", bench.Occupant == hum, true)
	hum.Sit = false
	task.wait(0.5)
	check("standing up clears the seat", bench.Occupant == nil, true)
	print(("SEAT done: %d right, %d wrong"):format(ok, bad))
end)
""")
		t = 0.0
	elif phase == 1 and t > 18.0:
		quit(0)
	return false

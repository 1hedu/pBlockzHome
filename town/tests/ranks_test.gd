# Token rank drives flame height: a published ranking reaches the world, and the five braziers
# come out evenly spaced with the lowest rank left exactly as the map authored it. The volumes
# behind a real ranking come off DexScreener and move hourly, so a fixed one is published here.
#
#   godot --headless --path . -s res://tests/ranks_test.gd
extends SceneTree
var world: PulseBlockzWorld
var t := 0.0
var phase := 0

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 6.0:
		phase = 1
		t = 0.0
		# Published the way the server publishes one. Rank 1 is busiest, 5 quietest.
		world.run_chunk("ranks", """
local rs = game:GetService("ReplicatedStorage")
local Ranks = require(rs:WaitForChild("Ranks"))
Ranks.node():SetAttribute("Ranks",
	'{"pulsex":1,"hex":2,"pulse":3,"provex":4,"inc":5}')
""")
	elif phase == 1 and t > 3.0:
		phase = 2
		t = 0.0
		world.run_chunk("look", """
local rs = game:GetService("ReplicatedStorage")
local Ranks = require(rs:WaitForChild("Ranks"))
local ok, bad = 0, 0
local function check(what, got, want)
	if got == want then ok += 1 else bad += 1 end
	print(("RANKS %-46s %-8s (wanted %s)%s"):format(what, tostring(got), tostring(want),
		got == want and "" or "   <-- WRONG"))
end

check("the ranking arrives", Ranks.of("pulsex"), 1)
check("and the bottom of it", Ranks.of("inc"), 5)
check("an unknown fire is bottom rank", Ranks.of("nonesuch"), 5)
check("the busiest is all the way up the ladder", Ranks.share(1), 1)
check("the quietest is not up it at all", Ranks.share(5), 0)

-- The flames. Every brazier's fire should now be a different height, evenly spaced, with the
-- lowest rank exactly what the map authored -- 0.5 to 0.9 seconds of lifetime.
local map = workspace:WaitForChild("Map", 30)
local lives = {}
for _, model in ipairs(map:GetDescendants()) do
	local key = model:GetAttribute("Flame")
	if key ~= nil then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("ParticleEmitter") and d.Name == "Flame" then
				lives[tostring(key)] = d.Lifetime.Max
				break
			end
		end
	end
end
local function about(a, b)
	return math.abs(a - b) < 0.02
end
check("the quietest fire is the one that was drawn", about(lives.inc or 0, 0.9), true)
check("the busiest is taller", (lives.pulsex or 0) > (lives.inc or 0), true)
-- Evenly spaced: four gaps, all the same, because that is what makes a rank readable.
local ladder = { lives.pulsex, lives.hex, lives.pulse, lives.provex, lives.inc }
local gaps = {}
for i = 1, 4 do
	gaps[i] = (ladder[i] or 0) - (ladder[i + 1] or 0)
end
local even = true
for i = 2, 4 do
	if not about(gaps[i], gaps[1]) then even = false end
end
check("and the rungs between are evenly spaced", even, true)

print(("RANKS done: %d right, %d wrong"):format(ok, bad))
""")
	elif phase == 2 and t > 3.0:
		quit(0)
	return false

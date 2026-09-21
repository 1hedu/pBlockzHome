# The candles: neon everywhere but the wick, two hearts off or on, and one use each.
#
#   node scripts/stage-preview.js redcandle,greencandle <stage dir>
#   godot --path . -s res://tests/candle_test.gd -- <stage dir>
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	stage = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in (dir.get_files() if dir else PackedStringArray()):
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	# Nobody here to click through the intro, so players are admitted on join.
	Arrive.now(world)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 6.0:
		phase = 1
		t = 0.0
		for key in ["redcandle", "greencandle"]:
			var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
			world.add_model("ReplicatedStorage", key,
				raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("candle", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local Health = require(game:GetService("ServerScriptService").Health)
local ok, bad = 0, 0
local function check(what, got, want)
	if got == want then ok += 1 else bad += 1 end
	print(("CANDLE %-40s %-6s (wanted %s)%s"):format(what, tostring(got), tostring(want),
		got == want and "" or "   <-- WRONG"))
end

local player = Players:GetPlayers()[1]
local ch = player.Character
local hum = ch:FindFirstChildOfClass("Humanoid")

-- The item itself: neon all the way through, and the flame is geometry rather than an
-- emitter, which is the whole point of asking for a shape.
local red = rs:FindFirstChild("Red Candle")
check("the red candle is published", red ~= nil, true)
if red then
	local neon, other, emitters = 0, 0, 0
	local dull = {}
	for _, d in ipairs(red:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			if d.Material == Enum.Material.Neon then neon += 1
			else other += 1 table.insert(dull, d.Name) end
		end
		if d:IsA("ParticleEmitter") then emitters += 1 end
	end
	-- The wick, and only the wick. This used to demand that every visible piece glow and
	-- that there be at least five of them, which was true of the candle as it was first
	-- built -- one body and four tongues, all Neon. The candle has been redrawn since: the
	-- tongues are three, each its own colour, and it has a wick, which is Slate because a
	-- wick that glows is not a wick. So the shape of the check changes with it rather than
	-- the number: everything lights except the wick.
	check("the only piece that does not glow is the wick", table.concat(dull, ","), "Wick")
	check("and the rest of it does", neon >= 4, true)
	check("the flame is a shape, not particles", emitters, 0)
end

-- Two hearts off, and two back on.
hum.Health = 6
check("full", hum.Health, 6)
Health.hit(player, nil, 4, 0)
check("the red candle takes two hearts", hum.Health, 2)
check("healing puts two back", Health.heal(player, nil, 4), true)
check("which is four half-hearts", hum.Health, 6)
check("and it will not overfill", Health.heal(player, nil, 4), false)
check("still three hearts", hum.Health, 6)

-- Mending does not care about duelling: a friend can pick you up whatever you set.
Health.setFights(player, false)
hum.Health = 2
check("healed while out of duelling", Health.heal(player, nil, 4), true)
check("back to three hearts", hum.Health, 6)
Health.setFights(player, true)

-- One use: the wardrobe is told, and stops offering it.
local spent = rs:FindFirstChild("ItemConsumed")
check("there is a way to say it is spent", spent ~= nil, true)

print(("CANDLE done: %d right, %d wrong"):format(ok, bad))
""")
	elif phase == 1 and t > 6.0:
		quit(0)
	return false

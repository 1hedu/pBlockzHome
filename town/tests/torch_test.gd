# The torches: one textured emitter per flame colour, and a burn that ticks in half-hearts.
#
#   node scripts/stage-preview.js plstorch,inctorch <stage dir>
#   godot --path . -s res://tests/torch_test.gd -- <stage dir>
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
	var w2 := FileAccess.open("user://preview/flame.png", FileAccess.WRITE)
	if w2:
		w2.store_buffer(FileAccess.get_file_as_bytes("res://../../../scripts/models/flame.png"))
		w2.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	# Nothing here watches the intro, so players are let in as they join (tests/Arrive.gd).
	Arrive.now(world)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 5.0:
		phase = 1
		t = 0.0
		for key in ["plstorch", "inctorch"]:
			var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
			world.add_model("ReplicatedStorage", key,
				raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("assets", """
local rs = game:GetService("ReplicatedStorage")
local place = rs:FindFirstChild("PlaceAssets") or Instance.new("Folder")
place.Name = "PlaceAssets"
place.Parent = rs
if not place:FindFirstChild("FlameSprite") then
	local v = Instance.new("StringValue")
	v.Name = "FlameSprite"
	v.Value = "user://preview/flame.png"
	v.Parent = place
end
""")
	elif phase == 1 and t > 3.0:
		phase = 2
		t = 0.0
		world.run_chunk("torch", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local Health = require(game:GetService("ServerScriptService").Health)
local ok, bad = 0, 0
local function check(what, got, want)
	if got == want then ok += 1 else bad += 1 end
	print(("TORCH %-38s %-6s (wanted %s)%s"):format(what, tostring(got), tostring(want),
		got == want and "" or "   <-- WRONG"))
end

local player = Players:GetPlayers()[1]
local torch = rs:FindFirstChild("PLS Torch"):Clone()
check("the item says which fire it burns", tostring(torch:GetAttribute("Flame")), "pulse")
torch.Parent = player.Character
task.wait(1.0)

-- Torch.server.luau should have turned the one authored emitter into one per colour, and
-- given every one of them the sprite.
local emitters, textured = 0, 0
for _, d in ipairs(torch:GetDescendants()) do
	if d:IsA("ParticleEmitter") and d.Name == "Flame" then
		emitters += 1
		if d.Texture ~= "" then textured += 1 end
	end
end
check("pulse is five colours, so five emitters", emitters, 5)
check("and every one has the sprite", textured, emitters)

-- The burn: a heart and a half over five seconds, in half-heart ticks, the first on contact.
local hum = player.Character:FindFirstChildOfClass("Humanoid")
check("full to start", hum.Health, 6)
-- Three half-hearts over four seconds: on contact, at two, and at four.
Health.burn(player, nil, 3, 4, "pulse")
task.wait(0.3)
check("half a heart on contact", hum.Health, 5)
check("and the body is alight", player.Character:FindFirstChild("OnFire") ~= nil, true)
task.wait(2.0)                                   -- past the second tick, at 2s
check("a second half-heart", hum.Health, 4)
task.wait(1.5)                                   -- not yet the third, which is at 4s
check("and the last one waits its turn", hum.Health, 4)
task.wait(1.0)                                   -- past 4s
check("a heart and a half, all told", hum.Health, 3)
task.wait(1.0)
check("and it stops there", hum.Health, 3)
check("the fire goes out", player.Character:FindFirstChild("OnFire") == nil, true)

-- Being lit again restarts rather than stacks.
Health.burn(player, nil, 3, 4, "inc")
task.wait(0.3)
Health.burn(player, nil, 3, 4, "inc")
task.wait(0.3)
check("relighting does not double the tick", hum.Health, 2)

print(("TORCH done: %d right, %d wrong"):format(ok, bad))
""")
	elif phase == 2 and t > 14.0:
		quit(0)
	return false

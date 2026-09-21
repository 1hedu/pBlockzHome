# Hearts, the mercy window, respawning and the void, checked in numbers; the heart meter itself
# is photographed, since a half-full heart is a question about pixels.
#
#   godot --path . -s res://tests/combat_test.gd -- <stage dir> <shots dir>
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
var world: PulseBlockzWorld
var stage := ""
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0]
	shots = args[1]
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
	DirAccess.make_dir_recursive_absolute(shots)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 5.0:
		phase = 1
		# The meter draws nothing without a HeartIcon in ReplicatedStorage.PlaceAssets.
		world.run_chunk("assets", """
local rs = game:GetService("ReplicatedStorage")
local place = rs:FindFirstChild("PlaceAssets") or Instance.new("Folder")
place.Name = "PlaceAssets"
place.Parent = rs
if not place:FindFirstChild("HeartIcon") then
	local v = Instance.new("StringValue")
	v.Name = "HeartIcon"
	v.Value = "user://preview/heart.png"
	v.Parent = place
end
""")
		t = 0.0
	elif phase == 1 and t > 3.0:
		phase = 2
		t = 0.0
		world.run_chunk("combat", """
local Health = require(game:GetService("ServerScriptService").Health)
local player = game:GetService("Players"):GetPlayers()[1]
local ok, bad = 0, 0
local function check(what, got, want)
	if got == want then ok += 1 else bad += 1 end
	print(("COMBAT %-34s %-6s (wanted %s)%s"):format(what, tostring(got), tostring(want),
		got == want and "" or "   <-- WRONG"))
end

local hum = player.Character:FindFirstChildOfClass("Humanoid")
check("three hearts to start", hum.MaxHealth, 6)
check("and all of them full", hum.Health, 6)

-- Spaced past the mercy window each time: blows inside it are refused on purpose, so a
-- test that lands three in one instant is testing the i-frames rather than the damage.
local MERCY = 0.4

-- A graze off the crude spoon.
Health.hit(player, nil, 1, 0)
check("half a heart off", hum.Health, 5)

-- And again straight away: refused, because that is what the mercy window is for.
Health.hit(player, nil, 1, 0)
check("a second blow inside the window", hum.Health, 5)

task.wait(MERCY)
-- A whole container, as BFS 9000 takes.
Health.hit(player, nil, 2, 0)
check("a full heart off", hum.Health, 3)

task.wait(MERCY)
-- Spent right down: the runtime is what respawns, so this is a death.
Health.hit(player, nil, 3, 0)
check("emptied", hum.Health, 0)

task.spawn(function()
	-- Players.RespawnTime is five seconds by default.
	local came = player.CharacterAdded:Wait()
	local h2 = came:WaitForChild("Humanoid", 10)
	task.wait(0.6)
	check("respawned with three hearts", h2.MaxHealth, 6)
	check("and full again", h2.Health, 6)

	-- Off the edge of the world.
	local root = came:WaitForChild("HumanoidRootPart", 5)
	root.CFrame = CFrame.new(0, -40, 0)
	local fell = false
	for _ = 1, 120 do
		task.wait(0.05)
		if h2.Health <= 0 then fell = true break end
	end
	check("the void kills rather than drops", fell, true)
	print(("COMBAT done: %d right, %d wrong"):format(ok, bad))
end)
""")
	elif phase == 2 and t > 2.0 and phase == 2:
		phase = 3
		get_root().get_texture().get_image().save_png(shots.path_join("hearts.png"))
		print("  -> hearts.png")
	elif phase == 3 and t > 22.0:
		quit(0)
	return false

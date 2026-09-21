# Where the pet car ends up with the wallet left running, so the wardrobe syncs as it does
# in the game and can take away a pet that is not owned and equipped.
#
#   godot --path . -s res://tests/car_where.gd -- <stage dir>
extends SceneTree
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
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 5.0:
		phase = 1
		var raw := FileAccess.get_file_as_string(stage.path_join("roma.json"))
		world.add_model("ReplicatedStorage", "roma",
			raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("where", """
local Pets = require(game:GetService("ServerScriptService").Pets)
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]

local tpl = rs:FindFirstChild("White Roma")
print("CAR template exists: " .. tostring(tpl ~= nil))
if tpl then
	for _, d in ipairs(tpl:GetDescendants()) do
		if d:IsA("BasePart") then
			print(("CAR  tpl %-8s size %s  mesh %s"):format(d.Name, tostring(d.Size), tostring(d.MeshId)))
		end
	end
end

task.spawn(function()
	while true do
		local ch = player.Character
		if ch and ch:FindFirstChild("HumanoidRootPart") and not Pets.has(player) then
			Pets.summon(player, tpl, "glide")
		end
		task.wait(1)
	end
end)

task.spawn(function()
	for i = 1, 10 do
		task.wait(1.5)
		local found
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and m.Name:match("^Pet_") then found = m break end
		end
		if not found then
			print("CAR  tick " .. i .. ": no Pet_ model in workspace at all")
		else
			local ch = player.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local n = 0
			for _, d in ipairs(found:GetDescendants()) do
				if d:IsA("BasePart") then n += 1 end
			end
			print(("CAR  tick %d: %s, %d parts, at %s, %.1f studs from you, transparency %s"):format(
				i, found.Name, n, tostring(found:GetPivot().Position),
				root and (found:GetPivot().Position - root.Position).Magnitude or -1,
				found.PrimaryPart and tostring(found.PrimaryPart.Transparency) or "?"))
		end
	end
	print("CAR done")
end)
""")
		t = 0.0
	elif phase == 1 and t > 17.0:
		quit(0)
	return false

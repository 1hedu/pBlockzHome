# How many times each swing sounds: the hachimonji is two strokes, the crude spoon's slash and
# thrust one each. Counted on the client, where the clips arrive.
#
#   godot --path . -s res://tests/swing_sfx.gd -- <stage dir>
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var phase := 0
var asked := false

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

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 5.0:
		phase = 1
		for key in ["crudespoon", "spoonie"]:
			var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
			world.add_model("ReplicatedStorage", key,
				raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_client_chunk("count", """
local rs = game:GetService("ReplicatedStorage")
-- Printed rather than tallied: _G is readonly here, and a line per event counts just as well.
rs:WaitForChild("CombatSfx").OnClientEvent:Connect(function(role)
	print("SWINGSFX " .. tostring(role))
end)
""")
		t = 0.0
	elif phase == 1 and t > 2.0:
		phase = 2
		t = 0.0
		world.run_chunk("swing", """
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local hum = player.Character:FindFirstChildOfClass("Humanoid")

-- Worn directly: the wardrobe is not what is being tested here.
local function wear(name)
	for _, d in ipairs(player.Character:GetChildren()) do
		if d:IsA("Accoutrement") then d:Destroy() end
	end
	local m = rs:FindFirstChild(name)
	if not m then print("SWING no model " .. name) return false end
	local copy = m:Clone()
	if copy:IsA("Accoutrement") then
		copy.Parent = player.Character
		hum:AddAccessory(copy)
		return true
	end
	-- A Model holding the accessory.
	for _, c in ipairs(copy:GetChildren()) do
		if c:IsA("Accoutrement") then
			c.Parent = player.Character
			hum:AddAccessory(c)
			return true
		end
	end
	print("SWING " .. name .. " is not an accessory: " .. copy.ClassName)
	return false
end

task.spawn(function()
	for _, want in ipairs({ { "BFS 9000", "master", 2 }, { "Spoonie", "sword1", 1 } }) do
		local name, role, expect = want[1], want[2], want[3]
		if wear(name) then
			task.wait(0.4)
			print("SWING ready " .. name)
			task.wait(1.8)
		end
		print(("SWING --- %s done, wanted %s x%d ---"):format(name, role, expect))
	end
end)
""")
	elif phase == 2 and t > 1.2 and not asked:
		asked = true
		# FireServer only exists on the client.
		world.run_client_chunk("swingnow", """
local rs = game:GetService("ReplicatedStorage")
task.spawn(function()
	for i = 1, 2 do
		rs.WeaponRemote:FireServer()
		task.wait(2.2)
	end
end)
""")
	elif phase == 2 and t > 9.0:
		phase = 3
		t = 0.0
	elif phase == 3 and t > 2.0:
		quit(0)
	return false

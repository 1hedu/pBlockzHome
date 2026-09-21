# A weapon just swapped to cannot swing until it is drawn; one already drawn swings at once.
#
#   node scripts/stage-preview.js spoonie,redcandle <stage dir>
#   godot --path . -s res://tests/draw_test.gd -- <stage dir>
extends SceneTree
const Verdict = preload("res://tests/Verdict.gd")
var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var phase := 0
var lines: Array[String] = []

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
	# Without this the title card holds the intro, Arrived never fires and no character is made.
	main.show_title = false
	world.script_print.connect(func(_n, line): lines.append(String(line)))
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 6.0:
		phase = 1
		t = 0.0
		for key in ["spoonie", "redcandle"]:
			var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
			world.add_model("ReplicatedStorage", key,
				raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("count", """
local rs = game:GetService("ReplicatedStorage")
local n = Instance.new("IntValue")
n.Name = "Swings"
n.Value = 0
n.Parent = rs
rs:WaitForChild("WeaponRemote").OnClientEvent:Connect(function() end)
""")
		world.run_client_chunk("listen", """
local rs = game:GetService("ReplicatedStorage")
local seen = Instance.new("StringValue")
seen.Name = "LastSwing"
seen.Value = ""
seen.Parent = rs
rs:WaitForChild("WeaponRemote").OnClientEvent:Connect(function(kind)
	seen.Value = tostring(kind)
end)
""")
	elif phase == 1 and t > 6.0:   # the intro fires Arrived about ten seconds in, and the character is made then
		phase = 2
		t = 0.0
		world.run_chunk("swap", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local player = Players:GetPlayers()[1]
local ch = player.Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local function hold(name)
	for _, d in ipairs(ch:GetChildren()) do
		if d:IsA("Accoutrement") then d:Destroy() end
	end
	task.wait()
	local copy = rs:FindFirstChild(name):Clone()
	copy.Parent = ch
	hum:AddAccessory(copy)
end
hold("BFS 9000")
""")
		world.run_client_chunk("ask1", """
task.wait(1.6)
local rs = game:GetService("ReplicatedStorage")
rs.LastSwing.Value = ""
rs.WeaponRemote:FireServer()
""")
	elif phase == 2 and t > 3.2:
		phase = 3
		t = 0.0
		world.run_client_chunk("read1", """
local rs = game:GetService("ReplicatedStorage")
print("DRAW after waiting, a drawn weapon swings: " .. rs.LastSwing.Value .. " (wanted hachimonji)")
""")
	elif phase == 3 and t > 1.5:
		phase = 4
		t = 0.0
		# Swap and swing at once, inside the draw cooldown.
		world.run_chunk("swap2", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local ch = Players:GetPlayers()[1].Character
local hum = ch:FindFirstChildOfClass("Humanoid")
for _, d in ipairs(ch:GetChildren()) do
	if d:IsA("Accoutrement") then d:Destroy() end
end
task.wait()
local copy = rs:FindFirstChild("Red Candle"):Clone()
copy.Parent = ch
hum:AddAccessory(copy)
""")
		world.run_client_chunk("ask2", """
task.wait(0.35)
local rs = game:GetService("ReplicatedStorage")
rs.LastSwing.Value = ""
rs.WeaponRemote:FireServer()
""")
	elif phase == 4 and t > 1.4:
		phase = 5
		t = 0.0
		world.run_client_chunk("read2", """
local rs = game:GetService("ReplicatedStorage")
print("DRAW a weapon just swapped to is refused: " .. rs.LastSwing.Value .. " (wanted drawing)")
""")
	elif phase == 5 and t > 1.6:
		phase = 6
		t = 0.0
		world.run_client_chunk("ask3", """
local rs = game:GetService("ReplicatedStorage")
rs.LastSwing.Value = ""
rs.WeaponRemote:FireServer()
""")
	elif phase == 6 and t > 1.2:
		phase = 7
		world.run_client_chunk("read3", """
local rs = game:GetService("ReplicatedStorage")
print("DRAW and swings once it is drawn: " .. rs.LastSwing.Value .. " (wanted candle)")
""")
	elif phase == 7 and t > 1.5:
		quit(Verdict.finish(lines, "DRAW"))
	return false

# Does a weapon land in the hand the first time it is put on?
#
#   node scripts/stage-preview.js crudespoon,plstorch <stage dir>
#   godot --path . -s res://tests/equip_probe.gd -- <stage dir>
#
# Six swaps, each printing the Handle's distance from the right arm. Attached, it rides under a
# stud from the arm; 2.5 is margin over that, so anything at or past it was parented and never
# found its attachment.
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
	main.get_node("Wallet").auto_start = false
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 6.0:
		phase = 1
		t = 0.0
		for key in ["crudespoon", "plstorch"]:
			var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
			world.add_model("ReplicatedStorage", key,
				raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("equip", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local player = Players:GetPlayers()[1]
local ch = player.Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local arm = ch:FindFirstChild("Right Arm")

local GAP = GAPSECS

local function wear(name)
	for _, d in ipairs(ch:GetChildren()) do
		if d:IsA("Accoutrement") then d:Destroy() end
	end
	if GAP > 0 then task.wait(GAP) end
	local copy = rs:FindFirstChild(name):Clone()
	copy.Parent = ch
	hum:AddAccessory(copy)
	return copy
end

for round = 1, 6 do
	local name = round % 2 == 1 and "Spoonie" or "PLS Torch"
	local acc = wear(name)
	task.wait(0.7)
	local handle = acc:FindFirstChild("Handle")
	local d = handle and (handle.Position - arm.Position).Magnitude or -1
	print(("EQUIP %d  %-12s handle %.2f studs from the hand%s"):format(
		round, name, d, d >= 0 and d < 2.5 and "" or "   <-- NOT IN HAND"))
	if d >= 2.5 then
		-- Does it come right on its own? If it does, something dropped a retry; if it never
		-- does, it latched onto the wrong thing and no amount of waiting will help.
		task.wait(2.5)
		local d2 = handle and (handle.Position - arm.Position).Magnitude or -1
		print(("EQUIP    ...after another 2.5s: %.2f  (%s)"):format(d2,
			d2 < 2.5 and "came right by itself" or "still adrift"))
	end
end
print("EQUIP done")
""")
	elif phase == 1 and t > 8.0:
		quit(0)
	return false

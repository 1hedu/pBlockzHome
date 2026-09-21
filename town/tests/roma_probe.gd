# What the car is actually doing, in numbers.
#
#   node scripts/stage-preview.js roma <stage dir>
#   godot --path . -s res://tests/roma_probe.gd -- <stage dir>
#
# A stud-long pet photographs as a speck, so the answers are printed as numbers instead:
# nose against travel, whether it is level, and where the wheels sit in the car's own frame.
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
	if phase == 0 and t > 4.0:
		phase = 1
		var raw := FileAccess.get_file_as_string(stage.path_join("roma.json"))
		raw = raw.replace(stage.replace("\\", "/") + "/", "user://preview/")
		world.add_model("ReplicatedStorage", "roma", raw)
		world.run_chunk("probe", """
local Pets = require(game:GetService("ServerScriptService").Pets)
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local ch = player.Character
ch:PivotTo(CFrame.new(-40, 4, 40))
task.wait(0.3)
local car = Pets.summon(player, rs["White Roma"], "glide")

-- As built, before anything drives it: the nose is -Z, so the front wheels should sit at
-- negative Z in the model's own frame and the wheels should be the lowest thing on it.
local at = car:GetPivot()
print("ROMA parts, in the car's own frame:")
for _, d in ipairs(car:GetDescendants()) do
	if d:IsA("BasePart") then
		local o = at:ToObjectSpace(d.CFrame).Position
		print(("  %-8s  x %6.3f  y %6.3f  z %6.3f   (z<0 is the nose)"):format(d.Name, o.X, o.Y, o.Z))
	end
end

task.spawn(function()
	local hum = ch:FindFirstChildOfClass("Humanoid")
	for i = 1, 90 do
		local a = i * 0.3
		hum:MoveTo(Vector3.new(-40 + math.cos(a) * 15, 4, 40 + math.sin(a) * 15))
		task.wait(0.2)
	end
end)

task.spawn(function()
	local was = car:GetPivot().Position
	task.wait(1.5)
	for i = 1, 8 do
		local cf = car:GetPivot()
		local went = cf.Position - was
		was = cf.Position
		local flat = Vector3.new(went.X, 0, went.Z)
		local look = cf.LookVector
		-- Nose against travel: 1 is driving forwards, -1 is driving in reverse, 0 is
		-- crabbing sideways, which is the thing a car cannot do.
		local agree = flat.Magnitude > 1e-3 and look:Dot(flat.Unit) or 0
		-- Level: Up should be straight up bar the lean, and the nose should not pitch.
		-- The wheels have to stay under the body. If the pivot is a part something here
		-- turns, the model reads that turn back as its own and rolls over; a positive
		-- offset here is that happening.
		local hi = -9
		for _, d in ipairs(car:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:match("^Wheel") then
				hi = math.max(hi, cf:ToObjectSpace(d.CFrame).Position.Y)
			end
		end
		print(("ROMA  nose.y %6.3f  up.y %6.3f  nose-vs-travel %6.3f  speed %5.2f  highest wheel vs body %6.3f"):format(
			look.Y, cf.UpVector.Y, agree, flat.Magnitude / 0.4, hi))
		task.wait(0.4)
	end
	print("ROMA done")
end)
""")
		t = 0.0
	elif phase == 1 and t > 9.0:
		quit(0)
	return false

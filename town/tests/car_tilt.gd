# How far over the pet car leans, in degrees, sampled while its rider circles.
#
#   godot --path . -s res://tests/car_tilt.gd -- <stage dir>
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
	if phase == 0 and t > 4.0:
		phase = 1
		var raw := FileAccess.get_file_as_string(stage.path_join("roma.json"))
		world.add_model("ReplicatedStorage", "roma",
			raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("tilt", """
local Pets = require(game:GetService("ServerScriptService").Pets)
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local ch = player.Character
ch:PivotTo(CFrame.new(-40, 4, 40))
task.wait(0.3)
local car = Pets.summon(player, rs["White Roma"], "glide")
-- The wardrobe takes away any pet you do not own and have equipped, so it has to be put
-- back the way the preview does it -- which is also the state the screenshot was taken in.
task.spawn(function()
	while true do
		if not Pets.has(player) then car = Pets.summon(player, rs["White Roma"], "glide") end
		task.wait(1)
	end
end)
task.spawn(function()
	local hum = ch:FindFirstChildOfClass("Humanoid")
	for i = 1, 200 do
		local a = i * 0.25
		hum:MoveTo(Vector3.new(-40 + math.cos(a) * 6, 4, 40 + math.sin(a) * 6))
		task.wait(0.18)
	end
end)
task.spawn(function()
	local worst = 0
	for i = 1, 24 do
		task.wait(0.25)
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and m.Name:match("^Pet_") then car = m break end
		end
		local cf = car:GetPivot()
		local root = ch:FindFirstChild("HumanoidRootPart")
		-- Roll is how far the car's own right-hand axis has come off level.
		local roll = math.deg(math.asin(math.clamp(cf.RightVector.Y, -1, 1)))
		local pitch = math.deg(math.asin(math.clamp(cf.LookVector.Y, -1, 1)))
		worst = math.max(worst, math.abs(roll))
		-- And how far each wheel's bottom is off the ground: two wheels up is two of these
		-- much higher than the other two.
		local low = {}
		for _, d in ipairs(car:GetDescendants()) do
			if d:IsA("BasePart") and d.Name:match("^Wheel") then
				table.insert(low, ("%s %.3f"):format(d.Name:sub(6), d.Position.Y - d.Size.Y / 2))
			end
		end
		table.sort(low)
		-- How far the front wheels are turned off straight ahead. Pinned at the lock every
		-- sample means the steering is saturated and the car is permanently cranked over.
		local lock = 0
		local fl = car:FindFirstChild("WheelFL")
		if fl then
			local _, y = cf:ToObjectSpace(fl.CFrame):ToEulerAnglesYXZ()
			lock = math.deg(y)
		end
		print(("TILT roll %6.2f  pitch %6.2f  front wheels %6.2f deg off straight  car.y %5.2f"):format(
			roll, pitch, lock, cf.Position.Y))
	end
	print(("TILT worst roll %.2f deg"):format(worst))
end)
""")
		t = 0.0
	elif phase == 1 and t > 9.0:
		quit(0)
	return false

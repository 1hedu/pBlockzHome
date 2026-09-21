# How the pet car's own parts lie, not how its model pivot says they lie.
#
#   godot --path . -s res://tests/car_roll.gd -- <stage dir>
#
# GetPivot hands back the CFrame PivotTo was given, so it says nothing about how the parts
# themselves ended up: measure the body part, never the model pivot.
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
		world.run_chunk("roll", """
local Pets = require(game:GetService("ServerScriptService").Pets)
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local ch = player.Character
ch:PivotTo(CFrame.new(-40, 4, 40))
task.wait(0.3)
Pets.summon(player, rs["White Roma"], "glide")
task.spawn(function()
	while true do
		if not Pets.has(player) then Pets.summon(player, rs["White Roma"], "glide") end
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
	for i = 1, 12 do
		task.wait(0.5)
		local car
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and m.Name:match("^Pet_") then car = m break end
		end
		if not car then print("ROLL no car") else
			local body = car:FindFirstChild("Chassis")
			local pivot = car:GetPivot()
			local function tilt(cf)
				return math.deg(math.asin(math.clamp(cf.RightVector.Y, -1, 1))),
				       math.deg(math.asin(math.clamp(cf.LookVector.Y, -1, 1)))
			end
			-- Where each wheel sits relative to the body it belongs to. The catalogue puts
			-- them at x +-0.262, y -0.109, z +-0.385 off the body's middle; anything else is
			-- the per-frame placement drifting them out of their arches.
			local out = {}
			for _, d in ipairs(car:GetDescendants()) do
				if d:IsA("BasePart") and d.Name:match("^Wheel") then
					local o = body.CFrame:ToObjectSpace(d.CFrame).Position
					table.insert(out, ("%s %+.3f %+.3f %+.3f"):format(d.Name:sub(6), o.X, o.Y, o.Z))
				end
			end
			table.sort(out)
			-- UP, not roll. asin(RightVector.Y) is zero both for a level car and for one
			-- turned clean over, so every "level" reading so far was blind to the one
			-- thing being asked. UpVector.Y is +1 upright and -1 on its roof.
			print(("ROLL body up.y %+.3f  right.y %+.3f  look.y %+.3f  %s | wheels: %s"):format(
				body.CFrame.UpVector.Y, body.CFrame.RightVector.Y, body.CFrame.LookVector.Y,
				body.CFrame.UpVector.Y > 0.5 and "UPRIGHT" or (body.CFrame.UpVector.Y < -0.5 and "ON ITS ROOF" or "ON ITS SIDE"),
				table.concat(out, "  ")))
		end
	end
	print("ROLL done")
end)
""")
		t = 0.0
	elif phase == 1 and t > 8.0:
		quit(0)
	return false

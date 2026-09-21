# The car driving, in four frames.
#
#   godot --path . -s res://tests/roma_drive.gd -- <stage dir> <shots dir>
#
# The character walks a tight ring and the pet keeps station behind them, so the car is always
# steering. A gait in one still is a guess. Nothing asserts: the four frames pass if the car is
# coming round -- front wheels turned, body leaning out of the bend, wheels rolling with the
# ground they cover.
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var shots := ""
var t := 0.0
var phase := 0
var shot := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0]
	shots = args[1] if args.size() > 1 else stage
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
	DirAccess.make_dir_recursive_absolute(shots)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		var raw := FileAccess.get_file_as_string(stage.path_join("roma.json"))
		world.add_model("ReplicatedStorage", "roma",
			raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("drive", """
local Pets = require(game:GetService("ServerScriptService").Pets)
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local ch = player.Character
ch:PivotTo(CFrame.new(-36, 4, 40))
task.wait(0.3)
Pets.summon(player, rs["White Roma"], "glide")
task.spawn(function()
	local hum = ch:FindFirstChildOfClass("Humanoid")
	-- A ring of four studs, walked slowly, so the car is always somewhere on it and always
	-- turning: a straight line would prove nothing that a still cannot fake.
	for i = 1, 200 do
		if not hum then break end
		local a = i * 0.25
		hum:MoveTo(Vector3.new(-40 + math.cos(a) * 4, 4, 40 + math.sin(a) * 4))
		task.wait(0.18)
	end
end)
print("DRIVE going")
""")
		# A camera riding with the car: a fixed vantage puts a stud-long pet forty pixels across.
		world.run_client_chunk("cam", """
local RunService = game:GetService("RunService")
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 24
RunService.RenderStepped:Connect(function()
	local car
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m.Name:match("^Pet_") then car = m break end
	end
	if not car or not car.PrimaryPart then return end
	local at = car:GetPivot().Position
	-- Behind and above its left shoulder. Far enough out that the lens is not lying: at a
	-- stud and a half from a stud-long car the near end is twice the size of the far one
	-- and a windscreen photographs as a floor pan.
	cam.CFrame = CFrame.new(at + Vector3.new(0, 0.05, 3.2), at)
end)
""")
		t = 0.0
	elif phase == 1 and t > 1.3:
		shot += 1
		get_root().get_texture().get_image().save_png(shots.path_join("roma-drive-%d.png" % shot))
		print("  -> roma-drive-%d.png" % shot)
		t = 0.0
		if shot == 4:
			quit(0)
	return false

# A static car and a driven car in one frame, from one level camera.
#
#   godot --path . -s res://tests/both_cars.gd -- <stage dir> <shots dir>
#
# Same lens, light and instant, side by side: whatever differs between them is the pet loop.
extends SceneTree
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
	DirAccess.make_dir_recursive_absolute(shots)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 5.0:
		phase = 1
		var raw := FileAccess.get_file_as_string(stage.path_join("roma.json"))
		world.add_model("ReplicatedStorage", "roma",
			raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("both", """
local Pets = require(game:GetService("ServerScriptService").Pets)
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local ch = player.Character

-- The driven one. Kept walking so the gait is actually running.
ch:PivotTo(CFrame.new(-44, 4, 40))
task.wait(0.3)
Pets.summon(player, rs["White Roma"], "glide")
task.spawn(function()
	local hum = ch:FindFirstChildOfClass("Humanoid")
	for i = 1, 300 do
		hum:MoveTo(Vector3.new(-44 + math.sin(i * 0.3) * 2, 4, 40))
		task.wait(0.2)
	end
end)

-- The static one, two studs to the side, placed once and never touched again.
local m = rs:FindFirstChild("White Roma"):Clone()
m.Name = "Static"
local first
for _, d in ipairs(m:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
		if not first then first = d end
		if not m.PrimaryPart and not d.Name:match("^Wheel") then m.PrimaryPart = d end
	end
end
if not m.PrimaryPart then m.PrimaryPart = first end
m.Parent = workspace
m:PivotTo(CFrame.new(Vector3.new(-40, 1.05, 40), Vector3.new(-39, 1.05, 40)))

-- A third: placed once like the static one, then driven by hand with exactly the two writes
-- the glide gait makes -- body frame, then wheels off that frame -- and nothing else. If
-- this one goes over and the static one does not, those two lines are the whole bug.
local h = rs:FindFirstChild("White Roma"):Clone()
h.Name = "Hand"
local hf
for _, d in ipairs(h:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = true
		d.CanCollide = false
		if not hf then hf = d end
		if not h.PrimaryPart and not d.Name:match("^Wheel") then h.PrimaryPart = d end
	end
end
if not h.PrimaryPart then h.PrimaryPart = hf end
h.Parent = workspace
h:PivotTo(CFrame.new(Vector3.new(-36, 1.05, 40), Vector3.new(-35, 1.05, 40)))
local hbody = h:FindFirstChild("Chassis")
local hrest = {}
for _, d in ipairs(h:GetDescendants()) do
	if d:IsA("BasePart") and d.Name:match("^Wheel") then
		table.insert(hrest, { part = d, rest = hbody.CFrame:ToObjectSpace(d.CFrame) })
	end
end
task.spawn(function()
	local spin = 0
	while true do
		local frame = CFrame.new(Vector3.new(-36, 1.05, 40), Vector3.new(-35, 1.05, 40))
		hbody.CFrame = frame
		spin -= 0.06
		local rolling = CFrame.Angles(spin, 0, 0)
		for _, w in ipairs(hrest) do w.part.CFrame = frame * w.rest * rolling end
		task.wait()
	end
end)
print("BOTH placed -- static -40, hand-driven -36, gait-driven near -44")
""")
		t = 0.0
	elif phase == 1 and t > 3.0:
		world.run_client_chunk("cam", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 26
-- Level with both of them, far enough back that neither is distorted.
cam.CFrame = CFrame.new(Vector3.new(-40, 1.15, 54), Vector3.new(-40, 1.05, 40))
""")
		phase = 2
		t = 0.0
	elif phase == 2 and t > 2.0:
		get_root().get_texture().get_image().save_png(shots.path_join("both-cars.png"))
		print("  -> both-cars.png")
		quit(0)
	return false

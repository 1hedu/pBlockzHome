# One elevation shot of the Pup at two scales beside the car and the character, for comparison.
#
#   godot --path . -s res://tests/pup_size.gd -- <stage dir> <shots dir>
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var shots := ""
var t := 0.0
var phase := 0

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
		for key in ["roma", "pup"]:
			var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
			world.add_model("ReplicatedStorage", key,
				raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("place", """
local rs = game:GetService("ReplicatedStorage")
local ch = game:GetService("Players"):GetPlayers()[1].Character
-- Standing in the row, for scale, and stopped so nothing drags the scene about.
ch:PivotTo(CFrame.new(Vector3.new(-46, 3.9, 40), Vector3.new(-46, 3.9, 41)))
local hum = ch:FindFirstChildOfClass("Humanoid")
if hum then hum:MoveTo(Vector3.new(-46, 4, 40)) end

local function put(name, at, k)
	local m = rs:FindFirstChild(name):Clone()
	m.Name = "Look_" .. tostring(at.X)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			if not m.PrimaryPart then m.PrimaryPart = d end
		end
	end
	m.Parent = workspace
	m:PivotTo(CFrame.new(at, at + Vector3.new(1, 0, 0)))
	if k ~= 1 then
		-- Scaled about its own pivot: every part's size and its offset from the middle.
		local mid = m:GetPivot()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				local o = mid:ToObjectSpace(d.CFrame)
				d.Size = d.Size * k
				d.CFrame = mid * CFrame.new(o.Position * k) * (o - o.Position)
			end
		end
	end
	return m
end

-- The dog as it was, as it is now, and the car it was cut to match.
-- All on one line across the view, so none of them is flattered by being nearer.
put("Pup", Vector3.new(-43.4, 3.05, 40), 1.25)     -- 1.95, the one that was too big
put("Pup", Vector3.new(-41.4, 3.05, 40), 1)        -- 1.56, the new one
put("White Roma", Vector3.new(-39.4, 3.1, 40), 1)
print("PUPS placed")
""")
		world.run_client_chunk("cam", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
-- Far enough back that a five-stud character is not the whole frame: at this distance the
-- view is about twelve studs tall, so everything in the row fits with room to spare.
cam.FieldOfView = 32
cam.CFrame = CFrame.new(Vector3.new(-42.7, 5.0, 62), Vector3.new(-42.7, 3.5, 40))
""")
		t = 0.0
	elif phase == 1 and t > 2.5:
		get_root().get_texture().get_image().save_png(shots.path_join("pup-size.png"))
		print("  -> pup-size.png")
		quit(0)
	return false

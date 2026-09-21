# One anchored car at a fixed pivot, one shot per run: static-wallet.png with the Wallet
# auto-starting and static-nowallet.png with it off. The wallet shot is the one to check for a
# car on its side; roll and pitch are printed, nothing is asserted.
#
#   godot --path . -s res://tests/static_car.gd -- <stage dir> <shots dir> [nowallet]
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var shots := ""
var tag := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0]
	shots = args[1]
	tag = args[2] if args.size() > 2 else "wallet"
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in (dir.get_files() if dir else PackedStringArray()):
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	if tag == "nowallet":
		main.get_node("Wallet").auto_start = false
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(shots)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 6.0:
		phase = 1
		var raw := FileAccess.get_file_as_string(stage.path_join("roma.json"))
		world.add_model("ReplicatedStorage", "roma",
			raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("static", """
local rs = game:GetService("ReplicatedStorage")
local ch = game:GetService("Players"):GetPlayers()[1].Character
ch:PivotTo(CFrame.new(-40, 4, 70))
local hum = ch:FindFirstChildOfClass("Humanoid")
if hum then hum:MoveTo(Vector3.new(-40, 4, 70)) end
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
m:PivotTo(CFrame.new(Vector3.new(-40, 3.2, 40), Vector3.new(-39, 3.2, 40)))
local body = m:FindFirstChild("Chassis")
print(("STATIC body roll %.2f deg, pitch %.2f deg"):format(
	math.deg(math.asin(math.clamp(body.CFrame.RightVector.Y, -1, 1))),
	math.deg(math.asin(math.clamp(body.CFrame.LookVector.Y, -1, 1)))))
""")
		world.run_client_chunk("cam", """
local at = Vector3.new(-40, 3.2, 40)
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 16
cam.CFrame = CFrame.new(at + Vector3.new(0, 0, 6), at)
""")
		t = 0.0
	elif phase == 1 and t > 2.5:
		get_root().get_texture().get_image().save_png(shots.path_join("static-%s.png" % tag))
		print("  -> static-%s.png" % tag)
		quit(0)
	return false

# The candle in hand, and its swing.
#
#   godot --path . -s res://tests/candle_look.gd -- <stage dir> <shots dir>
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
	DirAccess.make_dir_recursive_absolute(shots)
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
		for key in ["redcandle", "greencandle", "hextorch"]:
			var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
			world.add_model("ReplicatedStorage", key,
				raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("hold", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local player = Players:GetPlayers()[1]
local ch = player.Character
local hum = ch:FindFirstChildOfClass("Humanoid")
ch:PivotTo(CFrame.new(0, 4, 20))
local copy = rs:FindFirstChild("HEX Torch"):Clone()
copy.Parent = ch
hum:AddAccessory(copy)
""")
		world.run_client_chunk("cam", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 42
local at = Vector3.new(0, 3.2, 17.5)
cam.CFrame = CFrame.new(at + Vector3.new(13, 4.5, 12), at)
""")
	elif phase == 1 and t > 3.0:
		phase = 2
		t = 0.0
		get_root().get_texture().get_image().save_png(shots.path_join("candle-hold.png"))
		print("  -> candle-hold.png")
		# Mid-swing. Fired from the client: FireServer is the client's end of a RemoteEvent.
		world.run_client_chunk("swing", """
local rs = game:GetService("ReplicatedStorage")
rs:WaitForChild("WeaponRemote"):FireServer()
""")
	elif phase == 2 and t > 0.32:
		phase = 3
		get_root().get_texture().get_image().save_png(shots.path_join("candle-swing.png"))
		print("  -> candle-swing.png")
	elif phase == 3 and t > 3.0:
		quit(0)
	return false

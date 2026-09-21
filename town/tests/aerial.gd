# A photograph of the town from above: where the buildings are, where the paths run, and
# whether a path reaches the door it was drawn for. tests/shoot.gd is the other camera: an item
# worn by a character, which it needs staged first.
#
#   godot --path . -s res://tests/aerial.gd -- <shots dir> [height] [tilt]
#
# Windowed: the headless renderer is a dummy and draws nothing.
extends SceneTree

var world: PulseBlockzWorld
var shots := ""
var height := 150.0
var tilt := 0.0
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "."
	height = float(args[1]) if args.size() > 1 else 150.0
	tilt = float(args[2]) if args.size() > 2 else 0.0
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false      # the layout does not need the chain
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		world.run_client_chunk("aerial", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
if gui then for _, s in ipairs(gui:GetChildren()) do if s:IsA("ScreenGui") then s.Enabled = false end end end
for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA("BillboardGui") then d.Enabled = false end
end
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
-- Straight down is unreadable -- every building is its own roof and nothing has a side --
-- so the lens leans back by `tilt` degrees and looks at the middle of the square.
local h, k = %f, math.rad(%f)
cam.CFrame = CFrame.new(Vector3.new(0, h * math.cos(k), h * math.sin(k)), Vector3.new(0, 0, 0))
print(("AERIAL up %%.0f"):format(h))
""" % [height, tilt])
	elif phase == 1 and t > 6.0:
		var img := get_root().get_texture().get_image()
		var file: String = shots.path_join("town.png")
		img.save_png(file)
		print("wrote ", file)
		quit(0)
		return true
	return false

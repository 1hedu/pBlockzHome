# Unions photographed: a decal on a plate with a hole subtracted through it, and a two-ball
# union at SmoothingAngle 0 beside the same at 45. Windowed -- headless draws nothing.
#
#   godot --path . -s res://tests/union_shot.gd -- <shots dir>
extends SceneTree

var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 8.0:
		phase = 1
		world.run_chunk("place", """
local function block(size, at, color, shape)
	local p = Instance.new("Part")
	p.Size = size; p.CFrame = CFrame.new(at); p.Anchored = true
	if color then p.Color = color end
	if shape then p.Shape = shape end
	p.Parent = workspace
	return p
end
block(Vector3.new(40, 1, 16), Vector3.new(0, 199, 0), Color3.fromRGB(60, 60, 70))
local plate = block(Vector3.new(6, 6, 1), Vector3.new(-9, 203.5, 0), Color3.new(1, 1, 1))
local drill = block(Vector3.new(1.4, 2.4, 2.4), Vector3.new(-9, 203.5, 0), nil, Enum.PartType.Cylinder)
drill.CFrame = CFrame.new(-9, 203.5, 0) * CFrame.Angles(0, math.rad(90), 0)
local holed = plate:SubtractAsync({ drill })
plate:Destroy(); drill:Destroy()
holed.Parent = workspace
local d = Instance.new("Decal")
d.Face = Enum.NormalId.Back
d.ColorMapContent = Content.fromUri("res://splash.png")
d.Parent = holed
for i, angle in ipairs({ 0, 45 }) do
	local x = (i - 1) * 9
	local red = block(Vector3.new(4, 4, 4), Vector3.new(x - 0.8, 202, 0), Color3.new(0.9, 0.15, 0.15), Enum.PartType.Ball)
	local blue = block(Vector3.new(4, 4, 4), Vector3.new(x + 0.8, 202, 0), Color3.new(0.15, 0.3, 0.9), Enum.PartType.Ball)
	local u = red:UnionAsync({ blue })
	red:Destroy(); blue:Destroy()
	u.SmoothingAngle = angle
	u.Parent = workspace
end
""")
		world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(Vector3.new(-1, 206, 16), Vector3.new(-1, 202.5, 0))
cam.FieldOfView = 55
""")
	elif phase == 1 and t > 13.0:
		phase = 2
		var file := shots.path_join("unions.png")
		get_root().get_texture().get_image().save_png(file)
		print("  -> ", file)
		quit(0)
	return false

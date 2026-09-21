# A photograph of the Content maps drawn: a PBR decal beside a plain one, and a part with an
# emissive mask (stripes drawn into an EditableImage) beside the same part without. Windowed,
# because the headless renderer is a dummy that draws nothing.
#
#   godot --path . -s res://tests/maps_shot.gd -- <shots dir>
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
local AssetService = game:GetService("AssetService")
local function block(name, size, at, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Anchored = true
	p.CFrame = CFrame.new(at)
	p.Parent = workspace
	return p
end
local floor = block("Floor", Vector3.new(40, 1, 20), Vector3.new(0, 199, 0), Color3.fromRGB(60, 60, 70))

local plainWall = block("PlainWall", Vector3.new(6, 6, 1), Vector3.new(-10, 203, 0), Color3.new(1, 1, 1))
local plain = Instance.new("Decal")
plain.Face = Enum.NormalId.Back
plain.ColorMapContent = Content.fromUri("res://panel-screener.png")
plain.Parent = plainWall

local pbrWall = block("PbrWall", Vector3.new(6, 6, 1), Vector3.new(-3, 203, 0), Color3.new(1, 1, 1))
local pbr = Instance.new("Decal")
pbr.Face = Enum.NormalId.Back
pbr.ColorMapContent = Content.fromUri("res://panel-screener.png")
pbr.RoughnessMapContent = Content.fromUri("res://sky/MoonEarth_SkyboxUp.png")
pbr.MetalnessMapContent = Content.fromUri("res://sky/MoonEarth_SkyboxUp.png")
pbr.Parent = pbrWall

local stripes = AssetService:CreateEditableImage({ Size = Vector2.new(64, 64) })
for y = 0, 63, 16 do
	stripes:DrawRectangle(Vector2.new(0, y), Vector2.new(64, 8), Color3.new(1, 1, 1), 0, Enum.ImageCombineType.Overwrite)
end
local noGlow = block("NoGlow", Vector3.new(4, 4, 4), Vector3.new(4, 202, 0), Color3.fromRGB(40, 90, 200))
Instance.new("SurfaceAppearance").Parent = noGlow
local glow = block("Glow", Vector3.new(4, 4, 4), Vector3.new(10, 202, 0), Color3.fromRGB(40, 90, 200))
local sa = Instance.new("SurfaceAppearance")
sa.EmissiveMaskContent = Content.fromObject(stripes)
sa.EmissiveStrength = 2
sa.EmissiveTint = Color3.new(1, 0.8, 0.4)
sa.Parent = glow
""")
		world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(Vector3.new(0, 205, 22), Vector3.new(0, 202, 0))
cam.FieldOfView = 50
""")
	elif phase == 1 and t > 12.0:
		phase = 2
		var file := shots.path_join("maps.png")
		get_root().get_texture().get_image().save_png(file)
		print("  -> ", file)
		quit(0)
	return false

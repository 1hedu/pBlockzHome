# Photographs the six-faced sky. Not headless: the dummy renderer builds the cubemap but draws
# nothing to look at.
#
#   godot --path . -s res://tests/sky_shot.gd -- <shots dir>
extends SceneTree
var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://shots/sky")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(shots)
	print("== sky")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		world.run_chunk("sky", """
local Lighting = game:GetService("Lighting")
for _, k in ipairs(Lighting:GetChildren()) do
	if k:IsA("Sky") or k:IsA("Atmosphere") then k:Destroy() end
end
local s = Instance.new("Sky")
s.Name = "MoonEarthSky"
s.CelestialBodiesShown = false
s.StarCount = 0
s.SkyboxRt = "res://sky/MoonEarth_SkyboxRt.png"
s.SkyboxLf = "res://sky/MoonEarth_SkyboxLf.png"
s.SkyboxUp = "res://sky/MoonEarth_SkyboxUp.png"
s.SkyboxDn = "res://sky/MoonEarth_SkyboxDn.png"
s.SkyboxBk = "res://sky/MoonEarth_SkyboxBk.png"
s.SkyboxFt = "res://sky/MoonEarth_SkyboxFt.png"
s.Parent = Lighting
print("SKY six faces set")
""")
		t = 0.0
	elif phase == 1 and t > 4.0:
		phase = 2
		get_root().get_texture().get_image().save_png(shots.path_join("sky.png"))
		print("  -> %s" % shots.path_join("sky.png"))
		quit(0)
	return false

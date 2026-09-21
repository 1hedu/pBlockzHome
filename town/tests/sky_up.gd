# Photographs the seam where Up meets the sides, once per quarter turn of the top face. The
# four sides map across as they are; Roblox's SkyboxUp needs a quarter turn anticlockwise and
# SkyboxDn its mirror, or the seam shows -- pulseblockz_world.cpp, apply_skybox.
#
#   godot --path . -s res://tests/sky_up.gd -- <shots dir>
extends SceneTree

const FACES := ["Rt", "Lf", "Up", "Dn", "Bk", "Ft"]

var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var turns := 0
var phase := 0

func _initialize() -> void:
	shots = OS.get_cmdline_user_args()[0]
	# The cubemap rebuilds only when the set of image ids changes, so each round gets its own
	# directory; a reused path photographs round 0 four times.
	for i in 4:
		DirAccess.make_dir_recursive_absolute("user://sky%d" % i)
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false     # the local files, not the chain's copies
	root.add_child(main)

## Writes the six faces to user://sky<n>/, the top turned n quarters clockwise.
func _stage(n: int) -> void:
	for face in FACES:
		var img := Image.load_from_file("res://sky/MoonEarth_Skybox%s.png" % face)
		if img == null:
			printerr("no face ", face)
			continue
		if face == "Up":
			for i in n:
				img.rotate_90(CLOCKWISE)
		img.save_png("user://sky%d/%s.png" % [n, face])

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 3.0:
		_stage(turns)
		# Sky.server.luau builds its Sky once at startup, so setting PlaceAssets alone reaches
		# nothing: the properties go on the Sky as well.
		world.run_chunk("faces%d" % turns, """
local Lighting = game:GetService("Lighting")
local rs = game:GetService("ReplicatedStorage")
local place = rs:FindFirstChild("PlaceAssets") or Instance.new("Folder")
place.Name = "PlaceAssets"
place.Parent = rs
local sky
for _, e in ipairs(Lighting:GetChildren()) do
	if e:IsA("Sky") then sky = e break end
end
if not sky then
	sky = Instance.new("Sky")
	sky.Name = "MoonEarthSky"
	sky.CelestialBodiesShown = false
	sky.StarCount = 0
	sky.Parent = Lighting
end
for _, face in ipairs({"Rt", "Lf", "Up", "Dn", "Bk", "Ft"}) do
	local path = "user://sky%d/" .. face .. ".png"
	local name = "Skybox" .. face
	local v = place:FindFirstChild(name)
	if not v then v = Instance.new("StringValue") v.Name = name v.Parent = place end
	v.Value = path
	sky[name] = path
end
print("SKYUP set to round %d")
""" % [turns, turns])
		# A camera pinned where it is put, aimed up at the seam where Up meets the sides.
		world.run_client_chunk("cam%d" % turns, """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 80
local at = Vector3.new(0, 12, 0)
cam.CFrame = CFrame.new(at, at + Vector3.new(0.45, 0.89, 0))
""")
		phase = 1
		t = 0.0
	elif phase == 1 and t > 4.5:
		get_root().get_texture().get_image().save_png(shots.path_join("sky-up-%d.png" % turns))
		print("  -> sky-up-%d.png  (top turned %d quarter(s) clockwise)" % [turns, turns])
		turns += 1
		if turns > 3:
			quit(0)
		phase = 0
		t = 0.0
	return false

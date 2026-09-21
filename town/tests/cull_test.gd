# The same mesh wound both ways, side by side. The renderer has no DoubleSided property, so
# setting it does nothing and every MeshPart is single sided: Godot's front face is the clockwise
# triangle and an OBJ is written counter-clockwise, so a mesh wound wrong shows its inside.
#
#   godot --path . -s res://tests/cull_test.gd -- <stage dir> <shots dir>
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var shots := ""
var t := 0.0
var phase := 0
var lit := false                 # the intro has finished with the screen

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
	# The title is a ScreenGui over the whole window: a shot behind it is of the title card.
	main.show_title = false
	# The intro then holds black over the window for seconds, so the shot waits on its print
	# rather than on a timer.
	world.script_print.connect(func(_n, line):
		if String(line).begins_with("intro:") and String(line).find("the engine ran") >= 0:
			lit = true)
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(shots)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and lit and t > 5.0:
		phase = 1
		world.run_chunk("cull", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
ch:PivotTo(CFrame.new(-40, 4, 80))
local hum = ch:FindFirstChildOfClass("Humanoid")
if hum then hum:MoveTo(Vector3.new(-40, 4, 80)) end
local function rocket(x, mesh)
	local p = Instance.new("MeshPart")
	p.Name = "R" .. x
	p.Size = Vector3.new(4.04, 7.04, 2.635)
	p.Position = Vector3.new(x, 4.02, 40)
	p.MeshId = mesh
	p.TextureID = "user://preview/rocket-colors.png"
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.Parent = workspace
end
rocket(-44, "user://preview/rocket-flip.obj")   -- the blanket reverse
rocket(-36, "user://preview/rocket.obj")        -- per-face, from the GLB normals
print("CULL left blanket-reversed, right per-face")
""")
		world.run_client_chunk("cam", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 40
cam.CFrame = CFrame.new(Vector3.new(-40, 5.0, 56), Vector3.new(-40, 3.6, 40))
""")
		t = 0.0
	elif phase == 1 and t > 3.0:
		var img := get_root().get_texture().get_image()
		img.save_png(shots.path_join("cull.png"))
		print("  -> cull.png")
		# A rocket culled the wrong way round still fills pixels, so counting them proves only
		# that each side drew something. Which winding is right is for the eye: tests/WINDOWED.md.
		var w := img.get_width()
		var h := img.get_height()
		var left := 0
		var right := 0
		for y in range(h / 4, h * 3 / 4, 2):
			for x in range(0, w, 2):
				var c := img.get_pixel(x, y)
				if c.r + c.g + c.b > 0.9 and absf(c.r - c.g) + absf(c.g - c.b) > 0.15:
					if x < w / 2: left += 1
					else: right += 1
		var passed := 0
		var failed := 0
		if left > 200: passed += 1; print("  PASS the blanket-reversed rocket is drawn (%d coloured px)" % left)
		else: failed += 1; printerr("  FAIL the blanket-reversed rocket is not drawn (%d coloured px)" % left)
		if right > 200: passed += 1; print("  PASS the per-face rocket is drawn (%d coloured px)" % right)
		else: failed += 1; printerr("  FAIL the per-face rocket is not drawn (%d coloured px)" % right)
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

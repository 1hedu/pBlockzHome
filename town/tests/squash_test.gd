# ParticleEmitter.Squash, with and without: Roblox stretches a particle along its travel by a
# factor that runs over its life. Two emitters send one long-lived particle straight up, and the
# drawn height over width of each is measured off the shot.
#
#   godot --path . -s res://tests/squash_test.gd -- <shots dir>
extends SceneTree
var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0
var lit := false                 # the intro has finished with the screen

func _initialize() -> void:
	shots = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	# The title ScreenGui covers the whole window, and a shot taken behind it is a shot of it.
	main.show_title = false
	# The intro then holds a black over the window for seconds: shoot on its line, not on a timer.
	world.script_print.connect(func(_n, line):
		if String(line).begins_with("intro:") and String(line).find("the engine ran") >= 0:
			lit = true)
	root.add_child(main)

func _shoot(name: String) -> void:
	get_root().get_texture().get_image().save_png(shots.path_join(name + ".png"))
	print("  -> %s.png" % name)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and lit and t > 4.0:
		phase = 1
		world.run_chunk("plain", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
ch:PivotTo(CFrame.new(0, 4, 20))
local hum = ch:FindFirstChildOfClass("Humanoid")
if hum then hum:MoveTo(Vector3.new(0, 4, 20)) end

-- Two emitters side by side, alike but for Squash.
local function rig(x, squash)
	local p = Instance.new("Part")
	p.Name = "Rig" .. tostring(x)
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Position = Vector3.new(x, 60, 260)
	p.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0.34
	e.Lifetime = NumberRange.new(3.0, 3.0)
	e.Speed = NumberRange.new(0, 0)
	e.SpreadAngle = Vector2.new(0, 0)
	e.Size = NumberSequence.new(2)
	e.Transparency = NumberSequence.new(0)
	e.Color = ColorSequence.new(Color3.fromRGB(0, 255, 0))
	e.LightEmission = 0
	if squash > 0 then e.Squash = NumberSequence.new(squash) end
	e.Parent = p
end
rig(-4, 0)
rig(4, 3)
print("SQUASH two emitters up: left plain, right squashed 3")
""")
		world.run_client_chunk("cam", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 40
cam.CFrame = CFrame.new(Vector3.new(0, 60, 278), Vector3.new(0, 60, 260))
""")
		t = 0.0
	elif phase == 1 and t > 5.0:
		_shoot("squash")
		var img := get_root().get_texture().get_image()
		var w := img.get_width()
		var h := img.get_height()
		var box := { "l": [w, h, -1, -1], "r": [w, h, -1, -1] }
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				var c := img.get_pixel(x, y)
				if c.g > 0.6 and c.r < 0.35 and c.b < 0.35:
					var b: Array = box["l"] if x < w / 2 else box["r"]
					b[0] = mini(b[0], x); b[1] = mini(b[1], y); b[2] = maxi(b[2], x); b[3] = maxi(b[3], y)
		var passed := 0
		var failed := 0
		var ratio := {}
		for side in ["l", "r"]:
			var b: Array = box[side]
			var bw: int = b[2] - b[0]
			var bh: int = b[3] - b[1]
			ratio[side] = float(bh) / float(bw) if bw > 0 else 0.0
			print("  %s: %dx%d px, tall/wide %.2f" % ["plain" if side == "l" else "squashed", bw, bh, ratio[side]])
		if ratio["l"] > 0.7 and ratio["l"] < 1.4: passed += 1; print("  PASS the plain particle is about square")
		else: failed += 1; printerr("  FAIL the plain particle is not square (%.2f)" % ratio["l"])
		if ratio["r"] > ratio["l"] * 2.0: passed += 1; print("  PASS Squash 3 draws it tall (%.2f against %.2f)" % [ratio["r"], ratio["l"]])
		else: failed += 1; printerr("  FAIL Squash 3 did not stretch it (%.2f against %.2f)" % [ratio["r"], ratio["l"]])
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

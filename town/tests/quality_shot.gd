# Graphics Quality: GPU milliseconds per level, where Automatic settles, what UserGameSettings
# reads, and shots of the town at levels 10 and 1 and of the menu's Settings row. Windowed:
# Automatic stands down under the headless dummy renderer. set_quality's false saves nothing.
#
#   godot --path . -s res://tests/quality_shot.gd -- <shots dir>
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const StandIns = preload("res://tests/StandIns.gd")

const LEVELS := [10, 8, 7, 6, 5, 4, 3, 2, 1]

var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0
var at := 0
var sum := 0.0
var n := 0
var path: Array = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	StandIns.stage("quality")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(name, e): printerr("    LUA ERROR [%s] %s" % [name, e]))
	world.script_print.connect(func(_name, line): if str(line).begins_with("quality:"): print("  ", line))
	root.add_child(main)
	Arrive.now(world)

func _save(name: String) -> void:
	root.get_texture().get_image().save_png(shots.path_join(name))
	print("  -> ", shots.path_join(name))

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 12.0:
		phase = 1; t = 0.0
		# The heaviest view the town has: the whole square, from above one corner.
		world.run_client_chunk("view", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(Vector3.new(90, 45, 90), Vector3.new(0, 5, 0))
""")
		world.set_quality(LEVELS[0], false)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	elif phase == 1:
		if t > 1.0:
			sum += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			n += 1
		if t > 3.0:
			print("  level %2d: %.1f ms on the GPU (in effect: %d)" % [LEVELS[at], sum / n, world.get_quality_level()])
			if LEVELS[at] == 10: _save("quality-10.png")
			if LEVELS[at] == 1: _save("quality-1.png")
			sum = 0.0; n = 0; t = 0.0; at += 1
			if at >= LEVELS.size():
				phase = 2
				world.set_quality(0, false)
				path.append(world.get_quality_level())
			else:
				world.set_quality(LEVELS[at], false)
				RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	elif phase == 2:
		if world.get_quality_level() != path[-1]: path.append(world.get_quality_level())
		if t > 45.0:
			phase = 3; t = 0.0
			print("  Automatic, from level 1, over 45 s: ", path)
			world.run_client_chunk("read", """
local ugs = UserSettings():GetService("UserGameSettings")
print("quality: SavedQualityLevel reads " .. tostring(ugs.SavedQualityLevel))
print("quality: a script writing it: " .. tostring(pcall(function() ugs.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1 end)))
""")
			world.set_menu_open(true)
	elif phase == 3 and t > 1.5:
		_save("quality-menu.png")
		quit(0)
		return true
	return false

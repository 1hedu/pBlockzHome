# What a frame of the town costs the graphics chip: the main view and every other render target,
# measured again with glow, shadows, the 3D resolution and the GUI taken away in turn.
#
#   godot --path . -s res://tests/gpu_cost.gd
#
# Windowed: headless has a dummy renderer.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const StandIns = preload("res://tests/StandIns.gd")

var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var sum := 0.0
var cpu_sum := 0.0
var n := 0
var env: Environment
var lights: Array = []
var steps: Array = []

func _initialize() -> void:
	StandIns.stage("gpucost")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	Arrive.now(world)

func _measure_all(on: bool) -> void:
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), on)
	for vp in root.find_children("*", "SubViewport", true, false):
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), on)

func _begin(what: String, apply: Callable, undo: Callable) -> void:
	steps.append({"what": what, "apply": apply, "undo": undo})

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 12.0:
		phase = -1
		# The whole square from above one corner: the most the town ever asks for at once.
		world.run_client_chunk("view", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(Vector3.new(90, 45, 90), Vector3.new(0, 5, 0))
""")
	elif phase == -1 and t > 14.0:
		phase = 1; t = 0.0
		env = world.get_viewport().world_3d.environment
		for l in root.find_children("*", "Light3D", true, false):
			if l.shadow_enabled: lights.append(l)
		_measure_all(true)
		print("window %s, %d draw calls, %d shadowed light(s) of %d, %d render target(s)" % [
			str(DisplayServer.window_get_size()), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			lights.size(), root.find_children("*", "Light3D", true, false).size(), root.find_children("*", "SubViewport", true, false).size()])
		_begin("as it is", func(): pass, func(): pass)
		_begin("glow off", func(): env.glow_enabled = false, func(): env.glow_enabled = true)
		_begin("shadows off", func():
			for l in lights: l.shadow_enabled = false, func():
			for l in lights: l.shadow_enabled = true)
		_begin("3D at half resolution", func(): root.scaling_3d_scale = 0.5, func(): root.scaling_3d_scale = 1.0)
		_begin("the GUI hidden", func():
			for c in world.get_children():
				if c is CanvasItem: c.visible = false, func():
			for c in world.get_children():
				if c is CanvasItem: c.visible = true)
		steps[0].apply.call()
	elif phase >= 1:
		# Half a second to settle, then two seconds averaged.
		if t > 0.5:
			sum += RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
			n += 1
		if t > 2.5:
			var step: Dictionary = steps[phase - 1]
			var line := "  %-24s main view %.1f ms on the GPU, %.1f ms on the CPU" % [step.what, sum / n, cpu_sum / n]
			if phase == 1:
				var others := 0.0
				var busy := 0
				for vp in root.find_children("*", "SubViewport", true, false):
					var ms := RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
					others += ms
					if ms > 0.0: busy += 1
				line += "; the other render targets %.1f ms (%d drawing this frame)" % [others, busy]
			print(line)
			step.undo.call()
			sum = 0.0; cpu_sum = 0.0; n = 0; t = 0.0
			phase += 1
			if phase - 1 >= steps.size():
				quit(0)
				return true
			steps[phase - 1].apply.call()
	return false

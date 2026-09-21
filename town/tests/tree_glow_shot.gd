# Photographs of the tree from the square: far, and close under the canopy.
#
#   godot --path . -s res://tests/tree_glow_shot.gd -- <shots dir> [extra server chunk file]
#
# The extra chunk, when one is given, runs on the server once the tree is standing: a scratchpad
# for trying a look on the tree before it goes into the place's own files. Windowed, not
# headless: the dummy renderer draws nothing.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")
const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var shots := ""
var extra := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	if args.size() > 1: extra = FileAccess.get_file_as_string(args[1])
	DirAccess.make_dir_recursive_absolute(shots)
	StandIns.stage("treeglow")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(n, line): if line.begins_with("GLOW"): print(line))
	root.add_child(main)
	Arrive.now(world)

func _look(dist: float, rise: float) -> void:
	world.run_client_chunk("look", """
local tree
for _ = 1, 60 do
	tree = workspace:FindFirstChild("Tree", true)
	if tree and tree:FindFirstChild("Canopy") then break end
	task.wait(0.5)
end
local canopy = tree and tree:FindFirstChild("Canopy")
if not canopy then print("GLOW no canopy") return end
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local at = canopy.Position
local flat = Vector3.new(at.X, 0, at.Z).Unit
cam.CFrame = CFrame.lookAt(at - flat * %f + Vector3.new(0, %f, 0), at)
cam.FieldOfView = 60
for _, s in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if s:IsA("ScreenGui") then s.Enabled = false end
end
""" % [dist, rise])

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 6.0:
		phase = 1
		world.run_chunk("standins", StandIns.chunk("treeglow"))
	elif phase == 1 and t > 16.0:
		phase = 2
		if extra != "": world.run_chunk("extra", extra)
		_look(85.0, -10.0)
	elif phase == 2 and t > 20.0:
		phase = 3
		get_root().get_texture().get_image().save_png(shots.path_join("tree_far.png"))
		var lights := 0
		var stack: Array[Node] = [world]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is OmniLight3D and n.visible: lights += 1
			for c in n.get_children(): stack.append(c)
		print("  omni lights drawn: ", lights)
		_look(45.0, -8.0)
	elif phase == 3 and t > 22.5:
		phase = 4
		get_root().get_texture().get_image().save_png(shots.path_join("tree_near.png"))
		print("  -> ", shots)
		quit(0)
	return false

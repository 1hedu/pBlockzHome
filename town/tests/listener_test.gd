# SoundService:SetListener moves where this client hears from. Play Solo: the town's own
# Listener.client.luau puts the ear on the character's root, the ear follows the character,
# and SetListener(Camera) stands the node down again.
#
#   godot --headless --path . -s res://tests/listener_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("where the ear is")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _listener() -> AudioListener3D:
	for c in world.get_children():
		if c is AudioListener3D: return c
	return null

func _last(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

func _run() -> void:
	await create_timer(12.0).timeout
	world.run_client_chunk("where", """
local root = game:GetService("Players").LocalPlayer.Character:WaitForChild("HumanoidRootPart", 10)
local t, o = game:GetService("SoundService"):GetListener()
print(("LISTENER %s %s %.1f %.1f %.1f"):format(tostring(t), tostring(o), root.Position.X, root.Position.Y, root.Position.Z))
""")
	await create_timer(1.0).timeout
	var told := _last("LISTENER ").split(" ")
	check(told.size() == 5 and told[0] == "Enum.ListenerType.ObjectPosition" and told[1] == "HumanoidRootPart",
		"the town's script put the ear on the character's root: %s" % _last("LISTENER "))
	var ear := _listener()
	check(ear != null and ear.is_current(), "and the engine listens through a node of its own, not the camera")
	if ear and told.size() == 5:
		var at := Vector3(float(told[2]), float(told[3]), float(told[4]))
		check(ear.global_position.distance_to(at) < 1.0,
			"placed where the root is: ear %s, root %s" % [str(ear.global_position.round()), str(at.round())])
	world.run_client_chunk("move", """
local root = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart
root.CFrame = CFrame.new(root.Position + Vector3.new(30, 0, 0))
task.wait(0.5)
print(("MOVED %.1f %.1f %.1f"):format(root.Position.X, root.Position.Y, root.Position.Z))
""")
	await create_timer(1.5).timeout
	var moved := _last("MOVED ").split(" ")
	ear = _listener()
	if ear and moved.size() == 3:
		var at := Vector3(float(moved[0]), float(moved[1]), float(moved[2]))
		check(ear.global_position.distance_to(at) < 1.0, "and follows the character: ear %s, root %s" % [str(ear.global_position.round()), str(at.round())])
	else:
		check(false, "the character moved and the ear was found: %s" % _last("MOVED "))
	world.run_client_chunk("camera", 'game:GetService("SoundService"):SetListener(Enum.ListenerType.Camera)')
	await create_timer(1.0).timeout
	ear = _listener()
	check(ear == null or not ear.is_current(), "SetListener(Camera) hands hearing back to the camera")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

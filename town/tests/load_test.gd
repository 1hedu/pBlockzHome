# How long startup stays black: waits for the intro line that says the engine ran.
#
#   godot --headless --path . -s res://tests/load_test.gd
extends SceneTree

var world: PulseBlockzWorld
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		if String(line).begins_with("intro:"):
			print("  ", line)
			if String(line).find("the engine ran") >= 0: done = true)
	get_root().add_child(main)
	_run()

func _run() -> void:
	var waited := 0.0
	while not done and waited < 70.0:
		await create_timer(0.5).timeout
		waited += 0.5
	print("%d passed, %d failed" % [1 if done else 0, 0 if done else 1])
	quit(0 if done else 1)

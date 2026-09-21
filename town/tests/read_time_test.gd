# Times each leg of the town's chain read: the registry in slices, then the details, the
# inventory, the documents and the models. A live read: Chain.server prints the legs one by
# one and this stamps them as they arrive.
#
#   godot --headless --path . -s res://tests/read_time_test.gd
extends SceneTree

var world: PulseBlockzWorld
var started := 0.0
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		var t := String(line)
		if t.begins_with("Chain: ") or t.begins_with("intro:"):
			print("  %6.1fs  %s" % [Time.get_ticks_msec() / 1000.0 - started, t])
			if t.begins_with("Chain: ") and t.find("s, ") >= 0: done = true)
	started = Time.get_ticks_msec() / 1000.0
	get_root().add_child(main)
	_run()

func _run() -> void:
	var waited := 0.0
	while not done and waited < 120.0:
		await create_timer(0.5).timeout
		waited += 0.5
	print("  (%s after %.0fs)" % ["done" if done else "gave up", waited])
	print("%d passed, %d failed" % [1 if done else 0, 0 if done else 1])
	quit(0 if done else 1)

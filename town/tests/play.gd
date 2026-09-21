# The town to walk around in: an ordinary session, except that assets built but not yet
# published are dropped into PlaceAssets off disk (tests/StandIns.gd).
#
#   godot --path . -s res://tests/play.gd
#
# Never quits; close the window.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")

var world: PulseBlockzWorld
var staged := false
var t := 0.0

func _initialize() -> void:
	StandIns.stage("play")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	# No title card: this is for looking at the place.
	main.show_title = false
	world.script_error.connect(func(n, e): printerr("  [%s] %s" % [n, e]))
	get_root().add_child(main)

func _process(delta: float) -> bool:
	t += delta
	# Late enough that PlaceAssets exists; the place waits four minutes on these names.
	if not staged and t > 6.0:
		staged = true
		world.run_chunk("standins", StandIns.chunk("play"))
	return false

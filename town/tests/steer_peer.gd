# The client half of steer_net_test: joins, holds Ctrl + right mouse with W and D for three
# seconds -- WoW's left-drag steer, walking forward while the mouse turns him -- then lets go.
#
#   godot --headless --path . -s res://tests/steer_peer.gd -- --port=8842
extends SceneTree

var world: PulseBlockzWorld
var t := 0.0
var phase := 0

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name): return a.substr(("--%s=" % name).length())
	return fallback

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.mode = 2
	world.server_address = "127.0.0.1"
	world.server_port = int(_flag("port", "8842"))
	world.player_name = "Steerer"
	main.get_node("Wallet").auto_start = false
	root.add_child(main)

func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	e.ctrl_pressed = down and code == KEY_CTRL
	Input.parse_input_event(e)

func _right(down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = down
	e.position = Vector2(640, 360)
	e.global_position = e.position
	Input.parse_input_event(e)

func _process(delta: float) -> bool:
	t += delta
	if not world.is_server_connected():
		return false
	if phase == 0 and t > 20.0:
		phase = 1; t = 0.0
		_key(KEY_CTRL, true)
		_right(true)
		_key(KEY_W, true)
		_key(KEY_D, true)
		print("[peer] steering")
	elif phase == 1 and t > 3.0:
		phase = 2; t = 0.0
		_key(KEY_D, false)
		_key(KEY_W, false)
		_right(false)
		_key(KEY_CTRL, false)
		print("[peer] let go")
	elif phase == 2 and t > 30.0:
		quit(0)
	return false

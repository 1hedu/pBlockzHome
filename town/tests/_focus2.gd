extends SceneTree
var world: PulseBlockzWorld
func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	get_root().add_child(main)
	_run()
func _button(label: String) -> Control:
	var stack: Array[Node] = [get_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == label and (n as Button).is_visible_in_tree(): return n
		for c in n.get_children(): stack.append(c)
	return null
func _focus() -> String:
	var f := get_root().gui_get_focus_owner()
	return "none" if f == null else "%s (%s) focus_mode=%d" % [f.name, f.get_class(), f.focus_mode]
func _click(at: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = down
		ev.position = at; ev.global_position = at
		Input.parse_input_event(ev)
		await create_timer(0.2).timeout
func _run() -> void:
	await create_timer(14.0).timeout
	world.run_client_chunk("open", '''
local Players = game:GetService("Players")
Players.LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("Wardrobe").Enabled = true
''')
	await create_timer(3.0).timeout
	print("G before: focus=%s" % _focus())
	var b := _button("<")
	if b == null: print("G no arrow"); quit(1); return
	var mid := b.get_global_rect().get_center()
	Input.warp_mouse(mid)
	await create_timer(0.2).timeout
	await _click(mid)
	await create_timer(0.3).timeout
	print("G after arrow click: focus=%s" % _focus())
	# the same click on a button that is not an arrow, for comparison
	var save := _button("Save outfit")
	if save != null:
		var sm := save.get_global_rect().get_center()
		Input.warp_mouse(sm)
		await create_timer(0.2).timeout
		await _click(sm)
		await create_timer(0.3).timeout
		print("G after Save click: focus=%s" % _focus())
	quit(0)

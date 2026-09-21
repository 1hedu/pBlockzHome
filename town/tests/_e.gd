extends SceneTree
func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	main.get_node("Wallet").auto_start = false
	get_root().add_child(main)
	_run(main)
func _run(main) -> void:
	await create_timer(6.0).timeout
	var w = main.get_node("Wallet")
	print("E toast = %s" % w._toast)
	print("E chain = %s" % w._chain)
	print("E pulsex = %s" % w._pulsex)
	print("E world children = %d" % main.get_node("World").get_child_ids(0).size())
	quit(0)

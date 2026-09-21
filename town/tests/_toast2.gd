extends SceneTree
var w
var done := false
func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	w = main.get_node("Wallet")
	w.auto_start = false
	w.confirm_purchases = false
	get_root().add_child(main)
	_run()
func _swap() -> void:
	var got: Dictionary = await w.pulsex_swap("", w._pulsex.PULSEX_TOKENS[1].address, "0.004", 800)
	print("T swap ok=%s %s" % [got.get("ok"), got.get("message", "")])
	done = true
func _run() -> void:
	await create_timer(7.0).timeout
	_swap()                                  # started, not awaited
	await create_timer(5.0).timeout
	get_root().get_texture().get_image().save_png("user://toast_pending.png")
	print("T SHOT pending")
	var spun := 0
	while not done and spun < 100:
		spun += 1
		await create_timer(1.0).timeout
	await create_timer(1.5).timeout
	get_root().get_texture().get_image().save_png("user://toast_settled.png")
	print("T SHOT settled (waited %ds)" % spun)
	quit(0)

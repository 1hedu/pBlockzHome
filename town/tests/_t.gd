extends SceneTree
var w
var log_lines: Array[String] = []
func say(s: String) -> void:
	log_lines.append(s)
	var f := FileAccess.open("user://toast_log.txt", FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	w = main.get_node("Wallet")
	w.auto_start = false
	get_root().add_child(main)
	_bail()
	_run()
func _bail() -> void:
	await create_timer(45.0).timeout
	say("deadline")
	quit(0)
func _run() -> void:
	await create_timer(14.0).timeout
	var card: Control = w._toast.raise_pending("Sent", "Waiting for a block.",
		"0x81c15b148c930740fea72be54ee8e598b8dbe4fab9a80bd11f2879229d30fa9b")
	w._toast.raise_pending("Sent", "Waiting for a block.",
		"0x4b21aa09cc31de55e2bb0f0d7c9a1e3f77b2c8d41a6e5093fa2c7719d0e4b8a3")
	await create_timer(2.0).timeout
	get_root().get_texture().get_image().save_png("user://toast_a.png")
	say("shot A")
	w._toast.settle(card, "Confirmed", "It is on the chain.", true)
	await create_timer(2.0).timeout
	get_root().get_texture().get_image().save_png("user://toast_b.png")
	say("shot B")
	w._toast.raise_done("Reverted", "It was mined and the contract refused it. The gas is spent.",
		false, "0x9f0c1d2e3a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9012a3b4c5d6")
	await create_timer(2.0).timeout
	get_root().get_texture().get_image().save_png("user://toast_c.png")
	say("shot C")
	quit(0)

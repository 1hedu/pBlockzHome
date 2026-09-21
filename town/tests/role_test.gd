# Who answers the place: the server, never a joined client.
#
#   godot --headless --path . -s res://tests/role_test.gd
#
# Place scripts ask for chain work by writing an attribute onto ReplicatedStorage.Chain, and
# attributes always replicate -- rbx_net.cpp sends any property whose name starts with "@" to
# every client, with no filter -- so the request lands in every joined player's mirror too. A
# client that answered would sign somebody else's transaction and race the host's reply.
# _answers_the_place() is the code half of SERVER.md section 3: a public host carries no key.
extends SceneTree

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("who answers the place")
	_run()

## Brings up the town in one of the engine's three modes: 0 solo, 1 server, 2 client.
func _as(mode: int) -> Node:
	var main: Node = load("res://Main.tscn").instantiate()
	# No title card: nothing here presses Start.
	main.show_title = false
	var world: PulseBlockzWorld = main.get_node("World")
	# Before add_child: the world opens its socket and picks its half in its own _ready.
	# Serve.gd sets mode and listen_port ahead of the tree for the same reason.
	world.mode = mode
	world.auto_join = false          # nothing to join in a test; do not sit on a socket
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	get_root().add_child(main)
	return main

func _run() -> void:
	var client := _as(2)
	await create_timer(3.0).timeout
	var wallet = client.get_node("Wallet")
	check(not wallet._answers_the_place(),
		"a joined client does not answer the place's requests")
	client.queue_free()
	await create_timer(1.0).timeout

	var server := _as(1)
	await create_timer(3.0).timeout
	check(server.get_node("Wallet")._answers_the_place(),
		"the server does, because they are its own scripts asking")
	server.queue_free()
	await create_timer(1.0).timeout

	var solo := _as(0)
	await create_timer(3.0).timeout
	check(solo.get_node("Wallet")._answers_the_place(),
		"and Play Solo does, being both halves in one process")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

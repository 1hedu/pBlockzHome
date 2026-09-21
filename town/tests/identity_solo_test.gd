# Sign-in in Play Solo: the one process's own wallet signs its own player in.
#
#   godot --headless --path . -s res://tests/identity_solo_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var wallet: Node
var heard: Array[String] = []
var t := 0.0
var phase := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("sign-in, Play Solo")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	wallet = main.get_node("Wallet")
	wallet.auto_start = false
	world.script_print.connect(func(_n, line): heard.append(line))
	get_root().add_child(main)
	Arrive.now(world)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 5.0:
		phase = 1
		world.run_chunk("read", "print('ADDR ' .. tostring(game:GetService('Players'):GetPlayers()[1]:GetAttribute('WalletAddress')))")
	elif phase == 1 and t > 6.0:
		phase = 2
		var got := ""
		for line in heard: if line.begins_with("ADDR "): got = line.substr(5)
		if wallet.can_buy():
			check(got == wallet.wallet_address, "the local player is the wallet this process holds: %s against %s" % [got, wallet.wallet_address])
		else:
			check(got == "nil", "with no key the local player is a guest: %s" % got)
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

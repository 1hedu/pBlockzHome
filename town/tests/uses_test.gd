# A game is held to what its manifest declares it uses (host/Uses.gd).
#
#   godot --headless --path . -s res://tests/uses_test.gd
#
# Undeclared verbs are refused at the client, before anything is sent. A place run off local
# files declares nothing and is refused nothing.
extends SceneTree

const Uses = preload("res://host/Uses.gd")

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("declared uses")
	Uses.declared = false
	check(Uses.permits("pulsex") and Uses.permits("scan"), "off local files, nothing is declared and nothing is refused")

	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	var world: PulseBlockzWorld = main.get_node("World")
	world.data_store_path = ""
	var wallet: Node = main.get_node("Wallet")
	wallet.auto_start = false
	get_root().add_child(main)
	_run(main, wallet)

func _run(main: Node, wallet: Node) -> void:
	await create_timer(3.0).timeout
	Uses.declare(["chain", "nonsense"])
	check(Uses.uses == PackedStringArray(["chain"]), "a name the client does not know is dropped: %s" % [Uses.uses])

	var answers := {}
	for action in ["write", "sign_typed", "swap", "store"]:
		var got := {}
		wallet._handle_request(900 + answers.size(), {"action": action, "typed": {}, "to": "0x0", "fn": "x()"},
			func(_seq, result): got.merge(result))
		await create_timer(0.2).timeout
		answers[action] = got
	for action in answers:
		check(not answers[action].get("ok", true) and String(answers[action].get("message", "")).contains("didn't say it uses"),
			"%s is refused, saying why: %s" % [action, answers[action].get("message", "")])

	var market: Node = main.get_node("Market")
	check(not Uses.permits("scan") and not Uses.permits("market"), "the explorer and the market are not permitted")
	var searched: Dictionary = await market._answer({"search": "PLSX"})
	check(not searched.get("ok", true) and String(searched.get("message", "")).contains("market"),
		"a market search is refused: %s" % searched.get("message", ""))

	var lines := Uses.describe(["chain", "pulsex"])
	check(lines.size() == 2 and lines[1].contains("PulseX"), "the confirm screen reads what was declared: %s" % [lines])
	check(Uses.describe([]).is_empty(), "and nothing for a game that declares nothing")

	Uses.declared = false
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

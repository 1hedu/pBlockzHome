# Liquidity for any pair, not just token/PLS: add, remove and the position scan all take
# two ERC-20s.
#
#   godot --headless --path . -s res://tests/lp_test.gd
#
# Calls the wallet directly and signs nothing: each check stops where a signature would be
# asked for, so a read-only refusal passes as long as the pair itself was understood.
extends SceneTree

var wallet: Node
var passed := 0
var failed := 0
var t := 0.0
var phase := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS ", what)
	else:
		failed += 1
		printerr("  FAIL ", what)

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	wallet = main.get_node("Wallet")
	wallet.auto_start = false
	root.add_child(main)
	print("== liquidity")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 3.0:
		phase = 1
		_run()
	return false

func _run() -> void:
	var tokens: Array = wallet._pulsex_tokens()
	var erc: Array = []
	for tk in tokens:
		if String(tk.get("address", "")) != "":
			erc.append(tk)
	check(erc.size() >= 2, "there are at least two ERC-20s to pair with each other (%d)" % erc.size())

	var pos = await wallet.pulsex_positions()
	check(typeof(pos) == TYPE_ARRAY, "pulsex_positions returns a list")
	var named_both := true
	for p in pos:
		if not p.has("symbol_b"):
			named_both = false
	check(named_both, "every position names both of its sides")

	if erc.size() >= 2:
		var a := String(erc[0].address)
		var b := String(erc[1].address)
		var add = await wallet.pulsex_add_liquidity(a, b, "1", 50)
		var msg := String(add.get("message", ""))
		check(not msg.begins_with("I do not know"), "a token/token pair is accepted: %s" % msg)
		check(msg.find("/PLS") < 0, "and is not silently turned into a PLS pair")

		var rem = await wallet.pulsex_remove_liquidity(a, b, 50, 50)
		var rmsg := String(rem.get("message", ""))
		check(not rmsg.begins_with("I do not know"), "removing from a token/token pair is accepted: %s" % rmsg)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

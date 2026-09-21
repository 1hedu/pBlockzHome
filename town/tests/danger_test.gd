# Danger.gd names the calls and typed data that hand tokens over: approvals (unlimited ones as
# ALL), approval for every item, sends, PLS leaving, EIP-2612 and Permit2 permits, anything
# naming a spender, marketplace orders. A warned prompt focuses Reject, so Enter gives nothing.
#
#   godot --headless --path . -s res://tests/danger_test.gd
extends SceneTree

const Danger = preload("res://host/Danger.gd")
const MAX := "115792089237316195423570985008687907853269984665640564039457584007913129639935"
const SPENDER := "0x1111111111111111111111111111111111111111"
const TOKEN := "0x2222222222222222222222222222222222222222"

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _joined(lines: PackedStringArray) -> String:
	return " | ".join(lines)

func _initialize() -> void:
	print("danger")
	var w := Danger.of_call(TOKEN, "approve(address,uint256)", [SPENDER, MAX], "")
	check(w.size() == 1 and w[0].contains(SPENDER) and w[0].contains("ALL"), "an unlimited approval says ALL, and who: %s" % _joined(w))
	w = Danger.of_call(TOKEN, "approve(address,uint256)", [SPENDER, "5000"], "")
	check(w.size() == 1 and w[0].contains("up to 5000"), "a limited one says how much: %s" % _joined(w))
	w = Danger.of_call(TOKEN, "setApprovalForAll(address,bool)", [SPENDER, true], "")
	check(w.size() == 1 and w[0].contains("EVERY item"), "approval for every item: %s" % _joined(w))
	check(Danger.of_call(TOKEN, "setApprovalForAll(address,bool)", [SPENDER, false], "").is_empty(), "revoking it is not a warning")
	w = Danger.of_call(TOKEN, "transfer(address,uint256)", [SPENDER, "10"], "")
	check(w.size() == 1 and w[0].contains("does not come back"), "a send: %s" % _joined(w))
	w = Danger.of_call(SPENDER, "", [], "2.5")
	check(w.size() == 1 and w[0].contains("2.5 PLS"), "PLS leaving: %s" % _joined(w))
	check(Danger.of_call(TOKEN, "cast()", [], "").is_empty(), "casting a line is not a warning")

	w = Danger.of_typed({"primaryType": "Permit", "message": {"owner": "0x0", "spender": SPENDER, "value": MAX}})
	check(w.size() == 2 and w[0].contains("PERMIT") and w[1].contains("unlimited"), "an EIP-2612 permit, unlimited: %s" % _joined(w))
	w = Danger.of_typed({"primaryType": "PermitTransferFrom", "domain": {"name": "Permit2"}, "message": {"spender": SPENDER}})
	check(w.size() >= 1 and w[0].contains("PERMIT"), "a Permit2 transfer: %s" % _joined(w))
	w = Danger.of_typed({"primaryType": "Delegation", "message": {"operator": SPENDER}})
	check(w.size() == 1 and w[0].contains(SPENDER), "anything naming an operator: %s" % _joined(w))
	w = Danger.of_typed({"primaryType": "OrderComponents", "message": {"offerer": "0x0"}})
	check(w.size() == 1 and w[0].contains("marketplace order"), "a marketplace order: %s" % _joined(w))
	check(Danger.of_typed({"primaryType": "Result", "message": {"id": "0x1", "limit": 2}}).is_empty(), "a duel result is not a warning")

	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	main.get_node("World").data_store_path = ""
	var wallet: Node = main.get_node("Wallet")
	wallet.auto_start = false
	get_root().add_child(main)
	_prompt(wallet)

func _prompt(wallet: Node) -> void:
	await create_timer(2.0).timeout
	var answer := [null]
	var ask := func(): answer[0] = await wallet._confirm("Send this transaction?", "detail", PackedStringArray(["This lets somebody take ALL."]))
	ask.call()
	await process_frame
	await process_frame
	var layer: Node = wallet.get_child(wallet.get_child_count() - 1)
	var red := false
	var focused := ""
	for n in layer.find_children("*", "", true, false):
		if n is Label and (n as Label).text.begins_with("WARNING: This lets somebody take ALL."): red = true
		if n is Button and (n as Button).has_focus(): focused = (n as Button).text
	check(red, "the prompt shows the warning, above the detail")
	check(focused == "Reject", "and the focus is on Reject: %s" % focused)
	for n in layer.find_children("*", "Button", true, false):
		if (n as Button).text == "Reject": (n as Button).pressed.emit()
	await create_timer(0.2).timeout
	check(answer[0] == false, "and rejecting sends nothing")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

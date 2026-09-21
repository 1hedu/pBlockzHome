# The gas arithmetic in host/Gas.gd, and the fee controls on the wallet's confirm prompt.
#
#   godot --headless --path . -s res://tests/gas_test.gd
extends SceneTree

const Gas = preload("res://host/Gas.gd")

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("gas")
	check(Gas.gwei_to_wei("0.002") == 2_000_000 and Gas.gwei_to_wei("1") == 1_000_000_000, "gwei typed in becomes wei")
	check(Gas.gwei_to_wei("abc") == -1 and Gas.gwei_to_wei("0.0000000001") == -1, "and nonsense, or finer than a wei, is refused")
	check(Gas.wei_to_gwei(2_000_000) == "0.002" and Gas.wei_to_gwei(10_000_000_000_000) == "10000", "wei reads back as gwei")
	var t := Gas.presets(943)
	check(t.Low == 2_000_000 and t.Normal == 10_000_000 and t.Fast == 100_000_000, "testnet's presets are the measured ones: %s" % t)
	var h := Gas.presets(369, [["0x0", "0x0", "0x0"], ["0x3b9aca00", "0x77359400", "0xee6b2800"], ["0x1", "0x2", "0x3"]])
	check(h.Low >= Gas.FLOOR_WEI and h.Normal >= h.Low and h.Fast >= h.Normal, "history presets never fall under the floor, and faster is never cheaper: %s" % h)
	var none := Gas.presets(369, [])
	check(none.Normal == 1_000_000_000, "no history at all falls back to 1 gwei")
	check(Gas.limit_from_estimate(100_000) == 125_000, "a limit is the estimate plus a quarter")
	check(Gas.max_fee_for(7, 2_000_000) == 2_000_014, "the max fee is twice the base fee plus the tip")
	check(not Gas.read_choice("0.0001", "1", "", false).ok, "a tip under the floor is refused")
	check(not Gas.read_choice("1", "0.5", "", false).ok, "a max fee under the tip is refused")
	check(not Gas.read_choice("0.01", "0.01", "100", true).ok, "a gas limit under 21000 is refused")
	check(Gas.read_choice("0.01", "0.02", "50000", true).ok, "and a sensible choice is taken")

	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	main.get_node("World").data_store_path = ""
	var wallet: Node = main.get_node("Wallet")
	wallet.auto_start = false
	get_root().add_child(main)
	_prompt(wallet)

func _find(layer: Node, name: String) -> Node:
	var hits := layer.find_children(name, "", true, false)
	return hits[0] if hits.size() > 0 else null

func _prompt(wallet: Node) -> void:
	await create_timer(2.0).timeout
	check(wallet._even_hex(2_000_000) == "0x1e8480" and wallet._even_hex(15) == "0x0f", "fees go into the transaction as even-length hex")
	var fee := {"base_wei": 7, "presets": Gas.presets(943), "speed": "Normal", "tip_wei": 10_000_000,
		"max_fee_wei": Gas.max_fee_for(7, 10_000_000), "gas_limit": 60_000, "estimated": true, "estimate_failed": ""}
	var answer := [null]
	var ask := func(): answer[0] = await wallet._confirm("Send this transaction?", "detail", PackedStringArray(), fee)
	ask.call()
	await process_frame
	await process_frame
	var layer: Node = wallet.get_child(wallet.get_child_count() - 1)
	var tip: LineEdit = _find(layer, "Tip")
	var max_fee: LineEdit = _find(layer, "MaxFee")
	var limit: LineEdit = _find(layer, "GasLimit")
	var cost: Label = _find(layer, "FeeCost")
	check(tip != null and max_fee != null and limit != null, "the prompt has a tip, a max fee and a gas limit to edit")
	check(tip.text == "0.01" and limit.text == "60000", "starting at Normal and the estimated limit: %s, %s" % [tip.text, limit.text])
	check(cost.text.begins_with("At most 0.000000600"), "and it says the most it can cost, however small: %s" % cost.text)

	(_find(layer, "SpeedFast") as Button).pressed.emit()
	check(tip.text == "0.1" and max_fee.text == Gas.wei_to_gwei(Gas.max_fee_for(7, 100_000_000)), "Fast sets the tip and the max fee: %s / %s" % [tip.text, max_fee.text])

	tip.text = "0.00001"
	tip.text_changed.emit(tip.text)
	check(cost.text.contains("not mined"), "typing a tip under the floor says so: %s" % cost.text)
	var yes: Button = null
	for b in layer.find_children("*", "Button", true, false):
		if (b as Button).text == "Confirm": yes = b
	yes.pressed.emit()
	await process_frame
	check(is_instance_valid(layer) and layer.is_inside_tree(), "and Confirm will not send it")

	tip.text = "0.005"
	tip.text_changed.emit(tip.text)
	max_fee.text = "0.02"
	max_fee.text_changed.emit(max_fee.text)
	limit.text = "75000"
	limit.text_changed.emit(limit.text)
	yes.pressed.emit()
	await create_timer(0.2).timeout
	check(answer[0] == true, "a valid choice confirms")
	check(fee.tip_wei == 5_000_000 and fee.max_fee_wei == 20_000_000 and fee.gas_limit == 75000 and fee.speed == "Custom",
		"and what was typed is what will be bid: tip %s, max %s, limit %s" % [fee.tip_wei, fee.max_fee_wei, fee.gas_limit])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

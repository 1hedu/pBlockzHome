# PulseX against the live testnet v4 deployment: quotes, routes, price impact, pool shares.
# Reads only, so it signs nothing and costs no gas. Live rather than mocked because what it
# proves is that the shipped addresses hold code on this chain and the router answers.
#
#   godot --headless --path . -s res://tests/pulsex_live.gd
extends SceneTree

const Decimal := preload("res://host/Decimal.gd")

var wallet: Node
var passed := 0
var failed := 0

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
	print("== PulseX on testnet v4")
	_run()

func _run() -> void:
	await create_timer(1.0).timeout

	# ---- decimal arithmetic: a uint256 does not fit an int and a float rounds a trade ----
	check(Decimal.add("999", "1") == "1000", "decimal add carries")
	check(Decimal.mul_small("123456789012345678901234567890", 3)
		== "370370367037037036703703703670", "decimal multiply survives a uint256")
	check(Decimal.mul_div("1000000000000000000000", "1", "10000") == "100000000000000000",
		"decimal divide survives a uint256")
	check(Decimal.ratio_bps("1", "2") == 5000, "a half is 5000 basis points")
	check(Decimal.ratio_bps("1", "1000") == 10, "and a tenth of a percent is 10")

	# ---- the deployment is real ----------------------------------------------------
	var wpls: String = wallet.PULSEX.wpls
	var plsx := ""
	for t in wallet.PULSEX_TOKENS:
		if t.symbol == "PLSX":
			plsx = t.address
	var pair: String = await wallet._pulsex._pulsex_pair(plsx, wpls)
	check(pair != "", "the testnet factory has a PLSX/WPLS pool: %s" % pair)

	var path: Array = await wallet._pulsex._pulsex_path("", plsx)
	check(path.size() == 2 and String(path[0]).to_lower() == wpls.to_lower(),
		"PLS routes as WPLS, because the router wraps it")

	# ---- a quote off the real router -----------------------------------------------
	var q: Dictionary = await wallet.pulsex_quote("", plsx, "1000", 50)
	check(q.get("ok", false), "the router quotes 1000 PLS -> PLSX")
	if q.get("ok", false):
		print("       1000 PLS -> %s PLSX   impact %s   route %s" % [q.out, q.impact, q.route])
		check(q.out.to_float() > 0.0, "and the number is not zero")
		check(q.min_received.to_float() < q.out.to_float(),
			"minimum received sits under the quote, by the slippage")
		check(int(q.impact_bps) < 100, "1000 PLS barely moves a 77-billion-PLS pool")

	var big: Dictionary = await wallet.pulsex_quote("", plsx, "50000000000", 50)
	if big.get("ok", false):
		print("       50bn PLS -> %s PLSX   impact %s" % [big.out, big.impact])
		check(int(big.impact_bps) > int(q.get("impact_bps", 0)),
			"a bigger order shows a bigger price impact")

	# ---- a token pasted in by address ----------------------------------------------
	var bad: Dictionary = await wallet.add_token("not-an-address")
	check(not bad.get("ok", true), "a thing that is not an address is refused")
	var empty: Dictionary = await wallet.add_token("0x000000000000000000000000000000000000dEaD")
	check(not empty.get("ok", true), "and so is an address with no contract at it")

	# INC has its own address on testnet; the mainnet one holds no code here.
	var inc := "0x6eFAfcb715F385c71d8AF763E8478FeEA6faDF63"
	var known := false
	for t in wallet.PULSEX_TOKENS:
		if String(t.address).to_lower() == inc.to_lower():
			known = true
	check(known, "INC ships in the list at its testnet address, not the mainnet one")
	var incq: Dictionary = await wallet.pulsex_quote("", inc, "1000", 50)
	check(incq.get("ok", false), "and it quotes: %s INC" % incq.get("out", "-"))

	# ---- the Add Liquidity card: the last argument is the side the amount was typed on ----
	# Both prices, the LP tokens and the share are all checked because PulseX's own page shows
	# every one of them next to the paired amount.
	var pq: Dictionary = await wallet.pulsex_pool_quote("", plsx, "1000", "a")
	check(pq.get("ok", false) and pq.get("pool", false), "the card reads the PLS/PLSX pool")
	if pq.get("ok", false) and pq.get("pool", false):
		check(String(pq.b_amount).to_float() > 0.0, "1000 PLS pairs with %s PLSX" % pq.b_amount)
		check(String(pq.price_ab).to_float() > 0.0 and String(pq.price_ba).to_float() > 0.0,
			"and the prices read both ways: %s PLSX per PLS, %s PLS per PLSX" % [pq.price_ab, pq.price_ba])
		check(String(pq.lp) != "" and String(pq.share) != "", "and it says the LP tokens and the share: %s LP, %s" % [pq.lp, pq.share])
		var back: Dictionary = await wallet.pulsex_pool_quote("", plsx, String(pq.b_amount), "b")
		var pls_back := String(back.get("a_amount", "0")).to_float()
		check(back.get("ok", false) and absf(pls_back - 1000.0) < 1.0,
			"typed on the PLSX side, the PLS side comes back as %s" % back.get("a_amount", "-"))
	var same: Dictionary = await wallet.pulsex_pool_quote(plsx, plsx, "1", "a")
	check(not same.get("ok", true), "the same token on both sides is refused")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

# The screener's data, off DexScreener's public API.
#
#   godot --headless --path . -s res://tests/screener_live.gd
#
# Live and read-only: the columns a screener is for -- a dollar price, volume, the change over
# a day, depth -- arrive from the API rather than being derived from getReserves.
extends SceneTree

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
	print("== the screener")
	_run()

func _run() -> void:
	await create_timer(1.0).timeout
	check(wallet._compact(1234567.0) == "1.23M", "big numbers read as 1.23M, not as digits")
	check(wallet._compact(0.0) == "0", "and zero stays zero")
	check(wallet._price_str("0.000008632") == "$0.000008632".left(12) or
		wallet._price_str("0.000008632").begins_with("$0.0000086"),
		"a sub-cent price keeps its figures instead of rounding to zero")

	var out := {}
	await wallet._collect_screener(out)
	var sc: Dictionary = out.get("screener", {})
	check(not sc.is_empty(), "DexScreener answered")
	if sc.is_empty():
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed else 0)
		return
	var rows: Array = sc.rows
	check(rows.size() > 0, "with %d pairs" % rows.size())
	var first: Dictionary = rows[0]
	print("       top: %s  %s  vol %s  liq %s  24h %.2f%%  age %s" %
		[first.pair, first.price, first.volume, first.liquidity, first.h24, first.age])
	check(String(first.price) != "-" and String(first.price).begins_with("$"),
		"the price is in dollars, which is the whole reason to use the API")
	check(first.liquidity_raw > 0.0, "with real depth behind it")
	check(String(first.volume) != "0", "and 24h volume, which no getReserves call can give you")
	check(String(first.age) != "-", "and the pool's age, so a pair minted an hour ago says so")
	var sorted := true
	for i in range(1, rows.size()):
		if float(rows[i].liquidity_raw) > float(rows[i - 1].liquidity_raw):
			sorted = false
	check(sorted, "sorted by depth, deepest first")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

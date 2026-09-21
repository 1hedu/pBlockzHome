# Does every scan view come back without throwing?
#
#   godot --headless --path . -s res://tests/scan_probe.gd
#
# Blockscout sends a null wherever a field does not apply and String(null) is a hard error, so
# all seven views the panel names get walked. The Scan node serves them -- reading an explorer
# needs no key -- and the wallet only supplies a real address for the address view.
extends SceneTree

var scan: Node
var wallet: Node
var t := 0.0
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	wallet = main.get_node("Wallet")
	root.add_child(main)
	print("== scan probe")
	_run(main)

func _run(main: Node) -> void:
	for _i in 90:
		await process_frame
	# Main's _ready makes the Scan node, so it is not there at instantiate time.
	scan = main.get_node_or_null("Scan")
	if scan == null:
		printerr("no Scan node: %s" % [main.get_children()])
		done = true
		return
	var block := ""
	var tx := ""
	for view in ["home", "blocks", "txs", "tokens", "block", "tx", "address"]:
		var id := ""
		if view == "block": id = block
		elif view == "tx": id = tx
		elif view == "address": id = String(wallet.wallet_address)
		var p: Dictionary = await scan.scan_view(view, id)
		if not p.get("ok", false):
			print("  %-9s FAILED: %s" % [view, p.get("message", "?")])
			continue
		var rows := 0
		for tb in p.get("tables", []):
			rows += (tb.get("rows", []) as Array).size()
		print("  %-9s ok  url=%-22s stats=%d rows=%d detail=%d"
			% [view, p.get("url", ""), (p.get("stats", []) as Array).size(),
			   rows, (p.get("rows", []) as Array).size()])
		if view == "home":
			for tb in p.get("tables", []):
				for r in tb.get("rows", []):
					if r.get("view", "") == "block" and block == "": block = String(r.get("id", ""))
					if r.get("view", "") == "tx" and tx == "": tx = String(r.get("id", ""))

	# Overlapping asks, the way a click starts a page before the last one lands: the scan holds
	# its own request node rather than sharing the wallet's with the screener.
	print("  -- four at once --")
	var burst := ["home", "blocks", "txs", "tokens"]
	var got := {}
	for view in burst:
		_one(view, got)
	while got.size() < burst.size():
		await process_frame
	for view in burst:
		print("  %-9s %s" % [view, got[view]])
	done = true

func _one(view: String, got: Dictionary) -> void:
	var p: Dictionary = await scan.scan_view(view, "")
	var rows := 0
	for tb in p.get("tables", []):
		rows += (tb.get("rows", []) as Array).size()
	got[view] = "ok rows=%d" % rows if p.get("ok", false) else "FAILED: %s" % p.get("message", "?")

func _process(delta: float) -> bool:
	t += delta
	if done or t > 220.0:
		if not done: printerr("scan probe did not finish in %.0fs" % t)
		quit(0 if done else 1)
	return false

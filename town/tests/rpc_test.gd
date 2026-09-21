# Talking to a chain node.
#
#   godot --path . -s res://tests/rpc_test.gd
#
# Against the real node: Rpc.gd's whole job is somebody else's server, and a fake would only
# prove the fake agrees with itself. Every call here is a read -- nothing signs or spends.
extends SceneTree

const Rpc = preload("res://host/Rpc.gd")

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the chain node")
	var rpc: Node = Rpc.new()
	get_root().add_child(rpc)
	_run(rpc)

func _run(rpc) -> void:
	await create_timer(0.5).timeout

	var height: String = await rpc.one("eth_blockNumber", [])
	check(height.begins_with("0x") and height.length() > 2,
		"it answers a question: eth_blockNumber = %s" % height)
	var n: int = height.hex_to_int()
	check(n > 1000000, "and the answer is a real height: %d" % n)

	var doc: Dictionary = await rpc.one_dict("eth_chainId", [])
	check(doc.has("result"), "one_dict hands back the envelope, not just the result")
	check(String(doc.get("result", "")).hex_to_int() == 943,
		"and it is testnet v4: chainId %d" % String(doc.get("result", "0x0")).hex_to_int())

	# Order is the point: a node may answer a batch in any order and every caller reads the
	# answers positionally, so the batch alternates two methods with answers that differ.
	var calls := []
	for i in 12:
		calls.append({"method": "eth_chainId" if i % 2 == 0 else "eth_blockNumber", "params": []})
	var got: Array = await rpc.many(calls)
	check(got.size() == 12, "twelve asked for, twelve back: %d" % got.size())
	var right := 0
	for i in got.size():
		var v := String(got[i])
		if v == "":
			continue
		if (i % 2 == 0) == (v.hex_to_int() == 943):
			right += 1
	check(right == 12, "and every one in the slot it was asked from: %d of 12" % right)

	var mixed := [
		{"method": "eth_blockNumber", "params": []},
		{"method": "eth_thisIsNotAMethod", "params": []},
		{"method": "eth_chainId", "params": []},
	]
	var some: Array = await rpc.many(mixed)
	check(some.size() == 3, "a batch with a bad call still answers in three slots")
	check(String(some[0]) != "" and String(some[2]) != "",
		"the good ones came back")
	check(String(some[1]) == "", "and the bad one is an empty slot rather than a lost batch")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

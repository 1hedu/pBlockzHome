# What the registry says each item's metadata is. Prints; asserts nothing.
#
#   godot --headless --path . -s res://tests/uri_probe.gd
#
# The shelf falls back to "#5" and "no picture on chain" for any item whose metadata did not
# resolve. Reading uri() off UGC1155 directly separates the three causes: no uri at all, a uri
# nothing speaks (_resolve_item bails unless it begins with pblockz://), or a missing document.
extends SceneTree

var wallet: Node
var t := 0.0
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	wallet = main.get_node("Wallet")
	root.add_child(main)
	print("== uri probe")
	_run()

func _run() -> void:
	for _i in 90:
		await process_frame
	for id in range(1, 13):
		var raw: String = await wallet._tx_call(
			wallet.ADDRESSES.UGC1155, wallet._sel("uri(uint256)") + wallet._arg_uint(id))
		var uri: String = wallet._decode_string(raw)
		if uri == "":
			print("  #%-2d  (no uri on chain)" % id)
			continue
		if not uri.begins_with("pblockz://"):
			print("  #%-2d  %s   <- not a pblockz uri, so nothing resolves it" % [id, uri.substr(0, 70)])
			continue
		var bytes: PackedByteArray = await wallet.assets.fetch(uri)
		if bytes.is_empty():
			print("  #%-2d  %s   <- uri fine, document did not come back" % [id, uri.substr(0, 46)])
			continue
		var meta = JSON.parse_string(bytes.get_string_from_utf8())
		if typeof(meta) != TYPE_DICTIONARY:
			print("  #%-2d  %s   <- document is not JSON (%d bytes)" % [id, uri.substr(0, 46), bytes.size()])
			continue
		print("  #%-2d  name=%-22s thumb=%s model=%s" % [id,
			str(meta.get("name", "(none)")),
			"yes" if String(meta.get("thumbnail", "")) != "" else "NO",
			"yes" if String(meta.get("model", "")) != "" else "NO"])
	done = true

func _process(delta: float) -> bool:
	t += delta
	if done or t > 180.0:
		if not done: printerr("uri probe did not finish in %.0fs" % t)
		quit(0 if done else 1)
	return false

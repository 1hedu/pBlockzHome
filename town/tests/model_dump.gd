# What a published model is built out of.
#
#   godot --headless --path . -s res://tests/model_dump.gd
#
# Published models live on chain and nowhere on disk, so this fetches one through the wallet
# and prints every part's name, size and CFrame.
extends SceneTree

var wallet: Node
var t := 0.0
var done := false
const WANT := 26        # Maria Wig

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	wallet = main.get_node("Wallet")
	root.add_child(main)
	print("== model dump")
	_run()

func _walk(node, depth: int) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		return
	var props: Dictionary = node.get("properties", {})
	var cls := String(node.get("className", "?"))
	var line := "  ".repeat(depth) + "%s  %s" % [cls, String(props.get("Name", ""))]
	if props.has("Size"):
		line += "   size=%s" % [props["Size"]]
	if props.has("CFrame"):
		line += "   cframe=%s" % [props["CFrame"]]
	if props.has("Position"):
		line += "   pos=%s" % [props["Position"]]
	if props.has("Orientation"):
		line += "   orient=%s" % [props["Orientation"]]
	if props.has("Rotation"):
		line += "   rot=%s" % [props["Rotation"]]
	print(line)
	for kid in node.get("children", []):
		_walk(kid, depth + 1)

func _run() -> void:
	for _i in 90:
		await process_frame
	var raw: String = await wallet._tx_call(
		wallet.ADDRESSES.UGC1155, wallet._sel("uri(uint256)") + wallet._arg_uint(WANT))
	var uri: String = wallet._decode_string(raw)
	var meta_bytes: PackedByteArray = await wallet.assets.fetch(uri)
	var meta = JSON.parse_string(meta_bytes.get_string_from_utf8())
	print("  item #%d is %s" % [WANT, str(meta.get("name", "?"))])
	var model_bytes: PackedByteArray = await wallet.assets.fetch(String(meta.get("model", "")))
	if model_bytes.is_empty():
		printerr("  the model did not come back")
		done = true
		return
	var model = JSON.parse_string(model_bytes.get_string_from_utf8())
	_walk(model, 1)
	done = true

func _process(delta: float) -> bool:
	t += delta
	if done or t > 150.0:
		if not done: printerr("model dump did not finish in %.0fs" % t)
		quit(0 if done else 1)
	return false

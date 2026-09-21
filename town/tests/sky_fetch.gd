# All six sky faces come off the chain. The largest is 606KB, past what a node returns from one
# eth_call (--rpc.returndata-limit), so it can only arrive through the per-chunk fallback.
#
#   godot --headless --path . -s res://tests/sky_fetch.gd
extends SceneTree
var t := 0.0
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	_run()

func _run() -> void:
	for _i in 40:
		await process_frame
	var assets = get_root().get_node_or_null("/root/ChainAssets")
	if assets == null:
		printerr("no ChainAssets")
		done = true
		return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://place-assets.json"))
	print("== sky faces off the chain")
	for name in ["SkyboxRt", "SkyboxLf", "SkyboxUp", "SkyboxDn", "SkyboxBk", "SkyboxFt"]:
		var uri := String(manifest.get(name, ""))
		if uri == "":
			print("  %-9s not in the manifest" % name)
			continue
		var began := Time.get_ticks_msec()
		var bytes: PackedByteArray = await assets.fetch(uri)
		var took := (Time.get_ticks_msec() - began) / 1000.0
		print("  %-9s %7d bytes in %5.1fs  %s" % [name, bytes.size(), took,
			"ok" if bytes.size() > 0 else "FAILED"])
	done = true

func _process(delta: float) -> bool:
	t += delta
	if done or t > 600.0:
		if not done: printerr("did not finish in %.0fs" % t)
		quit(0)
	return false

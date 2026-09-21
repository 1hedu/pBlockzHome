# The scan on its own node, including search.
#
#   godot --headless --path . -s res://tests/scan2_probe.gd
extends SceneTree

var scan: Node
var t := 0.0
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	root.add_child(main)
	print("== scan on its own node")
	_run_after(main)

func _run_after(main: Node) -> void:
	for _i in 60:
		await process_frame
	scan = main.get_node_or_null("Scan")
	if scan == null:
		printerr("no Scan node: %s" % [main.get_children()])
		done = true
		return
	for probe in [["home", ""], ["search", "PLSX"], ["search", "25339481"],
			["search", "0x9E53d6dE1b989ed13aEE38645F3F3462Ca0Cff09"], ["tokens", ""]]:
		var p: Dictionary = await scan.scan_view(probe[0], probe[1])
		if not p.get("ok", false):
			print("  %-8s %-12s FAILED: %s" % [probe[0], probe[1], p.get("message", "?")])
			continue
		var rows := 0
		var first := ""
		for tb in p.get("tables", []):
			var rr: Array = tb.get("rows", [])
			rows += rr.size()
			if first == "" and rr.size() > 0:
				first = "%s -> %s/%s" % [rr[0].get("cells", [])[0], rr[0].get("view", ""), str(rr[0].get("id", "")).substr(0, 14)]
		print("  %-8s %-12s ok rows=%-3d %s" % [probe[0], probe[1], rows, first])
	done = true

func _process(delta: float) -> bool:
	t += delta
	if done or t > 180.0:
		if not done: printerr("did not finish in %.0fs" % t)
		quit(0 if done else 1)
	return false

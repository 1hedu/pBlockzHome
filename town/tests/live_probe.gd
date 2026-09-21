# What the host publishes, live: how long the first read of the chain takes and what came
# back. Reads the real chain, so it is not part of the offline suite.
#
#   godot --headless --path . -s res://tests/live_probe.gd
extends SceneTree

var world: PulseBlockzWorld
var wallet: Node
var t := 0.0
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	wallet = main.get_node("Wallet")
	root.add_child(main)
	world.script_error.connect(func(n, e): printerr("    ERROR [%s] %s" % [n, e]))
	wallet.published.connect(func(d):
		print("published after %.1fs" % t)
		print("  tokens   ", d.tokens.size(), "  items ", d.items.size(), "  listings ", d.listings.size())
		print("  chain    ", d.get("chain", {}))
		print("  pulsex   ", d.get("pulsex", {}))
		print("  holder   ", d.get("holder", {}))
		var locked := 0
		for l in d.listings:
			if l.get("locked", false): locked += 1
		print("  locked   %d of %d listings" % [locked, d.listings.size()])
		var named := 0
		for l in d.listings:
			if String(l.get("name", "")) != "": named += 1
		print("  listings with a name: %d of %d" % [named, d.listings.size()])
		for item in d.items:
			if String(item.get("source", "")) == "inventory":
				print("  made: %-24s model=%s  %s" % [item.get("name", "?"), item.get("model", "(none)"), String(item.get("id", "")).substr(0, 18)])
		# _publish hands the payload to the sandbox through run_chunk, which runs a frame or
		# two later: quitting when `published` fires kills it before any script sees the data.
		await root.get_tree().create_timer(8.0).timeout
		done = true)
	print("== live probe")

func _process(delta: float) -> bool:
	t += delta
	if done or t > 240.0:
		if not done: printerr("nothing published in %.0fs" % t)
		quit(0 if done else 1)
	return false

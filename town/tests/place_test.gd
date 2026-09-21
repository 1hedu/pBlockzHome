# The client fetches a published place by content hash, checks each file's hash and runs it.
#
#   godot --headless --path . -s res://tests/place_test.gd -- --place <pblockz uri>
#
# Also proves nothing under res://scripts loads: a fallback to disk looks like a loaded place.
extends SceneTree

var main: Node
var t := 0.0
var done := false
var passed := 0
var failed := 0
var log := ""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	var uri := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--place" and i + 1 < args.size(): uri = args[i + 1]
	if uri == "":
		printerr("needs: -- --place <pblockz uri>")
		quit(2); return
	main = load("res://Main.tscn").instantiate()
	main.confirm_place = false            # nobody is sitting here to say yes
	main.get_node("Wallet").auto_start = false
	get_root().add_child(main)
	main.get_node("World").script_print.connect(func(n, txt): log += "[%s] %s\n" % [n, txt])
	main.get_node("World").script_error.connect(func(n, e): log += "ERROR [%s] %s\n" % [n, e])

func _process(delta: float) -> bool:
	t += delta
	if done or t < 45.0: return false
	done = true

	var sync := main.get_node("ScriptSync")
	check(not sync.load_from_disk, "ScriptSync stood aside for the fetched place")

	var names: Array = sync.names()
	check(names.size() > 0, "the place mounted (%d files)" % names.size())
	# Named files rather than a count, so a half-mount cannot pass by being large.
	for want in ["ServerScriptService/Ranks.server.luau", "ReplicatedStorage/Ranks.luau",
			"ServerScriptService/Brazier.server.luau"]:
		check(names.has(want), "mounted %s" % want)

	check(log.length() > 0, "the mounted scripts actually ran")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return true

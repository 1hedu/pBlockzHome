# One hash in, and the code that hash names running: every file checked against its own hash on
# the way in, nothing mounted until all of them have arrived. Live, not part of the offline suite.
#
#   godot --headless --path . -s res://tests/experience_live.gd -- <pblockz:// uri>
#
# With no uri, the last publish: experiences.943.json, written by publish-experience.js.
extends SceneTree

var world: PulseBlockzWorld
var experience: Node
var t := 0.0
var phase := 0
var failed := 0
var uri := ""
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if not ok: failed += 1
	print(("  PASS " if ok else "  FAIL ") + what)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("pblockz://"):
			uri = a
	if uri == "":
		var path := ProjectSettings.globalize_path("res://").path_join("../../../experiences.943.json").simplify_path()
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				for name in parsed:
					uri = String(parsed[name].get("uri", ""))
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	# Nothing off disk: everything that runs has to have come from the chain.
	main.get_node("ScriptSync").scripts_dir = "res://nothing"
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	world.script_print.connect(func(n, txt):
		said.append(txt)
		print("    [%s] %s" % [n, txt]))
	world.script_error.connect(func(n, e): printerr("    ERROR [%s] %s" % [n, e]))

	experience = load("res://host/Experience.gd").new()
	experience.name = "Experience"
	experience.sync_path = ^"../ScriptSync"
	experience.confirm = false          # nobody here can click the join screen
	main.add_child(experience)
	print("== loading an experience from the chain")
	print("   ", uri if uri != "" else "(no uri: publish one first)")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 2.0:
		phase = 1
		if uri == "":
			printerr("  no experience published; run scripts/publish-experience.js first")
			quit(1)
			return true
		_run()
	elif phase == 1 and t > 90.0:
		phase = 2
		printerr("  timed out")
		quit(1)
	return false

func _run() -> void:
	var info: Dictionary = await experience.preview(uri)
	check(info.get("ok", false), "the manifest fetched and matched its own hash")
	if not info.ok:
		printerr("  ", info.get("error", ""))
		quit(1)
		return
	print("   name    %s" % info.name)
	print("   files   %d, %d bytes" % [info.count, info.bytes])
	print("   hash    %s" % info.hash)
	print("   blocked %s, seen before %s" % [info.blocked, info.seen_before])
	check(info.count > 0, "it names some files")
	check(not info.blocked, "no curation list blocks it")

	check(said.is_empty(), "nothing has run merely from looking at it")

	var result: Dictionary = await experience.mount(uri)
	check(result.get("ok", false), "every file fetched, verified, and mounted")
	if not result.ok:
		printerr("  ", result.get("error", ""))

	await Engine.get_main_loop().create_timer(3.0).timeout
	var all := " ".join(said)
	check(all.contains("on the desk"), "and the town's NPCs came up from code that was never on disk")
	print(("%d failed" % failed) if failed else "all passed")
	quit(1 if failed else 0)

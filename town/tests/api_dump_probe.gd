# Dumps every class the engine declares, with its members, as JSON -- the input a parity sweep
# works from. Not a suite.
#
#   godot --headless --path . -s res://tests/api_dump_probe.gd -- <out.json>
extends SceneTree

func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://api_dump.json"
	var world := PulseBlockzWorld.new()
	var api: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../../../scripts/roblox-api.json"))
	var dump := {}
	for cls in api.keys():
		var have: Dictionary = world.get_class_members(cls)
		if have.is_empty():
			continue
		dump[cls] = have
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(dump))
	f.close()
	print("DUMPED %d classes -> %s" % [dump.size(), ProjectSettings.globalize_path(out)])
	world.free()
	quit(0)

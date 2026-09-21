extends SceneTree
func _initialize() -> void:
	var m := ParticleProcessMaterial.new()
	print("--- anything with scale in the name ---")
	for p in m.get_property_list():
		if "scale" in String(p.name).to_lower():
			print("  %-34s type %d  hint %s" % [p.name, p.type, p.hint_string])
	quit(0)

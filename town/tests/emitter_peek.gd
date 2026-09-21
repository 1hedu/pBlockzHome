# Prints every GPUParticles3D in the running town and what its process material holds
extends SceneTree
var world: PulseBlockzWorld
var t := 0.0
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)

func _walk(n: Node, out: Array) -> void:
	if n is GPUParticles3D: out.append(n)
	for c in n.get_children(): _walk(c, out)

func _process(delta: float) -> bool:
	t += delta
	if not done and t > 8.0:
		done = true
		var found: Array = []
		_walk(root, found)
		print("  %d GPUParticles3D in the scene" % found.size())
		for p in found:
			var pm = p.process_material
			var sc = pm.scale_curve if pm else null
			print("  %-22s scale_curve %s   scale_min %.2f max %.2f   amount %d"
				% [p.name, ("<null>" if sc == null else sc.get_class()),
				   pm.scale_min if pm else -1, pm.scale_max if pm else -1, p.amount])
			if sc != null and sc.get_class() == "CurveXYZTexture":
				var cx: Curve = sc.curve_x
				var cy: Curve = sc.curve_y
				print("      x max %.2f sample(0.5) %.2f | y max %.2f sample(0.5) %.2f"
					% [cx.max_value, cx.sample(0.5), cy.max_value, cy.sample(0.5)])
		quit(0)
	return false

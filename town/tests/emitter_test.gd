# ParticleEmitter Shape, ShapeStyle, ShapeInOut and VelocityInheritance.
#
#   godot --headless --path . -s res://tests/emitter_test.gd
#
# A Godot emission shape fires every particle the same way, one direction plus a spread, and
# ShapeInOut can send them inward, so anything but a plain box firing outward is built as a
# cloud of starting points each carrying its own direction.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("emitter shapes")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	get_root().add_child(main)
	_run()

func _emitter(named: String) -> GPUParticles3D:
	var stack: Array[Node] = [get_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GPUParticles3D and n.get_parent() != null:
			# The emitter hangs below the part; the part carries the name, so walk up.
			var at: Node = n
			while at != null:
				if at.name == named: return n
				at = at.get_parent()
		for c in n.get_children():
			stack.append(c)
	return null

func _material(named: String) -> ParticleProcessMaterial:
	var e := _emitter(named)
	return e.process_material if e != null else null

func _make(name: String, props: String) -> void:
	world.run_chunk("emitter_probe", '''
local p = workspace:FindFirstChild("%s")
if not p then
	p = Instance.new("Part")
	p.Name = "%s"
	p.Anchored = true
	p.Size = Vector3.new(2, 4, 2)
	p.Position = Vector3.new(0, 80, 0)
	p.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Name = "Puff"
	e.Parent = p
end
local e = p:FindFirstChildOfClass("ParticleEmitter")
%s
''' % [name, name, props])
	await create_timer(0.6).timeout

func _run() -> void:
	await create_timer(3.0).timeout

	# The default -- a filled box firing out of one face -- stays on Godot's native box shape:
	# every emitter in the town is one of these.
	await _make("Plain", "e.Rate = 10")
	var plain := _material("Plain")
	check(plain != null, "an emitter has a process material")
	if plain == null:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	check(plain.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX,
		"a plain box emitter is still a box, drawn the cheap way")

	# Godot has no box-surface shape, so a Surface style has to become a cloud.
	await _make("Skin", "e.Rate = 10 e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface")
	var skin := _material("Skin")
	check(skin != null and skin.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS,
		"asking for a surface builds a cloud, because Godot has no box skin")
	check(skin != null and skin.emission_point_count == 256, "with points to pick from: %d"
		% (skin.emission_point_count if skin != null else -1))

	for shape in ["Cylinder", "Disc", "Sphere"]:
		await _make(shape, "e.Rate = 10 e.Shape = Enum.ParticleEmitterShape.%s" % shape)
		var m := _material(shape)
		check(m != null and m.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS,
			"a %s emitter is a %s and not a box" % [shape.to_lower(), shape.to_lower()])

	# Inward shows up as a direction per point, in the cloud's normals texture.
	await _make("Inward", '''
e.Rate = 10
e.Shape = Enum.ParticleEmitterShape.Sphere
e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
''')
	var inward := _material("Inward")
	check(inward != null and inward.emission_normal_texture != null,
		"an inward emitter carries a direction for every point")

	# VelocityInheritance: how much of the emitter's own motion the sparks leave with.
	await _make("Dragged", "e.Rate = 10 e.VelocityInheritance = 0.75")
	var dragged := _material("Dragged")
	check(dragged != null and absf(dragged.inherit_velocity_ratio - 0.75) < 0.001,
		"a torch carried at a run drags three quarters of its speed into the sparks (%.2f)"
		% (dragged.inherit_velocity_ratio if dragged != null else -1))
	await _make("Dragged", "e.VelocityInheritance = 0")
	check(_material("Dragged").inherit_velocity_ratio == 0.0,
		"and none of it at zero, which is what a standing torch does")

	# The town's own emitters must all still be boxes. Counted rather than asserted one by one,
	# and the count must not be zero, or the check passes by finding nothing.
	var boxes := 0
	var clouds := 0
	var mine := ["Plain", "Skin", "Cylinder", "Disc", "Sphere", "Inward", "Dragged"]
	var stack: Array[Node] = [get_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GPUParticles3D:
			var owned := false
			var at: Node = n
			while at != null:
				if mine.has(String(at.name)): owned = true
				at = at.get_parent()
			var m := (n as GPUParticles3D).process_material as ParticleProcessMaterial
			if not owned and m != null:
				if m.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX: boxes += 1
				elif m.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS: clouds += 1
		for c in n.get_children():
			stack.append(c)
	check(boxes > 0, "the town has emitters of its own to be broken: %d" % boxes)
	check(clouds == 0, "and not one of them was moved onto a cloud (%d)" % clouds)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

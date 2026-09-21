# SunRaysEffect and SpecialMesh.VertexColor, read where they land: an Environment's
# volumetric fog settings and a material's albedo. Whether the shafts look right needs a
# window -- see WINDOWED.md.
#
#   godot --headless --path . -s res://tests/lookfeel_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("sun rays and vertex colour")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	_run()

func _env() -> Environment:
	var w: WorldEnvironment = world.get_node_or_null("Lighting")
	return w.get_environment() if w != null else null

func _material(named: String) -> BaseMaterial3D:
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var at: Node = n
			while at != null:
				if String(at.name) == named:
					return (n as MeshInstance3D).get_material_override() as BaseMaterial3D
				at = at.get_parent()
		for c in n.get_children():
			stack.append(c)
	return null

func _make(body: String) -> void:
	world.run_chunk("look_probe", body)
	await create_timer(0.6).timeout

func _run() -> void:
	await create_timer(3.0).timeout

	var env := _env()
	check(env != null, "there is an environment to light")
	if env == null:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	# ---- sun rays ----------------------------------------------------------------------
	check(not env.volumetric_fog_enabled, "no rays until a place asks for them")
	await _make('''
local fx = Instance.new("SunRaysEffect")
fx.Name = "Shafts"
fx.Intensity = 0.5
fx.Spread = 0
fx.Parent = game:GetService("Lighting")
''')
	check(env.volumetric_fog_enabled, "a SunRaysEffect puts light in the air")
	var tight := env.volumetric_fog_anisotropy
	# Spread is the width of the shafts; anisotropy is how tightly light scatters forward, so
	# the mapping is inverted -- a wide spread is a LOW anisotropy.
	await _make('game:GetService("Lighting").Shafts.Spread = 1')
	check(env.volumetric_fog_anisotropy < tight,
		"a wide spread scatters more broadly than a narrow one (%.2f against %.2f)"
		% [env.volumetric_fog_anisotropy, tight])

	var faint := env.volumetric_fog_density
	await _make('game:GetService("Lighting").Shafts.Intensity = 1')
	check(env.volumetric_fog_density > faint,
		"and turning the intensity up puts more light in the air (%.4f against %.4f)"
		% [env.volumetric_fog_density, faint])

	await _make('game:GetService("Lighting").Shafts:Destroy()')
	check(not env.volumetric_fog_enabled, "taking it away takes the rays with it")

	# ---- VertexColor ---------------------------------------------------------------------
	await _make('''
local p = Instance.new("Part")
p.Name = "Tinted"
p.Anchored = true
p.Size = Vector3.new(4, 4, 4)
p.Position = Vector3.new(0, 120, 0)
p.BrickColor = BrickColor.new("Institutional white")
p.Parent = workspace
local m = Instance.new("SpecialMesh")
m.MeshType = Enum.MeshType.Brick
m.Parent = p
''')
	var plain := _material("Tinted")
	check(plain != null, "a part with a SpecialMesh has a material")
	if plain == null:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	var before := plain.albedo_color
	check(before.r > 0.8 and before.g > 0.8 and before.b > 0.8, "and it is white to start with")

	await _make('workspace.Tinted:FindFirstChildOfClass("SpecialMesh").VertexColor = Vector3.new(1, 0, 0)')
	var red := _material("Tinted")
	check(red != null and red.albedo_color.r > 0.8 and red.albedo_color.g < 0.1 and red.albedo_color.b < 0.1,
		"a red VertexColor makes a white part red without touching its Color: %s"
		% (red.albedo_color if red != null else "none"))

	await _make('workspace.Tinted:FindFirstChildOfClass("SpecialMesh").VertexColor = Vector3.new(1, 1, 1)')
	var back := _material("Tinted")
	check(back != null and back.albedo_color.g > 0.8,
		"and white is no tint at all, which is why it is the default")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

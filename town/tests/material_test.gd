# SurfaceAppearance's maps reach the part's material, and BasePart.MaterialVariant wears a
# MaterialService variant by name. A material is a resource on the mesh instance, not a buffer
# in the renderer, so it all reads back headless; whether a normal map looks bumpy does not.
#
#   godot --headless --path . -s res://tests/material_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var icon := ""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("surfaces")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	_run()

func _id(named: String) -> int:
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var at: int = stack.pop_back()
		for kid in world.get_child_ids(at):
			if world.get_instance(kid).name == named:
				return kid
			stack.append(kid)
	return 0

## The override on the mesh drawn under the part named this.
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
	world.run_chunk("mat_probe", body)
	await create_timer(0.6).timeout

func _run() -> void:
	await create_timer(4.0).timeout

	# A map that does not decode proves nothing, so these use a real image the town publishes.
	var said: Array[String] = []
	world.script_print.connect(func(_n, t): said.append(t))
	world.run_chunk("mat_icon", '''
local rs = game:GetService("ReplicatedStorage")
local a = rs:WaitForChild("PlaceAssets"):WaitForChild("HeartIcon")
print("ICON " .. a.Value)
''')
	await create_timer(1.5).timeout
	for line in said:
		if line.begins_with("ICON "): icon = line.substr(5)
	check(icon != "", "the town ships an image to dress a part with")
	if icon == "":
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	# ---- a plain part, so there is a before to compare against --------------------------
	await _make('''
local p = Instance.new("Part")
p.Name = "Bare"
p.Anchored = true
p.Size = Vector3.new(4, 4, 4)
p.Position = Vector3.new(0, 90, 0)
p.Parent = workspace
''')
	var bare := _material("Bare")
	check(bare != null, "a part has a material")
	if bare == null:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	check(bare.albedo_texture == null, "and nothing on it, because nothing asked")
	check(not bare.normal_enabled, "no normal map either")

	# ---- SurfaceAppearance, hanging under the part ---------------------------------------
	await _make('''
local p = workspace:FindFirstChild("Bare")
local sa = Instance.new("SurfaceAppearance")
sa.ColorMap = "%s"
sa.NormalMap = "%s"
sa.MetalnessMap = "%s"
sa.RoughnessMap = "%s"
sa.Parent = p
''' % [icon, icon, icon, icon])
	var dressed := _material("Bare")
	check(dressed != null and dressed.albedo_texture != null,
		"a SurfaceAppearance's ColorMap becomes what the part is painted with")
	check(dressed != null and dressed.normal_enabled and dressed.normal_texture != null,
		"its NormalMap turns normal mapping on and supplies the picture")
	check(dressed != null and dressed.metallic_texture != null,
		"its MetalnessMap says which parts of it are metal")
	check(dressed != null and dressed.roughness_texture != null, "and its RoughnessMap, how rough")
	# The scalar multiplies the map, so it must be 1 or the Material enum's value caps it.
	check(dressed != null and absf(dressed.roughness - 1.0) < 0.001,
		"with the scalar at 1 so the map decides rather than being capped by it")
	check(dressed != null and absf(dressed.metallic - 1.0) < 0.001, "and the same for metalness")

	await _make('workspace.Bare:FindFirstChildOfClass("SurfaceAppearance"):Destroy()')
	var stripped := _material("Bare")
	check(stripped != null and stripped.albedo_texture == null,
		"taking it off puts the plain surface back rather than leaving the maps behind")

	# ---- MaterialVariant, worn by name ---------------------------------------------------
	await _make('''
local ms = game:GetService("MaterialService")
local v = Instance.new("MaterialVariant")
v.Name = "RustyMetal"
v.BaseMaterial = Enum.Material.Metal
v.ColorMap = "%s"
v.StudsPerTile = 2
v.Parent = ms
local p = workspace:FindFirstChild("Bare")
p.MaterialVariant = "RustyMetal"
''' % icon)
	var mismatched := _material("Bare")
	# Roblox applies a variant only to a part whose Material is the variant's BaseMaterial.
	check(mismatched != null and mismatched.albedo_texture == null,
		"a variant of Metal does nothing to a part made of Plastic")

	await _make('workspace.Bare.Material = Enum.Material.Metal')
	var worn := _material("Bare")
	check(worn != null and worn.albedo_texture != null,
		"and everything once the part is made of the right stuff")
	check(worn != null and absf(worn.uv1_scale.x - 2.0) < 0.01,
		"tiled to StudsPerTile: a 4-stud face at 2 studs a tile repeats twice (%.2f)"
		% (worn.uv1_scale.x if worn != null else -1))
	await _make('game:GetService("MaterialService").RustyMetal.StudsPerTile = 4')
	check(absf((_material("Bare") as BaseMaterial3D).uv1_scale.x - 1.0) < 0.01,
		"and once at four, without the part being touched")

	await _make('workspace.Bare.MaterialVariant = ""')
	check((_material("Bare") as BaseMaterial3D).albedo_texture == null,
		"naming no variant wears none")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

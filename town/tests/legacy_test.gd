# Proves Accessory.AttachmentPos and the three Terrain water properties reach the engine.
#
#   godot --headless --path . -s res://tests/legacy_test.gd
#
# AttachmentPos is the pre-2016 hat attachment Roblox still honours. Water is a shader rather
# than a standard material because WaterWaveSize and WaterWaveSpeed animate it.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("hats and water")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	# Nobody here to sit through the intro: admit players as they join.
	Arrive.now(world)
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

## Where the hat's Handle rides, in the body's own frame. By id, not by walking the scene: a
## scene node takes its part's name, so a second Handle on a character lands as "Handle2".
func _hat() -> Transform3D:
	# Positive ids are the server's character. The wardrobe clones the Accessory onto the
	# client's, so several OldHats exist at once, some of them stale.
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var at: int = stack.pop_back()
		for kid in world.get_child_ids(at):
			if kid > 0 and world.get_instance(kid).name == "OldHat":
				for k in world.get_child_ids(kid):
					if world.get_instance(k).name == "Handle":
						return world.part_offset(k)
			stack.append(kid)
	return Transform3D()

func _make(body: String) -> void:
	world.run_chunk("legacy_probe", body)
	await create_timer(0.7).timeout

func _run() -> void:
	await create_timer(4.0).timeout

	# ---- the hat -----------------------------------------------------------------------
	var head := _id("Head")
	check(head != 0, "there is a head to put a hat on")
	if head == 0:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	# No Attachment child: AttachmentPos is what places the Handle in that shape.
	await _make('''
local ch = game:GetService("Players"):GetPlayers()[1].Character
local hat = Instance.new("Accessory")
hat.Name = "OldHat"
hat.AttachmentPos = Vector3.new(0, 1.5, 0)
local h = Instance.new("Part")
h.Name = "Handle"
h.Size = Vector3.new(2, 1, 2)
h.CanCollide = false
h.Massless = true
h.Parent = hat
hat.Parent = ch
''')
	var worn := _hat()
	check(worn != Transform3D(), "the hat is in the world")
	# The head rides about 1.5 above the root and AttachmentPos adds 1.5, so the hat lands near 3.
	check(worn.origin.y > 2.5 and worn.origin.y < 3.6,
		"and sits above the head where AttachmentPos put it (%.2f)" % worn.origin.y)

	# Re-set it: a value read only when the Accessory is parented passes the check above.
	await _make('''
local ch = game:GetService("Players"):GetPlayers()[1].Character
ch.OldHat.AttachmentPos = Vector3.new(0, 3, 0)
''')
	var moved := _hat()
	check(moved.origin.y > 4.0, "and moves when the offset does (%.2f)" % moved.origin.y)

	# Sideways, so a swapped axis shows up.
	await _make('''
local ch = game:GetService("Players"):GetPlayers()[1].Character
ch.OldHat.AttachmentPos = Vector3.new(2, 1.5, 0)
''')
	var sideways := _hat()
	check(absf(sideways.origin.x - 2.0) < 0.3,
		"two studs to the right is two studs to the right (%.2f)" % sideways.origin.x)

	# ---- the water ---------------------------------------------------------------------
	# The water properties take effect whether or not any water is carved, so carving first
	# here is the test's convenience, not an order the engine requires.
	await _make('''
local t = workspace.Terrain
-- A material with nothing wearing it is not a test. Carve a pool first.
t:FillBlock(CFrame.new(0, -20, 0), Vector3.new(40, 8, 40), Enum.Material.Water)
t.WaterWaveSize = 0
t.WaterWaveSpeed = 4
t.WaterReflectance = 0
''')
	var flat := _water()
	check(flat != null, "the terrain has a water material")
	if flat == null:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	check(float(flat.get_shader_parameter("wave_size")) == 0.0, "asking for no waves gets none")
	# WaterReflectance drives roughness and metallic: 0 is a dull pond, 1 a mirror.
	check(float(flat.get_shader_parameter("rough")) > 0.4, "a pond at reflectance 0 is rough")
	check(float(flat.get_shader_parameter("metal")) < 0.2, "and barely reflects")

	await _make('''
local t = workspace.Terrain
t.WaterWaveSize = 2
t.WaterWaveSpeed = 20
t.WaterReflectance = 1
''')
	check(absf(float(flat.get_shader_parameter("wave_size")) - 2.0) < 0.001, "waves two studs tall")
	check(absf(float(flat.get_shader_parameter("wave_speed")) - 20.0) < 0.001, "travelling at twenty")
	check(float(flat.get_shader_parameter("rough")) < 0.1, "a mirror at reflectance 1 is smooth")
	check(float(flat.get_shader_parameter("metal")) > 0.7, "and reflects")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _water() -> ShaderMaterial:
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var m = (n as MeshInstance3D).get_material_override()
			if m is ShaderMaterial and (m as ShaderMaterial).get_shader_parameter("wave_size") != null:
				return m
			for i in (n as MeshInstance3D).get_surface_override_material_count():
				var sm = (n as MeshInstance3D).get_surface_override_material(i)
				if sm is ShaderMaterial and (sm as ShaderMaterial).get_shader_parameter("wave_size") != null:
					return sm
		for c in n.get_children():
			stack.append(c)
	return null

# A BasePart's SurfaceType becomes geometry: how many studs or inlets a face grows, where they
# sit and which way they stand.
#
#   godot --headless --path . -s res://tests/surface_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("studs and inlets")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	get_root().add_child(main)
	_run()

## Where a part's studs or inlets sit, in part space. Not through the MultiMesh: its transforms
## live in the RenderingServer's buffer, which the headless dummy renderer drops, so a
## set-then-get there returns the identity. The world keeps the same list.
func _pieces(named: String, which: String) -> Array:
	var id := _id(named)
	return world.part_surface_pieces(id, which) if id != 0 else []

## A part by name, anywhere under the Workspace.
func _id(named: String) -> int:
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var at: int = stack.pop_back()
		for kid in world.get_child_ids(at):
			if world.get_instance(kid).name == named:
				return kid
			stack.append(kid)
	return 0

func _make(body: String) -> void:
	world.run_chunk("surface_probe", body)
	await create_timer(0.5).timeout

func _run() -> void:
	await create_timer(2.0).timeout

	# 4 x 1 x 2: a stud per stud of face, so four across the top by two deep.
	await _make('''
local p = Instance.new("Part")
p.Name = "Brick"
p.Anchored = true
p.Size = Vector3.new(4, 1, 2)
p.Position = Vector3.new(0, 50, 0)
p.TopSurface = Enum.SurfaceType.Studs
p.BottomSurface = Enum.SurfaceType.Inlet
for _, f in ipairs({"Left", "Right", "Front", "Back"}) do p[f .. "Surface"] = Enum.SurfaceType.Smooth end
p.Parent = workspace
''')
	var studs := _pieces("Brick", "Studs")
	check(studs.size() > 0, "a studded face grows studs")
	if studs.is_empty():
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	check(studs.size() == 8, "one per stud of face: 4 x 2 is %d" % studs.size())

	var above := 0
	var xs := {}
	var zs := {}
	var upright := true
	for t: Transform3D in studs:
		# The brick is 1 tall, so the top face is y = 0.5: at 0.5 a stud is flush, below it is
		# sunk into the part.
		if t.origin.y > 0.5: above += 1
		xs[snappedf(t.origin.x, 0.01)] = true
		zs[snappedf(t.origin.z, 0.01)] = true
		if t.basis.y.dot(Vector3.UP) < 0.99: upright = false
	check(above == 8, "all eight standing proud of the top face rather than sunk into it (%d)" % above)
	check(xs.size() == 4 and zs.size() == 2,
		"laid out four across and two deep, not stacked in the middle (%d x %d)" % [xs.size(), zs.size()])
	check(xs.has(-1.5) and xs.has(1.5), "the outer columns half a stud in from each edge")
	check(upright, "each standing out of the face rather than lying along it")

	var inlets := _pieces("Brick", "Inlets")
	check(inlets.size() == 8, "and the underside wears eight inlets")
	var below := 0
	for t: Transform3D in inlets:
		# An inlet is the rim of a hole: it lies in the face, so its origin is on it exactly.
		if absf(t.origin.y + 0.5) < 0.001: below += 1
	check(below == 8, "each lying flush in the bottom face (%d)" % below)

	# Roblox draws no stud on a face narrower than one stud rather than one overhanging the edge.
	await _make('''
local p = Instance.new("Part")
p.Name = "Sliver"
p.Anchored = true
p.Size = Vector3.new(0.4, 1, 0.4)
p.Position = Vector3.new(20, 50, 0)
p.TopSurface = Enum.SurfaceType.Studs
p.Parent = workspace
''')
	check(_pieces("Sliver", "Studs").is_empty(), "a face too small for a stud gets none")

	# A resize rebuilds the shape, and the grid follows it.
	await _make('local p = workspace:FindFirstChild("Brick") p.Size = Vector3.new(8, 1, 2)')
	var grown := _pieces("Brick", "Studs")
	check(grown.size() == 16, "twice as wide is twice as many: %d" % grown.size())

	await _make('''
local p = workspace:FindFirstChild("Brick")
p.TopSurface = Enum.SurfaceType.Smooth
p.BottomSurface = Enum.SurfaceType.Smooth
''')
	check(_pieces("Brick", "Studs").is_empty(), "smoothing a face takes its studs off")
	check(_pieces("Brick", "Inlets").is_empty(), "and its inlets")

	# The joint-making surfaces -- Weld, Glue, Hinge, Motor, Universal -- render smooth in Roblox.
	await _make('''
local p = workspace:FindFirstChild("Brick")
p.TopSurface = Enum.SurfaceType.Weld
''')
	check(_pieces("Brick", "Studs").is_empty(), "a Weld surface is smooth, as it is in Roblox")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

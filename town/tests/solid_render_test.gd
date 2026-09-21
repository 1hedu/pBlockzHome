# Solid modelled parts: what a union draws and what physics collides with. Held to Roblox's
# solid-modeling reference -- CollisionFidelity, RenderFidelity, SmoothingAngle, box-mapped UVs,
# and a Decal laid on a union from one direction.
#
#   godot --headless --path . -s res://tests/solid_render_test.gd
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

const SCRIPT := """
local GeometryService = game:GetService("GeometryService")
local AssetService = game:GetService("AssetService")
local function say(k, v) print("C " .. k .. " " .. tostring(v)) end
local function block(size, at, color, shape)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = CFrame.new(at)
	p.Anchored = true
	if color then p.Color = color end
	if shape then p.Shape = shape end
	p.Parent = workspace
	return p
end

-- U-shaped unions, one per fidelity, each with a ball over its notch
local fidelities = { "Default", "Hull", "Box", "PreciseConvexDecomposition", "Tunable" }
for i, name in ipairs(fidelities) do
	local x = (i - 3) * 14
	local base = block(Vector3.new(8, 6, 8), Vector3.new(x, 206, 0))
	local notch = block(Vector3.new(4, 5, 10), Vector3.new(x, 208, 0))
	local u = base:SubtractAsync({ notch }, Enum.CollisionFidelity[name])
	notch:Destroy(); base:Destroy()
	u.Name = "U" .. name
	u.Anchored = true
	u.Parent = workspace
	local ball = Instance.new("Part")
	ball.Name = "Ball" .. name
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(2, 2, 2)
	ball.CFrame = CFrame.new(x, 216, 0)
	ball.Parent = workspace
end

-- SmoothingAngle and colours: a red ball and a blue ball, one union
local red = block(Vector3.new(4, 4, 4), Vector3.new(0, 150, 40), Color3.new(1, 0, 0), Enum.PartType.Ball)
local blue = block(Vector3.new(4, 4, 4), Vector3.new(2, 150, 40), Color3.new(0, 0, 1), Enum.PartType.Ball)
local balls = red:UnionAsync({ blue })
red:Destroy(); blue:Destroy()
balls.Name = "Balls"
balls.Parent = workspace

-- Box UVs: a plain slab
local slabA = block(Vector3.new(4, 1, 2), Vector3.new(20, 150, 40))
local slab = slabA:UnionAsync({ block(Vector3.new(1, 1, 1), Vector3.new(20, 150, 40)) })
slabA:Destroy()
slab.Name = "Slab"
slab.Parent = workspace

-- A decal on a holed union's front
local plate = block(Vector3.new(6, 6, 1), Vector3.new(40, 150, 40))
local drill = block(Vector3.new(1, 2, 2), Vector3.new(40, 150, 40), nil, Enum.PartType.Cylinder)
drill.CFrame = CFrame.new(40, 150, 40) * CFrame.Angles(0, math.rad(90), 0)
local holed = plate:SubtractAsync({ drill })
plate:Destroy(); drill:Destroy()
holed.Name = "Holed"
holed.Parent = workspace
local d = Instance.new("Decal")
d.Name = "OnHoled"
d.Face = Enum.NormalId.Front
d.ColorMapContent = Content.fromUri("res://splash.png")
d.Parent = holed

-- A MeshPart result: the skull, cut
local skull = AssetService:CreateMeshPartAsync(Content.fromUri("res://../../../scripts/models/steven-face.obj"))
skull.Anchored = true
skull.CFrame = CFrame.new(60, 150, 40)
skull.Parent = workspace
local cutter = block(Vector3.new(0.6, 0.6, 2), Vector3.new(60, 150, 40))
local cut = GeometryService:SubtractAsync(skull, { cutter }, { SplitApart = false })
cutter:Destroy()
local cutPart = cut[1]
cutPart.Name = "CutSkull"
cutPart.Parent = workspace
say("CUTCLASS", cutPart.ClassName)

-- RenderFidelity: one union of many triangles, Automatic and Precise
local sphere = block(Vector3.new(6, 6, 6), Vector3.new(0, 150, 300), nil, Enum.PartType.Ball)
local auto = sphere:UnionAsync({ block(Vector3.new(1, 1, 1), Vector3.new(0, 150, 300)) })
auto.Name = "LodAuto"
auto.Parent = workspace
local sphere2 = block(Vector3.new(6, 6, 6), Vector3.new(12, 150, 300), nil, Enum.PartType.Ball)
local precise = sphere2:UnionAsync({ block(Vector3.new(1, 1, 1), Vector3.new(12, 150, 300)) }, Enum.CollisionFidelity.Default, Enum.RenderFidelity.Precise)
precise.Name = "LodPrecise"
precise.Parent = workspace
sphere:Destroy(); sphere2:Destroy()
local perf = AssetService:CreateMeshPartAsync(Content.fromUri("res://../../../scripts/models/tree-canopy.obj"), { RenderFidelity = Enum.RenderFidelity.Performance })
perf.Name = "LodPerformance"
perf.Anchored = true
perf.CFrame = CFrame.new(24, 150, 300)
perf.Parent = workspace
say("DONE", "ok")
"""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _c(key: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		var s := String(said[i])
		if s.begins_with("C " + key + " "): return s.substr(("C " + key + " ").length())
	return ""

func _child(parent: int, name: String) -> int:
	for id in world.get_child_ids(parent):
		if world.get_instance(id).get("name", "") == name: return id
	return 0

func _ws(name: String) -> int:
	return _child(_child(0, "Workspace"), name)

func _mesh_of(name: String) -> Mesh:
	var id := _ws(name)
	var mi = world.get_part_mesh(id) if id != 0 else null
	return mi.mesh if mi is MeshInstance3D else null

func _triangles(m: Mesh) -> int:
	if m == null: return -1
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		n += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
	return n

func _hulls(name: String) -> Array:
	var id := _ws(name)
	var body = world.get_part_node(id) if id != 0 else null
	var out := []
	if body == null: return out
	for c in body.get_children():
		if c is CollisionShape3D and c.shape != null: out.append(c.shape)
	return out

func _ball_y(name: String) -> float:
	var id := _ws(name)
	for p in world.get_properties(id, true):
		if p.name == "Position": return p.value.y
	return -1.0

func _look_from(pos: Vector3, at: Vector3) -> void:
	world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(Vector3.new(%f, %f, %f), Vector3.new(%f, %f, %f))
""" % [pos.x, pos.y, pos.z, at.x, at.y, at.z])

var flat_at_zero := -1.0
func _corner_deviation(name: String) -> float:
	var m := _mesh_of(name)
	if m == null: return -1.0
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var worst := 0.0
	for tri in range(0, v.size() - 2, 3):
		var fn := (v[tri + 2] - v[tri]).cross(v[tri + 1] - v[tri]).normalized()
		for k in 3: worst = max(worst, rad_to_deg(fn.angle_to(n[tri + k])))
	return worst

var near_auto := 0
var near_precise := 0
var high_perf := 0
var far_t := 0.0

func _initialize() -> void:
	print("solid modelled parts: drawing and collision")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): errors.append("%s: %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 2.0:
		phase = 1; t = 0.0
		world.run_chunk("solids", SCRIPT)
	elif phase == 1 and (_c("DONE") == "ok" or not errors.is_empty() or t > 40.0) and t > 1.0:
		phase = 2; t = 0.0
		_look_from(Vector3(0, 155, 320), Vector3(0, 150, 300))   # inside 250 studs: Automatic is Highest
	elif phase == 2 and t > 1.0:
		near_auto = _triangles(_mesh_of("LodAuto"))
		near_precise = _triangles(_mesh_of("LodPrecise"))
		phase = 3; t = 0.0
		_look_from(Vector3(0, 155, 950), Vector3(0, 150, 300))   # past 500 studs: Automatic is Lowest
	elif phase == 3 and t > 4.0:
		phase = 4; t = 0.0
		flat_at_zero = _corner_deviation("Balls")
		world.run_chunk("smooth", "workspace.Balls.SmoothingAngle = 60")
	elif phase == 4 and t > 1.0:
		phase = 5
		_finish()
	return false

func _finish() -> void:
	# ---- collision, by where a dropped ball settles ----
	var top := 209.0     # the U's top face; its notch floor is at 206
	for f in ["Default", "PreciseConvexDecomposition", "Tunable"]:
		var y := _ball_y("Ball" + f)
		check(y > 200 and y < top - 0.5, "%s: the ball settles down in the notch (y %.2f, top %.1f)" % [f, y, top])
		check(_hulls("U" + f).size() >= 2, "%s is a decomposition: %d convex hulls" % [f, _hulls("U" + f).size()])
	for f in ["Hull", "Box"]:
		var y := _ball_y("Ball" + f)
		check(y >= top + 0.5, "%s: the ball rests on top, the notch filled in (y %.2f)" % [f, y])
		check(_hulls("U" + f).size() == 1, "%s is one convex shape: %d" % [f, _hulls("U" + f).size()])
	var box: Array = _hulls("UBox")
	check(box.size() == 1 and box[0] is ConvexPolygonShape3D and box[0].points.size() == 8, "Box: the eight corners of the bounds")

	# ---- level of detail ----
	var far_auto := _triangles(_mesh_of("LodAuto"))
	var far_precise := _triangles(_mesh_of("LodPrecise"))
	check(near_auto > 400 and far_auto > 0 and far_auto <= near_auto / 3, "Automatic: highest up close, lowest past 500 studs: %d then %d triangles" % [near_auto, far_auto])
	check(near_precise == far_precise and near_precise > 400, "Precise: the highest at any distance: %d and %d" % [near_precise, far_precise])
	var perf_mesh := _mesh_of("LodPerformance")
	var file_tris := 0
	var canopy := load_obj_triangles()
	check(_triangles(perf_mesh) > 0 and _triangles(perf_mesh) < canopy, "Performance: the lowest even up close: %d of the file's %d" % [_triangles(perf_mesh), canopy])

	# ---- smoothing and colour ----
	var balls := _mesh_of("Balls")
	var seam_ok := true
	var smoothed_somewhere := false
	if balls != null:
		var a := balls.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var c: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var at := {}
		for i in v.size():
			var key := "%d,%d,%d" % [roundi(v[i].x * 1000), roundi(v[i].y * 1000), roundi(v[i].z * 1000)]
			if not at.has(key): at[key] = []
			at[key].append(i)
		for key in at:
			var group: Array = at[key]
			var colours := {}
			var normals := {}
			for i in group:
				colours[c[i].to_html()] = true
				normals["%d,%d,%d" % [roundi(n[i].x * 100), roundi(n[i].y * 100), roundi(n[i].z * 100)]] = true
			if colours.size() == 2 and normals.size() < 2: seam_ok = false
			if colours.size() == 1 and group.size() >= 3 and normals.size() == 1: smoothed_somewhere = true
	check(flat_at_zero >= 0 and flat_at_zero < 0.5, "SmoothingAngle 0, the default: every corner shows its own face's normal (worst %.2f degrees off)" % flat_at_zero)
	var smoothed := _corner_deviation("Balls")
	check(smoothed > 2.0, "SmoothingAngle 60: the ball's corners are smoothed across their neighbours (up to %.1f degrees off their faces)" % smoothed)
	check(balls != null and seam_ok, "and where red meets blue the two keep their own normals")

	# ---- box UVs: a PartOperation is always boxmapped ----
	var slab := _mesh_of("Slab")
	var corner_uv = null
	if slab != null:
		var a := slab.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		for tri in range(0, v.size() - 2, 3):
			var fn := (v[tri + 2] - v[tri]).cross(v[tri + 1] - v[tri])
			if fn.normalized().y < 0.9: continue
			for k in 3:
				if v[tri + k].distance_to(Vector3(2, 0.5, -1)) < 0.01: corner_uv = uv[tri + k]
	check(corner_uv != null and corner_uv.distance_to(Vector2(1, 0)) < 0.01, "a union's top face is box-mapped: its corner (2, 0.5, -1) at UV (1, 0), as on a box: %s" % str(corner_uv))

	# ---- a MeshPart result keeps the main part's UVs, (0, 0) for faces from the others ----
	var cut := _mesh_of("CutSkull")
	var zero := 0
	var mapped := 0
	if cut != null:
		var a := cut.surface_get_arrays(0)
		for u in a[Mesh.ARRAY_TEX_UV]:
			if u == Vector2.ZERO: zero += 1
			else: mapped += 1
	check(_c("CUTCLASS") == "MeshPart", "cutting a MeshPart with GeometryService gives a MeshPart")
	check(mapped > 100 and zero > 0, "it keeps the skull's UVs, and the faces the cutter left are (0, 0): %d mapped, %d at zero" % [mapped, zero])

	# ---- a decal on a holed union ----
	var holed_id := _ws("Holed")
	var holed_mesh = world.get_part_mesh(holed_id) if holed_id != 0 else null
	var decal: MeshInstance3D = holed_mesh.get_node_or_null("OnHoled") if holed_mesh != null else null
	var covers_hole := false
	var faces_front := true
	var count := 0
	if decal != null and decal.mesh != null and not (decal.mesh is QuadMesh):
		var a: Array = decal.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		count = v.size() / 3
		for tri in range(0, v.size() - 2, 3):
			var fn := (v[tri + 2] - v[tri]).cross(v[tri + 1] - v[tri]).normalized()
			if fn.z > -0.9: faces_front = false
			if _inside(Vector2(0, 0), Vector2(v[tri].x, v[tri].y), Vector2(v[tri + 1].x, v[tri + 1].y), Vector2(v[tri + 2].x, v[tri + 2].y)): covers_hole = true
	check(count > 0 and faces_front, "a Decal on a union is laid on the faces that face its Face: %d triangles" % count)
	check(count > 0 and not covers_hole, "so the hole through that face stays a hole")
	check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _inside(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p - b).cross(a - b)
	var d2 := (p - c).cross(b - c)
	var d3 := (p - a).cross(c - a)
	return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))

func load_obj_triangles() -> int:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../../../scripts/models/tree-canopy.obj"))
	var n := 0
	for line in text.split("\n"):
		if line.begins_with("f "): n += line.substr(2).strip_edges().split(" ", false).size() - 2
	return n

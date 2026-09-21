# EditableMesh and AssetService's CreateEditableMesh / CreateEditableMeshAsync /
# CreateMeshPartAsync, held to the class reference in creator-docs classes/EditableMesh.yaml.
# Everything is asked of the sharp cube that reference builds.
#
#   godot --headless --path . -s res://tests/editable_mesh_test.gd
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

const SKULL := "res://../../../scripts/models/steven-skull.obj"

const SCRIPT := """
local AssetService = game:GetService("AssetService")
local function say(k, v) print("C " .. k .. " " .. tostring(v)) end
local function msg(f) local ok, e = pcall(f) return ok and "ok" or tostring(e):gsub("^.-:%%d+: ", "") end
local function v3(v) return ("%%.2f,%%.2f,%%.2f"):format(v.X, v.Y, v.Z) end

-- The reference's sharp cube, word for word
local function addSharpQuad(editableMesh, vid0, vid1, vid2, vid3)
	local nid = editableMesh:AddNormal()
	local fid1 = editableMesh:AddTriangle(vid0, vid1, vid2)
	editableMesh:SetFaceNormals(fid1, {nid, nid, nid})
	local fid2 = editableMesh:AddTriangle(vid0, vid2, vid3)
	editableMesh:SetFaceNormals(fid2, {nid, nid, nid})
end
local function makeSharpCube()
	local editableMesh = AssetService:CreateEditableMesh()
	local v1 = editableMesh:AddVertex(Vector3.new(0, 0, 0))
	local v2 = editableMesh:AddVertex(Vector3.new(1, 0, 0))
	local v3_ = editableMesh:AddVertex(Vector3.new(0, 1, 0))
	local v4 = editableMesh:AddVertex(Vector3.new(1, 1, 0))
	local v5 = editableMesh:AddVertex(Vector3.new(0, 0, 1))
	local v6 = editableMesh:AddVertex(Vector3.new(1, 0, 1))
	local v7 = editableMesh:AddVertex(Vector3.new(0, 1, 1))
	local v8 = editableMesh:AddVertex(Vector3.new(1, 1, 1))
	addSharpQuad(editableMesh, v5, v6, v8, v7) -- Front
	addSharpQuad(editableMesh, v1, v3_, v4, v2) -- Back
	addSharpQuad(editableMesh, v1, v5, v7, v3_) -- Left
	addSharpQuad(editableMesh, v2, v4, v8, v6) -- Right
	addSharpQuad(editableMesh, v1, v2, v6, v5) -- Bottom
	addSharpQuad(editableMesh, v3_, v7, v8, v4) -- Top
	editableMesh:RemoveUnused()
	return editableMesh
end
local cube = makeSharpCube()
say("OBJECT", typeof(cube) .. " " .. cube.ClassName .. " " .. tostring(cube.FixedSize) .. " " .. (msg(function() return Instance.new("EditableMesh") end):match("Unable") and "notnew" or "new"))
say("COUNTS", ("%%d %%d %%d %%d %%d"):format(#cube:GetVertices(), #cube:GetFaces(), #cube:GetNormals(), #cube:GetUVs(), #cube:GetColors()))
say("BOUNDS", v3(cube:GetSize()) .. " " .. v3(cube:GetCenter()))
local front = cube:GetFaces()[1]
say("FRONTNORMAL", v3(cube:GetNormal(cube:GetFaceNormals(front)[1])))
local topFaces = cube:GetFaces()
say("SHARP", tostring(cube:GetFaceNormals(topFaces[1])[1] ~= cube:GetFaceNormals(topFaces[3])[1]))
say("IDSTRING", cube:IdDebugString(cube:GetVertices()[1]) .. " " .. cube:IdDebugString(front))

-- Split attributes: a second triangle on the same vertices reuses their attribute ids
local m = AssetService:CreateEditableMesh()
local a, b, c, d = m:AddVertex(Vector3.new(0, 0, 0)), m:AddVertex(Vector3.new(1, 0, 0)), m:AddVertex(Vector3.new(1, 1, 0)), m:AddVertex(Vector3.new(0, 1, 0))
local f1 = m:AddTriangle(a, b, c)
local f2 = m:AddTriangle(a, c, d)
say("REUSE", tostring(m:GetFaceNormals(f1)[1] == m:GetFaceNormals(f2)[1]) .. " " .. tostring(m:GetFaceUVs(f1)[3] == m:GetFaceUVs(f2)[2]) .. " " .. #m:GetNormals())
say("DEFAULTS", v3(m:GetNormal(m:GetFaceNormals(f1)[1])) .. " " .. tostring(m:GetUV(m:GetFaceUVs(f1)[1])) .. " " .. tostring(m:GetColor(m:GetFaceColors(f1)[1])) .. " " .. m:GetColorAlpha(m:GetFaceColors(f1)[1]))
-- Stable ids
m:RemoveFace(f1)
say("STABLE", tostring(#m:GetFaces() == 1 and m:GetFaces()[1] == f2) .. " " .. msg(function() return m:GetFaceVertices(f1) end))
local removed = m:RemoveUnused()
say("UNUSED", #removed)
say("VERTEXFACES", #m:GetVertexFaces(a) .. " " .. #cube:GetAdjacentVertices(cube:GetVertices()[1]) .. " " .. #cube:GetAdjacentFaces(front))
say("ADJACENTFACES", #cube:GetAdjacentFaces(front))

-- Queries
local fid, point, bary = cube:RaycastLocal(Vector3.new(0.25, 0.5, 5), Vector3.new(0, 0, -10))
say("RAY", tostring(fid ~= nil) .. " " .. (point and v3(point) or "nil") .. " " .. (bary and ("%%.2f"):format(bary.X + bary.Y + bary.Z) or "nil"))
say("RAYSHORT", tostring(cube:RaycastLocal(Vector3.new(0.25, 0.5, 5), Vector3.new(0, 0, -1)) == nil))
local cf, cp = cube:FindClosestPointOnSurface(Vector3.new(0.5, 0.5, 3))
say("CLOSEST", tostring(cf ~= nil) .. " " .. v3(cp))
say("NEARVERT", v3(cube:GetPosition(cube:FindClosestVertex(Vector3.new(0.9, 1.2, 1.1)))))
say("SPHERE", #cube:FindVerticesWithinSphere(Vector3.new(0, 0, 0), 1.05))

-- Batches
local bm = AssetService:CreateEditableMesh()
local vids = bm:BatchAdd(Enum.MeshAttribute.Vertex, { Vector3.new(0, 0, 0), Vector3.new(2, 0, 0), Vector3.new(0, 2, 0), Vector3.new(2, 2, 0) })
local fids = bm:BatchAdd(Enum.MeshAttribute.Face, { { vids[1], vids[2], vids[3] }, { vids[2], vids[4], vids[3] } })
local positions = bm:BatchGetValues(vids)
say("BATCHADD", #vids .. " " .. #fids .. " " .. v3(positions[4]))
bm:BatchSetValues({ vids[4] }, { Vector3.new(3, 3, 0) })
local cids = bm:BatchAdd(Enum.MeshAttribute.Color, { Color3.new(1, 0, 0), Color3.new(0, 1, 0) }, { 0.5, 1 })
local cols, alphas = bm:BatchGetValues(cids)
say("BATCHCOLOR", tostring(cols[1]) .. " " .. tostring(alphas[1]) .. " " .. v3(bm:GetPosition(vids[4])))
bm:BatchSetFaceAttributes({ fids[1] }, { { cids[1], cids[1], cids[2] } })
local corners = bm:BatchGetFaceAttributes(Enum.MeshAttribute.Color, { fids[1] })
say("BATCHFACE", tostring(corners[1][3] == cids[2]))
local around = bm:BatchGetVertexAttributes(Enum.MeshAttribute.Face, { vids[2] })
say("BATCHVERTEX", #around[1])
bm:BatchSetVertexFaceAttributes({ vids[1] }, { fids[1] }, { cids[2] })
say("BATCHCORNER", tostring(bm:BatchGetVertexFaceAttributes(Enum.MeshAttribute.Color, { vids[1] }, { fids[1] })[1] == cids[2]))
say("BATCHMIX", msg(function() bm:BatchGetValues({ vids[1], cids[1] }) end) ~= "ok")
bm:BatchRemove({ fids[2] })
say("BATCHREMOVE", #bm:GetFaces())
bm:BatchSetValues(bm:GetFaceNormals(fids[1]), nil)

-- Bones and FACS
local bones = AssetService:CreateEditableMesh()
local root = bones:AddBone({ Name = "Root", CFrame = CFrame.new(0, 1, 0) })
local jaw = bones:AddBone({ Name = "Jaw", ParentId = root, Virtual = true })
say("BONES", bones:GetBoneName(jaw) .. " " .. tostring(bones:GetBoneParent(jaw) == root) .. " " .. tostring(bones:GetBoneIsVirtual(jaw)) .. " " .. v3(bones:GetBoneCFrame(root).Position) .. " " .. tostring(bones:GetBoneByName("Jaw") == jaw))
say("BONEDUP", msg(function() bones:AddBone({ Name = "Root" }) end) ~= "ok")
say("BONECYCLE", msg(function() bones:SetBoneParent(root, jaw) end) ~= "ok")
local bv = bones:AddVertex(Vector3.zero)
bones:SetVertexBones(bv, { root, jaw })
bones:SetVertexBoneWeights(bv, { 0.25, 0.75 })
say("SKIN", #bones:GetVertexBones(bv) .. " " .. bones:GetVertexBoneWeights(bv)[2])
bones:SetFacsPose(Enum.FacsActionUnit.JawDrop, { jaw }, { CFrame.new(0, -0.2, 0) })
local ids, cframes = bones:GetFacsPose(Enum.FacsActionUnit.JawDrop)
say("FACS", #ids .. " " .. v3(cframes[1].Position) .. " " .. tostring(bones:GetFacsPoses()[1]))
say("FACSVIRTUAL", msg(function() bones:SetFacsPose(Enum.FacsActionUnit.Pucker, { root }, { CFrame.new() }) end) ~= "ok")
bones:SetFacsCorrectivePose({ Enum.FacsActionUnit.JawDrop, Enum.FacsActionUnit.Pucker }, { jaw }, { CFrame.new(0, 0, 1) })
say("CORRECTIVE", #bones:GetFacsCorrectivePoses() .. " " .. #bones:GetFacsCorrectivePoses()[1])
bones:RemoveBone(root)
say("REMOVEBONE", #bones:GetBones() .. " " .. #bones:GetVertexBones(bv) .. " " .. tostring(bones:GetBoneParent(jaw)))

-- Limits and fixed size
local big = AssetService:CreateEditableMesh()
local lots = table.create(60000)
for i = 1, 60000 do lots[i] = Vector3.new(i, 0, 0) end
big:BatchAdd(Enum.MeshAttribute.Vertex, lots)
say("VERTEXLIMIT", msg(function() big:AddVertex(Vector3.zero) end))
local fromFile = AssetService:CreateEditableMeshAsync(Content.fromUri("%s"))
say("FROMFILE", tostring(fromFile.FixedSize) .. " " .. tostring(#fromFile:GetVertices() > 100) .. " " .. v3(fromFile:GetSize()))
say("FIXED", msg(function() fromFile:AddVertex(Vector3.zero) end) .. " | " .. msg(function() fromFile:SetPosition(fromFile:GetVertices()[1], Vector3.zero) end))
local loose = AssetService:CreateEditableMeshAsync(Content.fromUri("%s"), { FixedSize = false })
say("LOOSE", tostring(loose.FixedSize) .. " " .. msg(function() loose:AddVertex(Vector3.zero) end))
local copied = AssetService:CreateEditableMeshAsync(Content.fromObject(cube), { FixedSize = false })
copied:SetPosition(copied:GetVertices()[1], Vector3.new(-5, 0, 0))
say("COPY", v3(cube:GetSize()) .. " " .. v3(copied:GetSize()))

-- A MeshPart on it, drawn and then edited live
local shown = AssetService:CreateMeshPartAsync(Content.fromObject(cube))
shown.Name = "Cube"
shown.Anchored = true
shown.CFrame = CFrame.new(0, 100, 0)
shown.Parent = workspace
say("PART", v3(shown.Size) .. " " .. tostring(shown.MeshContent.Object == cube) .. " " .. tostring(shown.MeshId))
for _, cid in ipairs(cube:GetColors()) do cube:SetColor(cid, Color3.new(1, 0, 0)) end
say("DONE1", "ok")
"""

# Split here so the host gets frames to draw the first half before the edit is measured
const SCRIPT2 := """
local AssetService = game:GetService("AssetService")
local function say(k, v) print("C " .. k .. " " .. tostring(v)) end
local function msg(f) local ok, e = pcall(f) return ok and "ok" or tostring(e):gsub("^.-:%d+: ", "") end
local function v3(v) return ("%.2f,%.2f,%.2f"):format(v.X, v.Y, v.Z) end
local shown = workspace.Cube
local cube = shown.MeshContent.Object
-- stretch one corner out: drawn at once, collided with only once applied again
local far = cube:FindClosestVertex(Vector3.new(1, 1, 1))
cube:SetPosition(far, Vector3.new(3, 1, 1))
say("EDITED", "ok")
"""

const SCRIPT3 := """
local AssetService = game:GetService("AssetService")
local function say(k, v) print("C " .. k .. " " .. tostring(v)) end
local function msg(f) local ok, e = pcall(f) return ok and "ok" or tostring(e):gsub("^.-:%d+: ", "") end
local function v3(v) return ("%.2f,%.2f,%.2f"):format(v.X, v.Y, v.Z) end
local shown = workspace.Cube
local cube = shown.MeshContent.Object
local again = AssetService:CreateMeshPartAsync(Content.fromObject(cube))
shown:ApplyMesh(again)
say("APPLIED", "ok")

-- Baked
local result, baked = AssetService:CreateDataModelContentAsync(Content.fromObject(cube))
local fromBaked = AssetService:CreateMeshPartAsync(baked)
local back = AssetService:CreateEditableMeshAsync(baked)
say("BAKED", tostring(result) .. " " .. tostring(baked.SourceType) .. " " .. v3(fromBaked.Size) .. " " .. #back:GetFaces() .. " " .. tostring(back.FixedSize))
say("BAKEDNOTIMAGE", msg(function() Instance.new("ImageLabel").ImageContent = baked end) ~= "ok")

-- Projection: a red decal straight onto a quad whose UVs cover the whole texture
local quad = AssetService:CreateEditableMesh()
local q = quad:BatchAdd(Enum.MeshAttribute.Vertex, { Vector3.new(-1, -1, 0), Vector3.new(1, -1, 0), Vector3.new(1, 1, 0), Vector3.new(-1, 1, 0) })
local qf = quad:BatchAdd(Enum.MeshAttribute.Face, { { q[1], q[2], q[3] }, { q[1], q[3], q[4] } })
local uvs = quad:BatchAdd(Enum.MeshAttribute.UV, { Vector2.new(0, 1), Vector2.new(1, 1), Vector2.new(1, 0), Vector2.new(0, 0) })
quad:BatchSetFaceAttributes(qf, { { uvs[1], uvs[2], uvs[3] }, { uvs[1], uvs[3], uvs[4] } })
local texture = AssetService:CreateEditableImage({ Size = Vector2.new(16, 16) })
local decal = AssetService:CreateEditableImage({ Size = Vector2.new(4, 4) })
decal:DrawRectangle(Vector2.zero, Vector2.new(4, 4), Color3.new(1, 0, 0), 0, Enum.ImageCombineType.Overwrite)
texture:DrawImageProjected(quad,
	{ Position = Vector3.new(0, 0, 2), Direction = Vector3.new(0, 0, -1), Up = Vector3.new(0, 1, 0), Size = Vector3.new(1, 1, 4) },
	{ Decal = decal, ColorBlendType = Enum.ImageCombineType.Overwrite, AlphaBlendType = Enum.ImageAlphaType.Default, FadeAngle = 90, BlendIntensity = 1 })
local function px(img, x, y) local b = img:ReadPixelsBuffer(Vector2.new(x, y), Vector2.one) return ("%d,%d,%d,%d"):format(buffer.readu8(b, 0), buffer.readu8(b, 1), buffer.readu8(b, 2), buffer.readu8(b, 3)) end
say("PROJECTED", px(texture, 8, 8) .. " " .. px(texture, 1, 1))
local sample = AssetService:CreateEditableImage({ Size = Vector2.new(4, 4) })
sample:SampleImageProjected(quad, texture,
	{ Position = Vector3.new(0, 0, 2), Direction = Vector3.new(0, 0, -1), Up = Vector3.new(0, 1, 0), Size = Vector3.new(1, 1, 4) },
	{ ColorBlendType = Enum.ImageCombineType.Overwrite, AlphaBlendType = Enum.ImageAlphaType.Default, FadeAngle = 180 })
say("SAMPLED", px(sample, 1, 1))

-- Destroy
local gone = AssetService:CreateEditableMesh()
gone:Destroy()
say("DESTROYED", msg(function() gone:AddVertex(Vector3.zero) end))
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

func _cube_mesh() -> MeshInstance3D:
	var id := _child(_child(0, "Workspace"), "Cube")
	var node = world.get_part_mesh(id) if id != 0 else null
	return node if node is MeshInstance3D else null

func _collision_extent() -> float:
	var id := _child(_child(0, "Workspace"), "Cube")
	var body = world.get_part_node(id) if id != 0 else null
	if body == null: return -1.0
	for child in body.get_children():
		if child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
			# the hull is fitted to Size, so its widest point never moves; the mean x does
			var sum := 0.0
			for p in child.shape.points: sum += p.x
			return sum / max(child.shape.points.size(), 1)
	return -1.0

var drawn_x := 0.0
var collide_before := 0.0
var skull_size := Vector3()

func _initialize() -> void:
	print("EditableMesh")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): errors.append("%s: %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../../../scripts/models/steven-skull.obj"))
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for line in text.split("\n"):
		if line.begins_with("v "):
			var p := line.substr(2).strip_edges().split(" ", false)
			var v := Vector3(float(p[0]), float(p[1]), float(p[2]))
			lo = lo.min(v); hi = hi.max(v)
	skull_size = hi - lo

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 2.0:
		phase = 1; t = 0.0
		world.run_chunk("mesh1", SCRIPT % [SKULL, SKULL])
	elif phase == 1 and (_c("DONE1") == "ok" or not errors.is_empty() or t > 30.0) and t > 1.5:
		phase = 2; t = 0.0
		var mi := _cube_mesh()
		drawn_x = mi.mesh.get_aabb().size.x if mi != null and mi.mesh != null else -1.0
		collide_before = _collision_extent()
		world.run_chunk("mesh2", SCRIPT2)
	elif phase == 2 and t > 1.5:
		phase = 3; t = 0.0
		var mi := _cube_mesh()
		var edited_x: float = mi.mesh.get_aabb().size.x if mi != null and mi.mesh != null else -1.0
		check(abs(drawn_x - 1.0) < 0.01, "the host draws the cube at its Size: %.2f" % drawn_x)
		var mat = mi.material_override if mi != null else null
		if mat == null and mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0: mat = mi.get_active_material(0)
		check(mat is BaseMaterial3D and mat.vertex_color_use_as_albedo, "with its corners' colours")
		check(abs(edited_x - 3.0) < 0.01, "an edit is drawn at once, at the scale it was applied with: the corner pulled out to x 3 draws 3 wide (%.2f)" % edited_x)
		var collide_after := _collision_extent()
		check(collide_before > -1.0 and abs(collide_after - collide_before) < 0.001, "while collision keeps the shape it was applied with: %.3f then %.3f" % [collide_before, collide_after])
		world.run_chunk("mesh3", SCRIPT3)
		collide_before = collide_after
	elif phase == 3 and (_c("DONE") == "ok" or not errors.is_empty() or t > 30.0) and t > 1.5:
		phase = 4
		var collide_applied := _collision_extent()
		check(collide_applied > -1.0 and abs(collide_applied - collide_before) > 0.05, "ApplyMesh brings the collision up to the edit: %.3f to %.3f" % [collide_before, collide_applied])
		check(_c("OBJECT") == "Object EditableMesh false notnew", "an EditableMesh is an Object, not fixed-size when made empty, not Instance.new-able: %s" % _c("OBJECT"))
		check(_c("COUNTS") == "8 12 6 8 8", "the sharp cube: 8 vertices, 12 triangles, 6 normals once RemoveUnused has run, a UV and a colour per vertex: %s" % _c("COUNTS"))
		check(_c("BOUNDS") == "1.00,1.00,1.00 0.50,0.50,0.50", "GetSize and GetCenter: %s" % _c("BOUNDS"))
		check(_c("FRONTNORMAL") == "0.00,0.00,1.00", "an unset normal is computed from its faces: the front faces +Z: %s" % _c("FRONTNORMAL"))
		check(_c("SHARP") == "true", "each side has its own normal: a sharp edge")
		check(_c("IDSTRING").begins_with("v") and _c("IDSTRING").find(" f") > 0, "IdDebugString names the kind: %s" % _c("IDSTRING"))
		check(_c("REUSE") == "true true 4", "AddTriangle reuses the attributes of vertices already in a face: %s" % _c("REUSE"))
		check(_c("DEFAULTS") == "0.00,0.00,1.00 0, 0 1, 1, 1 1", "and new ones default to a computed normal, UV (0, 0), white, opaque: %s" % _c("DEFAULTS"))
		check(_c("STABLE").begins_with("true ") and _c("STABLE").find("invalid face id") >= 0, "ids are stable: the other face keeps its id, the removed one is gone: %s" % _c("STABLE"))
		check(_c("UNUSED") == "4", "RemoveUnused returns what it removed (a vertex and its normal, UV and colour): %s" % _c("UNUSED"))
		check(_c("VERTEXFACES").begins_with("1 6"), "GetVertexFaces, and GetAdjacentVertices -- a cube corner meets six others along its triangles' edges: %s" % _c("VERTEXFACES"))
		check(_c("ADJACENTFACES") == "3", "GetAdjacentFaces: a cube triangle shares an edge with three others: %s" % _c("ADJACENTFACES"))
		check(_c("RAY") == "true 0.25,0.50,1.00 1.00", "RaycastLocal: the face, the point on it, barycentrics summing to one: %s" % _c("RAY"))
		check(_c("RAYSHORT") == "true", "the direction's length is the reach: a short ray misses")
		check(_c("CLOSEST") == "true 0.50,0.50,1.00", "FindClosestPointOnSurface: %s" % _c("CLOSEST"))
		check(_c("NEARVERT") == "1.00,1.00,1.00", "FindClosestVertex: %s" % _c("NEARVERT"))
		check(_c("SPHERE") == "4", "FindVerticesWithinSphere: the corner and its three neighbours: %s" % _c("SPHERE"))
		check(_c("BATCHADD") == "4 2 2.00,2.00,0.00", "BatchAdd and BatchGetValues: %s" % _c("BATCHADD"))
		check(_c("BATCHCOLOR") == "1, 0, 0 0.5 3.00,3.00,0.00", "colours come back with their alphas; BatchSetValues writes positions: %s" % _c("BATCHCOLOR"))
		check(_c("BATCHFACE") == "true" and _c("BATCHCORNER") == "true", "BatchSetFaceAttributes, BatchGet / SetVertexFaceAttributes")
		check(_c("BATCHVERTEX") == "2", "BatchGetVertexAttributes(Face): the faces around a vertex: %s" % _c("BATCHVERTEX"))
		check(_c("BATCHMIX") == "true", "a batch of mixed kinds throws")
		check(_c("BATCHREMOVE") == "1", "BatchRemove")
		check(_c("BONES") == "Jaw true true 0.00,1.00,0.00 true", "bones: name, parent, virtual, bind CFrame, found by name: %s" % _c("BONES"))
		check(_c("BONEDUP") == "true" and _c("BONECYCLE") == "true", "a bone name used twice, or a parent loop, throws")
		check(_c("SKIN") == "2 0.75", "SetVertexBones and SetVertexBoneWeights: %s" % _c("SKIN"))
		check(_c("FACS") == "1 0.00,-0.20,0.00 Enum.FacsActionUnit.JawDrop", "a FACS pose reads back: %s" % _c("FACS"))
		check(_c("FACSVIRTUAL") == "true", "and must be made of virtual bones")
		check(_c("CORRECTIVE") == "1 2", "a corrective pose of two units: %s" % _c("CORRECTIVE"))
		check(_c("REMOVEBONE") == "1 1 0", "RemoveBone clears its skinning and unparents its children: %s" % _c("REMOVEBONE"))
		check(_c("VERTEXLIMIT").find("60,000") >= 0, "a 60,001st vertex throws: %s" % _c("VERTEXLIMIT"))
		var fs := "%.2f,%.2f,%.2f" % [skull_size.x, skull_size.y, skull_size.z]
		check(_c("FROMFILE") == "true true %s" % fs, "CreateEditableMeshAsync loads a mesh file, fixed-size by default, at the file's size: %s, file %s" % [_c("FROMFILE"), fs])
		check(_c("FIXED").begins_with("AddVertex: a fixed-size") and _c("FIXED").ends_with("| ok"), "a fixed-size mesh refuses new vertices and takes new positions: %s" % _c("FIXED"))
		check(_c("LOOSE") == "false ok", "FixedSize = false lets it grow: %s" % _c("LOOSE"))
		check(_c("COPY") == "1.00,1.00,1.00 6.00,1.00,1.00", "from an EditableMesh it is a copy: %s" % _c("COPY"))
		check(_c("PART") == "1.00,1.00,1.00 true ", "CreateMeshPartAsync on it: Size from the mesh, MeshContent its object, MeshId \"\": %s" % _c("PART"))
		check(_c("BAKED") == "Enum.CreateContentResult.Success Enum.ContentSourceType.Opaque 3.00,1.00,1.00 12 true",
			"baked: Opaque content a MeshPart and an EditableMesh can be made from: %s" % _c("BAKED"))
		check(_c("BAKEDNOTIMAGE") == "true", "and it is a mesh, not an image")
		check(_c("PROJECTED") == "255,0,0,255 0,0,0,0", "DrawImageProjected paints the decal where the projector covers the quad, and not outside it: %s" % _c("PROJECTED"))
		check(_c("SAMPLED") == "255,0,0,255", "SampleImageProjected reads it back off the mesh: %s" % _c("SAMPLED"))
		check(_c("DESTROYED").find("destroyed") >= 0, "a destroyed mesh cannot be edited: %s" % _c("DESTROYED"))
		check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

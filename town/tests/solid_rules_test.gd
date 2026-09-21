# Solid modelling rule by rule, each check naming the rule it holds the engine to. Rules from
# Roblox/creator-docs: BasePart.yaml, GeometryService.yaml, PartOperation.yaml, MeshPart.yaml,
# TriangleMeshPart.yaml, parts/solid-modeling.md.
#
#   godot --headless --path . -s res://tests/solid_rules_test.gd
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

const CUBE := "user://preview/solid_cube.obj"

const SERVER := """
local GeometryService = game:GetService("GeometryService")
local CollectionService = game:GetService("CollectionService")
local function say(k, v) print("R " .. k .. " " .. tostring(v)) end
local function vec(v) return ("%.2f,%.2f,%.2f"):format(v.X, v.Y, v.Z) end
local function block(size, at, color, parent)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = CFrame.new(at)
	p.Color = color or Color3.new(1, 1, 1)
	p.Anchored = true
	p.Parent = parent
	return p
end

-- "Resulting IntersectOperation with default name Intersect."
local a = block(Vector3.new(2, 2, 2), Vector3.new(0, 60, 0), nil, workspace)
local b = block(Vector3.new(2, 2, 2), Vector3.new(1, 60, 0), nil, workspace)
local inter = a:IntersectAsync({ b })
say("INTERSECT", inter.ClassName .. "/" .. inter.Name)
local uni = a:UnionAsync({ b })
say("UNIONNAME", uni.ClassName .. "/" .. uni.Name)

-- BasePart's: "The input parts do not need to be parented to the scene" is GeometryService's
-- difference, so these must be.
local loose = block(Vector3.new(1, 1, 1), Vector3.new(0, 60, 0), nil, nil)
local okLoose, whyLoose = pcall(function() return a:UnionAsync({ loose }) end)
say("LOOSE", tostring(okLoose) .. " " .. tostring(whyLoose))
local okGsLoose, gsLoose = pcall(function() return GeometryService:UnionAsync(loose, { block(Vector3.new(1,1,1), Vector3.new(0.5,60,0)) }, { SplitApart = false }) end)
say("GSLOOSE", tostring(okGsLoose) .. " " .. (okGsLoose and tostring(#gsLoose) or tostring(gsLoose)))

-- "Only Parts are supported, not Terrain or MeshParts."
-- (a script makes a MeshPart through AssetService: its MeshId is not a script's to write)
local mp = game:GetService("AssetService"):CreateMeshPartAsync(Content.fromUri("CUBE_PATH"))
mp.Size = Vector3.new(1, 1, 1)
mp.CFrame = CFrame.new(0, 60, 0)
mp.Anchored = true
mp.Parent = workspace
local okMp, whyMp = pcall(function() return a:UnionAsync({ mp }) end)
say("BASEMESH", tostring(okMp) .. " " .. tostring(whyMp))

-- GeometryService: "If the input contained any MeshParts, then the results will always be
-- MeshParts", and "its Color will be white".
local red = block(Vector3.new(1, 1, 1), Vector3.new(0.6, 60, 0), Color3.new(1, 0, 0))
local okMr, mr = pcall(function() return GeometryService:UnionAsync(red, { mp }, { SplitApart = false }) end)
say("MESHRESULT", okMr and (mr[1].ClassName .. " " .. vec(Vector3.new(mr[1].Color.R, mr[1].Color.G, mr[1].Color.B))) or tostring(mr))

-- "All the returned parts are in the coordinate space of the main part, so their
-- PVInstance.Origin positions are the same as the main part's."
local main = block(Vector3.new(2, 2, 2), Vector3.new(0, 70, 0))
local off = block(Vector3.new(2, 2, 2), Vector3.new(3, 70, 0))
local kept = GeometryService:UnionAsync(main, { off }, { SplitApart = false })[1]
say("KEEPPOS", vec(kept.Position))
say("KEEPSIZE", vec(kept.Size))

-- rbxNegate: "negation equivalent to Studio's Negate toolbar button". A slab cut clean through
-- the middle leaves two bodies, which SplitApart (true by default) hands back separately.
local bar = block(Vector3.new(6, 1, 1), Vector3.new(0, 80, 0))
local cutter = block(Vector3.new(1, 3, 3), Vector3.new(0, 80, 0))
CollectionService:AddTag(cutter, "rbxNegate")
local halves = GeometryService:UnionAsync(bar, { cutter })
say("NEGATED", #halves)

-- The properties "applied to the resulting PartOperations or MeshParts": Color, Material,
-- MaterialVariant, Reflectance, Transparency, AudioCanCollide, CanCollide, Anchored,
-- CustomPhysicalProperties.
local look = block(Vector3.new(2, 2, 2), Vector3.new(0, 90, 0), Color3.new(0, 1, 0), workspace)
look.Material = Enum.Material.Metal
look.Reflectance = 0.3
look.Transparency = 0.25
look.CanCollide = false
look.AudioCanCollide = false
look.Anchored = false
local lookOther = block(Vector3.new(2, 2, 2), Vector3.new(1, 90, 0), Color3.new(0, 0, 1), workspace)
local wore = look:UnionAsync({ lookOther })
say("LOOK", table.concat({ tostring(wore.Material), ("%.2f"):format(wore.Reflectance), ("%.2f"):format(wore.Transparency),
	tostring(wore.CanCollide), tostring(wore.AudioCanCollide), tostring(wore.Anchored), tostring(wore.Color == look.Color) }, " "))
-- "By default, the resulting union respects the Color property of each of its parts."
say("USEPARTCOLOR", wore.UsePartColor)
say("FACEDATA", wore.MeshData)

-- TriangleCount: the engine's to write, a script's only to read.
say("TRIANGLES", wore.TriangleCount)
local okTri = pcall(function() wore.TriangleCount = 3 end)
say("TRIWRITE", okTri)

-- "Cannot be set to Performance mode."
local okPerf = pcall(function() wore.RenderFidelity = Enum.RenderFidelity.Performance end)
say("PERFORMANCE", okPerf)

-- SubstituteGeometry: "preserving the original part's properties, attributes, tags, and children".
local keep = GeometryService:UnionAsync(block(Vector3.new(2,2,2), Vector3.new(0,100,0)), { block(Vector3.new(2,2,2), Vector3.new(1,100,0)) }, { SplitApart = false })[1]
keep.Name = "Keeper"
keep:SetAttribute("Mark", 7)
Instance.new("Attachment").Parent = keep
local donor = GeometryService:SubtractAsync(block(Vector3.new(4,2,2), Vector3.new(0,100,0)), { block(Vector3.new(1,4,4), Vector3.new(0,100,0)) }, { SplitApart = false })[1]
keep:SubstituteGeometry(donor)
say("SUBSTITUTE", table.concat({ tostring(keep.MeshData == donor.MeshData), tostring(keep.Size == donor.Size), keep.Name,
	tostring(keep:GetAttribute("Mark")), tostring(keep:FindFirstChildOfClass("Attachment") ~= nil) }, " "))
local okSubPart = pcall(function() keep:SubstituteGeometry(block(Vector3.new(1,1,1), Vector3.new(0,0,0))) end)
say("SUBSTITUTEPART", okSubPart)

-- ApplyMesh: "The object must be a MeshPart, otherwise the call throws an error."
if okMr then
	local plain = Instance.new("MeshPart")
	plain:ApplyMesh(mr[1])
	say("APPLYMESH", tostring(plain.MeshData == mr[1].MeshData) .. " " .. tostring(plain.MeshSize == mr[1].MeshSize))
	local okApplyPart = pcall(function() plain:ApplyMesh(block(Vector3.new(1,1,1), Vector3.new(0,0,0))) end)
	say("APPLYPART", okApplyPart)
end

-- "If a solid modeling operation would result in any parts with more than 20,000 triangles,
-- they will be simplified to 20,000."
local balls = {}
for k = 1, 12 do
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1, 1, 1)
	ball.CFrame = CFrame.new(k * 0.6, 110, 0)
	table.insert(balls, ball)
end
local first = table.remove(balls, 1)
local okBig, big = pcall(function() return GeometryService:UnionAsync(first, balls, { SplitApart = false }) end)
say("CAP", okBig and big[1].TriangleCount or tostring(big))
say("DONE", "ok")
"""

# CollisionFidelity is PluginSecurity: a game's own Script must be refused the write.
const GAME_SCRIPT := """
local p = Instance.new("Part")
p.Parent = workspace
local u = p:UnionAsync({})
local ok = pcall(function() u.CollisionFidelity = Enum.CollisionFidelity.Box end)
print("R GAMEWRITE " .. tostring(ok))
"""

const CLIENT := """
local GeometryService = game:GetService("GeometryService")
local serverPart = workspace:WaitForChild("ServerMade", 10)
local mine = Instance.new("Part")
mine.Size = Vector3.new(1, 1, 1)
local other = Instance.new("Part")
other.Size = Vector3.new(1, 1, 1)
other.Position = Vector3.new(0.5, 0, 0)
local okMine, got = pcall(function() return GeometryService:UnionAsync(mine, { other }, { SplitApart = false }) end)
print("R CLIENTOWN " .. tostring(okMine) .. " " .. (okMine and got[1].ClassName or tostring(got)))
local okTheirs, why = pcall(function() return GeometryService:UnionAsync(mine, { serverPart }, { SplitApart = false }) end)
print("R CLIENTSERVERPART " .. tostring(okTheirs) .. " " .. tostring(why))
"""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _r(key: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		var s := String(said[i])
		if s.begins_with("R " + key + " "): return s.substr(("R " + key + " ").length())
	return ""

## A closed unit cube, clockwise as seen from outside: the winding this engine draws as the front.
func _write_cube() -> void:
	DirAccess.make_dir_recursive_absolute("user://preview")
	var v := [Vector3(-0.5,-0.5,-0.5), Vector3(0.5,-0.5,-0.5), Vector3(0.5,0.5,-0.5), Vector3(-0.5,0.5,-0.5),
		Vector3(-0.5,-0.5,0.5), Vector3(0.5,-0.5,0.5), Vector3(0.5,0.5,0.5), Vector3(-0.5,0.5,0.5)]
	var quads := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [3,7,6,2], [0,4,7,3], [1,2,6,5]]
	var lines := PackedStringArray()
	for p in v: lines.append("v %f %f %f" % [p.x, p.y, p.z])
	for q in quads:
		# Reverse the quad when its listed winding faces inward.
		var a: Vector3 = v[q[0]]; var b: Vector3 = v[q[1]]; var c: Vector3 = v[q[2]]
		var centre: Vector3 = (a + b + c + v[q[3]]) / 4.0
		var outward := (b - a).cross(c - a).dot(centre) > 0
		var order: Array = [q[0], q[1], q[2], q[3]] if not outward else [q[0], q[3], q[2], q[1]]
		lines.append("f %d %d %d" % [order[0] + 1, order[1] + 1, order[2] + 1])
		lines.append("f %d %d %d" % [order[0] + 1, order[2] + 1, order[3] + 1])
	var f := FileAccess.open(CUBE, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()

## Distinct face colours in a PBOP MeshData of version 2 or later.
func _face_colours(b64: String) -> int:
	var raw := Marshalls.base64_to_raw(b64)
	if raw.size() < 16 or raw.decode_u32(4) < 2: return 0
	var stride := 44 if raw.decode_u32(4) == 3 else 36
	var seen := {}
	for i in raw.decode_u32(8):
		var at := 16 + i * stride
		seen["%.2f,%.2f,%.2f" % [raw.decode_float(at + 24), raw.decode_float(at + 28), raw.decode_float(at + 32)]] = true
	return seen.size()

func _index_triangles(b64: String) -> int:
	var raw := Marshalls.base64_to_raw(b64)
	return raw.decode_u32(12) / 3 if raw.size() >= 16 else -1

func _initialize() -> void:
	print("solid modelling, rule by rule")
	_write_cube()
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): errors.append("%s: %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 9.0:
		phase = 1; t = 0.0
		world.run_chunk("rules", SERVER.replace("CUBE_PATH", CUBE))
		world.run_chunk("servermade", 'local p = Instance.new("Part") p.Name = "ServerMade" p.Size = Vector3.new(1,1,1) p.Anchored = true p.Parent = workspace')
		world.add_model("ServerScriptService", "GameWrite", JSON.stringify({"className": "Script", "name": "GameWrite", "properties": {"Source": GAME_SCRIPT}}))
	elif phase == 1 and t > 3.0:
		phase = 2; t = 0.0
		world.run_client_chunk("clientrules", CLIENT)
	elif phase == 2 and (_r("DONE") == "ok" and _r("CLIENTSERVERPART") != "" or t > 40.0) and t > 2.0:
		phase = 3
		check(_r("INTERSECT") == "IntersectOperation/Intersect", "IntersectAsync makes an IntersectOperation named Intersect: %s" % _r("INTERSECT"))
		check(_r("UNIONNAME") == "UnionOperation/Union", "UnionAsync makes a UnionOperation named Union: %s" % _r("UNIONNAME"))
		check(_r("LOOSE").begins_with("false") and _r("LOOSE").find("Workspace") >= 0, "BasePart's methods refuse a part that is not in the scene: %s" % _r("LOOSE"))
		check(_r("GSLOOSE") == "true 1", "GeometryService's do not: %s" % _r("GSLOOSE"))
		check(_r("BASEMESH").begins_with("false") and _r("BASEMESH").find("MeshPart") >= 0, "BasePart's methods refuse MeshParts: %s" % _r("BASEMESH"))
		check(_r("MESHRESULT") == "MeshPart 1.00,1.00,1.00", "a MeshPart input makes a white MeshPart result: %s" % _r("MESHRESULT"))
		check(_r("KEEPPOS") == "0.00,70.00,0.00", "GeometryService keeps the main part's origin: %s" % _r("KEEPPOS"))
		check(_r("KEEPSIZE") == "5.00,2.00,2.00", "while its Size covers the whole body: %s" % _r("KEEPSIZE"))
		check(_r("NEGATED") == "2", "an rbxNegate part is cut out, and SplitApart returns the halves: %s" % _r("NEGATED"))
		check(_r("LOOK") == "Enum.Material.Metal 0.30 0.25 false false false true", "the documented properties come from the main part: %s" % _r("LOOK"))
		check(_r("USEPARTCOLOR") == "false", "UsePartColor is off by default")
		check(_face_colours(_r("FACEDATA")) >= 2, "and the faces keep each part's colour: %d colours" % _face_colours(_r("FACEDATA")))
		var tri := int(_r("TRIANGLES"))
		check(tri > 0 and tri == _index_triangles(_r("FACEDATA")), "TriangleCount is the geometry's own: %d" % tri)
		check(_r("TRIWRITE") == "false", "and a script cannot write it")
		check(_r("PERFORMANCE") == "false", "a PartOperation's RenderFidelity cannot be Performance")
		check(_r("GAMEWRITE") == "false", "a game script cannot write CollisionFidelity (PluginSecurity): %s" % _r("GAMEWRITE"))
		check(_r("SUBSTITUTE") == "true true Keeper 7 true", "SubstituteGeometry takes the shape and keeps the rest: %s" % _r("SUBSTITUTE"))
		check(_r("SUBSTITUTEPART") == "false", "and refuses anything that is not a PartOperation")
		check(_r("APPLYMESH") == "true true", "ApplyMesh copies the mesh and MeshSize: %s" % _r("APPLYMESH"))
		check(_r("APPLYPART") == "false", "and throws for anything that is not a MeshPart")
		var cap := int(_r("CAP"))
		check(cap > 0 and cap <= 20000, "a result over 20,000 triangles is simplified to 20,000: %s" % _r("CAP"))
		check(_r("CLIENTOWN").begins_with("true"), "a client can solid model the parts it made: %s" % _r("CLIENTOWN"))
		check(_r("CLIENTSERVERPART").begins_with("false"), "but not a part the server made: %s" % _r("CLIENTSERVERPART"))
		check(errors.is_empty(), "nothing threw that was not caught: %s" % str(errors.slice(0, 3)))
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

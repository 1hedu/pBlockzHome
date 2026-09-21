# AssetService:CreateMeshPartAsync, and the write it exists to replace.
#
#   godot --headless --path . -s res://tests/meshpart_async_test.gd
#
# MeshPart.MeshId and MeshContent are NotAccessibleSecurity on write -- no script may set them,
# plugins and the command bar included -- so this call is the only way to a scripted mesh: it
# yields for the load, sizes the part to the mesh, takes CollisionFidelity / RenderFidelity /
# FluidFidelity from its options, and throws if creation fails.
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0
var expected := Vector3()
var staged := ""

const SCRIPT := """
local AssetService = game:GetService("AssetService")
local function say(k, v) print("C " .. k .. " " .. tostring(v)) end
local uri = "%s"
local function f3(v) return ("%%.3f,%%.3f,%%.3f"):format(v.X, v.Y, v.Z) end

local p = AssetService:CreateMeshPartAsync(Content.fromUri(uri), {
	CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Precise })
say("CLASS", p.ClassName .. " " .. tostring(p.Parent))
say("MESH", tostring(p.MeshId == uri) .. " " .. tostring(p.MeshContent == Content.fromUri(uri)))
say("SIZE", f3(p.Size))
say("MESHSIZE", f3(p.MeshSize))
say("FIDELITY", tostring(p.CollisionFidelity) .. " " .. tostring(p.RenderFidelity) .. " " .. tostring(p.FluidFidelity))

local q = AssetService:CreateMeshPartAsync(Content.fromUri(uri))
say("DEFAULTS", tostring(q.CollisionFidelity) .. " " .. tostring(q.RenderFidelity) .. " " .. tostring(q.FluidFidelity))

local okMissing, missing = pcall(function() return AssetService:CreateMeshPartAsync(Content.fromUri("user://media/no-such-mesh.obj")) end)
say("MISSING", tostring(okMissing))
say("NONE", tostring((pcall(function() return AssetService:CreateMeshPartAsync(Content.none) end))))
say("NOTCONTENT", tostring((pcall(function() return AssetService:CreateMeshPartAsync(uri) end))))

-- The write it replaces, from the command bar, which may do most things
local okId, idErr = pcall(function() p.MeshId = "rbxassetid://1" end)
local okContent = pcall(function() p.MeshContent = Content.fromAssetId(1) end)
say("WRITE", tostring(okId) .. " " .. tostring(okContent) .. " " .. tostring(p.MeshId == uri))
say("WRITEMSG", idErr)
-- A copy keeps its mesh: the write is refused to scripts, not to the engine
say("CLONE", tostring(p:Clone().MeshId == uri))
p.Anchored = true
p.CFrame = CFrame.new(0, 90, 0)
p.Name = "Made"
p.Parent = workspace
say("DONE", "ok")
"""

# The same write from a place's own Script, which has neither plugin nor command bar standing.
const GAME_SCRIPT := """
local okId = pcall(function() Instance.new("MeshPart").MeshId = "rbxassetid://1" end)
print("R GAME " .. tostring(okId))
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

## Puts the skull where the host's cache would put a fetched mesh; expected is its bounds,
## taken straight off the .obj vertices.
func _stage() -> void:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../../../scripts/models/steven-skull.obj"))
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for line in text.split("\n"):
		if line.begins_with("v "):
			var p := line.substr(2).strip_edges().split(" ", false)
			var v := Vector3(float(p[0]), float(p[1]), float(p[2]))
			lo = lo.min(v)
			hi = hi.max(v)
	expected = hi - lo
	DirAccess.make_dir_recursive_absolute("user://media")
	staged = "user://media/test-meshpart-async.obj"
	var w := FileAccess.open(staged, FileAccess.WRITE)
	w.store_string(text)
	w.close()

func _initialize() -> void:
	print("CreateMeshPartAsync")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): errors.append("%s: %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	_stage()

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 2.0:
		phase = 1; t = 0.0
		world.run_chunk("meshpart", SCRIPT % staged)
		world.add_model("ServerScriptService", "GameWrite", JSON.stringify({"className": "Script", "name": "GameWrite", "properties": {"Source": GAME_SCRIPT}}))
	elif phase == 1 and (_c("DONE") == "ok" or not errors.is_empty() or t > 20.0) and t > 1.0:
		phase = 2
		var want := "%.3f,%.3f,%.3f" % [expected.x, expected.y, expected.z]
		check(_c("CLASS") == "MeshPart nil", "it hands back an unparented MeshPart: %s" % _c("CLASS"))
		check(_c("MESH") == "true true", "whose MeshId and MeshContent are the mesh")
		check(_c("SIZE") == want, "sized to the mesh's own bounds: %s, the file says %s" % [_c("SIZE"), want])
		check(_c("MESHSIZE") == want, "and MeshSize is the same: %s" % _c("MESHSIZE"))
		check(_c("FIDELITY") == "Enum.CollisionFidelity.Box Enum.RenderFidelity.Precise Enum.FluidFidelity.Automatic",
			"the options it was given, FluidFidelity left at its default: %s" % _c("FIDELITY"))
		check(_c("DEFAULTS") == "Enum.CollisionFidelity.Default Enum.RenderFidelity.Automatic Enum.FluidFidelity.Automatic",
			"no options: Default, Automatic, Automatic: %s" % _c("DEFAULTS"))
		check(_c("MISSING") == "false", "a mesh that cannot be loaded throws")
		check(_c("NONE") == "false", "Content.none throws")
		check(_c("NOTCONTENT") == "false", "a string is not a Content")
		check(_c("WRITE") == "false false true", "no script may write MeshId or MeshContent, the command bar included: %s" % _c("WRITE"))
		check(_c("WRITEMSG").find("Script write access is restricted") >= 0, "\"Script write access is restricted\": %s" % _c("WRITEMSG"))
		check(_c("CLONE") == "true", "a Clone keeps its mesh")
		var game := ""
		for s in said:
			if String(s).begins_with("R GAME "): game = String(s).substr(7)
		check(game == "false", "nor may a game's own Script: %s" % game)
		var made := _child(_child(0, "Workspace"), "Made")
		var mesh = world.get_part_mesh(made) if made != 0 else null
		var aabb := AABB()
		if mesh is MeshInstance3D and mesh.mesh != null: aabb = mesh.mesh.get_aabb()
		check(aabb.size.distance_to(expected) < 0.01, "and the host draws it at that size: %s" % aabb.size)
		check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

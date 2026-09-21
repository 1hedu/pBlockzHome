# Content and CustomPhysicalProperties across a real socket: a server fires them at a client
# in another process (tests/chunk_peer.gd). Object Contents arrive as placeholders, baked ones
# whole; CustomPhysicalProperties rides along as the wire's value type after ColorSequence.
#
#   godot --headless --path . -s res://tests/content_net_test.gd
extends SceneTree

const PORT := 8897

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var errors: Array[String] = []
var kids: Array[int] = []
var t := 0.0
var phase := 0
var report := ""

const PEER := """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ev = ReplicatedStorage:WaitForChild("ContentEvent")
ev.OnClientEvent:Connect(function(uri, none, obj, tbl)
	print("SEEN URI " .. tostring(typeof(uri) == "Content" and uri.SourceType == Enum.ContentSourceType.Uri and uri.Uri == "rbxassetid://4242"))
	print("SEEN NONE " .. tostring(none == Content.none))
	print("SEEN NESTED " .. tostring(typeof(tbl) == "table" and tbl.c == Content.fromUri("rbxasset://textures/x.png")))
	print("SEEN OBJ " .. typeof(obj) .. " " .. tostring(obj and obj.SourceType))
end)
ev:FireServer("ready")
local part = workspace:WaitForChild("Springy", 20)
while part and part.CustomPhysicalProperties == nil do task.wait(0.2) end
local pp = part and part.CustomPhysicalProperties
print("SEEN PHYS " .. (pp and ("%.2f %.2f %.2f"):format(pp.Density, pp.Friction, pp.Elasticity) or "nil"))

-- A server's EditableImage, shown on a replicated ImageLabel: this side gets a placeholder
local objLabel = ReplicatedStorage:WaitForChild("ObjLabel", 20)
local objContent = objLabel and objLabel.ImageContent
local stand = objContent and objContent.Object
local readable = stand and pcall(function() return stand:ReadPixelsBuffer(Vector2.zero, Vector2.one) end)
print("SEEN PLACEHOLDER " .. (stand and ("%s %s %s %s"):format(typeof(stand), stand.ClassName, tostring(objContent.SourceType), tostring(readable)) or "nil"))

-- Baked content the server made: here, as it was
local bakedLabel = ReplicatedStorage:WaitForChild("BakedLabel", 20)
local baked = bakedLabel and bakedLabel.ImageContent
local ok, copy = pcall(function() return game:GetService("AssetService"):CreateEditableImageAsync(baked) end)
local px = ok and copy:ReadPixelsBuffer(Vector2.new(2, 1), Vector2.one)
print("SEEN BAKED " .. (baked and tostring(baked.SourceType) or "nil") .. " " .. (px and ("%d %d %d,%d,%d"):format(copy.Size.X, copy.Size.Y, buffer.readu8(px, 0), buffer.readu8(px, 1), buffer.readu8(px, 2)) or tostring(copy)))

-- A server's EditableMesh on a MeshPart: a placeholder here too; a baked mesh, whole
local meshPart = workspace:WaitForChild("EditMeshPart", 20)
local em = meshPart and meshPart.MeshContent.Object
print("SEEN MESHHOLDER " .. (em and ("%s %s %s"):format(typeof(em), em.ClassName, tostring((pcall(function() return em:GetVertices() end)))) or "nil"))
local bakedMeshPart = workspace:WaitForChild("BakedMeshPart", 20)
local okMesh, meshCopy = pcall(function() return game:GetService("AssetService"):CreateEditableMeshAsync(bakedMeshPart.MeshContent) end)
print("SEEN BAKEDMESH " .. (okMesh and ("%d %d"):format(#meshCopy:GetVertices(), #meshCopy:GetFaces()) or tostring(meshCopy)))
"""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _seen() -> PackedStringArray:
	if not FileAccess.file_exists(report): return PackedStringArray()
	return FileAccess.get_file_as_string(report).split("\n", false)

func _line(prefix: String) -> String:
	var lines := _seen()
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with(prefix): return lines[i].substr(prefix.length())
	return ""

func _initialize() -> void:
	print("Content over the wire")
	report = OS.get_user_data_dir().path_join("content_peer.txt")
	var chunk_file := OS.get_user_data_dir().path_join("content_peer.luau")
	DirAccess.remove_absolute(report)
	var f := FileAccess.open(chunk_file, FileAccess.WRITE)
	f.store_string(PEER)
	f.close()
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	world.run_chunk("serve", """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ev = Instance.new("RemoteEvent")
ev.Name = "ContentEvent"
ev.Parent = ReplicatedStorage
local part = Instance.new("Part")
part.Name = "Springy"
part.Anchored = true
part.CFrame = CFrame.new(0, 60, 0)
part.CustomPhysicalProperties = PhysicalProperties.new(2.5, 0.25, 0.75)
part.Parent = workspace
local AssetService = game:GetService("AssetService")
local img = AssetService:CreateEditableImage({ Size = Vector2.new(2, 2) })

-- An EditableImage on a replicated label and a part: clients cannot have the object itself
local objLabel = Instance.new("ImageLabel")
objLabel.Name = "ObjLabel"
local serverImage = AssetService:CreateEditableImage({ Size = Vector2.new(6, 6) })
objLabel.ImageContent = Content.fromObject(serverImage)
objLabel.Parent = ReplicatedStorage
local SKULL = "res://../../../scripts/models/steven-skull.obj"
local objMesh = AssetService:CreateMeshPartAsync(Content.fromUri(SKULL))
objMesh.Name = "ObjMesh"
objMesh.Anchored = true
objMesh.CFrame = CFrame.new(-6, 60, 0)
objMesh.TextureContent = Content.fromObject(serverImage)
objMesh.Parent = workspace

-- Baked content: it does reach them
local toBake = AssetService:CreateEditableImage({ Size = Vector2.new(5, 4) })
local bytes = buffer.create(5 * 4 * 4)
for i = 0, 19 do buffer.writeu8(bytes, i * 4, 30) buffer.writeu8(bytes, i * 4 + 1, 160) buffer.writeu8(bytes, i * 4 + 2, 90) buffer.writeu8(bytes, i * 4 + 3, 255) end
toBake:WritePixelsBuffer(Vector2.zero, toBake.Size, bytes)
local _, baked = AssetService:CreateDataModelContentAsync(Content.fromObject(toBake))
local bakedLabel = Instance.new("ImageLabel")
bakedLabel.Name = "BakedLabel"
bakedLabel.ImageContent = baked
bakedLabel.Parent = ReplicatedStorage
local bakedMesh = AssetService:CreateMeshPartAsync(Content.fromUri(SKULL))
bakedMesh.Name = "BakedMesh"
bakedMesh.Anchored = true
bakedMesh.CFrame = CFrame.new(6, 60, 0)
bakedMesh.TextureContent = baked
bakedMesh.Parent = workspace

-- An EditableMesh, shown live and baked
local em = AssetService:CreateEditableMesh()
local v = em:BatchAdd(Enum.MeshAttribute.Vertex, { Vector3.new(0, 0, 0), Vector3.new(2, 0, 0), Vector3.new(0, 2, 0), Vector3.new(0, 0, 2) })
em:BatchAdd(Enum.MeshAttribute.Face, { { v[1], v[3], v[2] }, { v[1], v[2], v[4] }, { v[1], v[4], v[3] }, { v[2], v[3], v[4] } })
local editPart = AssetService:CreateMeshPartAsync(Content.fromObject(em))
editPart.Name = "EditMeshPart"
editPart.Anchored = true
editPart.CFrame = CFrame.new(0, 64, 0)
editPart.Parent = workspace
local _, bakedGeometry = AssetService:CreateDataModelContentAsync(Content.fromObject(em))
local bakedPart = AssetService:CreateMeshPartAsync(bakedGeometry)
bakedPart.Name = "BakedMeshPart"
bakedPart.Anchored = true
bakedPart.CFrame = CFrame.new(4, 64, 0)
bakedPart.Parent = workspace
ev.OnServerEvent:Connect(function(player)
	ev:FireClient(player, Content.fromAssetId(4242), Content.none, Content.fromObject(img), { c = Content.fromUri("rbxasset://textures/x.png") })
end)
""")
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tests/chunk_peer.gd", "--",
		"--port=%d" % PORT, "--chunk=%s" % chunk_file, "--out=%s" % report, "--parts=ObjMesh,BakedMesh"])
	if pid > 0: kids.append(pid)

func _finish() -> void:
	for pid in kids: OS.kill(pid)
	print("    client said: ", " | ".join(_seen()))
	check(_line("URI ") == "true", "a uri Content arrives as a Content with its uri")
	check(_line("NONE ") == "true", "Content.none arrives as Content.none")
	check(_line("NESTED ") == "true", "inside a table too")
	# Printed, not checked: PLACEHOLDER below is the assertion about object Contents
	print("    object Content on the client: ", _line("OBJ "))
	check(_line("PHYS ") == "2.50 0.25 0.75", "CustomPhysicalProperties reaches the client: %s" % _line("PHYS "))
	check(_line("PLACEHOLDER ") == "Object EditableImage Enum.ContentSourceType.Object false",
		"a server's EditableImage arrives as a placeholder EditableImage whose contents cannot be read: %s" % _line("PLACEHOLDER "))
	check(_line("TEX ObjMesh ") == "64x64 0,255,255", "which the client draws as the cyan and magenta checkerboard: %s" % _line("TEX ObjMesh "))
	check(_line("BAKED ") == "Enum.ContentSourceType.Opaque 5 4 30,160,90", "baked content reaches the client whole: %s" % _line("BAKED "))
	check(_line("TEX BakedMesh ") == "5x4 30,160,90", "and the client draws it: %s" % _line("TEX BakedMesh "))
	check(_line("MESHHOLDER ") == "Object EditableMesh false", "a server's EditableMesh arrives as a placeholder EditableMesh that cannot be read: %s" % _line("MESHHOLDER "))
	check(_line("BAKEDMESH ") == "4 4", "a baked mesh reaches the client whole, the tetrahedron's 4 vertices and 4 faces: %s" % _line("BAKEDMESH "))
	check(_seen().size() > 0 and " ".join(_seen()).find("ERROR") < 0, "the client threw nothing")
	check(errors.is_empty(), "the server threw nothing: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and (t > 40.0 or (_line("PHYS ") != "" and _line("OBJ ") != "" and _line("BAKED ") != "" and _line("BAKEDMESH ") != "" and _line("TEX BakedMesh ").begins_with("5x4") and _line("TEX ObjMesh ").begins_with("64x64"))):
		phase = 1
		_finish()
	return false

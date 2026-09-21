# EditableImage is an Object, not an Instance: no Name, Parent or children, and Instance.new
# cannot make one. Covers the ImageCombineType and AntiAliasing enums, DrawImageTransformed,
# Destroy, a Content holding its object, and AssetService's Editable and bake calls.
#
#   godot --headless --path . -s res://tests/object_test.gd
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

const PNG := "res://splash.png"
const WIDE := "res://panel-screener.png"   # 1152 wide: past the 1024 an EditableImage may be

# Roblox took ReadPixels, WritePixels, Resize, Rotate and Crop off EditableImage, so every
# pixel read and write below is the surviving *Buffer* call.
const SCRIPT := """
local AssetService = game:GetService("AssetService")
local function say(k, v) print("C " .. k .. " " .. tostring(v)) end
local function msg(f) local ok, e = pcall(f) return ok and "ok" or tostring(e):gsub("^.-:%%d+: ", "") end
local function px(img, x, y)
	local b = img:ReadPixelsBuffer(Vector2.new(x, y), Vector2.new(1, 1))
	return ("%%d,%%d,%%d,%%d"):format(buffer.readu8(b, 0), buffer.readu8(b, 1), buffer.readu8(b, 2), buffer.readu8(b, 3))
end
local function fill(img, r, g, b, a)
	local n = img.Size.X * img.Size.Y
	local buf = buffer.create(n * 4)
	for i = 0, n - 1 do buffer.writeu8(buf, i * 4, r) buffer.writeu8(buf, i * 4 + 1, g) buffer.writeu8(buf, i * 4 + 2, b) buffer.writeu8(buf, i * 4 + 3, a) end
	img:WritePixelsBuffer(Vector2.zero, img.Size, buf)
end

-- ---- Object -------------------------------------------------------------------------------
local img = AssetService:CreateEditableImage({ Size = Vector2.new(8, 8) })
local part = Instance.new("Part")
say("TYPEOF", typeof(img) .. " " .. typeof(part))
say("ISA", tostring(img:IsA("Object")) .. " " .. tostring(img:IsA("Instance")) .. " " .. tostring(part:IsA("Object")))
say("CLASSNAME", img.ClassName .. " " .. tostring(img))
say("NAME", msg(function() return img.Name end))
say("PARENT", msg(function() img.Parent = workspace end))
say("FIND", msg(function() return img:FindFirstChild("x") end))
say("NEW", msg(function() return Instance.new("EditableImage") end))
say("SIZERO", msg(function() img.Size = Vector2.new(4, 4) end))
say("REMOVED", msg(function() img:WritePixels(Vector2.zero, Vector2.one, {1, 1, 1, 1}) end) .. " | " .. msg(function() img:Resize(Vector2.new(2, 2)) end))
say("CHANGED", typeof(img.Changed) .. " " .. typeof(img:GetPropertyChangedSignal("Size")))
say("TOOBIG", msg(function() return AssetService:CreateEditableImage({ Size = Vector2.new(2048, 16) }) end))

-- ---- ImageCombineType ------------------------------------------------------------------------
say("ENUM", ("%%d %%d %%d %%d %%d %%d %%d"):format(Enum.ImageCombineType.BlendSourceOver.Value, Enum.ImageCombineType.Overwrite.Value,
	Enum.ImageCombineType.Add.Value, Enum.ImageCombineType.Multiply.Value, Enum.ImageCombineType.AlphaBlend.Value,
	Enum.ImageCombineType.NormalMapBlend.Value, Enum.ImageCombineType.Subtract.Value))
local function one(r, g, b, a, color, transparency, mode)
	local i = AssetService:CreateEditableImage({ Size = Vector2.new(1, 1) })
	fill(i, r, g, b, a)
	i:DrawRectangle(Vector2.zero, Vector2.one, color, transparency, mode)
	return px(i, 0, 0)
end
local T = Enum.ImageCombineType
-- half-transparent red over a transparent black pixel, and over an opaque blue one
say("SOURCEOVER", one(0, 0, 0, 0, Color3.new(1, 0, 0), 0.5, T.BlendSourceOver) .. " " .. one(0, 0, 255, 255, Color3.new(1, 0, 0), 0.5, T.BlendSourceOver))
say("ALPHABLEND", one(0, 0, 0, 0, Color3.new(1, 0, 0), 0.5, T.AlphaBlend) .. " " .. one(0, 0, 255, 255, Color3.new(1, 0, 0), 0.5, T.AlphaBlend))
say("OVERWRITE", one(0, 0, 255, 255, Color3.new(1, 0, 0), 0.5, T.Overwrite))
say("ADD", one(100, 100, 100, 100, Color3.fromRGB(100, 200, 0), 0, T.Add))
say("MULTIPLY", one(200, 200, 200, 255, Color3.fromRGB(128, 255, 0), 0, T.Multiply))
say("SUBTRACT", one(100, 100, 100, 255, Color3.fromRGB(50, 200, 0), 0, T.Subtract))
say("NORMALMAP", one(128, 128, 255, 255, Color3.fromRGB(255, 128, 128), 0.5, T.NormalMapBlend))
say("RECTOUTSIDE", msg(function() img:DrawRectangle(Vector2.new(-1, 0), Vector2.new(4, 4), Color3.new(1, 1, 1), 0, T.Overwrite) end))

-- ---- anti-aliasing -------------------------------------------------------------------------------
local function edges(aa)
	local i = AssetService:CreateEditableImage({ Size = Vector2.new(32, 32) })
	i:DrawCircle(Vector2.new(16, 16), 10, Color3.new(1, 1, 1), 0, T.Overwrite, aa)
	local soft = 0
	local b = i:ReadPixelsBuffer(Vector2.zero, i.Size)
	for k = 0, 32 * 32 - 1 do
		local a = buffer.readu8(b, k * 4 + 3)
		if a > 0 and a < 255 then soft += 1 end
	end
	return soft
end
say("AA", ("%%d %%d"):format(edges(Enum.AntiAliasing.Enabled), edges(Enum.AntiAliasing.Disabled)))
local lineImg = AssetService:CreateEditableImage({ Size = Vector2.new(16, 16) })
lineImg:DrawLine(Vector2.new(1, 1), Vector2.new(14, 9), Color3.new(1, 1, 1), 0, T.Overwrite)
say("LINEDEFAULTSOFT", px(lineImg, 7, 5) ~= "0,0,0,0")

-- ---- DrawImageTransformed ----------------------------------------------------------------------
local src = AssetService:CreateEditableImage({ Size = Vector2.new(2, 1) })
local two = buffer.create(8)
buffer.writeu8(two, 0, 255) buffer.writeu8(two, 3, 255)            -- red
buffer.writeu8(two, 6, 255) buffer.writeu8(two, 7, 255)            -- blue
src:WritePixelsBuffer(Vector2.zero, src.Size, two)
local dst = AssetService:CreateEditableImage({ Size = Vector2.new(8, 8) })
dst:DrawImageTransformed(Vector2.new(4, 4), Vector2.new(2, 2), 0, src, { SamplingMode = Enum.ResamplerMode.Pixelated, CombineType = T.Overwrite })
say("SCALED", px(dst, 2, 3) .. " " .. px(dst, 5, 4) .. " " .. px(dst, 1, 4))
local rot = AssetService:CreateEditableImage({ Size = Vector2.new(8, 8) })
rot:DrawImageTransformed(Vector2.new(4, 4), Vector2.new(2, 2), 90, src, { SamplingMode = Enum.ResamplerMode.Pixelated, CombineType = T.Overwrite })
say("ROTATED", px(rot, 4, 2) .. " " .. px(rot, 4, 5) .. " " .. px(rot, 1, 4))

-- ---- Destroy -------------------------------------------------------------------------------------
local gone = AssetService:CreateEditableImage({ Size = Vector2.new(4, 4) })
gone:Destroy()
say("DESTROYED", msg(function() gone:DrawCircle(Vector2.one, 1, Color3.new(1, 1, 1), 0, T.Overwrite) end))

-- ---- a Content holds its object ------------------------------------------------------------------
local label = Instance.new("ImageLabel")
label.Name = "Holder"
label.Parent = game:GetService("ReplicatedStorage")
do
	local kept = AssetService:CreateEditableImage({ Size = Vector2.new(3, 3) })
	fill(kept, 10, 20, 30, 255)
	label.ImageContent = Content.fromObject(kept)
end
local weak = setmetatable({}, { __mode = "v" })
for i = 1, 300000 do local _ = { i } end
local held = label.ImageContent.Object
say("HELD", held and (held.ClassName .. " " .. px(held, 1, 1)) or "gone")

-- ---- CreateEditableImageAsync ----------------------------------------------------------------------
local fromFile = AssetService:CreateEditableImageAsync(Content.fromUri("%s"))
say("FROMURI", ("%%d %%d %%s"):format(fromFile.Size.X, fromFile.Size.Y, px(fromFile, 3, 2)))
say("FROMMISSING", msg(function() return AssetService:CreateEditableImageAsync(Content.fromUri("res://no-such.png")) end) ~= "ok")
say("FROMWIDE", msg(function() return AssetService:CreateEditableImageAsync(Content.fromUri("%s")) end))
local copy = AssetService:CreateEditableImageAsync(Content.fromObject(held))
fill(copy, 1, 2, 3, 4)
say("COPY", px(held, 0, 0) .. " " .. px(copy, 0, 0))

-- ---- CreateDataModelContentAsync ------------------------------------------------------------------
local result, baked = AssetService:CreateDataModelContentAsync(Content.fromObject(held))
say("BAKED", tostring(result) .. " " .. tostring(baked.SourceType) .. " " .. tostring(baked.Uri) .. " " .. tostring(baked.Object) .. " " .. typeof(baked.Opaque))
fill(held, 99, 99, 99, 255)                                    -- the bake is a copy: changing the editable after changes nothing
local back = AssetService:CreateEditableImageAsync(baked)
say("BAKEDBACK", px(back, 1, 1))
local l2 = Instance.new("ImageLabel")
l2.ImageContent = baked
say("BAKEDPROP", tostring(l2.ImageContent == baked) .. " " .. tostring(l2.Image == ""))
say("BAKEDURIONLY", msg(function() Instance.new("ImageButton").HoverImageContent = baked end) ~= "ok")
say("BAKEOBJONLY", msg(function() return AssetService:CreateDataModelContentAsync(Content.fromUri("rbxassetid://1")) end) ~= "ok")
local shown = Instance.new("Part")
shown.Name = "BakedPart"
shown.Anchored = true
shown.CFrame = CFrame.new(0, 90, 0)
local mp = AssetService:CreateMeshPartAsync(Content.fromUri("res://../../../scripts/models/steven-skull.obj"))
mp.Name = "BakedMesh"
mp.Anchored = true
mp.CFrame = CFrame.new(0, 90, 0)
mp.TextureContent = baked
mp.Parent = workspace
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

func _initialize() -> void:
	print("Object and EditableImage")
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
		world.run_chunk("objects", SCRIPT % [PNG, WIDE])
	elif phase == 1 and (_c("DONE") == "ok" or not errors.is_empty() or t > 25.0) and t > 1.5:
		phase = 2
		check(_c("TYPEOF") == "Object Instance", "typeof an EditableImage is Object, a Part's Instance: %s" % _c("TYPEOF"))
		check(_c("ISA") == "true false true", "an EditableImage IsA Object and not an Instance; a Part is both: %s" % _c("ISA"))
		check(_c("CLASSNAME") == "EditableImage EditableImage", "ClassName, and tostring is the class (an Object has no Name): %s" % _c("CLASSNAME"))
		check(_c("NAME") == "Name is not a valid member of EditableImage", "no Name: %s" % _c("NAME"))
		check(_c("PARENT") == "Parent is not a valid member of EditableImage", "no Parent, in the words the devforum quotes: %s" % _c("PARENT"))
		check(_c("FIND") == "FindFirstChild is not a valid member of EditableImage", "no Instance methods: %s" % _c("FIND"))
		check(_c("NEW").find("Unable to create an Instance") >= 0, "Instance.new cannot make one: %s" % _c("NEW"))
		check(_c("SIZERO").find("read only") >= 0, "Size is read-only: %s" % _c("SIZERO"))
		check(_c("REMOVED") == "WritePixels is not a valid member of EditableImage | Resize is not a valid member of EditableImage",
			"WritePixels and Resize are gone: %s" % _c("REMOVED"))
		check(_c("CHANGED") == "RBXScriptSignal RBXScriptSignal", "Changed and GetPropertyChangedSignal are Object's")
		check(_c("TOOBIG") != "ok", "an image over 1024 a side is refused: %s" % _c("TOOBIG"))
		check(_c("ENUM") == "1 2 3 4 5 6 7", "ImageCombineType numbered as Roblox numbers it: %s" % _c("ENUM"))
		check(_c("SOURCEOVER") == "255,0,0,128 128,0,127,255", "BlendSourceOver: source over, a transparent destination's colour not counted: %s" % _c("SOURCEOVER"))
		check(_c("ALPHABLEND") == "128,0,0,128 128,0,127,255", "AlphaBlend: the destination's colour counts whatever its alpha: %s" % _c("ALPHABLEND"))
		check(_c("OVERWRITE") == "255,0,0,128", "Overwrite replaces the pixel: %s" % _c("OVERWRITE"))
		check(_c("ADD") == "200,255,100,255", "Add adds, and stops at 255: %s" % _c("ADD"))
		check(_c("MULTIPLY") == "100,200,0,255", "Multiply multiplies as values between 0 and 1: %s" % _c("MULTIPLY"))
		check(_c("SUBTRACT") == "50,0,100,0", "Subtract takes the source from the destination: %s" % _c("SUBTRACT"))
		var nm := _c("NORMALMAP").split(",")
		var n := Vector3(float(nm[0]) / 255 * 2 - 1, float(nm[1]) / 255 * 2 - 1, float(nm[2]) / 255 * 2 - 1) if nm.size() == 4 else Vector3.ZERO
		check(nm.size() == 4 and abs(n.length() - 1.0) < 0.02, "NormalMapBlend leaves a unit normal: %s (length %.3f)" % [_c("NORMALMAP"), n.length()])
		check(_c("RECTOUTSIDE") != "ok", "DrawRectangle's position cannot be outside the image: %s" % _c("RECTOUTSIDE"))
		var aa := _c("AA").split(" ")
		check(aa.size() == 2 and int(aa[0]) > 20 and int(aa[1]) == 0, "a circle's edge is soft anti-aliased and hard without: %s" % _c("AA"))
		check(_c("LINEDEFAULTSOFT") == "true", "DrawLine draws, anti-aliased by default")
		check(_c("SCALED") == "255,0,0,255 0,0,255,255 0,0,0,0", "scaled 2x about its middle, placed at the pivot: %s" % _c("SCALED"))
		check(_c("ROTATED") == "255,0,0,255 0,0,255,255 0,0,0,0", "turned 90 degrees clockwise, red above blue: %s" % _c("ROTATED"))
		check(_c("DESTROYED").find("destroyed") >= 0, "a destroyed image cannot be drawn into: %s" % _c("DESTROYED"))
		check(_c("HELD") == "EditableImage 10,20,30,255", "an image only an ImageLabel's ImageContent holds is still there: %s" % _c("HELD"))
		var file := Image.load_from_file(ProjectSettings.globalize_path(PNG))
		file.convert(Image.FORMAT_RGBA8)
		var c := file.get_pixel(3, 2)
		var want := "%d %d %d,%d,%d,%d" % [file.get_width(), file.get_height(), roundi(c.r * 255), roundi(c.g * 255), roundi(c.b * 255), roundi(c.a * 255)]
		check(_c("FROMURI") == want, "CreateEditableImageAsync loads a file, size and pixels: %s, the file %s" % [_c("FROMURI"), want])
		check(_c("FROMMISSING") == "true", "and throws when it cannot")
		check(_c("FROMWIDE").find("larger than 1024") >= 0, "or when the image is past 1024 a side: %s" % _c("FROMWIDE"))
		check(_c("COPY") == "10,20,30,255 1,2,3,4", "from an EditableImage it is a copy: %s" % _c("COPY"))
		check(_c("BAKED") == "Enum.CreateContentResult.Success Enum.ContentSourceType.Opaque nil nil Opaque",
			"CreateDataModelContentAsync: Success, and an Opaque Content with no Uri or Object: %s" % _c("BAKED"))
		check(_c("BAKEDBACK") == "10,20,30,255", "baked is a copy, and CreateEditableImageAsync turns it back: %s" % _c("BAKEDBACK"))
		check(_c("BAKEDPROP") == "true true", "it drives an image property, reading \"\" through the string")
		check(_c("BAKEDURIONLY") == "true", "not a property that only takes asset uris")
		check(_c("BAKEOBJONLY") == "true", "and only an Editable can be baked")
		var mesh_id := _child(_child(0, "Workspace"), "BakedMesh")
		var mesh = world.get_part_mesh(mesh_id) if mesh_id != 0 else null
		var size := Vector2()
		if mesh is MeshInstance3D:
			var mat = mesh.material_override
			if mat == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0: mat = mesh.get_active_material(0)
			if mat is BaseMaterial3D and mat.albedo_texture != null: size = mat.albedo_texture.get_size()
		check(size == Vector2(3, 3), "the host draws baked content on a MeshPart: texture %s" % size)
		check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

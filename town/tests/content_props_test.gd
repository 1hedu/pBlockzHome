# Every Content property beside the older string property it aliases: which pairs exist comes
# from rbx-dom's ContentIdToContent migrations, which may hold an object from the class
# reference. The fixtures are Studio 0.663's own files, from rbx-test-files.
#
#   godot --headless --path . -s res://tests/content_props_test.gd
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

const FIXTURES := "res://../../test/fixtures/"

const SCRIPT := """
local function say(k, v) print("C " .. k .. " " .. tostring(v)) end
local function throws(f) local ok, e = pcall(f) return not ok, e end
local AssetService = game:GetService("AssetService")

-- The rules, on an ImageLabel
local l = Instance.new("ImageLabel")
l.Image = "rbxassetid://5"
say("STRTOCON", l.ImageContent == Content.fromUri("rbxassetid://5"))
l.ImageContent = Content.fromAssetId(7)
say("CONTOSTR", l.Image == "rbxassetid://7")
local img = AssetService:CreateEditableImage({ Size = Vector2.new(7, 5) })
l.ImageContent = Content.fromObject(img)
say("OBJSTR", l.Image == "" and l.ImageContent.Object == img)
l.Image = "rbxassetid://9"
say("STRAFTEROBJ", l.ImageContent == Content.fromAssetId(9))
l.ImageContent = Content.fromObject(img)
l.Image = ""
say("EMPTYAFTEROBJ", l.ImageContent == Content.none)
l.ImageContent = Content.none
say("NONESTR", l.Image == "")

-- Both names announce a change to either
local heard = {}
l:GetPropertyChangedSignal("Image"):Connect(function() heard.image = (heard.image or 0) + 1 end)
l:GetPropertyChangedSignal("ImageContent"):Connect(function() heard.content = (heard.content or 0) + 1 end)
l.ImageContent = Content.fromAssetId(11)
l.Image = "rbxassetid://12"
task.wait()
say("SIGNALS", ("%d %d"):format(heard.image or 0, heard.content or 0))

-- Every pair on a class the kit has, both ways
local pairs_ = {
	{ "Animation", "AnimationId", "AnimationContent" }, { "Tool", "TextureId", "TextureContent" },
	{ "Beam", "Texture", "TextureContent" }, { "ClickDetector", "CursorIcon", "CursorIconContent" },
	{ "Decal", "Texture", "TextureContent" }, { "Texture", "Texture", "TextureContent" },
	{ "SpecialMesh", "MeshId", "MeshContent" }, { "SpecialMesh", "TextureId", "TextureContent" },
	{ "ImageButton", "Image", "ImageContent" }, { "ImageButton", "HoverImage", "HoverImageContent" },
	{ "ImageButton", "PressedImage", "PressedImageContent" }, { "ImageLabel", "Image", "ImageContent" },
	{ "MaterialVariant", "ColorMap", "ColorMapContent" }, { "MaterialVariant", "MetalnessMap", "MetalnessMapContent" },
	{ "MaterialVariant", "NormalMap", "NormalMapContent" }, { "MaterialVariant", "RoughnessMap", "RoughnessMapContent" },
	{ "MeshPart", "TextureID", "TextureContent" },   -- (MeshId / MeshContent: no script writes them; meshpart_async_test)
	{ "ParticleEmitter", "Texture", "TextureContent" }, { "ScrollingFrame", "BottomImage", "BottomImageContent" },
	{ "ScrollingFrame", "MidImage", "MidImageContent" }, { "ScrollingFrame", "TopImage", "TopImageContent" },
	{ "Sky", "MoonTextureId", "MoonTextureContent" }, { "Sky", "SkyboxBk", "SkyboxBackContent" },
	{ "Sky", "SkyboxDn", "SkyboxDownContent" }, { "Sky", "SkyboxFt", "SkyboxFrontContent" },
	{ "Sky", "SkyboxLf", "SkyboxLeftContent" }, { "Sky", "SkyboxRt", "SkyboxRightContent" },
	{ "Sky", "SkyboxUp", "SkyboxUpContent" }, { "Sky", "SunTextureId", "SunTextureContent" },
	{ "Sound", "SoundId", "AudioContent" }, { "SurfaceAppearance", "ColorMap", "ColorMapContent" },
	{ "SurfaceAppearance", "MetalnessMap", "MetalnessMapContent" }, { "SurfaceAppearance", "NormalMap", "NormalMapContent" },
	{ "SurfaceAppearance", "RoughnessMap", "RoughnessMapContent" }, { "Trail", "Texture", "TextureContent" },
	{ "UserInputService", "MouseIcon", "MouseIconContent" }, { "WrapLayer", "CageMeshId", "CageMeshContent" },
	{ "WrapLayer", "ReferenceMeshId", "ReferenceMeshContent" },
}
local bad = {}
for _, p in ipairs(pairs_) do
	local ok, err = pcall(function()
		local i = p[1] == "UserInputService" and game:GetService("UserInputService") or Instance.new(p[1])
		i[p[2]] = "rbxassetid://101"
		assert(i[p[3]] == Content.fromAssetId(101), "string -> content")
		i[p[3]] = Content.fromUri("rbxasset://x.png")
		assert(i[p[2]] == "rbxasset://x.png", "content -> string")
		i[p[3]] = Content.none
		assert(i[p[2]] == "", "none -> string")
	end)
	if not ok then table.insert(bad, p[1] .. "." .. p[3] .. ": " .. tostring(err)) end
end
say("PAIRS", #bad == 0 and ("all " .. #pairs_) or table.concat(bad, " | "))

-- A default carried over: ParticleEmitter's sparkles
say("DEFAULT", Instance.new("ParticleEmitter").TextureContent == Content.fromUri("rbxasset://textures/particles/sparkles_main.dds"))

-- What each may hold
local button = Instance.new("ImageButton")
say("URIONLY", (throws(function() button.HoverImageContent = Content.fromObject(img) end))
	and (throws(function() game:GetService("UserInputService").MouseIconContent = Content.fromObject(img) end))
	and (throws(function() Instance.new("Sound").AudioContent = Content.fromObject(img) end)))
say("WRONGKIND", (throws(function() button.ImageContent = Content.fromObject(Instance.new("Part")) end)))
local mp = Instance.new("MeshPart")
say("MESHNOTIMAGE", (throws(function() mp.MeshContent = Content.fromObject(img) end)))
say("IMAGEOK", pcall(function() mp.TextureContent = Content.fromObject(img); Instance.new("Beam").TextureContent = Content.fromObject(img) end))

-- An EditableImage on a MeshPart, for the host to draw
local drawn = AssetService:CreateEditableImage({ Size = Vector2.new(13, 9) })
drawn:DrawRectangle(Vector2.zero, Vector2.new(13, 9), Color3.new(1, 0, 0), 0, Enum.ImageCombineType.Overwrite)
local shown = Instance.new("MeshPart")
shown.Name = "ShowsEditable"
shown.Anchored = true
shown.CFrame = CFrame.new(0, 80, 0)
shown.TextureContent = Content.fromObject(drawn)
shown.Parent = workspace

-- The fixtures
local function fixture(name)
	return workspace:WaitForChild(name, 10)
end
local ilb, ilx = fixture("ILCBinary"), fixture("ILCXml")
for tag, m in pairs({ BIN = ilb, XML = ilx }) do
	say("IL" .. tag, m and ("%s|%s|%s|%s"):format(
		tostring(m.Placeholder.ImageContent.Uri), m.Placeholder.Image,
		tostring(m.SpawnLocation.ImageContent.Uri), tostring(m.None.ImageContent == Content.none)) or "missing")
end
local mb, mx = fixture("MixedBinary"), fixture("MixedXml")
for tag, m in pairs({ BIN = mb, XML = mx }) do
	say("MIX" .. tag, m and ("%s|%s|%s|%s"):format(
		m.Decal_SpawnLocation.Texture, tostring(m.Decal_SpawnLocation.TextureContent.Uri),
		tostring(m.Decal_None.TextureContent == Content.none), tostring(m.ImageLabel_SpawnLocation.ImageContent.Uri)) or "missing")
end
say("DONE", "ok")
"""

# The PluginSecurity maps from a game's own Script, which does not have the security the
# command bar chunk above runs with.
const GAME_SCRIPT := """
local mv = Instance.new("MaterialVariant")
local sa = Instance.new("SurfaceAppearance")
local readMap = pcall(function() return mv.ColorMap end)
local readMapContent = pcall(function() return mv.ColorMapContent end)
local readSurface = pcall(function() return sa.ColorMapContent end)
local writeSurface = pcall(function() sa.ColorMapContent = Content.fromUri("rbxasset://x.png") end)
print(("R GAME %s %s %s %s"):format(tostring(readMap), tostring(readMapContent), tostring(readSurface), tostring(writeSurface)))
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
	print("Content properties")
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
		var dir := ProjectSettings.globalize_path(FIXTURES)
		world.load_file("Workspace/ILCBinary.rbxm", Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(dir.path_join("imagelabel-content.rbxm"))))
		world.load_file("Workspace/ILCXml.rbxmx", FileAccess.get_file_as_string(dir.path_join("imagelabel-content.rbxmx")))
		world.load_file("Workspace/MixedBinary.rbxm", Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(dir.path_join("content-mixed.rbxm"))))
		world.load_file("Workspace/MixedXml.rbxmx", FileAccess.get_file_as_string(dir.path_join("content-mixed.rbxmx")))
		world.run_chunk("content props", SCRIPT)
		world.add_model("ServerScriptService", "GameRead", JSON.stringify({"className": "Script", "name": "GameRead", "properties": {"Source": GAME_SCRIPT}}))
	elif phase == 1 and (_c("DONE") == "ok" or t > 30.0) and t > 1.5:
		phase = 2
		check(_c("STRTOCON") == "true", "writing Image sets ImageContent to Content.fromUri of it")
		check(_c("CONTOSTR") == "true", "writing ImageContent leaves its uri in Image")
		check(_c("OBJSTR") == "true", "an object in ImageContent reads as \"\" through Image")
		check(_c("STRAFTEROBJ") == "true", "writing Image over an object replaces it with the uri")
		check(_c("EMPTYAFTEROBJ") == "true", "writing \"\" to Image over an object is Content.fromUri(\"\"), which is none")
		check(_c("NONESTR") == "true", "Content.none reads as \"\"")
		check(_c("SIGNALS") == "2 2", "a write to either fires both properties' changed signals: %s" % _c("SIGNALS"))
		check(_c("PAIRS").begins_with("all "), "every pair reads and writes the other: %s" % _c("PAIRS"))
		check(_c("DEFAULT") == "true", "a Content property's default is its string twin's")
		check(_c("URIONLY") == "true", "a property that only supports asset uris refuses an object")
		check(_c("WRONGKIND") == "true", "an image property refuses an object that is not an EditableImage")
		check(_c("MESHNOTIMAGE") == "true", "MeshContent refuses an EditableImage")
		check(_c("IMAGEOK") == "true", "TextureContent on a MeshPart and a Beam take one")
		var game := ""
		for s in said:
			if String(s).begins_with("R GAME "): game = String(s).substr(7)
		check(game == "false false true false",
			"a game script cannot read MaterialVariant's maps or write SurfaceAppearance's, and can read SurfaceAppearance's: %s" % game)
		const PLACEHOLDER := "rbxasset://textures/ui/GuiImagePlaceholder.png"
		const SPAWN := "rbxasset://textures/SpawnLocation.png"
		var il := "%s|%s|%s|true" % [PLACEHOLDER, PLACEHOLDER, SPAWN]
		check(_c("ILBIN") == il, "Studio's binary ImageLabels load their ImageContent (value type 0x22): %s" % _c("ILBIN"))
		check(_c("ILXML") == il, "and its XML ones (<uri>, <null>): %s" % _c("ILXML"))
		var mix := "%s|%s|true|%s" % [SPAWN, SPAWN, SPAWN]
		check(_c("MIXBIN") == mix, "a Decal's Texture as a 0.663 file wrote it, beside ImageContent, binary: %s" % _c("MIXBIN"))
		check(_c("MIXXML") == mix, "and XML: %s" % _c("MIXXML"))
		var ws := _child(0, "Workspace")
		var part_id := _child(ws, "ShowsEditable")
		var mesh = world.get_part_mesh(part_id) if part_id != 0 else null
		var size := Vector2()
		if mesh is MeshInstance3D:
			var mat = mesh.material_override
			if mat == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0: mat = mesh.get_active_material(0)
			if mat is BaseMaterial3D and mat.albedo_texture != null: size = mat.albedo_texture.get_size()
		check(size == Vector2(13, 9), "the host draws an EditableImage through MeshPart.TextureContent: texture %s" % size)
		var members: Dictionary = world.get_class_members("Sound")
		check(PackedStringArray(members.get("properties", [])).has("AudioContent"), "Sound.AudioContent is a member")
		var sound_props := {}
		var twin := ""
		var ss := _child(0, "SoundService")
		check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

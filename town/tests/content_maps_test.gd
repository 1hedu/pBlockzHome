# Decal's ColorMap aliases and PBR maps, SurfaceAppearance's emissive mask and the engine-only
# packs, held to the class reference and to rbx-dom's storage database. Decal.ColorMap and
# ColorMapContent are further names for Texture and TextureContent: NotReplicated, never saved.
#
#   godot --headless --path . -s res://tests/content_maps_test.gd
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

const IMG := "res://panel-screener.png"
const MASK := "res://sky/MoonEarth_SkyboxUp.png"

const SCRIPT := """
local function say(k, v) print("C " .. k .. " " .. tostring(v)) end
local IMG, MASK = "%s", "%s"

local part = Instance.new("Part")
part.Name = "Wall"
part.Size = Vector3.new(6, 6, 1)
part.Anchored = true
part.CFrame = CFrame.new(0, 70, 0)
part.Parent = workspace

local d = Instance.new("Decal")
d.Name = "Poster"
local heard = 0
d:GetPropertyChangedSignal("ColorMapContent"):Connect(function() heard += 1 end)
d.ColorMapContent = Content.fromUri(IMG)
say("ALIAS", d.TextureContent == Content.fromUri(IMG) and d.Texture == IMG and d.ColorMap == IMG)
d.Texture = MASK
say("ALIASBACK", d.ColorMapContent == Content.fromUri(MASK) and d.ColorMap == MASK)
d.ColorMap = IMG
say("ALIASSTR", d.TextureContent == Content.fromUri(IMG))
task.wait()
say("ALIASSIGNAL", heard)

d.NormalMapContent = Content.fromUri(IMG)
say("PBRPAIR", d.NormalMap == IMG)
d.RoughnessMap = MASK
say("PBRPAIR2", d.RoughnessMapContent == Content.fromUri(MASK))
d.MetalnessMapContent = Content.fromUri(MASK)
d.Parent = part

-- A MeshPart wearing a SurfaceAppearance with an emissive mask
local glowing = Instance.new("Part")
glowing.Name = "Glowing"
glowing.Size = Vector3.new(4, 4, 4)
glowing.Color = Color3.new(0.5, 1, 0.25)
glowing.Anchored = true
glowing.CFrame = CFrame.new(10, 70, 0)
glowing.Parent = workspace
local sa = Instance.new("SurfaceAppearance")
say("EMISSIVEDEFAULTS", ("%%s %%s %%s"):format(tostring(sa.EmissiveMaskContent == Content.none), tostring(sa.EmissiveStrength), tostring(sa.EmissiveTint)))
sa.EmissiveMaskContent = Content.fromUri(MASK)
sa.EmissiveStrength = 3
sa.EmissiveTint = Color3.new(1, 0.5, 0.5)
sa.Parent = glowing

-- The engine's own, from the command bar too
local ok1 = pcall(function() return d.TexturePackContent end)
local ok2 = pcall(function() return Instance.new("WrapLayer").HSRAssetId end)
local ok3 = pcall(function() Instance.new("WrapLayer").HSRContent = Content.fromUri(IMG) end)
say("ENGINEONLY", ("%%s %%s %%s"):format(tostring(ok1), tostring(ok2), tostring(ok3)))
say("DONE", "ok")
"""

# The same members from a game's own Script, which does not have the PluginSecurity the
# command bar chunk above runs with.
const GAME_SCRIPT := """
local d = Instance.new("Decal")
local sa = Instance.new("SurfaceAppearance")
local mv = Instance.new("MaterialVariant")
local r = {}
r[#r + 1] = pcall(function() return d.NormalMap end)                                  -- false: PluginSecurity read
r[#r + 1] = pcall(function() return d.NormalMapContent end)                           -- true
r[#r + 1] = pcall(function() d.NormalMapContent = Content.fromUri("a.png") end)       -- false: PluginSecurity write
r[#r + 1] = pcall(function() d.ColorMapContent = Content.fromUri("a.png") end)        -- true
r[#r + 1] = pcall(function() return sa.EmissiveMaskContent end)                       -- true
r[#r + 1] = pcall(function() sa.EmissiveMaskContent = Content.fromUri("a.png") end)   -- false
r[#r + 1] = pcall(function() return mv.EmissiveMaskContent end)                       -- false
r[#r + 1] = pcall(function() sa.EmissiveStrength = 2 end)                             -- true
for i, v in ipairs(r) do r[i] = tostring(v) end
print("R GAME " .. table.concat(r, " "))
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
	print("Content maps")
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
		world.run_chunk("maps", SCRIPT % [IMG, MASK])
		world.add_model("ServerScriptService", "GameMaps", JSON.stringify({"className": "Script", "name": "GameMaps", "properties": {"Source": GAME_SCRIPT}}))
	elif phase == 1 and (_c("DONE") == "ok" or not errors.is_empty() or t > 20.0) and t > 1.5:
		phase = 2
		check(_c("ALIAS") == "true", "ColorMapContent is TextureContent, and ColorMap is Texture")
		check(_c("ALIASBACK") == "true", "writing Texture is seen through ColorMapContent")
		check(_c("ALIASSTR") == "true", "and writing ColorMap through TextureContent")
		check(_c("ALIASSIGNAL") == "3", "ColorMapContent's changed signal fires for each of the three writes: %s" % _c("ALIASSIGNAL"))
		check(_c("PBRPAIR") == "true" and _c("PBRPAIR2") == "true", "the PBR maps read and write their string twins")
		check(_c("EMISSIVEDEFAULTS") == "true 1 1, 1, 1", "EmissiveMaskContent none, EmissiveStrength 1, EmissiveTint white: %s" % _c("EMISSIVEDEFAULTS"))
		check(_c("ENGINEONLY") == "false false false", "TexturePackContent and HSR are nobody's to read or write, command bar included: %s" % _c("ENGINEONLY"))
		var game := ""
		for s in said:
			if String(s).begins_with("R GAME "): game = String(s).substr(7)
		check(game == "false true false true true false false true", "a game script, as PluginSecurity allows it: %s" % game)

		# Host side: the maps land on the decal's Godot material
		var ws := _child(0, "Workspace")
		var wall := _child(ws, "Wall")
		var mesh = world.get_part_mesh(wall) if wall != 0 else null
		var poster: MeshInstance3D = mesh.get_node_or_null("Poster") if mesh != null else null
		var dm: StandardMaterial3D = poster.material_override if poster != null else null
		# The two files differ in size, which is how the textures are told apart
		var img_size := Image.load_from_file(ProjectSettings.globalize_path(IMG)).get_size()
		var mask_size := Image.load_from_file(ProjectSettings.globalize_path(MASK)).get_size()
		check(dm != null and dm.albedo_texture != null and dm.albedo_texture.get_size() == Vector2(img_size),
			"the decal draws ColorMapContent's image: %s, the file is %s" % [dm.albedo_texture.get_size() if dm != null and dm.albedo_texture != null else "none", img_size])
		check(dm != null and dm.normal_enabled and dm.normal_texture != null, "with its normal map")
		check(dm != null and dm.roughness_texture != null and dm.metallic_texture != null and dm.roughness == 1.0 and dm.metallic == 1.0,
			"and its roughness and metalness maps, each replacing the flat value")
		var glowing := _child(ws, "Glowing")
		var gmesh = world.get_part_mesh(glowing) if glowing != 0 else null
		var gm = null
		if gmesh is MeshInstance3D:
			gm = gmesh.material_override
			if gm == null and gmesh.mesh != null and gmesh.mesh.get_surface_count() > 0: gm = gmesh.get_active_material(0)
		var glow: ShaderMaterial = gm.next_pass if gm is StandardMaterial3D else null
		var code: String = glow.shader.code if glow != null and glow.shader != null else ""
		check(code.contains("unshaded") and code.contains("blend_add"), "an emissive mask adds an unlit pass over the lit one")
		var mask_tex = glow.get_shader_parameter("mask_tex") if glow != null else null
		check(img_size != mask_size and mask_tex != null and mask_tex.get_size() == Vector2(mask_size),
			"masked by EmissiveMaskContent")
		var want := Color(0.5 * 1 * 3, 1 * 0.5 * 3, 0.25 * 0.5 * 3)
		var got = glow.get_shader_parameter("glow") if glow != null else Vector3.ZERO
		check(Color(got.x, got.y, got.z).is_equal_approx(want),
			"in the albedo's colour times EmissiveTint times EmissiveStrength: %s" % got)
		var decal_id := _child(wall, "Poster")
		var alias := {}
		for p in world.get_properties(decal_id, true):
			if p.name == "ColorMapContent": alias = p
		check(str(alias.get("alias", "")) == "TextureContent" and not alias.get("is_default", true),
			"the panel shows ColorMapContent as TextureContent's value, marked so a save skips it")
		check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

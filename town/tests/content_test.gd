# The Content datatype against its reference (creator-docs, datatypes/Content.yaml): typeof,
# the members and their nils, fromUri / fromAssetId / fromObject and Content.none, equality,
# read-only-ness, the strong reference to the object, and Content as a property value.
#
#   godot --headless --path . -s res://tests/content_test.gd
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

const SCRIPT := """
local function say(k, v) print("C " .. k .. " " .. tostring(v)) end
local function throws(f, ...) return not pcall(f, ...) end

local u = Content.fromUri("rbxassetid://123")
say("TYPEOF", typeof(u))
say("URI", u.SourceType == Enum.ContentSourceType.Uri and u.Uri == "rbxassetid://123" and u.Object == nil and u.Opaque == nil)
say("EMPTYURI", Content.fromUri("") == Content.none)
say("NONE", Content.none.SourceType == Enum.ContentSourceType.None and Content.none.Uri == nil and Content.none.Object == nil)
say("ASSETID", Content.fromAssetId(123) == u and Content.fromAssetId(123).Uri == "rbxassetid://" .. tostring(123))
say("ASSETID0", Content.fromAssetId(0) == Content.none)
say("NONFINITE", throws(Content.fromAssetId, math.huge) and throws(Content.fromAssetId, 0/0) and throws(Content.fromAssetId, -math.huge))
-- Luau turns a numeric string into the number, as Roblox's own engineers describe it doing here
say("NUMSTRING", Content.fromAssetId("77").Uri == "rbxassetid://77")

local AssetService = game:GetService("AssetService")
local img = AssetService:CreateEditableImage({ Size = Vector2.new(4, 4) })
local o = Content.fromObject(img)
say("OBJECT", o.SourceType == Enum.ContentSourceType.Object and o.Object == img and o.Uri == nil)
say("OBJNIL", throws(Content.fromObject, nil) and throws(Content.fromObject))
say("OBJBAD", throws(Content.fromObject, 5) and throws(Content.fromObject, "rbxassetid://1"))
say("EQ", Content.fromObject(img) == o and Content.fromUri("a") ~= Content.fromUri("b") and o ~= u and u ~= "rbxassetid://123")
say("READONLY", throws(function() u.Uri = "x" end) and throws(function() u.SourceType = Enum.ContentSourceType.None end))
say("BADMEMBER", throws(function() return u.Nope end))
say("OPAQUE", Enum.ContentSourceType.Opaque.Value == 3)

-- A strong reference: the Content keeps the object alive and hands back the same one
local part = Instance.new("Part")
part.Name = "Held"
local held = Content.fromObject(part)
part = nil
-- a script cannot run the collector (collectgarbage takes only "count"), so make it run
local before = collectgarbage("count")
for i = 1, 400000 do local _ = { i } end
say("GC", typeof(before) == "number" and gcinfo() >= 0 and not pcall(collectgarbage, "collect") and not pcall(collectgarbage))
say("STRONG", held.Object ~= nil and held.Object.Name == "Held")

-- As a property value
local label = Instance.new("ImageLabel")
label.ImageContent = Content.fromAssetId(55)
say("PROPURI", label.ImageContent == Content.fromAssetId(55) and label.Image == "rbxassetid://55")
label.ImageContent = o
say("PROPOBJ", label.ImageContent.Object == img and label.ImageContent.SourceType == Enum.ContentSourceType.Object)
label.ImageContent = Content.none
say("PROPNONE", label.ImageContent == Content.none and label.Image == "")
say("PROPTYPE", throws(function() label.ImageContent = "rbxassetid://1" end))
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

func _initialize() -> void:
	print("Content")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): errors.append("%s: %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and world.is_node_ready() and t > 2.0:
		phase = 1; t = 0.0
		world.run_chunk("content", SCRIPT)
	elif phase == 1 and (_c("DONE") == "ok" or not errors.is_empty() or t > 20.0):
		phase = 2
		check(_c("TYPEOF") == "Content", "typeof says Content: %s" % _c("TYPEOF"))
		check(_c("URI") == "true", "fromUri: SourceType Uri, the uri, Object and Opaque nil")
		check(_c("EMPTYURI") == "true", "fromUri(\"\") is Content.none")
		check(_c("NONE") == "true", "Content.none: SourceType None, Uri and Object nil")
		check(_c("ASSETID") == "true", "fromAssetId(n) is fromUri(\"rbxassetid://\" .. tostring(n))")
		check(_c("ASSETID0") == "true", "fromAssetId(0) is Content.none")
		check(_c("NONFINITE") == "true", "fromAssetId throws on a non-finite id")
		check(_c("NUMSTRING") == "true", "a numeric string is taken as its number")
		check(_c("OBJECT") == "true", "fromObject: SourceType Object, the object, Uri nil")
		check(_c("OBJNIL") == "true", "fromObject(nil) throws")
		check(_c("OBJBAD") == "true", "fromObject of something that is not an Object throws")
		check(_c("EQ") == "true", "Contents compare by what they hold")
		check(_c("READONLY") == "true", "a Content cannot be changed")
		check(_c("BADMEMBER") == "true", "an unknown member throws")
		check(_c("OPAQUE") == "true", "Enum.ContentSourceType has Opaque = 3")
		check(_c("GC") == "true", "collectgarbage(\"count\") and gcinfo() read memory; collectgarbage refuses anything else")
		check(_c("STRONG") == "true", "a Content holds its object strongly")
		check(_c("PROPURI") == "true", "a uri Content set on ImageContent reads back equal, and Image follows")
		check(_c("PROPOBJ") == "true", "an object Content reads back with its object")
		check(_c("PROPNONE") == "true", "Content.none clears it")
		check(_c("PROPTYPE") == "true", "a string is not a Content")
		check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

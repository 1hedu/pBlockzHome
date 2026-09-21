# The draft cape tried on at the drawing table: built where it is looked at, from the panel's
# drawing and shared/Cape.luau, so trying one on signs nothing and reaches nowhere. It rides on
# Decal.TextureContent, because a place cannot write a file for Texture to name.
#
#   godot --headless --path . -s res://tests/paint_test.gd
extends SceneTree

var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var passed := 0
var failed := 0
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS ", what)
	else:
		failed += 1
		printerr("  FAIL ", what)

## A 20x26 sheet, one palette character per cell, "0" blank, with a band across the middle.
func drawing(colour: String) -> String:
	var out := ""
	for y in 26:
		for x in 20:
			out += colour if y > 8 and y < 18 else "0"
	return out

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, txt): said.append(txt))
	print("== the drawing table")

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var at := String(line).find(prefix)
		if at >= 0:
			out.append(String(line).substr(at + prefix.length()).strip_edges())
	return out

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 14.0:
		phase = 1
		said.clear()
		# Client-side: the drawing table is a LocalScript and an EditableImage belongs to the
		# machine looking at it.
		world.run_client_chunk("draft", """
local rs = game:GetService("ReplicatedStorage")
local Cape = require(rs:WaitForChild("Cape"))
local red, blue = "%s", "%s"

local a, image = Cape.preview(red, nil)
local names = {}
for _, c in ipairs(a:GetChildren()) do table.insert(names, c.Name) end
table.sort(names)
print("DRAFT class=" .. a.ClassName .. " name=" .. a.Name .. " parts=" .. table.concat(names, ","))

local handle = a:FindFirstChild("Handle")
local decal = handle and handle:FindFirstChild("DecalBack")
print("DECAL face=" .. tostring(decal and decal.Face) .. " texture='" .. tostring(decal and decal.Texture) .. "'")

-- Read the Content straight back off the property: what a place gets when it asks what a
-- face is showing has to be the image it put there, not an empty one.
local got = decal.TextureContent
print("CONTENT source=" .. tostring(got.SourceType) .. " same=" .. tostring(got.Object == image))

-- A second draft is its own picture. One shared image is how "it keeps showing me the
-- first thing I ever drew" happens, and it is silent.
local b, image2 = Cape.preview(blue, nil)
print("SECOND different=" .. tostring(image2 ~= image))

-- On a body, which is the whole point: an Accessory with a BodyBackAttachment finds the
-- torso's own attachment and hangs off it.
local neck = handle:FindFirstChild("BodyBackAttachment")
print("NECK " .. tostring(neck ~= nil))
a:Destroy() b:Destroy()
""" % [drawing("4"), drawing("9")])
	elif phase == 1 and t > 17.0:
		phase = 2
		var draft := _lines("DRAFT ")
		var decal := _lines("DECAL ")
		var content := _lines("CONTENT ")
		check(draft.size() > 0 and String(draft[0]).find("class=Accessory") >= 0,
			"the draft is an Accessory: %s" % str(draft))
		check(draft.size() > 0 and String(draft[0]).find("EdgeLeft,EdgeRight,Handle") >= 0,
			"with the same slight taper as a real cape: %s" % str(draft))
		check(decal.size() > 0 and String(decal[0]).find("face=Enum.NormalId.Back") >= 0,
			"the drawing goes on the back, which is the side you cannot see: %s" % str(decal))
		check(decal.size() > 0 and String(decal[0]).find("texture=''") >= 0,
			"and names no file, because there is no file: %s" % str(decal))
		check(content.size() > 0 and String(content[0]).find("same=true") >= 0,
			"TextureContent gives back the image it was given: %s" % str(content))
		check(content.size() > 0 and String(content[0]).find("source=Enum.ContentSourceType.Object") >= 0,
			"as an object rather than a uri: %s" % str(content))
		check(_lines("SECOND ").has("different=true"),
			"a second draft draws its own picture: %s" % str(_lines("SECOND ")))
		check(_lines("NECK ").has("true"), "and it hangs off the back of you")
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed else 0)
	return false

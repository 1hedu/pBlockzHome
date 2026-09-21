# Solid modelling from a script: BasePart:UnionAsync / SubtractAsync / IntersectAsync, and
# GeometryService's three. The ring's own MeshData is decoded and every vertex required to sit
# outside the hole and inside the rim, so a subtract that cut nothing fails.
#
#   godot --headless --path . -s res://tests/solid_test.gd
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

const SCRIPT := """
local function vec(v) return ("%.3f,%.3f,%.3f"):format(v.X, v.Y, v.Z) end

-- A ring: a cylinder two across and a fifth thick, less one a stud and a fifth across.
local outer = Instance.new("Part")
outer.Shape = Enum.PartType.Cylinder
outer.Size = Vector3.new(0.2, 2, 2)
outer.Color = Color3.fromRGB(200, 40, 40)
outer.Material = Enum.Material.Metal
outer.Anchored = true
outer.CFrame = CFrame.new(0, 40, 0) * CFrame.fromOrientation(0, math.rad(30), 0)
outer.Parent = workspace
local hole = Instance.new("Part")
hole.Shape = Enum.PartType.Cylinder
hole.Size = Vector3.new(0.6, 1.2, 1.2)
hole.CFrame = outer.CFrame
hole.Parent = workspace

local ok, ring = pcall(function() return outer:SubtractAsync({ hole }) end)
print("RING ok=" .. tostring(ok) .. " class=" .. (ok and ring.ClassName or tostring(ring)))
if ok then
	print("RINGNAME " .. ring.Name)
	print("RINGPARENT " .. tostring(ring.Parent))
	print("RINGSIZE " .. vec(ring.Size))
	print("RINGORIENT " .. vec(ring.Orientation) .. " caller " .. vec(outer.Orientation))
	print("RINGPOS " .. vec(ring.Position) .. " caller " .. vec(outer.Position))
	print("RINGLOOK " .. tostring(ring.Color == outer.Color) .. " " .. tostring(ring.Material == outer.Material))
	print("RINGDATA " .. ring.MeshData)
	ring.Parent = workspace
	-- Cloned, alone and inside a model: wearing an item is a Clone of its template, and a
	-- union that does not survive one never reaches the character.
	local copy = ring:Clone()
	print("CLONE " .. (copy and (copy.ClassName .. " " .. tostring(#copy.MeshData == #ring.MeshData)) or "nil"))
	local holder = Instance.new("Model")
	ring:Clone().Parent = holder
	local held = holder:Clone():FindFirstChildOfClass("UnionOperation")
	print("CLONEINMODEL " .. (held and tostring(#held.MeshData == #ring.MeshData) or "missing"))
end

-- Two blocks side by side, unioned: the result spans both.
local a = Instance.new("Part") a.Size = Vector3.new(2, 1, 1) a.CFrame = CFrame.new(10, 40, 0) a.Anchored = true a.Parent = workspace
local b = Instance.new("Part") b.Size = Vector3.new(2, 1, 1) b.CFrame = CFrame.new(12, 40, 0) b.Anchored = true b.Parent = workspace
local okU, u = pcall(function() return a:UnionAsync({ b }) end)
print("UNION " .. (okU and (u.ClassName .. " " .. vec(u.Size) .. " at " .. vec(u.Position)) or tostring(u)))

-- Two overlapping blocks, intersected: only the overlap is left.
local c = Instance.new("Part") c.Size = Vector3.new(2, 2, 2) c.CFrame = CFrame.new(20, 40, 0) c.Anchored = true c.Parent = workspace
local d = Instance.new("Part") d.Size = Vector3.new(2, 2, 2) d.CFrame = CFrame.new(21, 40, 0) d.Anchored = true d.Parent = workspace
local okI, i = pcall(function() return c:IntersectAsync({ d }) end)
print("INTERSECT " .. (okI and (vec(i.Size) .. " at " .. vec(i.Position)) or tostring(i)))

-- GeometryService, with the pieces kept apart: two blocks nowhere near each other.
local e = Instance.new("Part") e.Size = Vector3.new(1, 1, 1) e.CFrame = CFrame.new(30, 40, 0) e.Anchored = true e.Parent = workspace
local f = Instance.new("Part") f.Size = Vector3.new(1, 1, 1) f.CFrame = CFrame.new(35, 40, 0) f.Anchored = true f.Parent = workspace
local GeometryService = game:GetService("GeometryService")
local okS, pieces = pcall(function() return GeometryService:UnionAsync(e, { f }, { SplitApart = true }) end)
print("SPLIT " .. (okS and tostring(#pieces) or tostring(pieces)))
local okW, whole = pcall(function() return GeometryService:UnionAsync(e, { f }, { SplitApart = false }) end)
print("WHOLE " .. (okW and (tostring(#whole) .. " " .. vec(whole[1].Size)) or tostring(whole)))

-- The ways it has to refuse.
local same = Instance.new("Part") same.Size = outer.Size same.Shape = outer.Shape same.CFrame = outer.CFrame same.Parent = workspace
local okN, why = pcall(function() return outer:SubtractAsync({ same }) end)
print("NOTHING " .. tostring(okN) .. " " .. tostring(why))
local okX = pcall(function() return outer:SubtractAsync({ workspace }) end)
print("NOTPART " .. tostring(okX))
print("DONE ok")
"""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _line(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		var s := String(said[i])
		if s.begins_with(prefix): return s.substr(prefix.length())
	return ""

func _initialize() -> void:
	print("solid modelling from a script")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

## The ring's vertices from its MeshData, as [distance from the X axis, X].
func _radii(b64: String) -> Array:
	var raw := Marshalls.base64_to_raw(b64)
	if raw.size() < 16 or raw.slice(0, 4).get_string_from_ascii() != "PBOP": return []
	var nv := raw.decode_u32(8)
	# Vertex stride: 24 in version 1, 36 in version 2 (a face colour follows the normal), 44 in
	# version 3 (a UV follows that).
	var version := raw.decode_u32(4)
	var stride := 44 if version == 3 else 36 if version == 2 else 24
	var rs := []
	var xs := []
	for i in nv:
		var at := 16 + i * stride
		var y := raw.decode_float(at + 4)
		var z := raw.decode_float(at + 8)
		rs.append(sqrt(y * y + z * z))
		xs.append(raw.decode_float(at))
	return [rs, xs]

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 8.0:
		phase = 1
		t = 0.0
		world.run_chunk("solid", SCRIPT)
	elif phase == 1 and t > 1.0 and (_line("DONE ") == "ok" or t > 40.0):
		phase = 2
		check(_line("DONE ") == "ok", "the script ran to the end without hanging on the host")
		check(_line("RING ok=") == "true class=UnionOperation", "SubtractAsync hands back a UnionOperation: %s" % _line("RING ok="))
		check(_line("RINGNAME ") == "Union", "named Union: %s" % _line("RINGNAME "))
		check(_line("RINGPARENT ") == "nil", "and unparented, for the script to place")
		var size := _line("RINGSIZE ").split(",")
		check(size.size() == 3 and absf(float(size[0]) - 0.2) < 0.01 and absf(float(size[1]) - 2.0) < 0.02 and absf(float(size[2]) - 2.0) < 0.02,
			"its Size is the outer cylinder's bounds: %s" % _line("RINGSIZE "))
		var o := _line("RINGORIENT ").split(" caller ")
		check(o.size() == 2 and o[0] == o[1], "it keeps the calling part's orientation: %s" % _line("RINGORIENT "))
		var p := _line("RINGPOS ").split(" caller ")
		check(p.size() == 2 and p[0] == p[1], "and sits where the calling part did: %s" % _line("RINGPOS "))
		check(_line("RINGLOOK ") == "true true", "and wears its colour and material")
		var decoded := _radii(_line("RINGDATA "))
		var count: int = decoded[0].size() if decoded.size() == 2 else 0
		check(count > 0, "its MeshData decodes: %d vertices" % count)
		if count > 0:
			var lo := 1e9
			var hi := 0.0
			for r in decoded[0]:
				lo = minf(lo, r)
				hi = maxf(hi, r)
			check(lo > 0.6 - 0.02, "nothing is left inside the hole: nearest vertex to the axis %.3f, hole radius 0.6" % lo)
			check(absf(hi - 1.0) < 0.02, "and the rim reaches the outer radius: %.3f of 1.0" % hi)
		var un := _line("UNION ")
		check(un.begins_with("UnionOperation 4.000,1.000,1.000 at 11.000,40.000,0.000"), "UnionAsync of two blocks spans both: %s" % un)
		var inter := _line("INTERSECT ")
		check(inter.begins_with("1.000,2.000,2.000 at 20.500,40.000,0.000"), "IntersectAsync leaves only the overlap: %s" % inter)
		check(_line("SPLIT ") == "2", "GeometryService with SplitApart hands back each piece: %s" % _line("SPLIT "))
		check(_line("WHOLE ").begins_with("1 6.000,1.000,1.000"), "and without it, one part holding both: %s" % _line("WHOLE "))
		check(_line("NOTHING ").begins_with("false"), "cutting a part by its own twin is refused: %s" % _line("NOTHING "))
		check(_line("NOTPART ") == "false", "and so is something that is not a part")
		check(_line("CLONE ") == "UnionOperation true", "a union survives Clone, geometry and all: %s" % _line("CLONE "))
		check(_line("CLONEINMODEL ") == "true", "and so does one inside a cloned model: %s" % _line("CLONEINMODEL "))
		check(errors.is_empty(), "nothing threw that was not caught: %s" % str(errors.slice(0, 3)))
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

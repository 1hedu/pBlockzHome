# Spoonie's rim, made the way a Roblox builder makes a pipe: SubtractAsync.
#
#   godot --headless --path . -s res://tests/bake_spoonie_rim.gd
#
# The hole is an oval of its own rather than the outer one scaled down, so the rim is as wide at
# the tip as at the sides. SubtractAsync returns a UnionOperation whose MeshData goes to
# scripts/models/spoonie-rim.json for catalogue.js to put on the Lip, as a Roblox model carries one.
extends SceneTree

const OUT := "res://../../../scripts/models/spoonie-rim.json"

# The bowl's envelope is 0.34 tall by 0.5 long; the rim below is 0.04 wide and 0.07 thick, thicker
# than the dish that sits in it so that it stands above on both faces.
const SCRIPT := """
local GeometryService = game:GetService("GeometryService")
-- An oval, as a union. A Part's round shape cannot be stretched into an oval, but a union scales
-- its geometry to its Size -- so the cylinder is unioned with a speck inside it, which changes
-- nothing about its shape, and the union is stretched. GeometryService, because its parts do not
-- need to be in the scene; BasePart's methods require that.
local function oval(thick, tall, long)
	local c = Instance.new("Part")
	c.Shape = Enum.PartType.Cylinder
	c.Size = Vector3.new(thick, 1, 1)
	c.CFrame = CFrame.new(0, 200, 0)
	local speck = Instance.new("Part")
	speck.Size = Vector3.new(thick * 0.5, 0.1, 0.1)
	speck.CFrame = c.CFrame
	local u = GeometryService:UnionAsync(c, { speck }, { SplitApart = false })[1]
	u.Size = Vector3.new(thick, tall, long)
	return u
end
local ok, err = pcall(function()
	local outer = oval(0.07, 0.34, 0.5)
	local hole = oval(0.2, 0.34 - 0.08, 0.5 - 0.08)
	local rim = GeometryService:SubtractAsync(outer, { hole }, { SplitApart = false })[1]
	print(("RIMSIZE %.4f,%.4f,%.4f"):format(rim.Size.X, rim.Size.Y, rim.Size.Z))
	print("RIMDATA " .. rim.MeshData)
end)
if not ok then print("RIMERROR " .. tostring(err)) end
"""

var world: PulseBlockzWorld
var said: Array[String] = []
var t := 0.0
var phase := 0

func _line(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if String(said[i]).begins_with(prefix): return String(said[i]).substr(prefix.length())
	return ""

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 8.0:
		phase = 1
		t = 0.0
		world.run_chunk("rim", SCRIPT)
	elif phase == 1 and (_line("RIMDATA ") != "" or _line("RIMERROR ") != "" or t > 30.0):
		if _line("RIMDATA ") == "":
			printerr("bake: no rim -- ", _line("RIMERROR "))
			quit(1)
			return false
		var size := _line("RIMSIZE ").split(",")
		var f := FileAccess.open(ProjectSettings.globalize_path(OUT), FileAccess.WRITE)
		f.store_string(JSON.stringify({
			"meshData": _line("RIMDATA "),
			"size": [float(size[0]), float(size[1]), float(size[2])],
			"made": "outer:SubtractAsync({ hole }) -- tests/bake_spoonie_rim.gd",
		}))
		f.close()
		print("bake: rim ", _line("RIMSIZE "), ", ", _line("RIMDATA ").length(), " chars -> ", ProjectSettings.globalize_path(OUT))
		quit(0)
	return false

# A place cannot write itself new code while it runs.
#
#   godot --headless --path . -s res://tests/no_new_code_test.gd
#
# An experience is a hash: what runs has to be what was published, so code assembled at runtime
# would make the hash a statement about the first frame only. Source carries PluginSecurity on
# write, as on Roblox -- a plugin or the command bar may set it, a place's own scripts may not.
# The host's loaders write it from C++ and never reach the Lua property setter.
extends SceneTree

var world: PulseBlockzWorld
var t := 0.0
var ok := 0
var bad := 0
var said: Array[String] = []
var lines: Array[String] = []

func check(what: String, got, want) -> void:
	if got == want:
		ok += 1
	else:
		bad += 1
	lines.append("NEWCODE %-50s %-8s (wanted %s)%s" % [what, str(got), str(want), "" if got == want else "   <-- WRONG"])

func _initialize() -> void:
	world = PulseBlockzWorld.new()
	world.name = "World"
	world.mode = PulseBlockzWorld.MODE_PLAY_SOLO
	world.auto_join = false
	world.data_store_path = ""
	world.script_print.connect(func(_n, line): said.append(String(line)))
	world.script_error.connect(func(_n, e): said.append("ERROR " + String(e)))
	root.add_child(world)

	# A module the host loaded, so the ordinary path is checked beside the refused one: a place
	# whose own modules had stopped loading would pass the two refusal checks on its own.
	world.load_file("ReplicatedStorage/Real.luau", "return { from = 'the published place' }")

	# A script of the place, not run_chunk: a host-run chunk is the command bar, which may
	# write Source exactly as a plugin may.
	world.load_file("ServerScriptService/Try.server.luau", """
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The published module still loads.
local real = require(ReplicatedStorage:WaitForChild("Real"))
print("REAL " .. tostring(real.from))

-- Writing code at runtime does not.
local m = Instance.new("ModuleScript")
m.Name = "Made"
local wrote = pcall(function() m.Source = "return { from = 'nowhere' }" end)
print("WROTE " .. tostring(wrote))
m.Parent = ReplicatedStorage
local ran, got = pcall(function() return require(m) end)
print("RAN " .. tostring(ran) .. " " .. tostring(ran and got and got.from or "-"))
""")

func _process(delta: float) -> bool:
	t += delta
	if t < 5.0:
		return false
	var heard := func(s: String) -> bool:
		var hit := false
		for l in said:
			if l.find(s) != -1:
				hit = true
		return hit
	check("writing Source from a place script is refused", heard.call("WROTE false"), true)
	check("so the code it wanted never runs", heard.call("from nowhere"), false)
	check("the module the host loaded still loads", heard.call("REAL the published place"), true)
	check("and requiring the made one fails rather than returning it", heard.call("RAN false"), true)
	for l in lines:
		print(l)
	print("NEWCODE %d passed, %d failed" % [ok, bad])
	print("no new code: %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)
	return true

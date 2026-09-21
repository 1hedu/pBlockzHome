# The moment of safety after you spawn: SpawnLocation.Duration seconds of ForceField on arriving.
#
#   godot --headless --path . -s res://tests/forcefield_test.gd
#
# As on Roblox, a ForceField stops Humanoid:TakeDamage and nothing else -- it is what a place's
# own weapons respect by using TakeDamage, not a lock on the number.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the force field")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, t): said.append(t))
	get_root().add_child(main)
	_run()

func _ask(body: String, wait := 1.5) -> Array[String]:
	said.clear()
	world.run_chunk("ff_probe", body)
	await create_timer(wait).timeout
	return said.duplicate()

func _line(prefix: String) -> String:
	for l in said:
		if l.begins_with(prefix): return l.substr(prefix.length())
	return ""

func _run() -> void:
	await create_timer(3.0).timeout

	await _ask('''
local sp = Instance.new("SpawnLocation")
sp.Name = "Safe"
sp.Anchored = true
sp.Size = Vector3.new(6, 1, 6)
sp.Position = Vector3.new(0, 60, 300)
sp.Duration = 30   -- long, so the checks below have room; the expiry is its own spawn
sp.Parent = workspace
local plr = game:GetService("Players"):GetPlayers()[1]
plr.RespawnLocation = sp
plr:LoadCharacter()
''', 2.0)

	var seen := await _ask('''
local plr = game:GetService("Players"):GetPlayers()[1]
local ch = plr.Character
local ff = ch and ch:FindFirstChildOfClass("ForceField")
print("FF " .. tostring(ff ~= nil) .. "|" .. tostring(ff and ff.Visible))
''', 1.0)
	check(_line("FF ") == "true|true", "spawning on a Duration spawn gives you a force field: %s" % _line("FF "))

	# The bubble hangs off the character's root, and only while the field is Visible.
	check(_shields() > 0, "and a bubble round you to show for it (%d)" % _shields())
	await _ask('''
local plr = game:GetService("Players"):GetPlayers()[1]
plr.Character:FindFirstChildOfClass("ForceField").Visible = false
''', 1.0)
	check(_shields() == 0, "Visible = false takes the bubble away (%d left)" % _shields())
	await _ask('''
local plr = game:GetService("Players"):GetPlayers()[1]
plr.Character:FindFirstChildOfClass("ForceField").Visible = true
''', 1.0)
	check(_shields() > 0, "and puts it back (%d)" % _shields())

	var hurt := await _ask('''
local plr = game:GetService("Players"):GetPlayers()[1]
local h = plr.Character:FindFirstChildOfClass("Humanoid")
h.Health = 100
h:TakeDamage(40)
print("HP " .. tostring(h.Health))
''', 1.0)
	check(_line("HP ") == "100", "TakeDamage does nothing through it: %s" % _line("HP "))

	var written := await _ask('''
local plr = game:GetService("Players"):GetPlayers()[1]
local h = plr.Character:FindFirstChildOfClass("Humanoid")
h.Health = 55
print("HP " .. tostring(h.Health))
''', 1.0)
	check(_line("HP ") == "55",
		"but writing Health still works, which is Roblox's rule rather than an oversight: %s" % _line("HP "))

	# The town's blows all go through Health, which uses TakeDamage and drops the knockback with
	# it -- a place rule, not Roblox's: shoving a fresh spawn off the edge kills as well as damage.
	await _ask('''
local Health = require(game:GetService("ServerScriptService").Health)
local plr = game:GetService("Players"):GetPlayers()[1]
local ch = plr.Character
local h = ch:FindFirstChildOfClass("Humanoid")
h.MaxHealth = 6
h.Health = 6
local root = ch.HumanoidRootPart
root.AssemblyLinearVelocity = Vector3.zero
local hit = Health.hit(plr, nil, 2, 54)
local v = root.AssemblyLinearVelocity
local burnt = Health.burn(plr, nil, 3, 5, nil)
print("TOWN " .. tostring(hit) .. "|" .. tostring(h.Health) .. "|" .. string.format("%.1f", v.Magnitude) .. "|" .. tostring(burnt))
''', 1.0)
	check(_line("TOWN ") == "false|6|0.0|false",
		"a town blow lands nothing through it -- no damage, no shove, no burn: %s" % _line("TOWN "))

	await _ask('''
local spawn = workspace:FindFirstChild("TownSpawn", true)
print("SPAWN " .. tostring(spawn and spawn.Duration))
''', 0.8)
	check(_line("SPAWN ") == "6", "the town's spawn shields for six seconds: %s" % _line("SPAWN "))

	# Expiry gets its own short-Duration spawn: shortening the first would put every check above
	# in a race with the clock.
	await _ask('''
local sp = Instance.new("SpawnLocation")
sp.Name = "Brief"
sp.Anchored = true
sp.Size = Vector3.new(6, 1, 6)
sp.Position = Vector3.new(0, 60, 340)
sp.Duration = 2
sp.Parent = workspace
local plr = game:GetService("Players"):GetPlayers()[1]
plr.RespawnLocation = sp
plr:LoadCharacter()
''', 1.5)
	var fresh := await _ask('''
local ch = game:GetService("Players"):GetPlayers()[1].Character
print("FF " .. tostring(ch:FindFirstChildOfClass("ForceField") ~= nil))
''', 0.8)
	check(_line("FF ") == "true", "a two-second spawn shields you at first: %s" % _line("FF "))
	await create_timer(3.0).timeout
	await _ask('''
local ch = game:GetService("Players"):GetPlayers()[1].Character
local h = ch:FindFirstChildOfClass("Humanoid")
h.Health = 100
h:TakeDamage(40)
print("FF " .. tostring(ch:FindFirstChildOfClass("ForceField") ~= nil) .. "|" .. tostring(h.Health))
''', 1.5)
	check(_line("FF ") == "false|60",
		"and two seconds later it is gone and damage lands again: %s" % _line("FF "))
	await _ask('''
local Health = require(game:GetService("ServerScriptService").Health)
local plr = game:GetService("Players"):GetPlayers()[1]
local h = plr.Character:FindFirstChildOfClass("Humanoid")
h.MaxHealth = 6
h.Health = 6
print("TOWN " .. tostring(Health.hit(plr, nil, 2, 0)) .. "|" .. tostring(h.Health))
''', 1.0)
	check(_line("TOWN ") == "true|4", "and so do the town's blows: %s" % _line("TOWN "))
	# A frame for the freed node to actually go.
	await create_timer(0.5).timeout
	check(_shields() == 0, "with the bubble taken down too (%d left)" % _shields())

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## How many bubbles are drawn on the real character. Not the ones inside a SubViewport: the
## wardrobe's preview doll is a clone of the character's nodes, bubble included, and that clone
## is the wardrobe's to drop rather than something sync_shields removes.
func _shields() -> int:
	var found := 0
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SubViewport:
			continue
		if n is MeshInstance3D and String(n.name).begins_with("ForceField"):
			found += 1
		for c in n.get_children():
			stack.append(c)
	return found

func _shield() -> MeshInstance3D:
	return null

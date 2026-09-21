# The wardrobe's doll is a clone of the character; a spawn ForceField must not come with it.
#
#   godot --headless --path . -s res://tests/doll_shield_test.gd
#
# The doll is cloned when the panel opens, and again only when the outfit changes: a shield
# copied into it at open time stays there.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")

var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var pushed := false
var said: Array[String] = []
var ok := 0
var bad := 0

func check(cond: bool, what: String) -> void:
	if cond: ok += 1
	else: bad += 1
	print("  %s  %s" % ["PASS" if cond else "FAIL", what])

func _initialize() -> void:
	StandIns.stage("dollshield")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(func(_n, line): said.append(str(line)))
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 8.0:
		phase = 1; t = 0.0
		world.run_chunk("arrive", """
local player = game:GetService("Players"):GetPlayers()[1]
if not player.Character then player:LoadCharacterAsync() end
local ch = player.Character
if not ch:FindFirstChildOfClass("ForceField") then Instance.new("ForceField").Parent = ch end
print("shield: on the body " .. tostring(ch:FindFirstChildOfClass("ForceField") ~= nil))
""")
	elif phase == 1 and t > 1.0:
		phase = 2; t = 0.0
		# Nothing is drawn while the panel is closed.
		world.run_client_chunk("open", """
game:GetService("Players").LocalPlayer.PlayerGui:WaitForChild("Wardrobe").Enabled = true
""")
	elif phase == 2 and t > 1.0 and not pushed:
		pushed = true
		# An empty bag: the doll is the body either way.
		world.run_chunk("items", """
local player = game:GetService("Players"):GetPlayers()[1]
game:GetService("ReplicatedStorage").WardrobeRemote:FireClient(player, "items", {}, nil, nil, false)
""")
	elif phase == 2 and t > 4.0:
		phase = 3; t = 0.0
		world.run_client_chunk("look", """
local gui = game:GetService("Players").LocalPlayer.PlayerGui
local doll = gui:WaitForChild("Wardrobe"):FindFirstChild("Doll", true)   -- the wardrobe's: other panels have dolls of their own
local copy = doll and doll:FindFirstChild("Doll")
local n = 0
if copy then
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("ForceField") then n += 1 end
	end
end
print("shield: doll made " .. tostring(copy ~= nil) .. ", shields in it " .. n)
""")
	elif phase == 3 and t > 1.0:
		check(said.has("shield: on the body true"), "the body has its spawn shield when the doll is made")
		check(said.has("shield: doll made true, shields in it 0"), "the doll is made, and without the shield: %s" % str(said.filter(func(l): return l.begins_with("shield: doll"))))
		print("%d passed, %d failed" % [ok, bad])
		quit(1 if bad > 0 else 0)
		return true
	return false

# Nobody is in the town before they can see it.
#
#   godot --headless --path . -s res://tests/arrival_test.gd
#
# Players.CharacterAutoLoads is off, so only Arrival.server.luau makes a character: on the
# Arrived that Intro.client.luau fires as its black lifts, and RespawnTime after a death. A
# second Arrived must not bring anybody back early.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var errors: Array[String] = []
var heard: Array[String] = []
var t := 0.0
var phase := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _said(prefix: String) -> String:
	for i in range(heard.size() - 1, -1, -1):
		if heard[i].begins_with(prefix): return heard[i].substr(prefix.length())
	return ""

func _initialize() -> void:
	print("Arriving")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(func(_n, line): heard.append(line))
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 2.0:
		phase = 1
		world.run_chunk("watch", """
local Players = game:GetService("Players")
local p
repeat task.wait(0.05) p = Players:GetPlayers()[1] until p
print("ARR autoloads " .. tostring(Players.CharacterAutoLoads))
while not p.Character do task.wait(0.02) end
print("ARR body at " .. string.format("%.2f", os.clock()))
""")
		world.run_client_chunk("lift", """
local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local intro = gui:WaitForChild("Intro", 20)
local black = intro and intro:WaitForChild("Black", 5)
print("ARR no body under the black " .. tostring(game:GetService("Players").LocalPlayer.Character == nil))
while black and black.Parent and black.BackgroundTransparency <= 0 do task.wait() end
print("ARR lift at " .. string.format("%.2f", os.clock()))
""")
	elif phase == 1 and _said("ARR body at ") != "" and _said("ARR lift at ") != "":
		phase = 2
		t = 0.0
		world.run_chunk("die", """
local Players = game:GetService("Players")
local p = Players:GetPlayers()[1]
local first = p.Character
first:FindFirstChildOfClass("Humanoid").Health = 0
local died = os.clock()
print("ARR respawn time " .. tostring(Players.RespawnTime))
while p.Character == first and os.clock() - died < 10 do task.wait(0.02) end
print("ARR back after " .. string.format("%.2f", os.clock() - died) .. " " .. tostring(p.Character ~= nil and p.Character ~= first))
""")
		world.run_client_chunk("again", """
game:GetService("ReplicatedStorage"):WaitForChild("Arrived"):FireServer()
""")
	elif (phase == 1 and t > 45.0) or (phase == 2 and (_said("ARR back after ") != "" or t > 15.0)):
		phase = 3
		_finish()
	return false

func _finish() -> void:
	check(_said("ARR autoloads ") == "false", "Players.CharacterAutoLoads is off: %s" % _said("ARR autoloads "))
	check(_said("ARR no body under the black ") == "true", "no character while the intro is up")
	var body := float(_said("ARR body at "))
	var lift := float(_said("ARR lift at "))
	check(_said("ARR body at ") != "" and _said("ARR lift at ") != "", "a character arrives, and the black lifts")
	# 0.25s of slack: the character loads as the lift begins, and the lift is seen a frame either side.
	check(body >= lift - 0.25, "not before the town can be seen: body %.2f, lift %.2f" % [body, lift])
	check(body - lift < 1.0, "and promptly once it can: %.2fs after" % (body - lift))
	var back := _said("ARR back after ").split(" ")
	var respawn := float(_said("ARR respawn time "))
	check(back.size() == 2 and back[1] == "true", "a new body after dying: %s" % _said("ARR back after "))
	check(back.size() == 2 and float(back[0]) >= respawn - 0.05 and float(back[0]) < respawn + 1.0,
		"after RespawnTime (%.2f), not straight away for asking again: %s" % [respawn, back[0] if back.size() > 0 else "?"])
	check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

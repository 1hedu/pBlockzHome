# Proves which word a bar square sends the server: "act" for a worn item that has a use,
# "remove" for a worn item without one, "wear" for an unworn one.
#
#   godot --path . -s res://tests/bar_use_test.gd
#
# Not --headless: the bar binds 1-0 through ContextActionService, which sees an injected key
# only through a real window holding the focus. Number keys, not a click on a square, so this
# test stays clear of whether a click also swings the tool -- that is bar_click_test's job.
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var at := String(line).find(prefix)
		if at >= 0: out.append(String(line).substr(at + prefix.length()).strip_edges())
	return out

func _initialize() -> void:
	print("a bar square, pressed on something already worn")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

## Refill the bar. Needed before every press: the real Wardrobe refuses an action for an item
## the chain has never heard of and replies with the player's real inventory, empty here, which
## clears the three squares.
func _stock() -> void:
	world.run_chunk("stock", """
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("WardrobeRemote")
local player = Players:GetPlayers()[1]
-- Worn with a trick, worn without one, and not worn at all.
local items = {
	{ model = "Familiar", name = "Familiar", slot = "pet",  tier = 1, worn = true,  acts = "Speak" },
	{ model = "TopHat",   name = "Top Hat",  slot = "head", tier = 1, worn = true },
	{ model = "Boots",    name = "Boots",    slot = "feet", tier = 1, worn = false },
}
remote:FireClient(player, "items", items, nil, { "Familiar", "TopHat", "Boots" })
print("BAR stocked three squares")
""")
	await create_timer(1.5).timeout

func _press(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await create_timer(0.25).timeout

func _run() -> void:
	await create_timer(20.0).timeout
	# An unfocused window swallows input, so focus and spend one press before measuring -- the
	# same first-input trap gui_click_test documents.
	DisplayServer.window_move_to_foreground()
	await create_timer(1.0).timeout
	await _press(KEY_0)
	await create_timer(0.5).timeout

	# A second listener beside the real Wardrobe's, which stays connected and refuses these.
	said.clear()
	world.run_chunk("listen", """
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("WardrobeRemote")
local player = Players:GetPlayers()[1]
remote.OnServerEvent:Connect(function(who, action, model)
	if who == player and (action == "act" or action == "wear" or action == "remove") then
		print(("BAR asked %s %s"):format(tostring(action), tostring(model)))
	end
end)
print("BAR listening")
""")
	await create_timer(1.0).timeout
	await _stock()
	check(_lines("BAR ").size() > 0, "the bar took the list: %s" % str(_lines("BAR ")))

	said.clear()
	await _press(KEY_1)
	await create_timer(1.0).timeout
	var one := _lines("BAR asked ")
	check(one.size() > 0 and String(one[0]).begins_with("act Familiar"),
		"a worn thing with a trick does the trick: %s" % str(one))
	check(one.size() > 0 and not str(one).contains("remove"),
		"and is not taken off: %s" % str(one))

	await _stock()
	said.clear()
	await _press(KEY_2)
	await create_timer(1.0).timeout
	var two := _lines("BAR asked ")
	check(two.size() > 0 and String(two[0]).begins_with("remove TopHat"),
		"a worn thing with no trick still comes off: %s" % str(two))

	await _stock()
	said.clear()
	await _press(KEY_3)
	await create_timer(1.0).timeout
	var three := _lines("BAR asked ")
	check(three.size() > 0 and String(three[0]).begins_with("wear Boots"),
		"and something not worn goes on: %s" % str(three))

	# The click sound is not asserted: the squares cannot be reached from PlayerGui to read
	# their Sfx attribute. ActionBar.client.luau defines the sounds -- an "act" square is meant
	# to stay silent, since the trick it fires makes its own noise. See OPEN.md.

	check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 1.0:
		phase = 1
		_run()
	return false

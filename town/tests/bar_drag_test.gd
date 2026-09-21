# Dragging one square of the action bar onto another.
#
#   godot --path . -s res://tests/bar_drag_test.gd
#
# Not headless, and the window comes to the front: Godot runs its GUI mouse machinery only for
# a focused window. A Click fires only when press and release land on the same square, so a
# press on one square released over another must re-order and wear nothing.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []
var lit := false

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("moving things along the bar")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	main.show_title = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		said.append(line)
		if line.begins_with("intro:"): lit = true)
	get_root().add_child(main)
	_run()

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var at := line.find(prefix)
		if at >= 0:
			out.append(line.substr(at + prefix.length()).strip_edges())
	return out

func _drag(from: Vector2, to: Vector2) -> void:
	Input.warp_mouse(from)
	var move := InputEventMouseMotion.new()
	move.position = from
	move.global_position = from
	Input.parse_input_event(move)
	await create_timer(0.25).timeout

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	Input.parse_input_event(down)
	await create_timer(0.2).timeout

	for step in 10:
		var at := from.lerp(to, float(step + 1) / 10.0)
		Input.warp_mouse(at)
		var across := InputEventMouseMotion.new()
		across.position = at
		across.global_position = at
		across.relative = (to - from) / 10.0
		Input.parse_input_event(across)
		await create_timer(0.03).timeout
	await create_timer(0.2).timeout

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.global_position = to
	Input.parse_input_event(up)
	await create_timer(0.8).timeout

## The items list the server pushes, and the ten-square layout that goes with it.
func _push() -> void:
	world.run_chunk("fill", """
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
rs.WardrobeRemote:FireClient(player, "items", {
	{ id = "0x1", name = "Familiar", model = "Familiar", thumb = "", slot = "pet",
	  tier = 4, tier_name = "", worn = false },
	{ id = "0x2", name = "Top Hat", model = "Top Hat", thumb = "", slot = "hat",
	  tier = 2, tier_name = "", worn = false },
	{ id = "0x3", name = "Spoonie", model = "Spoonie", thumb = "", slot = "mainhand",
	  tier = 1, tier_name = "", worn = false },
}, { name = "", tier = 0 }, { "Familiar", "Top Hat", "Spoonie", "", "", "", "", "", "", "" })
""")
	await create_timer(0.8).timeout

## Where the squares are and what is in them.
func _read() -> Dictionary:
	said.clear()
	world.run_client_chunk("where", """
local Players = game:GetService("Players")
local row = Players.LocalPlayer.PlayerGui:WaitForChild("ActionBar"):WaitForChild("Row")
for i = 1, 10 do
	local slot = row:FindFirstChild("Slot" .. i)
	if slot then
		local label
		for _, kid in ipairs(slot:GetDescendants()) do
			if kid:IsA("TextLabel") and kid.Name == "Name" and kid.Visible then label = kid.Text end
		end
		print(("SLOT %d|%s|%.0f|%.0f"):format(i, tostring(label),
			slot.AbsolutePosition.X + slot.AbsoluteSize.X / 2,
			slot.AbsolutePosition.Y + slot.AbsoluteSize.Y / 2))
	end
end
""")
	await create_timer(0.8).timeout
	var out := {}
	for row in _lines("SLOT "):
		var bits: PackedStringArray = String(row).split("|")
		if bits.size() == 4:
			out[int(bits[0])] = {"name": bits[1], "at": Vector2(float(bits[2]), float(bits[3]))}
	return out

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	DisplayServer.window_move_to_foreground()

	world.run_chunk("listen", """
local rs = game:GetService("ReplicatedStorage")
rs:WaitForChild("WardrobeRemote").OnServerEvent:Connect(function(player, action, what)
	if action == "arrange" and type(what) == "table" then
		print("HEARD arrange " .. table.concat(what, ","))
	else
		print("HEARD " .. tostring(action) .. " " .. tostring(what))
	end
end)
""")
	# The bar re-asks the server every two seconds until a non-empty list arrives; with no chain
	# that never stops, so wait the retries out or they wipe what is pushed next.
	await create_timer(19.0).timeout

	await _push()
	var slots := await _read()
	check(slots.size() == 10, "the bar has its ten squares: %d" % slots.size())
	check(slots.has(1) and slots[1].name == "Familiar",
		"and the first of them is the first thing the chain handed over: %s"
		% (slots[1].name if slots.has(1) else "?"))

	# The first press after the window comes forward is swallowed, so spend one.
	await _drag(slots[1].at, slots[1].at)
	await _push()

	said.clear()
	await _drag(slots[1].at, slots[3].at)
	var heard := _lines("HEARD ")
	check(heard.size() == 1 and String(heard[0]).begins_with("arrange "),
		"a drag asks the server to re-order, and asks for nothing else: %s" % str(heard))
	check(heard.size() > 0 and String(heard[0]).find("Spoonie,Top Hat,Familiar") >= 0,
		"with the two swapped and the rest where they were: %s" % str(heard))

	# Asked of Bar directly: an arrange makes the server push the real list, which without a
	# chain is empty, so the drawn squares blank a moment later.
	said.clear()
	world.run_chunk("sorted", """
local Bar = require(game:GetService("ServerScriptService").ActionBar)
local player = game:GetService("Players"):GetPlayers()[1]
local out = Bar.showing(player, {
	{ model = "Familiar" }, { model = "Top Hat" }, { model = "Spoonie" },
})
print("SORTED " .. table.concat(out, ","))
local kept = Bar.of(player) or {}
local names = {}
for i = 1, 10 do names[i] = kept[i] or "" end
print("KEPT " .. table.concat(names, ","))
""")
	await create_timer(1.0).timeout
	check(_lines("SORTED ").has("Spoonie,Top Hat,Familiar,,,,,,,"),
		"the server gives back the squares as arranged: %s" % str(_lines("SORTED ")))
	check(_lines("KEPT ").has("Spoonie,Top Hat,Familiar,,,,,,,"),
		"and has written them down for next time: %s" % str(_lines("KEPT ")))

	# A press and release on the same square is still a use, not a move.
	await _push()
	var again := await _read()
	said.clear()
	await _drag(again[1].at, again[1].at)
	var clicked := _lines("HEARD ")
	check(clicked.size() == 1 and String(clicked[0]).begins_with("wear "),
		"a click where it started still wears the thing: %s" % str(clicked))


	# Put the layout back: an arrange writes through Bar.set to the signed-in player's real
	# DataStore, and ten stored empty squares is a layout the town then honours.
	world.run_chunk("restore", """
local Bar = require(game:GetService("ServerScriptService").ActionBar)
Bar.forget(game:GetService("Players"):GetPlayers()[1])
print("RESTORED")
""")
	await create_timer(1.0).timeout
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

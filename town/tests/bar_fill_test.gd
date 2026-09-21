# Putting something ON the action bar, by carrying it out of the bag.
#
#   godot --path . -s res://tests/bar_fill_test.gd
#
# Not headless, and the window comes to the front first. The bag and the bar are separate
# ScreenGuis built by separate scripts, so a press that begins in one and ends over the other
# crosses Carry.luau.
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
	print("carrying a thing out of the bag onto the bar")
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
	var m := InputEventMouseMotion.new()
	m.position = from
	m.global_position = from
	Input.parse_input_event(m)
	await create_timer(0.25).timeout
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.position = from
	d.global_position = from
	Input.parse_input_event(d)
	await create_timer(0.2).timeout
	for step in 12:
		var at := from.lerp(to, float(step + 1) / 12.0)
		Input.warp_mouse(at)
		var a := InputEventMouseMotion.new()
		a.position = at
		a.global_position = at
		Input.parse_input_event(a)
		await create_timer(0.03).timeout
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = to
	u.global_position = to
	Input.parse_input_event(u)
	await create_timer(0.9).timeout

## Three things owned, with only the first on the bar, so there are empty squares to drop into.
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
}, { name = "", tier = 0 }, { "Familiar", "", "", "", "", "", "", "", "", "" })
""")
	await create_timer(0.9).timeout

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
	world.run_client_chunk("open", """
local Players = game:GetService("Players")
Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Wardrobe").Enabled = true
""")
	# The bar re-asks every two seconds until a non-empty list arrives; wait the empty answers
	# out or they wipe what is pushed next.
	await create_timer(19.0).timeout
	await _push()

	var found := await _where()
	var tiles: Dictionary = found[0]
	var squares: Dictionary = found[1]
	check(tiles.has("Spoonie") and squares.has(5),
		"the bag and the bar are both on screen: %d tile(s), %d square(s)"
		% [tiles.size(), squares.size()])
	if not (tiles.has("Spoonie") and squares.has(5)):
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	# The first press after the window comes forward is swallowed.
	await _drag(tiles["Spoonie"], tiles["Spoonie"])
	await _push()
	# Re-read: the bag is rebuilt on every push and its tiles do not come back in the same
	# order, so a remembered pixel holds a different thing.
	found = await _where()
	tiles = found[0]
	squares = found[1]

	said.clear()
	await _drag(tiles["Spoonie"], squares[5])
	var heard := _lines("HEARD ")
	check(heard.size() >= 1 and String(heard[0]).begins_with("arrange "),
		"carrying a thing from the bag to an empty square puts it there: %s" % str(heard))
	check(heard.size() >= 1 and String(heard[0]).find("Familiar,,,,Spoonie") >= 0,
		"in the square it was dropped on, and nowhere else: %s" % str(heard))

	await _push()
	found = await _where()
	squares = found[1]
	said.clear()
	await _drag(squares[1], Vector2(40, 300))
	heard = _lines("HEARD ")
	check(heard.size() >= 1 and String(heard[0]).begins_with("arrange ,"),
		"and dragging one off the bar empties its square: %s" % str(heard))


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

## Where every bag tile and every bar square is, this instant.
func _where() -> Array:
	said.clear()
	world.run_client_chunk("where", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer.PlayerGui
local screen = gui:FindFirstChild("Wardrobe")
local bag
for _, d in ipairs(screen:GetDescendants()) do
	if d:IsA("ScrollingFrame") then bag = d break end
end
for _, d in ipairs(bag:GetChildren()) do
	if d:IsA("ImageButton") then
		local label
		for _, kid in ipairs(d:GetDescendants()) do
			if kid:IsA("TextLabel") and kid.Text ~= "worn" then label = kid.Text end
		end
		print(("TILE %s|%.0f|%.0f"):format(tostring(label),
			d.AbsolutePosition.X + d.AbsoluteSize.X / 2,
			d.AbsolutePosition.Y + d.AbsoluteSize.Y / 2))
	end
end
local row = gui:WaitForChild("ActionBar"):WaitForChild("Row")
for i = 1, 10 do
	local slot = row:FindFirstChild("Slot" .. i)
	print(("SQUARE %d|%.0f|%.0f"):format(i,
		slot.AbsolutePosition.X + slot.AbsoluteSize.X / 2,
		slot.AbsolutePosition.Y + slot.AbsoluteSize.Y / 2))
end
""")
	await create_timer(1.0).timeout
	var tiles := {}
	for row in _lines("TILE "):
		var bits: PackedStringArray = String(row).split("|")
		if bits.size() == 3:
			tiles[bits[0]] = Vector2(float(bits[1]), float(bits[2]))
	var squares := {}
	for row in _lines("SQUARE "):
		var bits: PackedStringArray = String(row).split("|")
		if bits.size() == 3:
			squares[int(bits[0])] = Vector2(float(bits[1]), float(bits[2]))
	return [tiles, squares]

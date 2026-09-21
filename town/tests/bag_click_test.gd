# Real clicks on the three bag gestures -- left-click acts, right-click wears the item or
# takes it off again, shift and right-click opens the menu -- checked by what the server is
# asked for. The item list is pushed down the remote, so no chain is needed.
#
#   godot --path . -s res://tests/bag_click_test.gd
#
# Not headless: Godot runs its GUI mouse machinery only for a focused window, so a pushed
# click at an unfocused one lands on nothing, neither press nor hover.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []
var lit := false
var spot := {}          # item name -> the centre pixel of its tile

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("clicking what is in your bag")
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

## A press and a release at a pixel, with the pointer warped there first so hover runs.
func _click(at: Vector2, button: int, shift := false) -> void:
	Input.warp_mouse(at)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await create_timer(0.25).timeout
	if shift:
		var down := InputEventKey.new()
		down.keycode = KEY_SHIFT
		down.physical_keycode = KEY_SHIFT
		down.pressed = true
		Input.parse_input_event(down)
		await create_timer(0.15).timeout
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = at
		e.global_position = at
		e.shift_pressed = shift
		Input.parse_input_event(e)
		await create_timer(0.15).timeout
	if shift:
		var up := InputEventKey.new()
		up.keycode = KEY_SHIFT
		up.physical_keycode = KEY_SHIFT
		up.pressed = false
		Input.parse_input_event(up)
	await create_timer(0.7).timeout

## Refills the bag and re-reads where each tile landed. Runs before every click: with no chain
## every "list" answer the action bar gets is empty, and an empty one reaches the wardrobe
## handler and clears the grid -- on a chain the first answer has items in it and the bar stops
## asking. Rebuilt tiles come back in an order of their own, so a remembered pixel is a
## different item.
func _fill() -> void:
	world.run_chunk("fill", """
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
rs.WardrobeRemote:FireClient(player, "items", {
	{ id = "0x1", name = "Familiar", model = "Familiar", thumb = "", slot = "pet",
	  tier = 4, tier_name = "", worn = false, acts = "Speak" },
	{ id = "0x2", name = "Top Hat", model = "Top Hat", thumb = "", slot = "hat",
	  tier = 2, tier_name = "", worn = false },
	-- An Engram, which is the one thing showing to somebody means anything for.
	{ id = "0x3", name = "Engram", model = "Engram#1", thumb = "", slot = "offhand",
	  tier = 0, tier_name = "", worn = false, shows = true },
}, { name = "", tier = 0 })
""")
	await create_timer(0.7).timeout
	said.clear()
	# An open menu floats over the grid at the tile it came from and covers the neighbouring
	# tiles, so a click aimed at one of those would hit the menu. Put it away.
	world.run_client_chunk("shut", """
local Players = game:GetService("Players")
local screen = Players.LocalPlayer.PlayerGui:FindFirstChild("Wardrobe")
for _, d in ipairs(screen:GetDescendants()) do
	if d:IsA("TextButton") and d.Text == "Show to someone" then
		local w = d.Parent
		while w and w.Parent and w.Parent ~= screen do w = w.Parent end
		if w then w.Visible = false end
	end
end
""")
	await create_timer(0.4).timeout
	world.run_client_chunk("where", """
local Players = game:GetService("Players")
local screen = Players.LocalPlayer.PlayerGui:FindFirstChild("Wardrobe")
local bag
for _, d in ipairs(screen:GetDescendants()) do
	if d:IsA("ScrollingFrame") then bag = d break end
end
for _, d in ipairs(bag:GetChildren()) do
	if d:IsA("ImageButton") then
		local at, size = d.AbsolutePosition, d.AbsoluteSize
		local label
		for _, kid in ipairs(d:GetDescendants()) do
			if kid:IsA("TextLabel") and kid.Text ~= "worn" then label = kid.Text end
		end
		-- Piped, because the names have spaces in them and a "Top Hat" split on spaces is
		-- an item called "Top".
		print(("BAG tile %s|%.0f|%.0f"):format(
			tostring(label), at.X + size.X / 2, at.Y + size.Y / 2))
	end
end
""")
	await create_timer(0.8).timeout
	spot = {}
	for row in _lines("BAG tile "):
		print("    tile ", row)
		var bits: PackedStringArray = String(row).split("|")
		if bits.size() == 3:
			spot[bits[0]] = Vector2(float(bits[1]), float(bits[2]))

## Diagnostic: every visible GuiObject covering a pixel, per ScreenGui, with its ZIndex. Printed
## in tree order, so the last hit of a ScreenGui is the one on top -- the control a click there
## goes to.
func _probe(at: Vector2) -> void:
	world.run_client_chunk("probe", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer.PlayerGui
local x, y = %f, %f
for _, screen in ipairs(gui:GetChildren()) do
	if screen:IsA("ScreenGui") then
		local hits = {}
		for _, d in ipairs(screen:GetDescendants()) do
			if d:IsA("GuiObject") and d.Visible then
				local p, s = d.AbsolutePosition, d.AbsoluteSize
				if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then
					table.insert(hits, ("%%s/%%s z%%d"):format(d.Name, d.ClassName, d.ZIndex))
				end
			end
		end
		if #hits > 0 or screen.Enabled then
			print(("UNDER %%s enabled=%%s order=%%d : %%s"):format(screen.Name,
				tostring(screen.Enabled), screen.DisplayOrder, table.concat(hits, ", ")))
		end
	end
end
""" % [at.x, at.y])
	await create_timer(1.0).timeout
	for row in _lines("UNDER "):
		print("    under ", row)

## The menu as "up=<bool> show=<bool> room=<px>", or "" if nothing answered.
func _menu() -> String:
	world.run_client_chunk("menu", """
local Players = game:GetService("Players")
local screen = Players.LocalPlayer.PlayerGui:FindFirstChild("Wardrobe")
local show, cancel
for _, d in ipairs(screen:GetDescendants()) do
	if d:IsA("TextButton") and d.Text == "Show to someone" then show = d end
	if d:IsA("TextButton") and d.Text == "Cancel" then cancel = d end
end
local window = show and show.Parent
while window and window.Parent and window.Parent ~= screen do window = window.Parent end
-- How much window is left under the last row. Negative means the menu is too short for
-- what is on it, which is what the fixed height did to the Engram's three.
local room = -99
if window and cancel then
	room = window.AbsoluteSize.Y
		- ((cancel.AbsolutePosition.Y - window.AbsolutePosition.Y) + cancel.AbsoluteSize.Y)
end
print(("MENU up=%s show=%s room=%d"):format(
	tostring(window ~= nil and window.Visible), tostring(show and show.Visible), room))
""")
	await create_timer(1.0).timeout
	var rows := _lines("MENU ")
	return String(rows[0]) if rows.size() > 0 else ""

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	DisplayServer.window_move_to_foreground()

	world.run_chunk("listen", """
local rs = game:GetService("ReplicatedStorage")
rs:WaitForChild("WardrobeRemote").OnServerEvent:Connect(function(player, action, model)
	print("HEARD " .. tostring(action) .. " " .. tostring(model))
end)
""")
	world.run_client_chunk("open", """
local Players = game:GetService("Players")
Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Wardrobe").Enabled = true
""")
	# Let the action bar finish asking: "list" every two seconds until an answer has something
	# in it, which with no chain is eight tries over sixteen seconds, each reply emptying the
	# grid the clicks below land on.
	await create_timer(19.0).timeout

	await _fill()
	check(spot.has("Familiar") and spot.has("Top Hat") and spot.has("Engram"),
		"all three tiles are on screen: %s" % str(spot.keys()))
	if not (spot.has("Familiar") and spot.has("Top Hat") and spot.has("Engram")):
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	# The first press after the window comes to the front is swallowed, so it is spent on the
	# tile itself: there is no neutral pixel, and the corner holds the button that shuts the
	# panel under test.
	await _click(spot["Familiar"], MOUSE_BUTTON_LEFT)
	await _fill()
	said.clear()
	await _click(spot["Familiar"], MOUSE_BUTTON_LEFT)
	check(_lines("HEARD ").has("act Familiar"),
		"left-click asks the Familiar to do its trick: %s" % str(_lines("HEARD ")))

	await _fill()
	said.clear()
	await _click(spot["Familiar"], MOUSE_BUTTON_RIGHT)
	check(_lines("HEARD ").has("wear Familiar"),
		"right-click puts it on: %s" % str(_lines("HEARD ")))

	await _fill()
	said.clear()
	await _click(spot["Top Hat"], MOUSE_BUTTON_LEFT)
	check(_lines("HEARD ").is_empty(),
		"left-click on a thing with no trick asks for nothing: %s" % str(_lines("HEARD ")))

	await _fill()
	said.clear()
	await _probe(spot["Top Hat"])
	said.clear()
	await _click(spot["Top Hat"], MOUSE_BUTTON_RIGHT)
	check(_lines("HEARD ").has("wear Top Hat"),
		"and right-click puts THAT on: %s" % str(_lines("HEARD ")))

	await _fill()
	said.clear()
	await _click(spot["Top Hat"], MOUSE_BUTTON_RIGHT, true)
	check(_lines("HEARD ").is_empty(),
		"shift and right-click wears nothing: %s" % str(_lines("HEARD ")))
	said.clear()
	var hat := await _menu()
	check(hat.find("up=true") >= 0, "it opens the menu instead: %s" % hat)
	check(hat.find("show=false") >= 0,
		"and a hat is not offered to anybody, because showing one means nothing: %s" % hat)

	# An Engram is a link, and showing one hands it over, so its menu carries a fourth row the
	# others do not and the window has to be tall enough for it.
	await _fill()
	said.clear()
	await _click(spot["Engram"], MOUSE_BUTTON_RIGHT, true)
	said.clear()
	var engram := await _menu()
	check(engram.find("show=true") >= 0, "an Engram IS offered to somebody: %s" % engram)
	var room := 0
	var at := engram.find("room=")
	if at >= 0:
		room = int(engram.substr(at + 5))
	check(room >= 0,
		"and the menu is tall enough to hold it: %d pixels of window under the last row" % room)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

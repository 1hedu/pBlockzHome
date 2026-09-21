# A ScrollingFrame's three grabber images and VerticalScrollBarInset, GuiObject.Selectable and
# GuiButton.Modal, on the Godot side.
#
#   godot --headless --path . -s res://tests/gui_props_test.gd
#
# Headless a GUI has no extent -- AbsoluteSize is 0, 0 -- so nothing clicks anything; each
# property is checked where it lands: a stylebox, focus_mode, the global mouse mode.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("scrollbars, selection, and the modal pointer")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, t): _said.append(t))
	get_root().add_child(main)
	_run()

## The Control a Roblox GuiObject is drawn as, found by id: the GUI tree is built without
## names, because a Roblox name is not unique among siblings and a Godot node's has to be.
func _control(named: String) -> Control:
	var id := _id(named)
	return world.gui_control(id) as Control if id != 0 else null

func _id(named: String) -> int:
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var at: int = stack.pop_back()
		for kid in world.get_child_ids(at):
			if world.get_instance(kid).name == named:
				return kid
			stack.append(kid)
	return 0

func _bar(frame: String, which: String) -> ScrollBar:
	var c := _control(frame)
	if c == null:
		return null
	var stack: Array[Node] = [c]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if which == "V" and n is VScrollBar: return n
		if which == "H" and n is HScrollBar: return n
		for k in n.get_children():
			stack.append(k)
	return null

func _run_chunk(body: String) -> void:
	# Client context: a GUI belongs to a player, and a server has no LocalPlayer.
	world.run_client_chunk("gui_props", body)
	await create_timer(0.5).timeout

var _said: Array[String] = []

## The frame's AbsoluteWindowSize.X with the vertical bar inset the given way, or -1.0.
func _window(inset: String) -> float:
	_said.clear()
	world.run_client_chunk("gui_inset", """
local f = game:GetService("Players").LocalPlayer.PlayerGui.PropsGui.Roll
f.VerticalScrollBarInset = Enum.ScrollBarInset.%s
task.wait(0.1)
print("WINDOW " .. tostring(f.AbsoluteWindowSize.X))
""" % inset)
	await create_timer(0.8).timeout
	for line in _said:
		if line.begins_with("WINDOW "):
			return float(line.substr(7))
	return -1.0

func _run() -> void:
	await create_timer(2.0).timeout
	await create_timer(3.0).timeout

	await _run_chunk('''
local g = Instance.new("ScreenGui")
g.Name = "PropsGui"
g.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local f = Instance.new("ScrollingFrame")
f.Name = "Roll"
f.Size = UDim2.new(0, 200, 0, 200)
f.CanvasSize = UDim2.new(0, 400, 0, 400)
f.Parent = g
local plain = Instance.new("Frame")
plain.Name = "Deco"
plain.Size = UDim2.new(0, 50, 0, 50)
plain.Parent = g
local b = Instance.new("TextButton")
b.Name = "Press"
b.Size = UDim2.new(0, 50, 0, 50)
b.Parent = g
''')

	# ---- the grabber -------------------------------------------------------------------
	var vbar := _bar("Roll", "V")
	check(vbar != null, "a ScrollingFrame has a vertical bar")
	if vbar == null:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	# None of the town's nine scrolling panels names a grabber image, so this flat default is
	# what every one of them renders with.
	var flat := vbar.get_theme_stylebox("grabber")
	check(flat is StyleBoxFlat,
		"with none of the three images set it keeps the plain rounded grabber it always had")

	await _run_chunk('''
local f = game:GetService("Players").LocalPlayer.PlayerGui.PropsGui.Roll
f.TopImage = "rbxasset://textures/ui/Scroll/scroll-top.png"
f.MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
f.BottomImage = "rbxasset://textures/ui/Scroll/scroll-bottom.png"
''')
	# Those three rbxasset paths are Roblox's own built-ins, not shipped here, so none decodes.
	check(vbar.get_theme_stylebox("grabber") is StyleBoxFlat,
		"three images that do not resolve leave the grabber alone rather than blanking it")

	# HeartIcon ships in the place's assets, so the guard below takes its branch -- a failure in
	# the three checks after it is the property, not a missing asset.
	await _run_chunk('''
local rs = game:GetService("ReplicatedStorage")
local assets = rs:FindFirstChild("PlaceAssets")
local icon = assets and assets:FindFirstChild("HeartIcon")
local f = game:GetService("Players").LocalPlayer.PlayerGui.PropsGui.Roll
if icon then
	f.TopImage = icon.Value
	f.MidImage = icon.Value
	f.BottomImage = icon.Value
end
''')
	var textured := vbar.get_theme_stylebox("grabber")
	check(textured is StyleBoxTexture, "images that do resolve become a textured grabber")
	if textured is StyleBoxTexture:
		var sb: StyleBoxTexture = textured
		check(sb.texture != null and sb.texture.get_height() > 0, "stacked into one texture")
		check(sb.get_texture_margin(SIDE_TOP) > 0 and sb.get_texture_margin(SIDE_BOTTOM) > 0,
			"with the two caps held out of the stretch, which is what three images are for")

	# ---- the insets --------------------------------------------------------------------
	# AbsoluteWindowSize is the frame minus an inset bar, and is the number children sized in
	# Scale are a fraction of.
	var wide := await _window("None")
	var narrow := await _window("Always")
	var thick := 12.0
	check(wide > 0.0, "the window has a width to lose (%.0f)" % wide)
	check(absf(wide - narrow - thick) < 1.5,
		"an inset bar takes exactly its own thickness off it (%.0f -> %.0f, bar %.0f)" % [wide, narrow, thick])
	check(await _window("ScrollBar") == narrow,
		"and ScrollBar insets it too, because this frame's bar is showing")

	# ---- Selectable and Modal ----------------------------------------------------------
	var deco := _control("Deco")
	var press := _control("Press")
	check(deco != null and press != null, "a plain frame and a button to compare")
	if deco != null and press != null:
		# Roblox's defaults: a button can be selected, a frame cannot.
		check(deco.focus_mode == Control.FOCUS_NONE, "a plain frame does not take the selection")
		check(press.focus_mode == Control.FOCUS_ALL, "a button does")
		await _run_chunk('''
local g = game:GetService("Players").LocalPlayer.PlayerGui.PropsGui
g.Deco.Selectable = true
g.Press.Selectable = false
''')
		check((_control("Deco") as Control).focus_mode == Control.FOCUS_ALL,
			"and Selectable turns it on for the frame")
		# Fetched again, not cached: a GuiObject's node is rebuilt when a class-shaped property
		# changes, and a stale reference answers for the old one forever.
		check((_control("Press") as Control).focus_mode == Control.FOCUS_NONE, "and off for the button")

	# Modal frees the pointer while it is on screen, whatever MouseBehavior asked for.
	await _run_chunk('''
local uis = game:GetService("UserInputService")
uis.MouseBehavior = Enum.MouseBehavior.LockCenter
''')
	# wanted_mouse_mode(), not Input.mouse_mode: headless has no pointer to lock and reports
	# VISIBLE whatever it is asked for.
	check(world.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED, "LockCenter captures the pointer")
	await _run_chunk('game:GetService("Players").LocalPlayer.PlayerGui.PropsGui.Press.Modal = true')
	check(world.wanted_mouse_mode() == Input.MOUSE_MODE_VISIBLE,
		"a visible Modal button hands it back, which is the whole point of Modal")
	await _run_chunk('game:GetService("Players").LocalPlayer.PlayerGui.PropsGui.Press.Visible = false')
	check(world.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED, "hiding it locks the pointer again")
	await _run_chunk('''
local g = game:GetService("Players").LocalPlayer.PlayerGui.PropsGui
g.Press.Visible = true
''')
	check(world.wanted_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "showing it frees it again")
	await _run_chunk('game:GetService("Players").LocalPlayer.PlayerGui.PropsGui.Press:Destroy()')
	check(world.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED,
		"and destroying it outright locks it, which a visibility check alone would miss")

	# MouseBehavior is global: left as it is, every later test in a sweep runs captured.
	await _run_chunk('game:GetService("UserInputService").MouseBehavior = Enum.MouseBehavior.Default')

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

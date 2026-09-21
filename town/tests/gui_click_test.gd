# Both mouse buttons on a GuiButton, through to the script: Down, Click and Activated.
#
#   godot --path . -s res://tests/gui_click_test.gd
#
# Windowed, and the window is raised first: Godot runs its GUI mouse machinery only for a
# focused window, so a synthetic click at an unfocused one produces no press and no hover.
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
	print("both mouse buttons on a GuiButton")
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

func _heard(what: String) -> bool:
	for line in said:
		if line.find(what) >= 0:
			return true
	return false

func _click(at: Vector2, button: int) -> void:
	Input.warp_mouse(at)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await create_timer(0.25).timeout
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await create_timer(0.15).timeout
	await create_timer(0.6).timeout

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	DisplayServer.window_move_to_foreground()
	await create_timer(0.5).timeout

	world.run_client_chunk("makebutton", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local screen = Instance.new("ScreenGui")
screen.Name = "ClickProbe"
screen.IgnoreGuiInset = true
screen:SetAttribute("Hud", true)
screen.Parent = gui
local b = Instance.new("TextButton")
b.Name = "Probe"
b.Size = UDim2.new(0, 200, 0, 120)
b.Position = UDim2.new(0.5, -100, 0.5, -60)
b.Text = "probe"
b.Parent = screen
b.MouseEnter:Connect(function() print("GUI hover") end)
b.MouseButton1Down:Connect(function() print("GUI down1") end)
b.MouseButton1Click:Connect(function() print("GUI click1") end)
b.Activated:Connect(function() print("GUI activated") end)
b.MouseButton2Down:Connect(function() print("GUI down2") end)
b.MouseButton2Click:Connect(function() print("GUI click2") end)
print(("GUI probe at %d %d size %d %d"):format(
	b.AbsolutePosition.X, b.AbsolutePosition.Y, b.AbsoluteSize.X, b.AbsoluteSize.Y))
""")
	await create_timer(1.5).timeout

	var view := get_root().get_visible_rect().size
	var middle := view / 2

	said.clear()
	await _click(middle, MOUSE_BUTTON_LEFT)
	check(_heard("GUI hover"), "the pointer reaches a PlayerGui button at all")
	check(_heard("GUI down1"), "a left press arrives")
	check(_heard("GUI click1"), "and a left click")
	check(_heard("GUI activated"), "which is also an Activated, as Roblox has it")

	said.clear()
	await _click(middle, MOUSE_BUTTON_RIGHT)
	check(_heard("GUI down2"), "a right press arrives")
	check(_heard("GUI click2"),
		"and a right CLICK -- the one the host never fired, which left every right-click menu unopenable")
	check(not _heard("GUI activated"),
		"and a right-click is not an Activated: Roblox fires that for the left button only")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

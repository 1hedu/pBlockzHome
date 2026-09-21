# Roblox's rule: a focused TextBox takes the keyboard, so ContextActionService bindings do not
# fire. The key still reaches UserInputService with gameProcessedEvent true. The pointer is not
# swallowed: a click is what gets you out of the box.
#
#   godot --path . -s res://tests/typing_test.gd
#
# Not headless: a real key has to cross the viewport, and Godot runs its GUI machinery only for
# a focused window, so the window is raised first.
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
	print("typing, and what it must not set off")
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

func _count(what: String) -> int:
	var n := 0
	for line in said:
		if line.find(what) >= 0:
			n += 1
	return n

## A key, with the character it would type.
##
## `unicode` must be set: without it a focused box takes the event and types nothing, so "no
## hotkey fired" proves nothing. With it, the letter in the box names what took the key.
func _press(key: int, letter := 0) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = key
		e.physical_keycode = key
		e.unicode = letter
		e.pressed = pressed
		Input.parse_input_event(e)
		await create_timer(0.12).timeout
	await create_timer(0.5).timeout

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	DisplayServer.window_move_to_foreground()

	world.run_client_chunk("bind", """
local CAS = game:GetService("ContextActionService")
local Players = game:GetService("Players")
CAS:BindAction("ProbeKey", function(_, state)
	if state == Enum.UserInputState.Begin then print("KEY heard") end
end, false, Enum.KeyCode.K)
local screen = Instance.new("ScreenGui")
screen.Name = "TypingProbe"
screen.IgnoreGuiInset = true
screen:SetAttribute("Hud", true)
screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local box = Instance.new("TextBox")
box.Name = "Probe"
box.Size = UDim2.new(0, 300, 0, 40)
box.Position = UDim2.new(0.5, -150, 0.5, -20)
box.Text = ""
box.Parent = screen
game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
	if input.KeyCode == Enum.KeyCode.K then
		print("UIS heard, processed=" .. tostring(processed))
	end
end)
""")
	await create_timer(1.5).timeout

	# The first press is swallowed, the pointer never having been in the window, so spend one
	# before anything is counted.
	await _press(KEY_K, 107)

	said.clear()
	await _press(KEY_K, 107)
	check(_count("KEY heard") == 1, "with nothing focused, a bound key fires: %d" % _count("KEY heard"))
	check(_count("UIS heard") == 1, "and UserInputService hears it too")

	world.run_client_chunk("focus", """
local Players = game:GetService("Players")
Players.LocalPlayer.PlayerGui.TypingProbe.Probe:CaptureFocus()
print("TYPING " .. tostring(game:GetService("UserInputService"):GetFocusedTextBox() ~= nil))
""")
	await create_timer(1.0).timeout
	check(_count("TYPING true") == 1, "the box has the keyboard")

	said.clear()
	await _press(KEY_K, 107)
	check(_count("KEY heard") == 0,
		"and now the same key sets off NOTHING: %d action(s)" % _count("KEY heard"))
	world.run_client_chunk("read", """
local Players = game:GetService("Players")
print("TEXT [" .. Players.LocalPlayer.PlayerGui.TypingProbe.Probe.Text .. "]")
""")
	await create_timer(1.0).timeout
	check(_count("TEXT [k]") == 1,
		"the letter went into the box, which is the proof it was the box that took it")
	check(_count("UIS heard, processed=true") == 1,
		"while UserInputService still hears it, marked as already handled")
	# processed arrives true with nothing focused as well, so a script cannot yet tell a key
	# the game took from one it did not. Not asserted either way.

	world.run_client_chunk("unfocus", """
local Players = game:GetService("Players")
Players.LocalPlayer.PlayerGui.TypingProbe.Probe:ReleaseFocus()
""")
	await create_timer(1.0).timeout
	said.clear()
	await _press(KEY_K, 107)
	check(_count("KEY heard") == 1,
		"and it works again the moment you leave the box: %d" % _count("KEY heard"))

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

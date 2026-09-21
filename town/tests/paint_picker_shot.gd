# The tailor's colour mixer and the words on a cape, driven with real mouse and key events and
# photographed at each step. Windowed: headless draws nothing and a real press needs a window.
#
#   godot --path . -s res://tests/paint_picker_shot.gd -- <shots dir>
extends SceneTree

var world: PulseBlockzWorld
var shots := ""
var said: Array[String] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	_run()

func _said(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

func _move(at: Vector2) -> void:
	Input.warp_mouse(at)
	var m := InputEventMouseMotion.new()
	m.position = at; m.global_position = at
	Input.parse_input_event(m)

func _button(at: Vector2, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT; b.pressed = pressed
	b.position = at; b.global_position = at
	Input.parse_input_event(b)

func _click(at: Vector2) -> void:
	_move(at)
	await create_timer(0.15).timeout
	_button(at, true)
	await create_timer(0.12).timeout
	_button(at, false)
	await create_timer(0.35).timeout

## Screen rect of the first visible PaintTable control the Lua predicate `test` matches.
func _find(test: String) -> Rect2:
	said.clear()
	world.run_client_chunk("find", """
local gui = game:GetService("Players").LocalPlayer.PlayerGui
for _, d in ipairs(gui.PaintTable:GetDescendants()) do
	if d:IsA("GuiObject") and d.Visible and (%s) then
		print(("AT %%d %%d %%d %%d"):format(d.AbsolutePosition.X, d.AbsolutePosition.Y, d.AbsoluteSize.X, d.AbsoluteSize.Y))
		break
	end
end
""" % test)
	await create_timer(0.4).timeout
	var p := _said("AT ").split(" ")
	if p.size() != 4: return Rect2()
	return Rect2(float(p[0]), float(p[1]), float(p[2]), float(p[3]))

func _shot(name: String) -> void:
	get_root().get_texture().get_image().save_png(shots.path_join(name))

func _run() -> void:
	await create_timer(9.0).timeout
	DisplayServer.window_move_to_foreground()
	world.run_chunk("open", """
local rs = game:GetService("ReplicatedStorage")
local Paint = require(rs.Paint)
rs.TailorRemote:FireClient(game:GetService("Players"):GetPlayers()[1], "paint", { w = Paint.W, h = Paint.H, palette = Paint.PALETTE })
""")
	await create_timer(1.5).timeout
	# The first press after a window takes focus is swallowed; spend one on nothing.
	await _click(Vector2(5, 5))

	# LayoutOrder 5 is palette slot 4: red {220, 50, 50} in Paint.PALETTE, green after the mixer.
	var red := await _find("d:IsA('TextButton') and d.LayoutOrder == 5 and d.Parent:FindFirstChildOfClass('UIGridLayout') ~= nil")
	await _click(red.get_center())
	var mix := await _find("d:IsA('TextButton') and d.Text == 'Mix...'")
	await _click(mix.get_center())
	_shot("mix_open.png")
	var hue := await _find("d:IsA('ImageButton') and d.AbsoluteSize.Y < 30")
	# Green is a third of the way along the strip.
	await _click(Vector2(hue.position.x + hue.size.x / 3.0, hue.get_center().y))
	var square := await _find("d:IsA('ImageButton') and d.AbsoluteSize.Y > 60")
	await _click(Vector2(square.end.x - 3, square.position.y + 3))
	_shot("mix_chosen.png")
	var use := await _find("d:IsA('TextButton') and d.Text == 'Use it'")
	await _click(use.get_center())

	said.clear()
	world.run_client_chunk("swatch", """
local gui = game:GetService("Players").LocalPlayer.PlayerGui
for _, d in ipairs(gui.PaintTable:GetDescendants()) do
	if d:IsA("TextButton") and d.LayoutOrder == 5 and d.Parent:FindFirstChildOfClass("UIGridLayout") then
		local c = d.BackgroundColor3
		print(("SWATCH %d %d %d"):format(c.R * 255 + 0.5, c.G * 255 + 0.5, c.B * 255 + 0.5))
	end
end
""")
	await create_timer(0.4).timeout
	print("  swatch 4 is now ", _said("SWATCH "))

	var box := await _find("d:IsA('TextBox') and d.PlaceholderText == 'words on the cape'")
	await _click(box.get_center())
	for ch in "PULSE":
		var k := InputEventKey.new()
		k.pressed = true
		k.unicode = ch.unicode_at(0)
		k.keycode = OS.find_keycode_from_string(ch)
		Input.parse_input_event(k)
		await create_timer(0.05).timeout
		var up := k.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		await create_timer(0.05).timeout
	var text_tool := await _find("d:IsA('TextButton') and d.Text == 'Text'")
	await _click(text_tool.get_center())
	var paper := await _find("d:IsA('Frame') and d:FindFirstChildOfClass('UIGridLayout') ~= nil and d.AbsoluteSize.X > 100")
	await _click(Vector2(paper.position.x + paper.size.x * 0.12, paper.position.y + paper.size.y * 0.1))
	# A pencil stroke under the words, in the colour just mixed, so one shot holds both.
	var pencil := await _find("d:IsA('TextButton') and d.Text == 'Pencil'")
	await _click(pencil.get_center())
	var from := Vector2(paper.position.x + paper.size.x * 0.1, paper.position.y + paper.size.y * 0.45)
	var to := Vector2(paper.position.x + paper.size.x * 0.9, paper.position.y + paper.size.y * 0.45)
	_move(from)
	await create_timer(0.15).timeout
	_button(from, true)
	for i in 60:
		_move(from.lerp(to, float(i + 1) / 60.0))
		await create_timer(0.012).timeout
	_button(to, false)
	await create_timer(0.3).timeout
	var try_on := await _find("d:IsA('TextButton') and d.Text == 'Try it on'")
	await _click(try_on.get_center())
	await create_timer(1.0).timeout
	_shot("words_table.png")
	print("  -> ", ProjectSettings.globalize_path(shots))
	quit(0)

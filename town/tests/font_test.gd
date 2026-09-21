# A FontFace naming a file loads that file, and the label on screen is drawn with it -- not
# with a Godot SystemFont asking the machine for a family by name.
#
#   godot --path . -s res://tests/font_test.gd -- <font.ttf> [shots dir]
#
# A missing font does not fail loudly: Godot falls back and the label still reads correctly,
# so the check is pixels -- the same string rendered with the font and without. Not headless:
# the dummy renderer draws nothing to compare.
extends SceneTree

var world: PulseBlockzWorld
var src := ""
var shots := ""
var t := 0.0
var phase := 0
var lit := false                 # the intro has finished with the screen
var shot_default: Image
var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS ", what)
	else:
		failed += 1
		printerr("  FAIL ", what)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	src = args[0] if args.size() > 0 else ""
	shots = args[1] if args.size() > 1 else ""
	if src == "" or not FileAccess.file_exists(src):
		printerr("usage: godot --path . -s res://tests/font_test.gd -- <font.ttf> [shots]")
		quit(1)
		return
	# user:// is where a published asset would already have been put.
	var bytes := FileAccess.get_file_as_bytes(src)
	var w := FileAccess.open("user://Reactor7.ttf", FileAccess.WRITE)
	w.store_buffer(bytes)
	w.close()
	print("== font test, %d bytes" % bytes.size())
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	# The title screen is a ScreenGui over the whole window: a shot behind it is of the title card.
	main.show_title = false
	# The intro then holds a black over the window for several seconds, so nothing until it says
	# it has handed the screen over.
	world.script_print.connect(func(_n, line):
		if String(line).begins_with("intro:") and String(line).find("the engine ran") >= 0:
			lit = true)
	root.add_child(main)

func _label(font: String) -> void:
	world.run_client_chunk("label", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
for _, s in ipairs(gui:GetChildren()) do if s:IsA("ScreenGui") then s.Enabled = false end end
local old = gui:FindFirstChild("FontProbe")
if old then old:Destroy() end
local screen = Instance.new("ScreenGui")
screen.Name = "FontProbe"
screen.Parent = gui
local l = Instance.new("TextLabel")
l.Size = UDim2.new(0, 640, 0, 120)
l.Position = UDim2.new(0, 40, 0, 40)
l.BackgroundColor3 = Color3.fromRGB(12, 16, 40)
l.TextColor3 = Color3.fromRGB(236, 240, 250)
l.TextSize = 32
l.Text = "CLOUD STRIFE  1234"
%s
l.Parent = screen
print("LABEL ok")
""" % ("l.FontFace = Font.new(\"user://Reactor7.ttf\")" if font != "" else "-- the default face"))

func _grab() -> Image:
	return get_root().get_texture().get_image()

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and lit and t > 3.5:
		phase = 1
		_label("")
		t = 0.0
	elif phase == 1 and t > 1.2:
		phase = 2
		shot_default = _grab()
		_label("Reactor7")
		t = 0.0
	elif phase == 2 and t > 1.2:
		phase = 3
		var withFont := _grab()
		if shots != "":
			DirAccess.make_dir_recursive_absolute(shots)
			withFont.save_png(shots.path_join("font.png"))
			shot_default.save_png(shots.path_join("font-default.png"))
		# Only the strip the label occupies: the rest of the world would drown the difference out.
		var diff := 0
		for y in range(40, 160, 2):
			for x in range(40, 680, 2):
				if shot_default.get_pixel(x, y) != withFont.get_pixel(x, y):
					diff += 1
		var total := (160 - 40) / 2 * (680 - 40) / 2
		print("  %d of %d sampled pixels differ" % [diff, total])
		check(diff > total * 0.01, "the label is drawn with the file's own face, not a fallback")
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed else 0)
		return true
	return false

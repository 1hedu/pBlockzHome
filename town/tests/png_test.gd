# A PNG encoded by the place's Png module and decoded by Godot.
#
#   godot --headless --path . -s res://tests/png_test.gd
#
# Godot's decoder is the judge, not the encoder's own reader: it refuses a CRC over the wrong
# bytes, a LEN whose complement does not match, or adler32 taken over the compressed stream
# instead of the raw one. Main.tscn, because a bare world mounts no scripts and so no Png.
extends SceneTree

var passed := 0
var failed := 0
var said: Array = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("PNG, written in the place")
	var main: Node = load("res://Main.tscn").instantiate()
	main.get_node("Wallet").auto_start = false
	get_root().add_child(main)
	var w: PulseBlockzWorld = main.get_node("World")
	w.script_print.connect(func(_n, t): said.append(t))
	w.script_error.connect(func(n, e): said.append("ERROR %s: %s" % [n, e]))
	_run(w)

func _run(w: PulseBlockzWorld) -> void:
	await create_timer(3.0).timeout
	# A different known colour per corner: a row- or channel-order mistake reads back as a
	# specific wrong colour.
	w.run_chunk("png", """
local Png = require(game:GetService("ReplicatedStorage"):WaitForChild("Png", 10))
local bytes = Png.encode(2, 2, {
	255,0,0,255,      0,255,0,255,
	0,0,255,255,      255,255,255,128,
})
print("PNG64 " .. Png.base64(bytes))

-- And the shape a paint counter actually has: indices plus a palette, scaled up.
local paletted = Png.fromPalette(2, 1, "01", { {10,20,30,255}, {200,100,50,255} }, 4)
print("PAL64 " .. Png.base64(paletted))
""")
	await create_timer(3.0).timeout

	var one := ""
	var two := ""
	for line in said:
		var s := String(line)
		if s.begins_with("PNG64 "): one = s.substr(6)
		elif s.begins_with("PAL64 "): two = s.substr(6)
		elif s.begins_with("ERROR"): printerr("  ", s)
	check(one != "", "the place produced a file")

	var img := Image.new()
	var err := img.load_png_from_buffer(Marshalls.base64_to_raw(one)) if one != "" else ERR_INVALID_DATA
	check(err == OK, "and Godot's decoder accepts it")
	if err == OK:
		check(img.get_width() == 2 and img.get_height() == 2, "at the size it was asked for")
		check(img.get_pixel(0, 0).is_equal_approx(Color8(255, 0, 0, 255)), "top-left is red")
		check(img.get_pixel(1, 0).is_equal_approx(Color8(0, 255, 0, 255)), "top-right is green")
		check(img.get_pixel(0, 1).is_equal_approx(Color8(0, 0, 255, 255)), "bottom-left is blue")
		check(img.get_pixel(1, 1).a < 0.6, "and alpha survived")

	var pal := Image.new()
	var perr := pal.load_png_from_buffer(Marshalls.base64_to_raw(two)) if two != "" else ERR_INVALID_DATA
	check(perr == OK, "a paletted drawing encodes too")
	if perr == OK:
		check(pal.get_width() == 8 and pal.get_height() == 4, "scaled by the factor asked for")
		check(pal.get_pixel(0, 0).is_equal_approx(Color8(10, 20, 30, 255)), "index 0 is the first colour")
		check(pal.get_pixel(7, 3).is_equal_approx(Color8(200, 100, 50, 255)), "index 1 is the second")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

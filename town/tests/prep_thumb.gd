# The place tile, resized to 512x288 and saved as JPEG: deflate cannot compress a starfield,
# which comes out at 248KB as a PNG. Godot encodes it because scripts/png.js writes only PNG.
#
#   godot --headless --path . -s res://tests/prep_thumb.gd -- <src.png> <out.jpg> [quality]
extends SceneTree

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var src := a[0]
	var out := a[1]
	var quality := float(a[2]) if a.size() > 2 else 0.85
	var img := Image.new()
	var err := img.load(src)
	if err != OK:
		printerr("could not read ", src)
		quit(1); return
	var was := Vector2i(img.get_width(), img.get_height())
	img.resize(512, 288, Image.INTERPOLATE_LANCZOS)
	if img.save_jpg(out, quality) != OK:
		printerr("could not write ", out)
		quit(1); return
	print("%dx%d -> 512x288  q=%.2f  %d bytes" % [was.x, was.y, quality, FileAccess.get_file_as_bytes(out).size()])
	quit(0)

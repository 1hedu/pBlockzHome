# Writes the town's cursor out as a PNG among the place's assets, for a client script to name
# through UserInputService.MouseIcon. Roblox takes the hotspot as the centre of the picture and
# offers no property for it, so the image is padded until the fingertip sits at that centre.
#
#   godot --headless --path . -s res://MakeCursor.gd
extends SceneTree

# Copied from a Final Fantasy VII frame, rotated a quarter turn anticlockwise so the finger
# points up. '.' nothing, '#' the outline, 'W' the glove, 's' its shading
const ART := [
	"..####..........",
	"..#Ws##.........",
	"..#WWs##........",
	".##WWWs#........",
	".#sWWWW#........",
	".#sWWWW#........",
	".#sWWWW#........",
	".#sWWWW#........",
	".#sWWWW#........",
	".#sWWWs#........",
	".#sWWWs#........",
	".#sWWWs#........",
	".#sWWWs#####....",
	".#sWWWs##ss#....",
	".##WWss#sWs#....",
	".##WWsWWWs###...",
	".#sWWWWWWsss##..",
	"##sWWWWWWssWs#..",
	"#sWWWWWssWss##..",
	"#sWWWWWssWss####",
	"#sWWWWWWWWsssss#",
	"#sWWWWWWWWWWsss#",
	"##sWWWWWWWWWsss#",
	".##WWWWWWWWWs###",
	"..#sWWWWWWWWs#..",
	"..##WWWWWWWWs#..",
	"...#sWWWWWWWs#..",
	"..##sWWWWWWWs##.",
	"..#sssWWWWWWss#.",
	"..#sWWWWWWWWss#.",
	"..#sWWWWWWWWs##.",
	"..##sWWWWWss####",
	"...##ssWWWWWsss#",
	"....##sWWWWWsss#",
	".....###sWssss##",
]

## Whole pixels, never filtered: the art is small on a modern screen but must stay a drawing.
const SCALE := 2
const HOTSPOT := Vector2i(3, 1)      # the fingertip, in art pixels

const INTO := "res://../../../scripts/models/cursor.png"

func _initialize() -> void:
	var w: int = ART[0].length() * SCALE
	var h: int = ART.size() * SCALE
	var tip := HOTSPOT * SCALE
	var size := Vector2i(maxi(tip.x, w - tip.x) * 2, maxi(tip.y, h - tip.y) * 2)
	var at := Vector2i(size.x / 2 - tip.x, size.y / 2 - tip.y)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := {
		"#": Color(0.04, 0.04, 0.09, 1.0),      # the outline, near-black like the panels
		"W": Color(1.0, 1.0, 1.0, 1.0),
		"s": Color(0.68, 0.70, 0.78, 1.0),      # the underside of the hand
	}
	for y in ART.size():
		var row: String = ART[y]
		for x in ART[0].length():
			if not ink.has(row[x]):
				continue
			for dy in SCALE:
				for dx in SCALE:
					img.set_pixelv(at + Vector2i(x * SCALE + dx, y * SCALE + dy), ink[row[x]])
	var path := ProjectSettings.globalize_path(INTO).simplify_path()
	var err := img.save_png(path)
	print("cursor: %dx%d, fingertip at the middle -> %s (%s)" % [size.x, size.y, path, error_string(err)])
	quit(0 if err == OK else 1)

# Draws on the tailor's paper, presses Try it on, photographs the result. Not headless: the doll
# is a ViewportFrame with a world of its own, and only a picture shows the drawing on the cape.
#
#   godot --path . -s res://tests/paint_shot.gd -- <shots dir>
extends SceneTree

var world: PulseBlockzWorld
var shots := ""
var said: Array[String] = []
var lit := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "."
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		said.append(line)
		if line.begins_with("intro:"): lit = true)
	get_root().add_child(main)
	_run()

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var at := String(line).find(prefix)
		if at >= 0:
			out.append(String(line).substr(at + prefix.length()).strip_edges())
	return out

## A press, a sweep and a release. The pencil paints a cell when the pointer enters it and a
## cell is about twenty pixels across, so the sweep steps every four: longer steps skip cells.
func _drag(from: Vector2, to: Vector2, steps := 0) -> void:
	if steps <= 0:
		steps = int(max(2.0, from.distance_to(to) / 4.0))
	Input.warp_mouse(from)
	var m := InputEventMouseMotion.new()
	m.position = from; m.global_position = from
	Input.parse_input_event(m)
	await create_timer(0.2).timeout
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT; d.pressed = true
	d.position = from; d.global_position = from
	Input.parse_input_event(d)
	await create_timer(0.15).timeout
	for step in steps:
		var at := from.lerp(to, float(step + 1) / float(steps))
		Input.warp_mouse(at)
		var a := InputEventMouseMotion.new()
		a.position = at; a.global_position = at
		Input.parse_input_event(a)
		await create_timer(0.012).timeout
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT; u.pressed = false
	u.position = to; u.global_position = to
	Input.parse_input_event(u)
	await create_timer(0.4).timeout

func _click(at: Vector2) -> void:
	await _drag(at, at, 2)

## Paper cells no longer the blank colour, or -1 if the client never answered.
func _painted() -> int:
	said.clear()
	world.run_client_chunk("count", """
local Players = game:GetService("Players")
local screen = Players.LocalPlayer.PlayerGui:FindFirstChild("PaintTable")
local paper
for _, d in ipairs(screen:GetDescendants()) do
	if d:IsA("UIGridLayout") then paper = d.Parent break end
end
local n = 0
for _, c in ipairs(paper:GetChildren()) do
	if c:IsA("Frame") and c.BackgroundColor3 ~= Color3.fromRGB(242, 242, 246) then n += 1 end
end
print("PAINTED " .. n)
""")
	await create_timer(0.6).timeout
	var rows := _lines("PAINTED ")
	return int(String(rows[rows.size() - 1])) if rows.size() > 0 else -1

## Screen rects keyed "paper", "try" and "doll".
func _where() -> Dictionary:
	said.clear()
	world.run_client_chunk("where", """
local Players = game:GetService("Players")
local screen = Players.LocalPlayer.PlayerGui:FindFirstChild("PaintTable")
local function box(g, what)
	print(("AT %s|%.0f|%.0f|%.0f|%.0f"):format(what,
		g.AbsolutePosition.X, g.AbsolutePosition.Y, g.AbsoluteSize.X, g.AbsoluteSize.Y))
end
for _, d in ipairs(screen:GetDescendants()) do
	if d:IsA("TextButton") and d.Text == "Try it on" then box(d, "try") end
	if d:IsA("ViewportFrame") and d.Name == "Doll" then box(d, "doll") end
	if d:IsA("UIGridLayout") then box(d.Parent, "paper") end
end
""")
	await create_timer(0.8).timeout
	var out := {}
	for row in _lines("AT "):
		var bits: PackedStringArray = String(row).split("|")
		if bits.size() == 5:
			out[bits[0]] = Rect2(float(bits[1]), float(bits[2]), float(bits[3]), float(bits[4]))
	return out

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(6.0).timeout
	DisplayServer.window_move_to_foreground()

	# Open the table over TailorRemote, the way the tailor does.
	world.run_chunk("open", """
local rs = game:GetService("ReplicatedStorage")
local Paint = require(rs:WaitForChild("Paint"))
local player = game:GetService("Players"):GetPlayers()[1]
rs.TailorRemote:FireClient(player, "paint", { w = Paint.W, h = Paint.H, palette = Paint.PALETTE })
""")
	await create_timer(2.0).timeout

	var at := await _where()
	if not at.has("paper") or not at.has("try"):
		printerr("the table did not open: ", str(at.keys()))
		quit(1)
		return
	var paper: Rect2 = at["paper"]
	var tryAt: Rect2 = at["try"]
	print("paper ", paper, "  try ", tryAt)

	# The first press after the window comes forward is swallowed; spend it on a corner cell.
	await _click(paper.position + Vector2(8, 8))

	# Bands near the top, so the shot shows which way up the drawing landed on the cape.
	for i in 3:
		var y := paper.position.y + paper.size.y * (0.10 + 0.05 * i)
		await _drag(Vector2(paper.position.x + 6, y),
			Vector2(paper.position.x + paper.size.x - 6, y))
	print("painted ", await _painted(), " cell(s)")

	await _click(tryAt.position + tryAt.size / 2)
	await create_timer(2.5).timeout

	var img := get_root().get_texture().get_image()
	img.save_png(shots + "/paint-draft.png")
	print("wrote ", shots, "/paint-draft.png")
	quit(0)

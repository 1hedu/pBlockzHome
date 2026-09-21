# Proves the wardrobe's doll frame holds one anchored body, that its camera is aimed at that
# body, and that the picture reaches the screen. Windowed, not headless: headless has no
# renderer to fill a ViewportTexture and reports every core GUI as invisible.
#
#   godot --path . -s res://tests/doll_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the paper doll")
	var main: Node = load("res://Main.tscn").instantiate()
	# Nothing here to press Start
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, t): said.append(t))
	get_root().add_child(main)
	_run()

func _doll_viewport() -> SubViewport:
	var stack: Array[Node] = [get_root()]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SubViewport and n.get_parent() != null and String(n.get_parent().name) == "Doll":
			# Paint keeps a frame called Doll too; the wardrobe's is the one with a body in it.
			var kids: Array[Node] = [n]
			while not kids.is_empty():
				var x: Node = kids.pop_back()
				if x is MeshInstance3D: return n
				for c in x.get_children(): kids.append(c)
		for c in n.get_children(): stack.append(c)
	return null

func _doll_picture() -> TextureRect:
	var vp := _doll_viewport()
	if vp == null: return null
	var ctl := vp.get_parent()
	var stack: Array[Node] = [ctl]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is TextureRect and String(x.name) == "Picture": return x
		for c in x.get_children(): stack.append(c)
	return null

func _run() -> void:
	await create_timer(14.0).timeout
	said.clear()
	# A closed frame is never drawn: the wardrobe has to be open before any of this is visible
	world.run_client_chunk("doll_open", '''
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local w = gui:FindFirstChild("Wardrobe")
if w then w.Enabled = true end
''')
	await create_timer(4.0).timeout
	# Counted on the Luau side: the wardrobe rebuilds the doll whenever the chain payload
	# changes, and a walk of Godot's mesh nodes can land between the old copy and the new one.
	world.run_client_chunk("doll_probe", '''
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
-- Under the Wardrobe, not just any frame called Doll. The paint table keeps one under
-- that name too, and taking the first match in the tree found ITS empty preview and
-- reported the wardrobe as broken.
local wardrobe = gui:FindFirstChild("Wardrobe")
if not wardrobe then print("D none") return end
local frame
for _, c in ipairs(wardrobe:GetDescendants()) do
	if c:IsA("ViewportFrame") and c.Name == "Doll" then frame = c break end
end
if not frame then print("D none") return end
local bodies, parts, loose, lowest = 0, 0, 0, 0
for _, c in ipairs(frame:GetChildren()) do
	if c:IsA("Model") then bodies += 1 end
end
for _, d in ipairs(frame:GetDescendants()) do
	if d:IsA("BasePart") then
		parts += 1
		if not d.Anchored then loose += 1 end
		if d.Position.Y < lowest then lowest = d.Position.Y end
	end
end
print(("D bodies=%d parts=%d loose=%d lowest=%.2f"):format(bodies, parts, loose, lowest))
''')
	await create_timer(3.0).timeout
	var line := ""
	for l in said:
		if l.begins_with("D "): line = l
	check(line != "" and line != "D none", "the wardrobe put a doll in its frame: %s" % line)
	if line == "" or line == "D none":
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	var f := {}
	for pair in line.substr(2).split(" ", false):
		var kv := pair.split("=")
		if kv.size() == 2: f[kv[0]] = float(kv[1])

	# An R6 body is seven parts -- six limbs and a root -- plus whatever accessories it wears
	check(f.get("bodies", 0) == 1, "exactly one of you in it: %d" % int(f.get("bodies", 0)))
	check(f.get("parts", 0) > 0 and f.get("parts", 0) <= 20,
		"one body's worth of parts, not a heap: %d" % int(f.get("parts", 0)))
	# A clone keeps its Humanoid and a ViewportFrame is a world with gravity and no floor:
	# unanchored, the doll falls out of shot and the frame pulls its camera back to follow.
	check(f.get("loose", 1) == 0,
		"and every part of it anchored, so it stands where it was put: %d loose"
		% int(f.get("loose", 1)))
	check(f.get("lowest", -9999.0) > -8.0,
		"which it does: lowest part at y %.1f" % f.get("lowest", -9999.0))

	# ---- and the camera is actually pointed at it ------------------------------------------
	# The frame only aims its camera while it is visible on screen.
	var vp := _doll_viewport()
	check(vp != null, "the frame has a world of its own to look into")
	if vp != null:
		var cam: Camera3D = null
		var box := AABB()
		var first := true
		var stack: Array[Node] = [vp]
		while not stack.is_empty():
			var x: Node = stack.pop_back()
			if x is Camera3D: cam = x
			var m := x as VisualInstance3D
			if m != null:
				var b: AABB = m.global_transform * m.get_aabb()
				box = b if first else box.merge(b)
				first = false
			for c in x.get_children(): stack.append(c)
		check(cam != null, "with a camera in it")
		if cam != null and not first:
			var away := cam.global_transform.origin.distance_to(box.get_center())
			# Studs: far enough to take in a whole person, near enough that one fills the frame.
			check(away > 1.0 and away < 20.0,
				"standing off the doll by %.1f studs, which is looking AT it" % away)
			var fwd := -cam.global_transform.basis.z
			var to_doll := (box.get_center() - cam.global_transform.origin).normalized()
			check(fwd.dot(to_doll) > 0.95,
				"and aimed at the middle of it: %.3f" % fwd.dot(to_doll))

	# ---- and it is on the screen ------------------------------------------------------------
	# A ViewportTexture resolves a node PATH, so one taken while the TextureRect is still
	# detached never binds: everything above can pass into a texture nothing is showing.
	var pic := _doll_picture()
	check(pic != null, "the frame is drawn through a picture")
	if pic != null:
		check(pic.texture != null and pic.texture.get_image() != null,
			"holding a live texture, not a dead one: %s" % str(pic.texture))
		if pic.texture != null:
			var img: Image = pic.texture.get_image()
			if img != null:
				var lit := 0
				var shades := {}
				for y in range(0, img.get_height(), 3):
					for x in range(0, img.get_width(), 3):
						var c := img.get_pixel(x, y)
						if c.a > 0.05:
							lit += 1
							shades[c.to_html()] = true
				check(lit > 200 and shades.size() > 20,
					"with a body actually drawn in it: %d lit samples in %d shades"
					% [lit, shades.size()])

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

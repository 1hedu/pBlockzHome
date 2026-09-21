# The off hand points in front of him for every frame of the BFS 9000 technique. It is aimed at
# a grip up the handle towards the butt, which sits behind the plane of his chest for much of
# the cut, so Weapons.server.luau offHand() clamps that aim to AHEAD in front of the shoulder.
#
#   node scripts/stage-preview.js spoonie <dir>
#   godot --headless --path . -s res://tests/offhand_test.gd -- <staged dir>
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var stage := ""
var lit := false

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	stage = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in (dir.get_files() if dir else PackedStringArray()):
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	main.show_title = false
	world.script_error.connect(func(n, e): printerr("  LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		if line.begins_with("intro:"): lit = true
		elif line.begins_with("SW "): print(line))
	get_root().add_child(main)
	# Let players in as they join; nothing here watches the intro (tests/Arrive.gd).
	Arrive.now(world)
	print("the off hand, through the hachimonji")
	_run()

func _limb(named: String) -> Transform3D:
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is SubViewport:
			continue
		if n is CharacterBody3D:
			for c in n.get_children():
				if c is MeshInstance3D and String(c.name) == named:
					return (c as MeshInstance3D).transform
		for c in n.get_children():
			stack.append(c)
	return Transform3D()

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout

	var json := FileAccess.get_file_as_string(stage.path_join("spoonie.json"))
	json = json.replace(stage.replace("\\", "/") + "/", "user://preview/")
	world.add_model("ReplicatedStorage/OnChain", "spoonie", json)
	world.run_chunk("wear", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local src = rs:WaitForChild("OnChain", 3):FindFirstChild("BFS 9000")
local ch = Players:GetPlayers()[1].Character
ch:FindFirstChildOfClass("Humanoid"):AddAccessory(src:Clone())
print("SW worn")
""")
	await create_timer(2.0).timeout
	world.run_client_chunk("swing", """
game:GetService("ReplicatedStorage"):WaitForChild("WeaponRemote"):FireServer()
""")
	# Direction, not position: a limb is placed by its joint, so its centre moves with the
	# torso's twist whatever the arm points at. -basis.y is the shoulder-to-hand axis in the
	# body's frame; negative z is in front of him.
	var worst := -9.0
	var atWorst := 0.0
	var moved := false
	for i in 26:
		await create_timer(0.06).timeout
		var l := -_limb("Left Arm").basis.y
		var r := -_limb("Right Arm").basis.y
		if absf(r.z) > 0.3 or absf(r.x) > 0.3:
			moved = true
		# Only while the off hand is across him: at rest it hangs straight down and z is noise.
		if absf(l.x) > 0.3 and l.z > worst:
			worst = l.z
			atWorst = i * 0.06
	check(moved, "the technique ran at all: the sword arm left its rest pose")
	check(worst < 0.0,
		"and the off arm points in front of him for every frame of it -- worst %.2f at %.2fs"
		% [worst, atWorst])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

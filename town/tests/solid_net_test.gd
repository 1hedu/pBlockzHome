# A UnionOperation made on the server reaches a client with its MeshData intact, byte for byte.
# Two processes: this one serves, tests/solid_peer.gd joins over a socket and writes down what
# arrived. solid_test runs in one process and so cannot see replication at all.
#
#   godot --headless --path . -s res://tests/solid_net_test.gd
extends SceneTree

const PORT := 8898

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []
var errors: Array[String] = []
var kids: Array[int] = []
var t := 0.0
var phase := 0
var report := ""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _line(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if String(said[i]).begins_with(prefix): return String(said[i]).substr(prefix.length())
	return ""

func _initialize() -> void:
	print("a server's union, seen from a client")
	report = OS.get_user_data_dir().path_join("solid_peer.txt")
	DirAccess.remove_absolute(report)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tests/solid_peer.gd", "--",
		"--port=%d" % PORT, "--out=%s" % report])
	if pid > 0: kids.append(pid)

func _finish() -> void:
	for pid in kids: OS.kill(pid)
	var seen := FileAccess.get_file_as_string(report).strip_edges() if FileAccess.file_exists(report) else ""
	var mine := _line("MADE ")
	print("    server: ", mine.substr(0, 90))
	print("    client: ", seen.substr(0, 90))
	check(mine.begins_with("class=UnionOperation"), "the server made a union: %s" % mine.substr(0, 60))
	check(seen != "", "the client found it in its Workspace")
	var mlen := int(mine.get_slice("len=", 1).get_slice(" ", 0)) if mine.find("len=") >= 0 else 0
	var slen := int(seen.get_slice("len=", 1).get_slice(" ", 0)) if seen.find("len=") >= 0 else -1
	check(mlen > 1000, "it has geometry on the server: %d chars" % mlen)
	check(slen == mlen, "and the client got all of it: %d of %d chars" % [slen, mlen])
	check(seen.get_slice("head=", 1).get_slice(" ", 0) == mine.get_slice("head=", 1).get_slice(" ", 0),
		"the same bytes, not merely the same length")
	check(errors.is_empty(), "the server threw nothing: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 12.0:
		phase = 1
		world.run_chunk("make", """
local outer = Instance.new("Part")
outer.Shape = Enum.PartType.Cylinder
outer.Size = Vector3.new(0.3, 3, 3)
outer.Anchored = true
outer.CFrame = CFrame.new(0, 30, 0)
-- In the Workspace: BasePart's methods need their parts in the scene, where GeometryService's do not.
outer.Parent = workspace
local hole = Instance.new("Part")
hole.Shape = Enum.PartType.Cylinder
hole.Size = Vector3.new(0.6, 2, 2)
hole.CFrame = outer.CFrame
hole.Parent = workspace
local ring = outer:SubtractAsync({ hole })
ring.Name = "NetRing"
ring.Parent = workspace
print(("MADE class=%s len=%d head=%s size=%.3f,%.3f,%.3f"):format(ring.ClassName, #ring.MeshData,
	ring.MeshData:sub(1, 40), ring.Size.X, ring.Size.Y, ring.Size.Z))
""")
	elif phase == 1 and t > 30.0:
		phase = 2
		_finish()
	return false

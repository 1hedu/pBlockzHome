# The jump, over the wire, on a machine with work to do.
#
#   godot --headless --path . -s res://tests/jump_net_test.gd
#
# The jump fixture that needs both a server and a loaded box: jump_test rides Play Solo, and
# tramp_net_test takes one jump across the wire on a quiet machine. A town, bots for load, then
# twenty-four jumps -- sixteen tapped, eight with the key held -- all the same height.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld

## Every script error the server threw while this ran; _finish asserts it is empty.
var errors: Array[String] = []
var kids: Array[int] = []
var t := 0.0
var phase := 0
var report := ""

const PORT := 8894
const LOAD := 8            # bots, purely to load the machine
const APEX := 6.79         # JumpPower 50 against gravity 196.2, plus a frame of overshoot

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _spawn(script: String, args: Array) -> void:
	var all := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", script, "--"]
	all.append_array(args)
	var pid := OS.create_process(OS.get_executable_path(), all)
	if pid > 0: kids.append(pid)

func _initialize() -> void:
	print("the jump, over the wire, on a busy machine")
	report = OS.get_user_data_dir().path_join("jumpnet.txt")
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
	get_root().add_child(main)
	# Nobody is watching the intro: let players in as they join (tests/Arrive.gd).
	Arrive.now(world)

	for i in LOAD:
		_spawn("res://tests/bot.gd", ["--name=Load%d" % i, "--port=%d" % PORT, "--every=1.3"])
	_spawn("res://tests/jump_peer.gd", ["--name=Jumper", "--port=%d" % PORT, "--out=%s" % report])

func _finish() -> void:
	for pid in kids: OS.kill(pid)
	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## Every jump the client wrote down, as (label, apex).
func _jumps() -> Array:
	if not FileAccess.file_exists(report):
		return []
	var out := []
	for row in FileAccess.get_file_as_string(report).strip_edges().split("\n"):
		var line := String(row)
		# Trace rows carry an apex of nought on purpose; they are not jumps.
		if line.begins_with("vy-") or line.begins_with("dy-") or line.begins_with("trace-") \
			or line.begins_with("state-"):
			continue
		var i := line.find("apex ")
		if i < 0: continue
		out.append([line.split("|")[0], float(line.substr(i + 5).split(" ")[0])])
	return out

func _process(delta: float) -> bool:
	t += delta
	# 135 s: the bots and the jumper have to get in, then two dozen jumps with a wait between.
	if phase == 0 and t > 135.0:
		phase = 1
		var jumps := _jumps()
		check(jumps.size() >= 20, "the client jumped two dozen times: %d recorded" % jumps.size())
		if jumps.size() < 20:
			printerr("    (nothing at %s -- did the jumper join?)" % report)
			_finish()
			return false

		var lo: float = jumps[0][1]
		var hi: float = jumps[0][1]
		var refused := 0
		for j in jumps:
			var a: float = j[1]
			lo = min(lo, a)
			hi = max(hi, a)
			if a < 1.0: refused += 1
		print("    %d jumps, %.2f to %.2f studs" % [jumps.size(), lo, hi])

		# A jump under a stud is Humanoid.Jump left standing true with nothing consuming it.
		check(refused == 0, "not one of them was refused: %d went nowhere" % refused)
		check(hi - lo < 0.5,
			"and they are all the same height whatever the machine is doing: %.2f to %.2f"
				% [lo, hi])
		check(abs(lo - APEX) < 0.6 and abs(hi - APEX) < 0.6,
			"which is the height JumpPower asks for: %.2f against %.2f" % [lo, APEX])
		_finish()
	return false

# Standing up off a bench with the space bar.
#
#   godot --headless --path . -s res://tests/bench_jump_test.gd
#
# rbx_runtime unseats on three things: Sit going false, Health hitting nought, and
# Humanoid.Jump going true. seat_test covers the first; the space bar is the only one a player
# has, and the host's seated branch polls the physical key itself (is_physical_key_pressed,
# not an event) before deciding what to write. So this holds a real key and asks whether the
# body left the bench -- writing a property instead tests the other door.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var satY := 0.0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _last(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		var s := String(said[i])
		var at := s.find(prefix)
		if at >= 0: return s.substr(at + prefix.length()).strip_edges()
	return ""

func _initialize() -> void:
	print("getting off a bench with the space bar")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false          # a title screen is a menu, and a menu eats the space bar
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	root.add_child(main)
	# Let players in as they join, with no intro to sit through (tests/Arrive.gd).
	Arrive.now(world)

## The host polls the key rather than taking the event, so a press and release in the same
## frame can fall between two polls and never be seen.
func _press(down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_SPACE
	e.keycode = KEY_SPACE
	e.pressed = down
	Input.parse_input_event(e)

func _report(tag: String) -> void:
	said.clear()
	world.run_chunk(tag, """
local Players = game:GetService("Players")
local ch = Players:GetPlayers()[1] and Players:GetPlayers()[1].Character
local hum = ch and ch:FindFirstChildOfClass("Humanoid")
local root = ch and ch:FindFirstChild("HumanoidRootPart")
local seat = hum and hum.SeatPart
local welds = 0
if ch then
	for _, d in ipairs(ch:GetDescendants()) do
		if d:IsA("Weld") and d.Name == "SeatWeld" then welds += 1 end
	end
end
-- The weld is counted from the SEAT's side too, because unseat destroys it there and a
-- SeatPart cleared while the weld survives is a body still pinned to the plank.
local map = workspace:FindFirstChild("Map")
local bench = map and map:FindFirstChild("BenchNorthWest2", true)
if bench then
	for _, d in ipairs(bench:GetDescendants()) do
		if d:IsA("Weld") and d.Name == "SeatWeld" then welds += 1 end
	end
end
print(("SEATED seat=%s sit=%s welds=%d occupant=%s y=%.2f state=%s"):format(
	seat and seat.Name or "none", tostring(hum and hum.Sit), welds,
	bench and bench.Occupant and "yes" or "no",
	root and root.Position.Y or -1, hum and tostring(hum:GetState()) or "?"))
""")

func _process(delta: float) -> bool:
	t += delta
	# Sit down by landing on the seat, not by writing Sit.
	if phase == 0 and t > 8.0:
		phase = 1; t = 0.0
		world.run_chunk("sit", """
local Players = game:GetService("Players")
local ch = Players:GetPlayers()[1].Character
local map = workspace:FindFirstChild("Map")
local bench = map and map:FindFirstChild("BenchNorthWest2", true)
if not bench then print("SIT no bench") return end
ch:PivotTo(CFrame.new(bench.Position + Vector3.new(0, 3.5, 0)))
print("SIT dropped onto " .. bench:GetFullName())
""")
	elif phase == 1 and t > 6.0:
		phase = 2; t = 0.0
		_report("before")
	elif phase == 2 and t > 2.0:
		phase = 3; t = 0.0
		var before := _last("SEATED ")
		print("    before: ", before)
		check(before.find("seat=BenchNorthWest2") >= 0, "sitting on the bench to begin with: %s" % before)
		check(before.find("welds=0") < 0, "and welded to it")
		var at := before.find("y=")
		satY = float(before.substr(at + 2).split(" ")[0]) if at >= 0 else 0.0
		_press(true)
	# Held half a second so a poll lands inside the press.
	elif phase == 3 and t > 0.5:
		phase = 4; t = 0.0
		_press(false)
	elif phase == 4 and t > 1.5:
		phase = 5; t = 0.0
		_report("after")
	elif phase == 5 and t > 2.0:
		phase = 6
		var after := _last("SEATED ")
		print("    after:  ", after)
		check(after.find("seat=none") >= 0, "the space bar got me off the bench: %s" % after)
		check(after.find("sit=false") >= 0, "and Sit came back down")
		check(after.find("welds=0") >= 0, "and the SeatWeld is gone, both ends")
		check(after.find("occupant=no") >= 0, "and the bench knows nobody is on it")
		# standUp hops the body, so the root must have moved: a cleared SeatPart with the body
		# still on the plank is the same bug.
		var at := after.find("y=")
		var nowY := float(after.substr(at + 2).split(" ")[0]) if at >= 0 else 0.0
		check(absf(nowY - satY) > 0.35, "and the body actually left the seat: %.2f, was %.2f" % [nowY, satY])
		check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false

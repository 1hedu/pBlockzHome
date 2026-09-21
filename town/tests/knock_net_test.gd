# Does the shove reach a real player, and does it still scale once it has?
#
#   godot --headless --path . -s res://tests/knock_net_test.gd
#
# knockback_test checks the arithmetic in Health.shove under Play Solo: 1.0 at full containers,
# 1.5 at the last half. A shove is a velocity the SERVER writes onto a body another machine
# simulates, so the distance here is measured by the peer off its own root. Four rounds of each
# health, with bots loading the box, because one round of a race measures nothing.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var errors: Array[String] = []
var kids: Array[int] = []
var t := 0.0
var phase := 0
var report := ""
var step := 0

const PORT := 8897
const LOAD := 6            # bots, purely to load the machine
const FORCE := 30.0        # the same force knockback_test uses, so the two are comparable
const ROUNDS := 4

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _spawn(script: String, args: Array) -> void:
	var all := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", script, "--"]
	all.append_array(args)
	var pid := OS.create_process(OS.get_executable_path(), all)
	if pid > 0: kids.append(pid)

func _initialize() -> void:
	print("the shove, over the wire, measured by the body it lands on")
	report = OS.get_user_data_dir().path_join("knocknet.txt")
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
	_spawn("res://tests/knock_peer.gd", ["--name=Shoved", "--port=%d" % PORT, "--out=%s" % report])

## Set the health -- the CHANGE is what arms the peer -- then shove, or don't, for a control.
func _round(half: int, shove: bool) -> void:
	var chunk := """
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local them = Players:FindFirstChild("Shoved")
if not them or not them.Character then print("SHOVE nobody here") return end
local hum = them.Character:FindFirstChildOfClass("Humanoid")
local root = them.Character:FindFirstChild("HumanoidRootPart")
if not hum or not root then print("SHOVE no body") return end
task.spawn(function()
	hum.Health = %d
	-- Long enough for the peer to see the health and start watching, and for the body to be
	-- standing still again after whatever the last round did to it.
	task.wait(0.7)
	if %s then
		Health.shove(them, nil, %s, true)
		print(("SHOVE at %%d of %%d, force %%s"):format(hum.Health, hum.MaxHealth, %s))
	else
		print(("SHOVE control at %%d, nothing thrown"):format(hum.Health))
	end
end)
""" % [half, "true" if shove else "false", FORCE, FORCE]
	world.run_chunk("shove%d" % step, chunk)

## Every measurement the client wrote down, as health -> [distances].
func _went() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(report):
		return out
	for row in FileAccess.get_file_as_string(report).strip_edges().split("\n"):
		if row.find("at=") < 0 or row.find("went=") < 0:
			continue
		var at := int(row.substr(row.find("at=") + 3).split(" ")[0])
		var d := float(row.substr(row.find("went=") + 5).split(" ")[0])
		if not out.has(at): out[at] = []
		out[at].append(d)
	return out

func _median(rows: Array) -> float:
	if rows.is_empty(): return 0.0
	var s := rows.duplicate()
	s.sort()
	return float(s[s.size() / 2])

func _finish() -> void:
	for pid in kids: OS.kill(pid)
	var went := _went()
	print("    measured: ", went)

	var full: Array = went.get(6, [])
	var dying: Array = went.get(1, [])
	var control: Array = went.get(3, [])

	check(full.size() >= ROUNDS - 1, "the client reported its full-health shoves: %d" % full.size())
	check(dying.size() >= ROUNDS - 1, "and its last-half shoves: %d" % dying.size())

	# The control catches drift: a round with nothing thrown has to measure as nothing.
	check(_median(control) < 0.5,
		"a round with nothing thrown moves nobody: %.2f studs" % _median(control))

	# Before the scale: does it land at all.
	var landedFull := 0
	for d in full: if d > 0.5: landedFull += 1
	var landedDying := 0
	for d in dying: if d > 0.5: landedDying += 1
	check(landedFull == full.size() and landedDying == dying.size(),
		"every shove moved the body it was aimed at: %d/%d full, %d/%d dying"
			% [landedFull, full.size(), landedDying, dying.size()])

	# On the median: one round is a race, not a measurement.
	var mf := _median(full)
	var md := _median(dying)
	check(mf > 0.0 and md > mf * 1.3,
		"further the fewer hearts are left, over the wire: %.2f studs full, %.2f dying" % [mf, md])

	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _process(delta: float) -> bool:
	t += delta
	# 30 s: the town, the bots and the client all have to arrive first.
	if phase == 0:
		if t > 30.0:
			phase = 1; t = 0.0
		return false
	# Four times over: a control at 3 hearts, a shove at the full 6, a shove at the last 1.
	if t > 4.0:
		t = 0.0
		if step >= ROUNDS * 3:
			_finish()
			return false
		var which := step % 3
		if which == 0: _round(3, false)
		elif which == 1: _round(6, true)
		else: _round(1, true)
		step += 1
	return false

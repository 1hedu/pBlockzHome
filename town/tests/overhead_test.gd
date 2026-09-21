# The name and the hearts over everyone's head, drawn on each client.
#
#   godot --headless --path . -s res://tests/overhead_test.gd
#
# Both are drawn client-side, so this half is the server: a real client joins and reports its
# own PlayerGui through a file.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld

## Every script error the server threw while this ran; asserted on in _finish.
var errors: Array[String] = []
var main: Node
var said: Array[String] = []
var kids: Array[int] = []
var t := 0.0
var phase := 0

const PORT := 8815
const PEER := "Watcher"        # the client that does the looking
const TARGET := "Runner"       # the body it looks at; bot.gd arms this one with nothing
const HITTER := "BFS 9000"      # the one that swings at it
# Seven more bodies: the load a played town puts on the server.
const LOAD := 7
var REPORT := ""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var i := String(line).find(prefix)
		if i >= 0:
			out.append(String(line).substr(i + prefix.length()).strip_edges())
	return out

func _spawn(script: String, args: Array) -> void:
	var all := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", script, "--"]
	all.append_array(args)
	var pid := OS.create_process(OS.get_executable_path(), all)
	if pid <= 0:
		printerr("could not start %s" % script)
	else:
		kids.append(pid)

func _initialize() -> void:
	print("the name and the hearts over a head, read from inside a client")
	REPORT = OS.get_user_data_dir().path_join("overhead.json")
	# A stale report from a previous run would be read as this run's answer.
	DirAccess.remove_absolute(REPORT)

	main = load("res://Main.tscn").instantiate()
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
	# A character each on join, instead of the nine seconds Arrival.server.luau waits for a
	# client to report it can see; the spawn ForceField goes with it (tests/Arrive.gd).
	Arrive.now(world)

	_spawn("res://tests/overhead_peer.gd", ["--name=%s" % PEER, "--port=%d" % PORT,
		"--out=%s" % REPORT])
	_spawn("res://tests/bot.gd", ["--name=%s" % TARGET, "--port=%d" % PORT, "--every=9.9"])
	_spawn("res://tests/bot.gd", ["--name=%s" % HITTER, "--port=%d" % PORT, "--every=0.8"])
	for i in LOAD:
		_spawn("res://tests/bot.gd", ["--name=Load%d" % i, "--port=%d" % PORT, "--every=1.3"])

func _finish() -> void:
	for pid in kids: OS.kill(pid)
	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## The peer's latest look at its own screen.
func _report() -> Dictionary:
	if not FileAccess.file_exists(REPORT):
		return {}
	var blob := FileAccess.get_file_as_string(REPORT)
	var got = JSON.parse_string(blob)
	return got if got is Dictionary else {}

## The peer's board for one player, by the name Overhead.client.luau gives it.
func _board(who: String) -> Dictionary:
	for row in _report().get("boards", []):
		if row is Dictionary and String(row.get("board", "")) == "Overhead" + who:
			return row
	return {}

func _process(delta: float) -> bool:
	t += delta
	# 45 s: the children connect, get a body, and the peer writes its first report.
	if phase == 0 and t > 45.0:
		phase = 1
		t = 0.0
		var report := _report()
		check(report.size() > 0, "the client wrote down what it can see")
		if report.size() == 0:
			printerr("    (no report at %s -- did the peer join?)" % REPORT)
			_finish()
			return false
		check(report.get("screen", false) == true,
			"it built the Overhead screen at all")
		check(report.get("mine", true) == false,
			"and no board for itself: you have the meter along the bottom of your own screen")

		var board := _board(TARGET)
		check(board.size() > 0, "there is a board over the other player: %s" % str(report.get("boards")))
		if board.size() == 0:
			_finish()
			return false
		# A board adorned to the wrong part draws in the wrong place; to a destroyed head, nowhere.
		check(String(board.get("adornee", "")).ends_with(".Head"),
			"hung on their Head: %s" % board.get("adornee"))
		check(String(board.get("text", "")) == TARGET,
			"with their name on it: [%s]" % board.get("text"))
		if board.get("themeHasFont", false):
			check(board.get("faced", false) == true,
				"in the place's own face rather than the engine's default")
		else:
			print("    (the place's font had not been fetched, so the face is untested)")
		check(board.get("heartsShown", false) == true, "and the hearts are up")
		# The owner publishes StateName and it replicates; deriving it from velocity reads
		# Freefall on flat ground. Health.aloft reads that same state and nothing else, so a
		# wrong one changes what a shove does and which hit sound plays (server/Health.luau).
		check(String(board.get("seenState", "?")).find("Running") >= 0,
			"and a watcher knows it is standing, not falling: %s" % board.get("seenState"))
		# Freefall holds the right arm at or above the head; by the side it hangs ~1.5 studs below.
		check(float(board.get("armUp", 0)) < -0.5,
			"and its arms hang by its sides rather than straight up: right arm %s studs from the head"
				% board.get("armUp"))
		# The host writes AbsoluteSize back each frame, so a board never placed reads nought.
		check(float(board.get("drawnWidth", 0)) > 1.0,
			"and the host actually placed it on the screen: %s wide at (%s, %s)"
				% [board.get("drawnWidth"), board.get("atX"), board.get("atY")])
		check(int(board.get("containers", 0)) == 3,
			"three containers, as a new body has: %d" % int(board.get("containers", 0)))
		check(int(board.get("halves", 0)) == 6,
			"all six halves full: %d" % int(board.get("halves", 0)))

		said.clear()
		world.run_chunk("hurt", ("""
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local them = Players:FindFirstChild("TARGET_NAME")
if not them then print("HURT nobody") return end
Health.setFights(them, true)
local hum = them.Character:WaitForChild("Humanoid")
hum.Health = 1
print(("HURT left them on %d of %d"):format(hum.Health, hum.MaxHealth))
""").replace("TARGET_NAME", TARGET))
	elif phase == 1 and t > 3.0:
		phase = 2
		t = 0.0
		check(_lines("HURT ").size() > 0, "hearts were taken off on the server: %s" % str(_lines("HURT ")))
		var board := _board(TARGET)
		check(int(board.get("halves", -1)) == 1,
			"and the row on the other machine followed the damage down to one half: %d"
				% int(board.get("halves", -1)))
		check(int(board.get("containers", 0)) == 3,
			"with the empty containers still drawn: %d" % int(board.get("containers", 0)))

		# Out of the fight the hearts go entirely -- not greyed, not drawn empty: nothing can hit
		# them, so a meter there would be showing a number that can never move.
		said.clear()
		world.run_chunk("peace", ("""
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local them = Players:FindFirstChild("TARGET_NAME")
if not them then print("PEACE nobody") return end
Health.setFights(them, false)
print(("PEACE fights=%s attr=%s"):format(
	tostring(Health.fights(them)), tostring(them:GetAttribute("Fights"))))
""").replace("TARGET_NAME", TARGET))
	elif phase == 2 and t > 3.0:
		phase = 3
		t = 0.0
		var peace := _lines("PEACE ")
		check(peace.size() > 0 and String(peace[0]).find("attr=false") >= 0,
			"the server put the flag where every client can read it: %s" % str(peace))
		var board := _board(TARGET)
		check(board.get("heartsShown", true) == false,
			"out of the fight, the hearts are gone")
		check(String(board.get("text", "")) == TARGET,
			"and the name is still there: [%s]" % board.get("text"))

		# ---- a real fight -------------------------------------------------------------
		# Damage from a bot swinging on its own clock, not from a health write in this chunk.
		said.clear()
		world.run_chunk("fight", ("""
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local them = Players:FindFirstChild("TARGET_NAME")
local hitter = Players:FindFirstChild("HITTER_NAME")
if not them or not hitter then print("FIGHT nobody") return end
Health.setFights(them, true)
Health.setFights(hitter, true)

local ch = hitter.Character
if ch and not ch:FindFirstChild("HITTER_NAME") then
	local acc = Instance.new("Accessory")
	acc.Name = "HITTER_NAME"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 2.2, 0.4)
	handle.Parent = acc
	acc.Parent = ch
end

local theirs = ch:WaitForChild("HumanoidRootPart")
local mine = them.Character:WaitForChild("HumanoidRootPart")
local hum = them.Character:WaitForChild("Humanoid")
hum.Health = hum.MaxHealth

-- Counted at Health.hit and only the swinger's, the way hitbox_test does it. Watching the
-- health instead is a race: three blows empty a body, a dead body is replaced, and the server
-- then reads a fresh Humanoid while the watching client is still showing the old one. That is
-- a disagreement about nothing.
local blows = 0
local realHit = Health.hit
Health.hit = function(who, attacker, half, shove)
	local landed = realHit(who, attacker, half, shove)
	if landed and attacker == hitter and who == them then
		blows += 1
		-- Kept on their feet, so the body under the row is never replaced mid-measurement.
		local h = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
		if h and h.Health < 3 then h.Health = h.MaxHealth end
	end
	return landed
end

-- Stood in front of it and held there, since a body its own client simulates drifts back.
local look = theirs.CFrame.LookVector
look = Vector3.new(look.X, 0, look.Z).Unit
local spot = theirs.Position + look * 5
local stop = false
task.spawn(function()
	while not stop do
		mine.CFrame = CFrame.new(spot, theirs.Position)
		mine.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		task.wait()
	end
end)
-- Stopped before it can finish them. Three blows from a BFS 9000 empty a body, and a body
-- that dies is replaced -- the server would then be reading a corpse's Humanoid while the
-- watching client had already moved on to the new one, and the two would disagree for a
-- reason that has nothing to do with what is under test.
task.wait(3.0)
stop = true
Health.hit = realHit
local live = them.Character and them.Character:FindFirstChildOfClass("Humanoid")
print(("FIGHT %d blow(s) landed, server reads %s of %s"):format(
	blows, live and tostring(live.Health) or "?", live and tostring(live.MaxHealth) or "?"))
""").replace("TARGET_NAME", TARGET).replace("HITTER_NAME", HITTER))
	elif phase == 3 and t > 5.0:
		phase = 4
		var fight := _lines("FIGHT ")
		check(fight.size() > 0, "a bot swung a real weapon at them: %s" % str(fight))
		if fight.size() > 0:
			var f := String(fight[0])
			var blows := int(f.split(" ")[0])
			var onServer := int(f.substr(f.find("reads ") + 6).split(" ")[0])
			var board2 := _board(TARGET)
			var onClient := int(board2.get("seenHealth", -1))
			check(onClient == onServer,
				"the watching client sees the same health the server does: %d against %d"
					% [onClient, onServer])
			print("    every health this client was handed: %s"
				% str(_report().get("runs", {}).get(TARGET, "(none)")))
			check(int(board2.get("halves", -1)) == onClient,
				"and its row drew that: %d halves for %d health"
					% [int(board2.get("halves", -1)), onClient])
			# Only that swings land: comparing blows against the drawn row at one instant is a race.
			check(blows > 0, "and real swings landed on it: %d" % blows)
		_finish()
	return false

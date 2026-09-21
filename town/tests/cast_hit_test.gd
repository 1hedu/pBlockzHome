# The cane's orb landing on somebody: half a heart for a click, two hearts for a full charge,
# nothing through a wall, and a third client hearing every shot.
#
#   godot --headless --path . -s res://tests/cast_hit_test.gd
#
# Two bot processes on a real server, rigged as hitbox_test.gd does it, plus a watching
# chunk_peer.gd --voices. The cane keeps its charge when the button comes up and throws it on
# the next click, so the caster's --holds list alternates hold and click.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")
const PORT := 8814
const OUT := 10.0

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var main: Node
var bots: Array[int] = []
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0
var walled_at := -1
var heard := ""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _lines(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line in said:
		var i := line.find(prefix)
		if i >= 0: out.append(line.substr(i + prefix.length()).strip_edges())
	return out

func _spawn(name: String, extra: Array) -> void:
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/bot.gd", "--",
		"--name=%s" % name, "--port=%d" % PORT]
	args.append_array(extra)
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid > 0: bots.append(pid)
	else: printerr("could not start bot %s" % name)

func _initialize() -> void:
	StandIns.stage("cast_hit")
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
	_spawn("Cane", ["--every=10", "--holds=0,6.3,0,6.3,0,0", "--walk=3:1:4"])
	_spawn("Runner", ["--every=99"])
	heard = OS.get_user_data_dir().path_join("cast_heard.txt")
	DirAccess.remove_absolute(heard)
	var chunk := OS.get_user_data_dir().path_join("cast_heard.luau")
	var cf := FileAccess.open(chunk, FileAccess.WRITE)
	cf.store_string("print('SEEN watching') workspace.DescendantAdded:Connect(function(d) if d.Name == 'SfxBuster' then print('SEEN BUSTER ' .. d:GetFullName() .. ' playing=' .. tostring(d.Playing)) end end)")
	cf.close()
	var wpid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/chunk_peer.gd", "--", "--port=%d" % PORT, "--chunk=%s" % chunk, "--out=%s" % heard, "--voices=1"])
	if wpid > 0: bots.append(wpid)

func _finish() -> void:
	for pid in bots: OS.kill(pid)
	check(errors.is_empty(), "the server threw nothing: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 24.0:
		phase = 1; t = 0.0
		world.run_chunk("standins", StandIns.chunk("cast_hit"))
		world.run_chunk("open", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Health = require(game:GetService("ServerScriptService").Health)
local hitter, victim = Players:FindFirstChild("Cane"), Players:FindFirstChild("Runner")
if not hitter or not victim or not hitter.Character or not victim.Character then print("OPEN missing") return end
Health.setFights(hitter, true)
Health.setFights(victim, true)

-- The cane in its hand: an Accoutrement named for the weapon is the whole weapon to the fight.
local acc = Instance.new("Accessory")
acc.Name = "Cane"
local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Size = Vector3.new(0.15, 2, 0.15)
handle.Parent = acc
acc.Parent = hitter.Character

-- No shove to move anybody (the cane has none anyway), and every blow the caster lands counted
-- with what it took, the victim put straight back to full so it never dies.
local realHit = Health.hit
local blows = 0
Health.hit = function(who, attacker, half, shove)
	local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
	local before = hum and hum.Health or -1
	local landed = realHit(who, attacker, half, shove)
	if landed and attacker == hitter and who == victim then
		blows += 1
		print(("BLOW half=%d shove=%s before=%d"):format(half, tostring(shove), before))
		if hum and hum.Health > 0 then hum.Health = hum.MaxHealth end
	end
	return landed
end

-- When the server sees the caster walking, and stop.
local wasMoving = false
RunService.Heartbeat:Connect(function()
	local h = hitter.Character and hitter.Character:FindFirstChildOfClass("Humanoid")
	local moving = h ~= nil and h.MoveDirection.Magnitude > 0.1
	if moving ~= wasMoving then
		wasMoving = moving
		print(("MOVE %s at %.2f"):format(moving and "on" or "off", os.clock()))
	end
end)
-- And when a charge starts and the button comes up, off the remote itself.
game:GetService("ReplicatedStorage").WeaponRemote.OnServerEvent:Connect(function(p, what)
	if p == hitter then print(("PRESS %s at %.2f"):format(tostring(what), os.clock())) end
end)
-- Every orb leaving the cane, with its charge. Once three blows have landed, the next ordinary
-- shot is met by a victim on half a heart, so that it kills.
local weakened = false
workspace.ChildAdded:Connect(function(o)
	if o.Name == "CaneOrb" then
		print(("CAST charge=%.2f half=%d"):format(o:GetAttribute("Charge") or -1, o:GetAttribute("Half") or -1))
		if blows >= 3 and not weakened and o:GetAttribute("Half") == 1 then
			weakened = true
			local hum = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.Health = 1 end
			print("WEAKENED")
		end
	end
end)

-- The victim held OUT studs in front of the caster, and both held still, every frame -- out on the
-- open ground south of the square, where nothing stands between them (the Archivist is at z 46).
RunService.Heartbeat:Connect(function()
	local a = hitter.Character and hitter.Character:FindFirstChild("HumanoidRootPart")
	local v = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	if not a or not v then return end
	local here = Vector3.new(0, a.Position.Y, 56)
	a.CFrame = CFrame.new(here, here + Vector3.new(0, 0, 1))
	a.AssemblyLinearVelocity = Vector3.zero
	v.CFrame = CFrame.new(here + Vector3.new(0, 0, OUT), here)
	v.AssemblyLinearVelocity = Vector3.zero
end)
task.delay(0.5, function()
	local a = hitter.Character.HumanoidRootPart
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { hitter.Character, victim.Character }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(a.Position + Vector3.new(0.7, 0.4, 0), Vector3.new(0, 0, OUT + 2), params)
	print(("PATH %s"):format(hit and (hit.Instance:GetFullName() .. " at " .. tostring(hit.Position)) or "clear"))
end)
print("OPEN ok")
""".replace("OUT", str(OUT)))
	elif phase == 1 and t > 2.0:
		phase = 2; t = 0.0
		check(not _lines("OPEN ok").is_empty(), "both bots are in the town, one holding the cane")
		var path := _lines("PATH ")
		check(path.size() == 1 and path[0] == "clear", "nothing solid stands between them: %s" % str(path))
		if _lines("OPEN ok").is_empty():
			_finish()
	elif phase == 2:
		# 120s cap: the bot's hold list is a minute round and may start partway through it.
		var casts := _lines("CAST ")
		var tap := casts.filter(func(c): return c.contains("half=1"))
		var full := casts.filter(func(c): return c.contains("half=4"))
		if (not tap.is_empty() and not full.is_empty() and casts.size() >= 5 and not _lines("WEAKENED").is_empty() and t > 0.0 and casts[casts.size() - 1].contains("half=") and _settled()) or t > 120.0:
			phase = 3; t = 0.0
			walled_at = casts.size()
			world.run_chunk("wall", """
local wall = Instance.new("Part")
wall.Name = "TestWall"
wall.Anchored = true
wall.Size = Vector3.new(14, 14, 1)
local a = game:GetService("Players").Cane.Character.HumanoidRootPart
wall.CFrame = CFrame.new(Vector3.new(0, a.Position.Y, 56 + OUT / 2))
wall.Parent = workspace
print("WALL up")
""".replace("OUT", str(OUT)))
	# The watching client needs time to hear the last cast before its file is read.
	elif phase == 3 and (_lines("CAST ").size() > walled_at and t > 12.0 and _settled() or t > 45.0):
		phase = 4
		_judge()
	return false

var settle_from := -1.0
## True once the latest cast has had two seconds to land.
func _settled() -> bool:
	var n := _lines("CAST ").size()
	if n != int(settle_from):
		settle_from = n
		settle_time = t
	return t - settle_time > 2.0
var settle_time := 0.0

func _judge() -> void:
	# Walk the log in order: each blow belongs to the cast before it.
	var events: Array[String] = []
	for line in said:
		if line.find("CAST ") >= 0 or line.find("BLOW ") >= 0 or line.find("WALL up") >= 0:
			events.append(line.strip_edges())
	print("  events: ", events)
	var before_wall := true
	var tap_ok := false
	var full_ok := false
	var matched := true
	var blows_before := 0
	var through_wall := 0
	var walled_casts := 0
	var last_cast_half := ""
	for e in events:
		if e.contains("WALL up"):
			before_wall = false
		elif e.begins_with("CAST") or e.contains("CAST "):
			last_cast_half = e.substr(e.find("half=") + 5)
			if not before_wall: walled_casts += 1
		elif e.contains("BLOW "):
			var half := e.substr(e.find("half=") + 5).split(" ")[0]
			if before_wall:
				if last_cast_half == "1" and half == "1": tap_ok = true
				if last_cast_half == "4" and half == "4": full_ok = true
				blows_before += 1
				if half != last_cast_half: matched = false
			else:
				through_wall += 1
	check(tap_ok, "a click's orb takes half a heart")
	check(full_ok, "a full charge's orb takes two hearts")
	check(matched and blows_before >= 4, "every cast lands for exactly what it charged, the walked one included (%d blows)" % blows_before)
	_judge_knock()
	_judge_walk()
	check(walled_casts > 0 and through_wall == 0, "and with a wall between them, a cast lands nothing (%d cast, %d blows)" % [walled_casts, through_wall])
	_judge_heard(events)
	_finish()

## What the watching client heard: the charge as an Audio API voice, each shot as an SfxBuster Sound.
func _judge_heard(events: Array[String]) -> void:
	var last := ""
	if FileAccess.file_exists(heard):
		for line in FileAccess.get_file_as_string(heard).split("\n", false):
			if line.begins_with("HEARD "): last = line.substr(6)
	var bits := last.split(" ")
	var frames := int(bits[0]) if bits.size() > 0 and bits[0] != "" else 0
	var shots := 0
	if bits.size() > 1:
		for pair in bits[1].split(",", false):
			if pair.begins_with("SfxBuster="): shots = int(pair.substr(10))
	var casts := events.filter(func(e): return e.contains("CAST ")).size()
	check(frames > 60, "another player hears the charge: their engine played it for %d frames" % frames)
	check(casts > 0 and shots >= casts, "and every shot: %d heard for %d cast (%s)" % [shots, casts, last])

## The walked hold: charge is (release - press) - (walking), timed off the server's clock because
## a loaded bot runs its own timers slow.
func _judge_walk() -> void:
	var on := -1.0
	var off := -1.0
	var press := -1.0
	var release := -1.0
	var charge := -1.0
	for line in said:
		var at := float(line.substr(line.find(" at ") + 4)) if line.find(" at ") >= 0 else -1.0
		if line.find("MOVE on") >= 0 and on < 0.0: on = at
		elif line.find("MOVE off") >= 0 and on >= 0.0 and off < 0.0: off = at
		elif line.find("PRESS nil") >= 0 and on < 0.0: press = at
		elif line.find("PRESS release") >= 0 and off >= 0.0 and release < 0.0: release = at
		elif line.find("CAST ") >= 0 and release >= 0.0 and charge < 0.0:
			charge = float(line.substr(line.find("charge=") + 7).split(" ")[0])
	# The 0.5: the arm goes up twice, at the press and after the walk, a quarter-second each and
	# charging nothing.
	var expected: float = minf((release - press) - (off - on) - 0.5, 6.0)
	check(on > 0.0 and off > on and press > 0.0 and release > off and abs(charge - expected) < 0.5 and charge < (release - press) - 1.0,
		"walking during a hold charges nothing: held %.2fs, walked %.2fs, so about %.2fs of charge -- got %.2f" % [release - press, off - on, expected, charge])

## Shove per blow: 54, the BFS 9000's, for a killing blow or a full charge, none otherwise.
func _judge_knock() -> void:
	var cast_charge := -1.0
	var right := true
	var kinds := {"full": 0, "lethal": 0, "none": 0}
	var rows: Array[String] = []
	for line in said:
		if line.find("CAST ") >= 0:
			cast_charge = float(line.substr(line.find("charge=") + 7).split(" ")[0])
		elif line.find("BLOW ") >= 0:
			var half := int(line.substr(line.find("half=") + 5).split(" ")[0])
			var shove := float(line.substr(line.find("shove=") + 6).split(" ")[0])
			var before := int(line.substr(line.find("before=") + 7).split(" ")[0])
			var full := cast_charge >= 6.0
			var lethal := before <= half
			var want := 54.0 if (full or lethal) else 0.0
			if abs(shove - want) > 0.01: right = false
			if full: kinds["full"] += 1
			elif lethal: kinds["lethal"] += 1
			else: kinds["none"] += 1
			rows.append("%s %d/%d shove %d" % ["full" if full else ("kill" if lethal else "plain"), half, before, int(shove)])
	check(right and kinds["full"] > 0 and kinds["lethal"] > 0 and kinds["none"] > 0,
		"knockback as hard as the BFS 9000's for a full charge or a killing blow, and none otherwise: %s" % str(rows))

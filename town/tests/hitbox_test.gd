# Proves a swing reaches only what is in front of it and inside its reach. Both bodies are
# bots: a headless server run has no local player to use as one, and neither bot is a body it
# simulates. The blows come from the swinger's own stroke -- Health.hit takes no geometry.
#
#   godot --headless --path . -s res://tests/hitbox_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld

## Script errors raised by the server; _finish asserts this stayed empty.
var errors: Array[String] = []
var main: Node
var said: Array[String] = []
var bots: Array[int] = []
var t := 0.0
var phase := 0
var results := {}

const PORT := 8813               # not 8800, and not netfight_test's 8811
const WEAPON := "BFS 9000"        # reach 5.0, radius 2.0, arc 70 degrees
const VICTIM := "Runner"         # bot.gd gives this name no weapon and no route to walk
const RING := 5.0                # the weapon's reach, where a hit is still possible

# deg is off the swinger's facing, 0 in front; out is studs. Nothing sits at the 70-degree arc
# edge, where a hit comes down to rounding.
var stands := [
	{"deg": 0.0, "out": RING, "hit": true, "what": "straight in front of it"},
	{"deg": 180.0, "out": RING, "hit": false, "what": "directly behind it"},
	{"deg": 135.0, "out": RING, "hit": false, "what": "behind its shoulder"},
	# The sweep is solid from the body outward, not a shell at the reach, so point blank lands
	{"deg": 0.0, "out": 0.6, "hit": true, "what": "chest to chest"},
	{"deg": 0.0, "out": 12.0, "hit": false, "what": "well out past the reach"},
	# GetPartBoundsInRadius catches any part, not the root's centre, and a body is two studs wide
	{"deg": 0.0, "out": RING, "hit": true, "what": "in front of it and moving", "sway": 2.2},
	# Mirrored pair at one range: both land, or the hitbox is lopsided. 25 degrees, not 55 --
	# the region is a ball in front of the swinger, so the arc only trims the back and the
	# usable fan narrows with distance: 2.7 studs off the line at five studs, about thirty
	# degrees, so the declared 70-degree arc bounds nothing at RING.
	{"deg": 25.0, "out": RING, "hit": true, "what": "off its right shoulder"},
	{"deg": -25.0, "out": RING, "hit": true, "what": "off its left shoulder"},
]
var at := 0

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

func _spawn(name: String, every: String) -> void:
	var pid := OS.create_process(OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/bot.gd", "--",
		"--name=%s" % name, "--port=%d" % PORT, "--every=%s" % every])
	if pid <= 0:
		printerr("could not start bot %s" % name)
	else:
		bots.append(pid)

func _initialize() -> void:
	print("what a swing can reach: a %s swinging at a %s" % [WEAPON, VICTIM])
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
	# No title screen to wait through: a bot gets a body as it joins
	Arrive.now(world)

	_spawn(WEAPON, "0.8")
	_spawn(VICTIM, "9.9")

func _finish() -> void:
	for pid in bots: OS.kill(pid)
	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## Puts both bots in the fight and hands the swinger a weapon accessory.
func _open() -> void:
	said.clear()
	world.run_chunk("open", ("""
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local hitter = Players:FindFirstChild("WEAPON_NAME")
local victim = Players:FindFirstChild("VICTIM_NAME")
if not hitter or not victim then
	local who = {}
	for _, p in ipairs(Players:GetPlayers()) do table.insert(who, p.Name) end
	print(("OPEN missing -- the town holds [%s]"):format(table.concat(who, ", ")))
	return
end
Health.setFights(hitter, true)
Health.setFights(victim, true)

-- A stick in its hand, which is the one thing a client may not do for itself. Same shape
-- serve_bots.gd uses: Spoon looks for an Accoutrement whose Name is a weapon and nothing
-- else, so a handle and the right name is a whole weapon as far as the fight goes.
local ch = hitter.Character
if ch and not ch:FindFirstChild("WEAPON_NAME") then
	local acc = Instance.new("Accessory")
	acc.Name = "WEAPON_NAME"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 2.2, 0.4)
	handle.Parent = acc
	acc.Parent = ch
end
print(("OPEN hitter=%s victim=%s"):format(hitter.Name, victim.Name))
""").replace("WEAPON_NAME", WEAPON).replace("VICTIM_NAME", VICTIM))

## Holds the victim `out` studs away at `deg` off the swinger's own LookVector -- a bot spawns
## facing wherever the town put it, so no world axis will do -- and counts three swings' blows.
func _stand(deg: float, out: float, sway: float) -> void:
	said.clear()
	world.run_chunk("stand", ("""
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local hitter = Players:FindFirstChild("WEAPON_NAME")
local victim = Players:FindFirstChild("VICTIM_NAME")
if not hitter or not victim then print("STOOD nobody") return end
local theirs = hitter.Character and hitter.Character:FindFirstChild("HumanoidRootPart")
if not theirs then print("STOOD no swinger") return end

-- Counted at Health.hit, and only the ones the SWINGER landed.
--
-- Watching the health instead counts everything that can take a piece off you, and out at
-- twelve studs the spot to stand on is over an edge -- so the void was landing a blow a
-- second and reading as a weapon with infinite reach. Weapons.server.luau looks the function
-- up on this table when it calls it, so standing in front of it here sees every swing that
-- lands and nothing else.
local blows = 0
local atRange = ""

-- The shove is held off while the reach is being measured.
--
-- What this file is for is geometry: at this angle and this distance, does the swing reach
-- you. Knockback is the other question and knock_net_test asks it. They were quietly sharing
-- a body, and it held together only while a shove was small: the victim is pinned in place
-- every frame, and at HURT_KNOCK 1.5 the pin won. At 2.0 it does not -- the bodies ended up
-- 46 and 147 studs apart mid-measurement, so what the sweep was being asked about was a
-- body in flight, and the limbs trailing it read as a body coming apart.
--
-- Stubbed rather than tuned around, because a reach test that has to be re-tuned every time
-- the shove changes is a reach test measuring the wrong thing. The real one goes back at the
-- end of the run, with Health.hit.
local realShove = Health.shove
Health.shove = function() end
local realHit = Health.hit
Health.hit = function(who, attacker, half, shove)
	local landed = realHit(who, attacker, half, shove)
	if landed and attacker == hitter and who == victim then
		blows += 1
		-- Both bodies looked up again at the moment of the blow, not the ones captured when
		-- this chunk started: a respawn hands out a new character and the old root keeps
		-- answering with wherever it was destroyed.
		local a = hitter.Character and hitter.Character:FindFirstChild("HumanoidRootPart")
		local v = who.Character and who.Character:FindFirstChild("HumanoidRootPart")
		if a and v then atRange = ("%.1f"):format((v.Position - a.Position).Magnitude) end
		-- And put the hearts straight back, so the dummy never dies.
		--
		-- Four blows takes it out, and death hands it a NEW character at the spawn point --
		-- which is how a reach test ended up reporting the two bodies 143 studs apart and the
		-- limbs of the destroyed model strewn behind it. Nothing about that is a hitbox; it
		-- was read as one for an evening. The blow still has to LAND to be counted, which is
		-- the thing under test; what it must not do is end the body being measured.
		local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.Health = hum.MaxHealth end
	end
	return landed
end

local look = theirs.CFrame.LookVector
look = Vector3.new(look.X, 0, look.Z)
look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
local a = math.rad(DEGREES)
-- Turned about Y, so 90 is off one shoulder and 180 is its back.
local away = Vector3.new(
	look.X * math.cos(a) - look.Z * math.sin(a), 0,
	look.X * math.sin(a) + look.Z * math.cos(a))
local spot = theirs.Position + away * OUT_STUDS
local across = Vector3.new(-away.Z, 0, away.X)      -- across the line, for the moving case

-- Counted, not subtracted, and topped straight back up.
--
-- Health loss cannot be the measure: three blows from a BFS 9000 empty a body, and a body
-- that dies respawns at the town's spawn -- somewhere this loop no longer controls, often
-- right next to the swinger. Every case after the first was then measuring a loose body
-- standing wherever the game put it, which is how "twelve studs away" came back as a hit.
--
-- So it is put back to full the instant anything comes off, and what is reported is how many
-- times that happened. The mercy window keeps one blow from counting twice.
local stop = false
task.spawn(function()
	local swung = 0
	while not stop do
		swung += 0.05
		local ch = victim.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		local h = ch and ch:FindFirstChild("Humanoid")
		if r and h then
			-- Kept alive and full. Three blows from a BFS 9000 empty a body, and a body that
			-- dies respawns at the town's spawn -- somewhere this loop no longer controls,
			-- often right next to the swinger -- so every later case would be measuring a
			-- loose body standing wherever the game put it.
			if h.Health < h.MaxHealth then h.Health = h.MaxHealth end
			-- SWAY_STUDS of side to side, if this case asks for it: walked across the swing
			-- rather than planted in it, which is what a bot circling the fountain does.
			r.CFrame = CFrame.new(spot + across * (math.sin(swung * 4) * SWAY_STUDS), theirs.Position)
			r.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end
		task.wait()
	end
end)
task.wait(0.5)                    -- settle where it was put before counting anything
blows = 0
task.wait(3.0)                    -- three of its swings at --every=0.8
stop = true
Health.hit = realHit
Health.shove = realShove
local ch = victim.Character
local r = ch and ch:FindFirstChild("HumanoidRootPart")
-- Where every one of the victim's own parts actually is, relative to its root. A body whose
-- client simulates it is moved here by writing its root; if the limbs do not come with it,
-- a sweep that asks what the ball TOUCHES will catch a limb left behind.
local liveHitter = hitter.Character and hitter.Character:FindFirstChild("HumanoidRootPart")
local vch = victim.Character
local vr = vch and vch:FindFirstChild("HumanoidRootPart")
if vch and vr then
	--- Which of this body's parts are nowhere near its root.
	local function strayNow()
		local strays = {}
		local root = vch:FindFirstChild("HumanoidRootPart")
		if not root then return strays end
		for _, d in ipairs(vch:GetDescendants()) do
			if d:IsA("BasePart") then
				local off = (d.Position - root.Position).Magnitude
				-- Limbs only. The accessory handles are sixty studs out and would bury the line.
				if off > 3 and d.Parent == vch then
					table.insert(strays, ("%s@%.1f"):format(d.Name, off))
				end
			end
		end
		return strays
	end

	-- Twice, and the second one is the check.
	--
	-- Sampling once, the instant the swinging stops, cannot tell apart the two things it
	-- matters most to tell apart. A body in FLIGHT has its root ahead of its derived limbs by
	-- however far it travelled since they were last worked out -- that is a frame of lag and
	-- it closes itself. A body at REST with its limbs six studs away is a body that came
	-- apart, which is the bug this check was written for: limbs left behind for good.
	--
	-- It only ever mattered which one this was once the shove got big. At HURT_KNOCK 1.5 a
	-- dying man went about five studs and the in-flight lag stayed under the three-stud line
	-- by luck; at 2.0 he goes nearly eight and it does not, so the single sample started
	-- calling an ordinary knockback a broken body.
	local inFlight = strayNow()
	task.wait(1.0)
	local settled = strayNow()
	print(("LIMBS deg=DEGREES out=OUT_STUDS %d stray part(s): %s"):format(
		#settled, table.concat(settled, " ")))
	print(("LIMBSFLIGHT deg=DEGREES %d in flight: %s"):format(
		#inFlight, table.concat(inFlight, " ")))
end
print(("STOOD deg=DEGREES out=OUT_STUDS sway=SWAY_STUDS blows=%d, %.1f studs apart, hit at [%s]"):format(
	blows,
	(r and liveHitter) and (r.Position - liveHitter.Position).Magnitude or -1,
	atRange))
""").replace("WEAPON_NAME", WEAPON).replace("VICTIM_NAME", VICTIM)
		.replace("DEGREES", "%.1f" % deg).replace("OUT_STUDS", "%.2f" % out)
		.replace("SWAY_STUDS", "%.2f" % sway))

func _process(delta: float) -> bool:
	t += delta
	# 24 s: both bot processes have to start, connect and get a body
	if phase == 0 and t > 24.0:
		phase = 1
		t = 0.0
		_open()
	elif phase == 1 and t > 2.0:
		phase = 2
		t = 0.0
		var open := _lines("OPEN ")
		check(open.size() > 0 and String(open[0]).begins_with("hitter="),
			"both bots are in the town, one with a stick: %s" % str(open))
		if open.size() == 0 or not String(open[0]).begins_with("hitter="):
			_finish()
			return false
		_stand(stands[0]["deg"], stands[0]["out"], 0.0)
	elif phase == 2 and t > 4.6:
		t = 0.0
		var stood := _lines("STOOD ")
		var row: Dictionary = stands[at]
		if stood.size() == 0:
			check(false, "%s: nothing came back in time" % row["what"])
		else:
			var s := String(stood[stood.size() - 1])
			var lost := int(s.substr(s.find("blows=") + 6).split(",")[0])
			results[row["what"]] = lost
			if row["hit"]:
				check(lost > 0, "%s, it hits you: %s" % [row["what"], s])
			else:
				check(lost == 0, "%s, it cannot touch you: %s" % [row["what"], s])
		# A body this machine does not simulate has to carry its limbs with it. Checked on the
		# last stand only: a stand read just after its first teleport still shows limbs behind.
		if at == stands.size() - 1:
			var limbs := _lines("LIMBS ")
			if limbs.size() > 0:
				var last := String(limbs[limbs.size() - 1])
				check(last.find(" 0 stray") >= 0,
					"and a body moved every frame brings its limbs along: %s" % last)

		at += 1
		if at >= stands.size():
			phase = 3
			print("  what each spot cost: ", results)
			_finish()
			return false
		_stand(stands[at]["deg"], stands[at]["out"], float(stands[at].get("sway", 0.0)))
	return false

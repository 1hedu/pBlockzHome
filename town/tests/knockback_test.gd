# Health.shove scales knockback by how few hearts are left, and drops the lift in mid-air.
#
#   godot --headless --path . -s res://tests/knockback_test.gd
#
# Play Solo: the scale is arithmetic in Health.shove, and a velocity written on a body the
# server does not simulate is only a suggestion. netfight_test covers the wire.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld

## Every script_error the Luau server threw while this ran; asserted empty at the end.
var errors: Array[String] = []
var said: Array[String] = []
var lit := false

## Mirrors Health.luau's HURT_KNOCK: the shove multiplier at zero hearts. 2.0 is the smallest
## value at which the weakest weapon, a shove of 26, still scales perceptibly at the dying end.
const HURT_KNOCK := 2.0
const FLAT := 17.4            # KNOCK 0.58 of a shove of 30
const LIFT := 7.8             # LIFT 0.26 of the same

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the shove, and what being nearly dead does to it")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		said.append(line)
		if String(line).begins_with("intro:"): lit = true)
	get_root().add_child(main)
	_run()

## The multiplier at one half-heart of six, the lowest a live body reaches.
func dying() -> float:
	return 1.0 + (1.0 - 1.0 / 6.0) * (HURT_KNOCK - 1.0)

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var i := String(line).find(prefix)
		if i >= 0:
			out.append(String(line).substr(i + prefix.length()).strip_edges())
	return out

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(3.0).timeout

	said.clear()
	world.run_chunk("shove", """
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local player = Players:GetPlayers()[1]
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")
-- Where they started, so each measurement begins from the same spot rather than from
-- wherever the last throw left them.
local base = root.CFrame

-- Read back the instant it is written, before gravity or the walk have had a frame at it.
-- Health.shove sets the velocity outright, so this is the number the scale produced and
-- nothing else has touched it yet.
local function shoveAt(half, force)
	hum.Health = half
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	Health.shove(player, nil, force)
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude, v.Y
end

-- Every step from full down to the last half, at one force, so the shape of the curve is
-- visible and not just its two ends.
local rows = {}
for _, half in ipairs({6, 5, 4, 3, 2, 1}) do
	local flat, up = shoveAt(half, 30)
	table.insert(rows, ("%d:%.2f/%.2f"):format(half, flat, up))
end
print("SHOVE " .. table.concat(rows, " "))

-- And the two ends again, with the two real weapons' own numbers, so the check is not about
-- one made-up force.
local spoonFull = shoveAt(6, 26)
local spoonDying = shoveAt(1, 26)
local bigFull = shoveAt(6, 54)
local bigDying = shoveAt(1, 54)
print(("WEAPONS spoon %.2f -> %.2f, spoonie %.2f -> %.2f"):format(
	spoonFull, spoonDying, bigFull, bigDying))

hum.Health = hum.MaxHealth
root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

-- Off the ground, nothing is added upward and what they had is kept. Set outright rather
-- than jumped, so the measurement is of one known vertical speed and not of whatever frame
-- of a jump the wait happened to land on.
local function shoveAloft(vy, force)
	hum.Health = hum.MaxHealth
	-- Up off the floor first, or the controller has them standing and GetState says Running.
	root.CFrame = root.CFrame + Vector3.new(0, 14, 0)
	root.AssemblyLinearVelocity = Vector3.new(0, vy, 0)
	Health.shove(player, nil, force)
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude, v.Y
end
-- Whether the striker's feet are down, which is the decision behind the jump attack's
-- sound: Health.hit sends "stronghit" to both ends instead of the usual pair when the one
-- swinging it is in the air.
--
-- The decision and not the clip. The server says who hears what over CombatSfx, and
-- FireClient does not come back into the runtime it was sent from -- so a chunk here hears
-- nothing whatever it plays, and a test that listened would pass by being deaf.
local function aloftFrom(up)
	hum.Health = hum.MaxHealth
	root.CFrame = up and (base + Vector3.new(0, 14, 0)) or base
	root.AssemblyLinearVelocity = up and Vector3.new(0, 40, 0) or Vector3.new(0, 0, 0)
	task.wait(0.05)
	return Health.aloft(player)
end
print(("SOUND on the floor aloft=%s, out of the air aloft=%s"):format(
	tostring(aloftFrom(false)), tostring(aloftFrom(true))))
root.CFrame = base
root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
task.wait(0.6)

local upFlat, upY = shoveAloft(40, 30)
local downFlat, downY = shoveAloft(-40, 30)
print(("ALOFT rising %.2f flat %.2f up, falling %.2f flat %.2f up"):format(
	upFlat, upY, downFlat, downY))
root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
task.wait(1.2)

-- And once end to end, as a body actually moving: the velocity being right is not the same
-- claim as the body going anywhere, which is what the fight is about.
local function travelAt(half, force)
	hum.Health = half
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	task.wait(0.5)
	local at = root.Position
	Health.shove(player, nil, force)
	task.wait(1.1)
	return (root.Position - at).Magnitude
end
local function travel(half) return travelAt(half, 30) end
local wentFull = travel(hum.MaxHealth)
local wentDying = travel(1)
print(("WENT full %.2f studs, last half %.2f studs"):format(wentFull, wentDying))
-- And the biggest shove in the game, both ends, because that is the one that decides whether
-- this reads as a stagger or as a catapult.
local bigWentFull = travelAt(hum.MaxHealth, 54)
local bigWentDying = travelAt(1, 54)
print(("BIG spoonie full %.2f studs, last half %.2f studs"):format(bigWentFull, bigWentDying))
hum.Health = hum.MaxHealth
""")
	await create_timer(12.0).timeout

	var shove := _lines("SHOVE ")
	check(shove.size() > 0, "the shove was measured at every heart: %s" % str(shove))
	if shove.size() > 0:
		# Cells are "<half-hearts left>:<flat speed>/<lift>", one per heart from 6 down to 1.
		var flat := {}
		var lift := {}
		for cell in String(shove[0]).split(" ", false):
			var bits: PackedStringArray = String(cell).split(":")
			if bits.size() < 2: continue
			var pair: PackedStringArray = bits[1].split("/")
			flat[int(bits[0])] = float(pair[0])
			lift[int(bits[0])] = float(pair[1])

		check(abs(float(flat.get(6, 0)) - FLAT) < 0.3,
			"at full hearts it is the plain shove, unscaled: %.2f of %.2f" % [flat.get(6, 0), FLAT])
		check(abs(float(lift.get(6, 0)) - LIFT) < 0.3,
			"and the lift with it: %.2f of %.2f" % [lift.get(6, 0), LIFT])

		check(abs(float(flat.get(1, 0)) - FLAT * dying()) < 0.4,
			"on their last half it is half again: %.2f of %.2f" % [flat.get(1, 0), FLAT * dying()])
		check(abs(float(lift.get(1, 0)) - LIFT * dying()) < 0.4,
			"lift included, so there is air under it: %.2f of %.2f" % [lift.get(1, 0), LIFT * dying()])

		# The whole curve: a scale that only moved at the two ends passes the checks above.
		var rising := true
		for half in [5, 4, 3, 2, 1]:
			if float(flat.get(half, 0)) <= float(flat.get(half + 1, 0)): rising = false
		check(rising, "and it grows at every heart on the way down, not just at the ends")

	var weapons := _lines("WEAPONS ")
	check(weapons.size() > 0, "both weapons' own numbers scale too: %s" % str(weapons))

	var sound := _lines("SOUND ")
	check(sound.size() > 0, "the striker's footing was read both ways: %s" % str(sound))
	if sound.size() > 0:
		var snd := String(sound[0])
		check(snd.find("floor aloft=false") >= 0,
			"standing on the floor it knows their feet are down: %s" % snd)
		check(snd.find("air aloft=true") >= 0,
			"and in the air it knows they are not: %s" % snd)

	# CombatSfx carries only the role name, so a role the client has no entry for is a silent
	# hit. Neither end of that mapping is visible from the server's aloft() decision above.
	var client := FileAccess.get_file_as_string("res://scripts/src/client/Combat.client.luau")
	check(client.find("stronghit = \"SfxStrongHit\"") >= 0,
		"the client knows what a stronghit is and which asset it arrives as")
	check(FileAccess.file_exists("res://../../../scripts/sfx/stronghit.wav"),
		"and prep-sfx.js has decoded the clip to scripts/sfx/stronghit.wav")

	var aloft := _lines("ALOFT ")
	check(aloft.size() > 0, "a blow was landed on somebody in mid-air: %s" % str(aloft))
	if aloft.size() > 0:
		var a := String(aloft[0])
		var upFlat := float(a.substr(a.find("rising ") + 7).split(" ")[0])
		var upY := float(a.substr(a.find("flat ") + 5).split(" ")[0])
		var downY := float(a.substr(a.rfind("flat ") + 5).split(" ")[0])
		check(abs(upY - 40.0) < 1.0,
			"on the way up it keeps their climb and adds nothing: %.2f of 40.00" % upY)
		check(abs(downY + 40.0) < 1.0,
			"on the way down it keeps their fall, so the ground arrives: %.2f of -40.00" % downY)
		# Aloft, Health.shove drops the lift only; the ground push is the unreduced one.
		check(abs(upFlat - FLAT) < 0.3,
			"and the sideways push is undiminished: %.2f of %.2f" % [upFlat, FLAT])

	var big := _lines("BIG ")
	check(big.size() > 0, "the biggest shove in the game was measured: %s" % str(big))
	if big.size() > 0:
		var b := String(big[0])
		var bigDying := float(b.substr(b.find("last half ") + 10).split(" ")[0])
		# A ceiling. Travel is quadratic in the multiplier, so nudging HURT_KNOCK up again runs
		# away fast: at 2.0 the biggest weapon throws a dying body 19.96 studs across a town
		# 140 studs wide.
		check(bigDying < 26.0,
			"and even it is a shove and not a flight: %.2f studs at the last half" % bigDying)
	var went := _lines("WENT ")
	check(went.size() > 0, "and a body was actually thrown: %s" % str(went))
	if went.size() > 0:
		var w := String(went[0])
		var full := float(w.substr(w.find("full ") + 5).split(" ")[0])
		var dying := float(w.substr(w.find("last half ") + 10).split(" ")[0])
		check(dying > full * 1.3,
			"further the fewer hearts are left: %.2f studs full, %.2f dying" % [full, dying])
		check(full < 6.0, "and at full hearts it is still a stagger: %.2f studs" % full)

	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
